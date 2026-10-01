import AppKit
import CoreGraphics
import Foundation

// Ayuda de QA: imprime las ventanas visibles de LIFEOS como
// `id x y ancho alto`, de mayor a menor.
//
//   swift scripts/window_id.swift            # ventanas
//   swift scripts/window_id.swift --screen   # tamaño lógico de la pantalla
//
// Se usa desde `qa_screenshots.sh`. Ojo: en este Mac `screencapture -l` y
// `screencapture -R` fallan («could not create image from window/rect») aunque la
// captura de pantalla completa sí funciona, así que la revisión visual se hace
// capturando toda la pantalla y recortando la ventana con esos datos.

if CommandLine.arguments.contains("--screen") {
    if let screen = NSScreen.main {
        print("\(Int(screen.frame.width))\t\(Int(screen.frame.height))")
    }
    exit(0)
}

let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

struct Entry {
    let id: Int
    let x: Int
    let y: Int
    let width: Int
    let height: Int
}

var entries: [Entry] = []
for window in list {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    guard owner.uppercased().contains("LIFEOS") else { continue }
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    entries.append(
        Entry(
            id: window[kCGWindowNumber as String] as? Int ?? 0,
            x: Int(bounds["X"] as? Double ?? 0),
            y: Int(bounds["Y"] as? Double ?? 0),
            width: Int(bounds["Width"] as? Double ?? 0),
            height: Int(bounds["Height"] as? Double ?? 0)
        )
    )
}

for entry in entries.sorted(by: { $0.width > $1.width }) {
    print("\(entry.id)\t\(entry.x)\t\(entry.y)\t\(entry.width)\t\(entry.height)")
}
