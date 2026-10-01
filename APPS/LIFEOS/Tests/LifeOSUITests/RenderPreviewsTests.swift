import AppKit
import SwiftUI
import XCTest

// `@testable` para poder usar los inicializadores internos de los modelos y el
// sembrado de datos de ejemplo: son de prueba, no de la API pública.
@testable import LifeOSAPI
@testable import LifeOSCore
@testable import LifeOSUI

/// Genera las imágenes de revisión de diseño renderizando las vistas **fuera de
/// pantalla**, sin ventana ni permisos del sistema.
///
/// Se salta salvo que se pida, porque escribe ficheros:
///
/// ```sh
/// LIFEOS_RENDER_PREVIEWS=1 swift test --filter RenderPreviewsTests
/// ```
///
/// Sale en `docs/design/v2-apple` (o donde diga `LIFEOS_PREVIEW_OUT`).
///
/// Nota: `screencapture` no sirve aquí: en este Mac devuelve imágenes negras en
/// cuanto la pantalla se duerme, y capturar por ventana o por rectángulo está
/// bloqueado. Renderizar la vista da el mismo diseño, siempre, y sin depender
/// del estado del escritorio.
@MainActor
final class RenderPreviewsTests: XCTestCase {
    private var outputDirectory: URL {
        if let raw = ProcessInfo.processInfo.environment["LIFEOS_PREVIEW_OUT"] {
            return URL(fileURLWithPath: raw, isDirectory: true)
        }
        // Tests/LifeOSUITests/… → raíz del paquete.
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/design/v2-apple", isDirectory: true)
    }

