import Foundation
import PDFKit
import Vision
import AppKit

public struct ExtractionResult: Sendable, Equatable {
    public let text: String
    public let pageCount: Int?
    public let usedOCR: Bool
    public let hasTextLayer: Bool
}

/// Extracción local de texto: PDFKit (con OCR de respaldo), Vision OCR para imágenes,
/// texto plano y docx básico (vía `unzip` del sistema).
public enum TextExtractor {
    public static let maxCharacters = 200_000
    public static let ocrPageLimit = 3
    public static let minimumTextLayerCharacters = 40

    public static func extract(from url: URL, maxCharacters: Int = TextExtractor.maxCharacters) -> ExtractionResult? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return extractPDF(url: url, maxCharacters: maxCharacters)
        case "txt", "md", "csv", "json", "log":
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return ExtractionResult(
                text: String(text.prefix(maxCharacters)),
                pageCount: nil,
                usedOCR: false,
                hasTextLayer: true
            )
        case "rtf":
            guard let data = try? Data(contentsOf: url),
                  let attributed = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                  ) else { return nil }
            return ExtractionResult(
                text: String(attributed.string.prefix(maxCharacters)),
                pageCount: nil,
                usedOCR: false,
                hasTextLayer: true
            )
        case "docx":
            guard let text = docxText(url: url) else { return nil }
            return ExtractionResult(
                text: String(text.prefix(maxCharacters)),
                pageCount: nil,
                usedOCR: false,
                hasTextLayer: true
            )
        case "xlsx":
            guard let text = xlsxText(url: url) else { return nil }
            return ExtractionResult(
                text: String(text.prefix(maxCharacters)),
                pageCount: nil,
                usedOCR: false,
                hasTextLayer: true
            )
        case "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "bmp", "gif", "webp":
            guard let text = ocrImage(url: url) else { return nil }
            return ExtractionResult(
                text: String(text.prefix(maxCharacters)),
                pageCount: 1,
                usedOCR: true,
                hasTextLayer: false
            )
        default:
            return nil
        }
    }

    // MARK: - PDF

    private static func extractPDF(url: URL, maxCharacters: Int) -> ExtractionResult? {
        guard let document = PDFDocument(url: url) else { return nil }
        let pageCount = document.pageCount

        var collected = ""
        for index in 0..<pageCount {
            if let pageText = document.page(at: index)?.string {
                collected += pageText + "\n"
            }
            if collected.count >= maxCharacters { break }
        }
        let textLayer = String(collected.prefix(maxCharacters))
        if textLayer.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumTextLayerCharacters {
            return ExtractionResult(text: textLayer, pageCount: pageCount, usedOCR: false, hasTextLayer: true)
        }

        // Posible escaneado: OCR local de las primeras páginas.
        var ocrText = ""
        for index in 0..<min(pageCount, ocrPageLimit) {
            guard let page = document.page(at: index),
                  let cgImage = renderPageToCGImage(page: page),
                  let pageText = ocr(cgImage: cgImage) else { continue }
            ocrText += pageText + "\n"
            if ocrText.count >= maxCharacters { break }
        }
        let ocrResult = String(ocrText.prefix(maxCharacters))
        if !ocrResult.isEmpty {
            return ExtractionResult(text: ocrResult, pageCount: pageCount, usedOCR: true, hasTextLayer: false)
        }
        return ExtractionResult(text: textLayer, pageCount: pageCount, usedOCR: false, hasTextLayer: false)
    }

    private static func renderPageToCGImage(page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    // MARK: - OCR

    private static func ocrImage(url: URL) -> String? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return ocr(cgImage: cgImage)
    }

    private static func ocr(cgImage: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["es-ES", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    // MARK: - docx

    static func docxText(url: URL) -> String? {
        guard let xml = shellUnzip(url: url, entry: "word/document.xml") else { return nil }
        return textFromDocumentXML(xml)
    }

    /// Convierte `word/document.xml` en texto plano (strip de tags + saltos por párrafo).
    static func textFromDocumentXML(_ xml: String) -> String? {
        var text = xml
        text = text.replacingOccurrences(of: "</w:p>", with: "\n")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - xlsx

    /// Texto de un xlsx: cadenas compartidas (`sharedStrings.xml`) + textos en línea de la
    /// primera hoja. Suficiente para la búsqueda por contenido (no reconstruye la tabla).
    static func xlsxText(url: URL) -> String? {
        var pieces: [String] = []
        if let shared = shellUnzip(url: url, entry: "xl/sharedStrings.xml") {
            pieces.append(contentsOf: textsFromXLSX(xml: shared))
        }
        if let sheet = shellUnzip(url: url, entry: "xl/worksheets/sheet1.xml") {
            pieces.append(contentsOf: textsFromXLSX(xml: sheet))
        }
        let joined = pieces.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    /// Extrae el contenido de los elementos `<t>…</t>` (cadenas compartidas o en línea) y los
    /// des-escapa. Cada texto queda en su propia línea.
    static func textsFromXLSX(xml: String) -> [String] {
        var results: [String] = []
        guard let regex = try? NSRegularExpression(pattern: "<t[^>]*>(.*?)</t>", options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = xml as NSString
        for match in regex.matches(in: xml, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 1 else { continue }
            let text = unescapeXML(ns.substring(with: match.range(at: 1))).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { results.append(text) }
        }
        return results
    }

    private static func unescapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func shellUnzip(url: URL, entry: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entry]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
