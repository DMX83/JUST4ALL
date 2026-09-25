import SwiftUI

/// Buscador de destino con autocompletado (F13.0).
///
/// Petición del usuario (25-sep): «la lista de carpetas es muy grande y me es pesado buscar…
/// si un Excel es de mi carpeta de trabajo, debería poder escribir "trabajo" y me salgan opciones
/// de subitems además de "trabajo"». Escribir filtra la taxonomía al momento (sin acentos ni
/// mayúsculas; todos los términos deben aparecer) manteniendo el orden padre→hijos, y **Enter**
/// elige el primer resultado.
struct DestinationChooser: View {
    let title: String
    let destinations: [String]
    let onSelect: (String) -> Void
    let onCancel: () -> Void
    /// Si se define (F14.0), cuando no hay coincidencias se ofrece **crear la categoría** escrita.
    var onCreate: ((String) -> Void)? = nil

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            TextField("Buscar destino… (p. ej. «trabajo»)", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit { submit() }
            Divider()
            if results.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sin coincidencias para «\(query)».")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let onCreate, let newName = Self.sanitizedName(from: query) {
                        Button {
                            onCreate(newName)
                        } label: {
                            Label("Crear categoría «\(newName)»", systemImage: "plus.circle")
                        }
                        Text("Se creará la carpeta dentro de JUST4INDEX al mover; las próximas veces aparecerá en la lista y la IA también podrá usarla.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results, id: \.self) { destination in
                            Button {
                                onSelect(destination)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: destination.contains("/") ? "folder" : "folder.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(destination)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                            }
                            .buttonStyle(.plain)
                            .hoverHighlight(intensity: 0.06)
                        }
                    }
                }
                .frame(height: 240)
            }
            HStack {
                Text("\(results.count) de \(destinations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { searchFocused = true }
    }

    private var results: [String] { Self.matches(query: query, destinations: destinations) }

    /// Enter: elige el primer resultado o —si no hay ninguno— crea la categoría escrita (F14.0).
    private func submit() {
        if let first = results.first {
            onSelect(first)
        } else if let onCreate, let newName = Self.sanitizedName(from: query) {
            onCreate(newName)
        }
    }

    /// Nombre de categoría a partir de lo escrito: sin barras/dos puntos, espacios colapsados,
    /// sin puntos en los extremos y con iniciales en mayúscula («␣␣trading␣␣» → «Trading»).
    nonisolated static func sanitizedName(from query: String) -> String? {
        var name = query
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "\\", with: " ")
            .replacingOccurrences(of: ":", with: " ")
        name = name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !name.isEmpty else { return nil }
        return String(name.prefix(60)).capitalized(with: Locale(identifier: "es_ES"))
    }

    /// Cotejo puro (testeable): sin acentos ni mayúsculas, **todos** los términos de la búsqueda
    /// deben aparecer en la ruta; se conserva el orden de la taxonomía (padres antes que hijos),
    /// así «trabajo» devuelve `05_Trabajo` y a continuación sus subcarpetas.
    nonisolated static func matches(query: String, destinations: [String]) -> [String] {
        let cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return destinations }
        let terms = fold(cleaned)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return destinations }
        return destinations.filter { destination in
            let folded = fold(destination)
            return terms.allSatisfy { folded.contains($0) }
        }
    }

    nonisolated static func fold(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
    }
}
