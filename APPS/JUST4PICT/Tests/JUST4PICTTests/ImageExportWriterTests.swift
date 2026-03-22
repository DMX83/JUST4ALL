import XCTest
import AppKit
@testable import JUST4PICT

final class ImageExportWriterTests: XCTestCase {
    func testNSImageWriteHonorsWebLiteResizeAndByteBudget() throws {
        let writer = ImageExportWriter()
        let inputImage = makeSolidImage(width: 2600, height: 1800)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")

        defer { try? FileManager.default.removeItem(at: outputURL) }

        try writer.write(
            image: inputImage,
            to: outputURL,
            format: .jpg,
            quality: 0.92,
            exportProfile: .webLite,
            preset: .auto
        )

        let writtenSize = try pixelSize(for: outputURL)
        let fileSize = try XCTUnwrap(outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)

        XCTAssertEqual(writtenSize.width, 1280)
        XCTAssertEqual(writtenSize.height, 887)
        XCTAssertLessThanOrEqual(fileSize, 300_000)
    }

    private func pixelSize(for url: URL) throws -> (width: Int, height: Int) {
        guard let image = NSImage(contentsOf: url),
              let rep = image.representations.first else {
            throw XCTSkip("Could not inspect image at \(url.path)")
        }
        return (rep.pixelsWide, rep.pixelsHigh)
    }

    private func makeSolidImage(width: Int, height: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor(calibratedRed: 0.85, green: 0.86, blue: 0.88, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.unlockFocus()
        return image
    }
}
