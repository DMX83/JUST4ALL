import SwiftUI
import AppKit
import J4IAI
import J4ICore

/// G7 — «Chat del archivo»: preguntas en lenguaje natural sobre el archivo local.
///
/// Recuperación 100 % local (léxica + semántica); solo los fragmentos recortados (≤4.000
/// caracteres en total) viajan a DeepSeek cuando el usuario pregunta y la IA está activada
/// (interruptor y cap diario de Ajustes → IA). Los ficheros nunca se suben.
@MainActor
final class ChatModel: ObservableObject {
    struct Message: Identifiable {
        enum Role {
            case user
            case assistant
        }

        let id = UUID()
        let role: Role
        let text: String
        var citations: [ArchiveChatDocument] = []
        var isError = false
    }

    @Published private(set) var messages: [Message] = []
    @Published var draft: String = ""
    @Published private(set) var isAnswering = false

    private lazy var client: DeepSeekClient? = DeepSeekKeyResolver.resolve().map {
        DeepSeekClient(configuration: DeepSeekConfiguration(apiKey: $0))
    }

    func ask(_ raw: String, search: SearchViewModel) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAnswering else { return }
        draft = ""
        messages.append(Message(role: .user, text: question))
        isAnswering = true
        Task { await answer(question, search: search) }
    }

    func open(_ document: ArchiveChatDocument) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: document.path)])
    }

    private func answer(_ question: String, search: SearchViewModel) async {
        defer { isAnswering = false }
        let context = await search.chatContext(for: question)
        guard AIControlCenter.shared.canUseAI() else {
            messages.append(
                Message(
                    role: .assistant,
                    text: "La IA está desactivada o se alcanzó el cap diario (Ajustes → IA). La búsqueda semántica local sigue funcionando sin conexión.",
                    isError: true
                )
            )
            return
        }
        guard let client else {
            messages.append(
                Message(
                    role: .assistant,
                    text: "Falta la clave de DeepSeek (DEEPSEEK_API_KEY o .env.secrets). El chat no puede responder; la búsqueda semántica local no la necesita.",
                    isError: true
                )
            )
            return
        }
        guard !context.isEmpty else {
            messages.append(Message(role: .assistant, text: "No he encontrado nada relevante en tu archivo para esa pregunta."))
            return
        }
        let (system, user) = ArchiveChatPrompt.build(question: question, documents: context)
        AIControlCenter.shared.registerCall()
        do {
            let answerText = try await client.completeText(system: system, user: user, maxTokens: 700)
            let cited = ArchiveChatPrompt.citedIndices(in: answerText, documentCount: context.count)
            let citations = cited.compactMap { context.indices.contains($0 - 1) ? context[$0 - 1] : nil }
            messages.append(
                Message(
                    role: .assistant,
                    text: answerText.trimmingCharacters(in: .whitespacesAndNewlines),
                    citations: citations
                )
            )
            J4Log.info(.ai, "Chat del archivo: respuesta con \(citations.count) cita(s) sobre \(context.count) fragmento(s).")
        } catch {
            messages.append(Message(role: .assistant, text: "No se pudo responder: \(error.localizedDescription)", isError: true))
            J4Log.warn(.ai, "Chat del archivo falló: \(error.localizedDescription)")
        }
    }
}

struct ChatView: View {
    @EnvironmentObject private var search: SearchViewModel
    @StateObject private var model = ChatModel()
    @FocusState private var inputFocused: Bool

    private static let examples = [
        "¿Qué facturas tengo de enero?",
        "¿Dónde está el contrato del alquiler?",
        "¿Qué documentos hay de matemáticas?"
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.messages.isEmpty {
                            emptyState
                        }
                        ForEach(model.messages) { message in
                            messageRow(message)
                        }
                        if model.isAnswering {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Buscando en tu archivo…")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .id("busy")
                        }
                    }
                    .padding(J4I.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: model.isAnswering) { _, busy in
                    if busy {
                        withAnimation { proxy.scrollTo("busy", anchor: .bottom) }
                    }
                }
            }
            Divider()
            inputBar
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            inputFocused = true
            // El primer foco puede perderse antes de que la ventana sea «key»: reintento corto.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                inputFocused = true
            }
        }
    }

    // MARK: - Piezas

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(J4I.brand)
                Text("Pregunta a tu archivo")
                    .font(.title3.weight(.semibold))
            }
            Text("Busca por significado en el índice local (léxico + semántico) y responde con citas a tus documentos. Los archivos nunca se suben: solo fragmentos recortados viajan a la IA cuando preguntas.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Self.examples, id: \.self) { example in
                    Button {
                        model.ask(example, search: search)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                            Text(example)
                        }
                        .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(J4I.brand)
                }
            }
        }
        .padding(.vertical, J4I.Space.m)
    }

    @ViewBuilder
    private func messageRow(_ message: ChatModel.Message) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(J4I.brand)
                    )
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: message.isError ? "exclamationmark.triangle" : "sparkles")
                        .foregroundStyle(message.isError ? Color.orange : J4I.brand)
                        .padding(.top, 2)
                    Text(message.text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !message.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(message.citations, id: \.path) { document in
                            Button {
                                model.open(document)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text")
                                    Text(document.name)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(J4I.brandSoft))
                                .foregroundStyle(J4I.brand)
                            }
                            .buttonStyle(.plain)
                            .help("Mostrar «\(document.path)» en el Finder")
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: 600, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Pregunta a tu archivo…", text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .onSubmit { model.ask(model.draft, search: search) }
            Button {
                model.ask(model.draft, search: search)
            } label: {
                Image(systemName: "paperplane.fill")
                    .padding(6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAnswering)
            .help("Preguntar (↩)")
        }
        .padding(.horizontal, J4I.Space.l)
        .padding(.vertical, J4I.Space.m)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.caption2)
            Text("Recuperación local; al preguntar se envían fragmentos (≤4.000 caracteres) a DeepSeek. Respuestas orientativas: abre la cita para verificar.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, J4I.Space.l)
        .padding(.bottom, J4I.Space.s)
    }
}
