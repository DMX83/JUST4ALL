import SwiftUI
import AppKit
import UniformTypeIdentifiers
import J4IIndex

/// Fila de resultado: icono + nombre (con resaltado) + ruta + tamaño/fecha.
struct SearchResultRow: View {
    let hit: IndexSearchHit
    let terms: [String]
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: ResultIconCache.icon(for: hit.entry))
                .resizable()
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                SearchHighlight.highlightedText(hit.entry.name, terms: terms)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if hit.matchedSemantically {
                        Label("por significado", systemImage: "sparkles")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(J4I.brand)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(J4I.brandSoft))
                    }
                    if hit.matchedContent {
                        Label("contenido", systemImage: "text.magnifyingglass")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(J4I.brand)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(J4I.brandSoft))
                    }
                    Text(Self.displayPath(for: hit.entry.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let snippet = hit.contentSnippet {
                    SearchHighlight.highlightedText(snippet, terms: terms)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                if hit.entry.isDirectory {
                    Text("carpeta")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(Self.sizeText(hit.entry.sizeBytes))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let modified = hit.entry.modifiedAt {
                    Text(Self.dateText(modified))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .hoverHighlight(cornerRadius: 7, intensity: 0.05)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
    }

    // MARK: - Formato

    static func displayPath(for path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    static func sizeText(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }

    static func dateText(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

/// Cache de iconos por tipo (evita golpear LaunchServices por cada fila).
@MainActor
enum ResultIconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for entry: IndexEntry) -> NSImage {
        let key: NSString = entry.isDirectory ? "__dir__" : (entry.ext.isEmpty ? "__file__" : entry.ext as NSString)
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let type: UTType
        if entry.isDirectory {
            type = .folder
        } else if let extType = UTType(filenameExtension: entry.ext) {
            type = extType
        } else {
            type = .data
        }
        let icon = NSWorkspace.shared.icon(for: type)
        cache.setObject(icon, forKey: key)
        return icon
    }
}
