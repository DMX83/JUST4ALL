import XCTest
@testable import J4FOps

final class J4FErrorTests: XCTestCase {
    func testPassthrough() {
        XCTAssertEqual(J4FError.from(J4FError.cancelled), .cancelled)
        XCTAssertEqual(J4FError.from(J4FError.aiUnavailable(reason: "sin clave")), .aiUnavailable(reason: "sin clave"))
    }

    func testJobOpsDomainMapping() {
        let cancelled = NSError(domain: "J4FOps", code: 2099)
        XCTAssertEqual(J4FError.from(cancelled), .cancelled)

        let conflict = NSError(domain: "J4FOps", code: 2020)
        XCTAssertEqual(J4FError.from(conflict), .conflict(path: nil))

        let config = NSError(domain: "J4FOps", code: 2001, userInfo: [NSLocalizedDescriptionKey: "falta destino"])
        guard case .io(let message) = J4FError.from(config) else {
            return XCTFail("2001 debería mapear a .io")
        }
        XCTAssertTrue(message.contains("falta destino"))
    }

    func testCocoaPermissionAndMissing() {
        let permission = NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadNoPermission.rawValue)
        XCTAssertEqual(J4FError.from(permission), .permissionDenied(path: nil))

        let missing = NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadNoSuchFile.rawValue)
        XCTAssertEqual(J4FError.from(missing), .notFound(path: nil))
    }

    func testCocoaReadOnlyOutOfSpaceAndCancel() {
        let readOnly = NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteVolumeReadOnly.rawValue)
        XCTAssertEqual(J4FError.from(readOnly), .destinationReadOnly(path: nil))

        let noSpace = NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteOutOfSpace.rawValue)
        XCTAssertEqual(J4FError.from(noSpace), .diskFull(path: nil))

        let userCancelled = NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.userCancelled.rawValue)
        XCTAssertEqual(J4FError.from(userCancelled), .cancelled)
    }

    func testPathExtractionFromUserInfo() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.Code.fileReadNoPermission.rawValue,
            userInfo: [NSFilePathErrorKey: "/Users/dmx83/Origen"]
        )
        XCTAssertEqual(J4FError.from(error), .permissionDenied(path: "/Users/dmx83/Origen"))
    }

    func testPosixMapping() {
        let denied = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        XCTAssertEqual(J4FError.from(denied), .permissionDenied(path: nil))

        let readOnly = NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS))
        XCTAssertEqual(J4FError.from(readOnly), .destinationReadOnly(path: nil))

        let noSpace = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        XCTAssertEqual(J4FError.from(noSpace), .diskFull(path: nil))
    }

    func testUnknownKeepsMessage() {
        let error = NSError(domain: "X", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
        guard case .unknown(let message) = J4FError.from(error) else {
            return XCTFail("dominio desconocido debería mapear a .unknown")
        }
        XCTAssertEqual(message, "boom")
        XCTAssertEqual(J4FError.from(error).userMessage, "boom")
    }

    func testUserMessagesAreAlwaysPresent() {
        let samples: [J4FError] = [
            .permissionDenied(path: "/x"),
            .permissionDenied(path: nil),
            .notFound(path: "/x"),
            .destinationReadOnly(path: "/x"),
            .conflict(path: "/x"),
            .diskFull(path: "/x"),
            .cancelled,
            .bookmark(name: "Disco", reason: "stale"),
            .aiUnavailable(reason: "sín clave"),
            .io(message: "EOF"),
            .unknown(message: "")
        ]
        for sample in samples {
            XCTAssertFalse(sample.userMessage.isEmpty, "userMessage vacío en \(sample)")
            XCTAssertFalse(sample.technicalDescription.isEmpty, "technicalDescription vacío en \(sample)")
        }
        XCTAssertEqual(J4FError.unknown(message: "").userMessage, "Ocurrió un error inesperado.")
    }
}
