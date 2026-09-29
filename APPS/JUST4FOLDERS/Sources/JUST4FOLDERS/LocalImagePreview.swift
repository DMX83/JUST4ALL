import AppKit
import ImageIO
import UniformTypeIdentifiers

/// v2.3.8 — carga LOCAL de imágenes para la vista previa lateral.
///
/// Motivo: `QLPreviewView` puede contestar «sin vista previa» (icono genérico del tipo de
/// fichero) la primera vez que se le pide un fichero recién creado — el caso típico justo
/// después de «Mejorar con JUST4PICT» o de convertir/reconvertir una imagen: QuickLook aún no
/// tiene el fichero en su base y el icono genérico se quedaba pegado hasta cambiar la selección.
/// Para imágenes (que no necesitan controles de QuickLook) las pintamos nosotros con
/// ImageIO, que además aplica la orientación EXIF y reduce el tamaño para no cargar en memoria
/// una foto completa de 50 MP.
enum LocalImagePreview {

    /// ¿La URL apunta a una imagen reconocible por el sistema?
    static func isImage(_ url: URL) -> Bool {
        guard let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) else {
            return false
        }
        return type.conforms(to: .image)
    }

    /// Imagen lista para pintar (con la orientación EXIF aplicada y sin superar `maxPixelSize`).
    static func image(at url: URL, maxPixelSize: CGFloat = 2600) -> NSImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              cgImage.width > 0, cgImage.height > 0 else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