    func testRenderScreens() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LIFEOS_RENDER_PREVIEWS"] != nil,
            "Sin LIFEOS_RENDER_PREVIEWS: no se generan imágenes."
        )
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            let model = previewModel()

            // Se renderiza el *contenido* de cada pantalla, no el `ScrollView`:
            // `ImageRenderer` no pinta dentro de un contenedor con scroll.
            try render(TodayContent(model: model), size: CGSize(width: 900, height: 780), scheme: scheme, name: "\(name)-today")
            try render(
                AgendaContent(model: previewModel(agenda: SampleData.agendaWeek)),
                size: CGSize(width: 900, height: 1000),
                scheme: scheme,
                name: "\(name)-agenda"
            )
            try render(
                AgendaContent(model: previewModel(
                    agenda: SampleData.agendaWeek,
                    eventDraft: EventDraft(
                        title: "Café con Marta",
                        startsAt: Date().addingTimeInterval(3600),
                        endsAt: Date().addingTimeInterval(7200),
                        location: "Cafetería del barrio"
                    )
                )),
                size: CGSize(width: 900, height: 1180),
                scheme: scheme,
                name: "\(name)-agenda-form"
            )
            try render(
                TasksContent(model: previewModel(agenda: SampleData.agendaWeek, tasks: SampleData.tasks)),
                size: CGSize(width: 900, height: 880),
                scheme: scheme,
                name: "\(name)-tasks"
            )
            try render(
                TasksContent(model: previewModel(
                    agenda: SampleData.agendaWeek,
                    tasks: SampleData.tasks,
                    taskDraft: TaskDraft(title: "Pedir el certificado digital", priority: 2, dueDate: Date(), context: "Papeleo")
                )),
                size: CGSize(width: 900, height: 900),
                scheme: scheme,
                name: "\(name)-tasks-form"
            )
            try render(
                InsightsContent(model: previewModel(timeline: SampleData.timeline)),
                size: CGSize(width: 900, height: 980),
                scheme: scheme,
                name: "\(name)-timeline"
            )
            try render(
                InsightsContent(model: previewModel(
                    timeline: SampleData.timeline,
                    searchResults: SampleData.searchResults,
                    insightMode: .search
                )),
                size: CGSize(width: 900, height: 720),
                scheme: scheme,
                name: "\(name)-search"
            )
            try render(CaptureContent(model: previewModel(draft: "Reunión con el cliente el jueves a las 10 y llamar al diseñador")), size: CGSize(width: 900, height: 620), scheme: scheme, name: "\(name)-capture")
            try render(InboxContent(model: model), size: CGSize(width: 900, height: 780), scheme: scheme, name: "\(name)-inbox")
            try render(JournalContent(model: model), size: CGSize(width: 900, height: 1000), scheme: scheme, name: "\(name)-journal")
            // La escala del ánimo y la energía **con valor puesto**: es la única forma de
            // revisar los puntos encendidos y la palabra que los acompaña.
            try render(
                JournalContent(model: previewModel(journalMood: 5, journalEnergy: 2)),
                size: CGSize(width: 900, height: 1000),
                scheme: scheme,
                name: "\(name)-journal-escala"
            )
            try render(
                JournalContent(model: previewModel(journalOpen: "j1")),
                size: CGSize(width: 900, height: 1120),
                scheme: scheme,
                name: "\(name)-journal-open"
            )
            try render(
                JournalContent(model: previewModel(
                    journalMentions: [
                        JournalMention(id: "t1", kind: "task", text: "Enviar el informe de gastos")
                    ],
                    journalDraft: "@hora:21:10\nCerré @tarea:Enviar el informe de gastos y me quedó pendiente @tarea:llamar al seguro."
                )),
                size: CGSize(width: 900, height: 620),
                scheme: scheme,
                name: "\(name)-journal-draft"
            )
            // El caso que abrió el 30-sep-2026: la hora escrita sin «:». El aviso del
            // compositor tiene que decir que se guardará a las 11:00.
            try render(
                JournalContent(model: previewModel(journalDraft: "@Time:1100 Fui a pelarme y luego al mercado.")),
                size: CGSize(width: 900, height: 620),
                scheme: scheme,
                name: "\(name)-journal-cabecera"
            )
            try render(
                JournalMentionPanel(
                    candidates: Self.sampleCandidates,
                    query: "informe",
                    loading: false,
                    onSelect: { _ in },
                    onClose: {}
                )
                .padding(LifeOSSpace.xl),
                size: CGSize(width: 720, height: 400),
                scheme: scheme,
                name: "\(name)-journal-picker"
            )
            try render(SettingsContent(model: model), size: CGSize(width: 900, height: 940), scheme: scheme, name: "\(name)-settings")
            try render(
                LoginPanel(model: previewModel(signedOut: true))
                    .frame(width: 420)
                    .padding(LifeOSSpace.xl)
                    .background(LoginCanvas()),
                size: CGSize(width: 900, height: 720),
                scheme: scheme,
                name: "\(name)-login"
            )
            try render(
                QuickCaptureView(model: previewModel(), onClose: {}),
                size: CGSize(width: 608, height: 268),
                scheme: scheme,
                name: "\(name)-panel"
            )
            try render(
                CaptureContent(model: previewModel(withProposal: true)),
                size: CGSize(width: 900, height: 720),
                scheme: scheme,
                name: "\(name)-proposal"
            )
        }

        let generated = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)
            .filter { $0.hasSuffix(".png") }
            .sorted()
        XCTAssertEqual(generated.count, 38, "Se esperaban 38 imágenes y hay \(generated.count)")
        print("Imágenes de revisión en \(outputDirectory.path): \(generated.joined(separator: ", "))")
    }

    // MARK: - Render

    private func render(_ view: some View, size: CGSize, scheme: ColorScheme, name: String) throws {
        let content = view
            .environment(\.colorScheme, scheme)
            // Sin ventana, los materiales del sistema salen negros: se cambian
            // por el color de superficie equivalente.
            .environment(\.lifeOSFlatSurfaces, true)
            .frame(width: size.width, height: size.height)
            .background(scheme == .light ? Color.white : Color.black)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2

        let image = try XCTUnwrap(renderer.nsImage, "No se pudo renderizar \(name)")
        let representation = try XCTUnwrap(
            NSBitmapImageRep(data: image.tiffRepresentation ?? Data()),
            "Sin representación de mapa de bits para \(name)"
        )
        let png = try XCTUnwrap(
            representation.representation(using: .png, properties: [:]),
            "No se pudo codificar \(name) como PNG"
        )

        let target = outputDirectory.appendingPathComponent("\(name).png")
        try png.write(to: target)
    }

    // MARK: - Datos de ejemplo

    private func previewModel(
        signedOut: Bool = false,
        withProposal: Bool = false,
        draft: String = "",
        journalOpen: String? = nil,
        journalMentions: [JournalMention] = [],
        journalDraft: String = "",
        journalMood: Int? = nil,
        journalEnergy: Int? = nil,
        agenda: AgendaDay? = nil,
        tasks: [LifeOSTask] = [],
        timeline: Timeline? = nil,
        searchResults: SearchResults? = nil,
        insightMode: InsightMode = .timeline,
        eventDraft: EventDraft? = nil,
        taskDraft: TaskDraft? = nil
    ) -> LifeOSModel {
        let defaults = UserDefaults(suiteName: "lifeos.previews.\(UUID().uuidString)")!
        let model = LifeOSModel(settings: SettingsStore(defaults: defaults))
        guard !signedOut else { return model }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let at: (Int, Int) -> Date = { hour, minute in
            calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: today) ?? today
        }

        model.seedForPreview(
            user: LifeOSUser(
                id: "u1",
                username: "andy@perlatec.net",
                displayName: "Andy",
                avatarUrl: nil,
                mfaMode: "disabled"
            ),
            dayClose: DayClose(
                date: "2026-09-30",
                completed: [
                    DayCloseItem(id: "t1", title: "Cerrar la semana pasada", at: Date()),
                    DayCloseItem(id: "t2", title: "Responder a la gestoría", at: Date())
                ],
                events: [
                    DayCloseItem(id: "e1", title: "Reunión con el equipo", at: at(10, 0)),
                    DayCloseItem(id: "e2", title: "Llamada con el banco", at: at(17, 30))
                ],
                openTasks: 13,
                pendingCaptures: 17,
                journalEntryId: nil,
                journalEntries: 1,
                suggestion: "Hoy ya has cerrado dos cosas y tienes 17 capturas por resolver."
            ),
            reminders: [
                ReminderItem(
                    id: "r1",
                    kind: "task",
                    title: "Enviar el informe de gastos",
                    at: at(11, 30),
                    remindAt: at(11, 15),
                    minutes: 15,
                    detail: "Trabajo"
                ),
                ReminderItem(
                    id: "r2",
                    kind: "event",
                    title: "Reunión con el equipo",
                    at: at(10, 0),
                    remindAt: at(9, 45),
                    minutes: 15,
                    detail: "Calendar · Personal"
                )
            ],
            inbox: [
                CaptureDetail(
                    id: "c1",
                    status: "ready",
                    proposalId: nil,
                    clarifyingQuestion: "",
                    manualKind: "",
                    content: "Comprar leche al volver del trabajo",
                    channel: "text",
                    sensitivity: "standard",
                    originalFilename: "",
                    originalPreserved: false,
                    createdAt: Date().addingTimeInterval(-600)
                ),
                CaptureDetail(
                    id: "c2",
                    status: "needs_clarification",
                    proposalId: nil,
                    clarifyingQuestion: "No sé si es una tarea o un objetivo: ¿lo quieres como algo que hacer o como algo a conseguir?",
                    manualKind: "",
                    content: "Preparar la media maratón",
                    channel: "text",
                    sensitivity: "standard",
                    originalFilename: "",
                    originalPreserved: false,
                    createdAt: Date().addingTimeInterval(-5400)
                ),
                CaptureDetail(
                    id: "c3",
                    status: "applied",
                    proposalId: nil,
                    clarifyingQuestion: "",
                    manualKind: "",
                    content: "Idea para la web: una vista de objetivos por semanas",
                    channel: "audio",
                    sensitivity: "sensitive",
                    originalFilename: "dictado.m4a",
                    originalPreserved: true,
                    createdAt: Date().addingTimeInterval(-90_000)
                )
            ],
            queued: [
                OutboxItem(
                    id: "q1",
                    content: "Llamar al fisio para cambiar la cita",
                    sensitivity: "standard",
                    createdAt: Date().addingTimeInterval(-3600),
                    attempts: 2,
                    lastError: "No se pudo conectar con LifeOS"
                )
            ],
            journal: Self.sampleJournal,
            journalOpen: journalOpen,
            journalMentions: journalMentions,
            journalDraft: journalDraft,
            journalMood: journalMood,
            journalEnergy: journalEnergy,
            agenda: agenda,
            tasks: tasks,
            timeline: timeline,
            searchResults: searchResults,
            insightMode: insightMode,
            eventDraft: eventDraft,
            taskDraft: taskDraft,
            draftState: withProposal ? .proposal(Self.sampleProposal) : .idle,
            draft: draft
        )
        return model
    }

    /// Candidatos de ejemplo para el selector de referencias.
    private static let sampleCandidates: [JournalReferenceCandidate] = [
        JournalReferenceCandidate(id: "t1", kind: "task", label: "Enviar el informe de gastos", detail: "Trabajo"),
        JournalReferenceCandidate(id: "t2", kind: "task", label: "Pedir el informe al gestor", detail: "Casa"),
        JournalReferenceCandidate(id: "e1", kind: "event", label: "Reunión del informe trimestral", detail: "jueves 10:00")
    ]

    /// Entradas de diario de ejemplo, en dos días distintos.
    private static var sampleJournal: [JournalEntry] {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86_400)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        // La hora del chip sale de `@hora:`, que es lo que hace el servidor.
        let at2530 = Calendar.current.date(
            bySettingHour: 22, minute: 30, second: 0, of: now
        ) ?? now
        return [
            JournalEntry(
                id: "j1",
                entryDate: formatter.string(from: now),
                title: "",
                contentMarkdown: "@hora:22:30\nDía largo pero cerrado: la reunión salió bien y me quité el informe de encima.\n\nMañana quiero empezar por lo difícil.",
                mood: 4,
                energy: 3,
                occurredAt: at2530,
                sensitivity: "sensitive",
                version: 2,
                createdAt: now,
                updatedAt: now,
                references: [
                    JournalReference(id: "t1", kind: "task", title: "Enviar el informe de gastos", text: "el informe", status: "ok")
                ],
                unresolvedReferences: []
            ),
            JournalEntry(
                id: "j2",
                entryDate: formatter.string(from: yesterday),
                // Tal cual lo pone el servidor cuando no hay título: no debe
                // tapar el texto en la lista.
                title: "Entrada del 29 de septiembre",
                contentMarkdown: "Comprar bombillas del salón y mirar lo del seguro.",
                mood: 3,
                energy: 2,
                occurredAt: nil,
                sensitivity: "sensitive",
                version: 1,
                createdAt: yesterday,
                updatedAt: yesterday,
                references: [],
                unresolvedReferences: ["@tarea:llamar al seguro"]
            )
        ]
    }

    /// Una propuesta de ejemplo: una tarea con hora, una idea y una métrica.
    private static var sampleProposal: Proposal {
        Proposal(
            id: "p1",
            captureId: "c9",
            status: "pending",
            operations: [
                ProposalOperation(
                    id: "op-1",
                    operation: "create",
                    entityKind: "event",
                    after: [
                        "title": .string("Reunión con el cliente"),
                        "starts_at": .string("2026-10-01T10:00:00+02:00")
                    ],
                    targetId: nil,
                    sourceId: nil,
                    relationType: nil,
                    confidence: 0.86,
                    dependencies: [],
                    warnings: ["Revisa y confirma antes de guardar."]
                ),
                ProposalOperation(
                    id: "op-2",
                    operation: "create",
                    entityKind: "task",
                    after: [
                        "title": .string("Llamar al diseñador"),
                        "due_date": .string("2026-10-02"),
                        "priority": .number(3)
                    ],
                    targetId: nil,
                    sourceId: nil,
                    relationType: nil,
                    confidence: 0.72,
                    dependencies: [],
                    warnings: []
                ),
                ProposalOperation(
                    id: "op-3",
                    operation: "create",
                    entityKind: "idea",
                    after: ["title": .string("Idea: una vista de objetivos por semanas")],
                    targetId: nil,
                    sourceId: nil,
                    relationType: nil,
                    confidence: 0.48,
                    dependencies: [],
                    warnings: []
                )
            ],
            explanation: "He visto un evento con hora, una tarea con fecha y una idea. Revisa antes de guardar."
        )
    }
}
