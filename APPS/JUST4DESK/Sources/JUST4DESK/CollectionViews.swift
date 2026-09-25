import SwiftUI
import J4ICore

/// G5 — Alta/edición de una colección: nombre + búsqueda guardada.
///
/// Se usa desde la tarjeta «Colecciones» de Inicio (nueva/editar) y desde la ventana «Buscar»
/// (guardar la búsqueda actual). No mueve nada: solo guarda la consulta.
struct CollectionEditorSheet: View {
    let title: String
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var query: String

    init(editing: SavedCollection? = nil, defaultQuery: String = "", onSave: @escaping (String, String) -> Void) {
        self.title = editing == nil ? "Nueva colección" : "Editar colección"
        self.onSave = onSave
        _name = State(initialValue: editing?.name ?? "")
        _query = State(initialValue: editing?.query ?? defaultQuery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: J4I.Space.m) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("Una colección es una búsqueda con nombre: organiza sin mover nada y se abre con un clic desde Inicio o el omnibox.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Nombre:")
                        .font(.system(size: 12))
                        .frame(width: 66, alignment: .leading)
                    TextField("Trading, Fiscal 2026…", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
                HStack(spacing: 8) {
                    Text("Búsqueda:")
                        .font(.system(size: 12))
                        .frame(width: 66, alignment: .leading)
                    TextField("trading, factura, .rsc…", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                }
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Guardar") {
                    onSave(name, query)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(J4I.Space.l)
        .frame(width: 450)
    }
}
