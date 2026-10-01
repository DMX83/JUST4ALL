import XCTest

import LifeOSAPI
import TestSupport

/// Voz: el cuerpo `multipart/form-data` que se manda y lo que se lee de vuelta.
///
/// El formato del cuerpo importa: si el límite (`boundary`) o los saltos de línea
/// no son exactos, el servidor responde 422 aunque el audio sea correcto. Se
/// comprueba la estructura, no «que no pete».
final class AudioContractTests: XCTestCase {
    private let base = URL(string: "https://lifeos.example")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func makeClient() -> APIClient {
        APIClient(baseURL: base, token: "t", session: StubURLProtocol.session())
    }

    // MARK: - El cuerpo

    func testMultipartBodyHasTheShapeTheServerExpects() {
        let audio = Data([0x01, 0x02, 0x03, 0x04])
        let body = MultipartFormData.build(
            boundary: "BOUNDARY",
            fields: [(name: "sensitivity", value: "sensitive"), (name: "language", value: "es")],
            file: (name: "file", filename: "nota.m4a", mimeType: "audio/m4a", data: audio)
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.hasPrefix("--BOUNDARY\r\n"), "El cuerpo empieza por el límite")
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"sensitivity\"\r\n\r\nsensitive\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"language\"\r\n\r\nes\r\n"))
        XCTAssertTrue(
            text.contains(
                "Content-Disposition: form-data; name=\"file\"; filename=\"nota.m4a\"\r\nContent-Type: audio/m4a\r\n\r\n"
            )
        )
        XCTAssertTrue(text.hasSuffix("\r\n--BOUNDARY--\r\n"), "Y cierra con el límite final")
        XCTAssertTrue(body.range(of: audio) != nil, "Los bytes del audio van tal cual, sin codificar")
        XCTAssertFalse(text.contains("\n\n"), "Los saltos son \\r\\n, no \\n")
    }

    func testBoundariesAreUnique() {
        XCTAssertNotEqual(MultipartFormData.makeBoundary(), MultipartFormData.makeBoundary())
    }

    // MARK: - La subida

    func testUploadSendsTheFileAndTheFields() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 202, body: Data(
                #"{"id":"c1","status":"stored_sensitive","transcript":null,"original_preserved":true}"#.utf8
            ))
        }

        let capture = try await makeClient().createAudioCapture(
            data: Data([0xAA, 0xBB]),
            filename: "nota.m4a",
            sensitivity: "sensitive"
        )

        XCTAssertEqual(capture.status, "stored_sensitive")
        XCTAssertTrue(capture.isStoredOnly)
        XCTAssertNil(capture.transcript)
        XCTAssertTrue(capture.originalPreserved)

        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/captures/audio")
        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="), contentType)
        let body = try XCTUnwrap(StubURLProtocol.body(of: request))
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("filename=\"nota.m4a\""))
    }

    func testTranscriptComesBackWhenItIsNotSensitive() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 202, body: Data(
                #"{"id":"c2","status":"pending","transcript":"Llamar al fisio mañana","original_preserved":true}"#.utf8
            ))
        }

        let capture = try await makeClient().createAudioCapture(data: Data([0x01]), filename: "nota.m4a")

        XCTAssertEqual(capture.transcript, "Llamar al fisio mañana")
        XCTAssertTrue(capture.isPending)
        XCTAssertFalse(capture.isStoredOnly)
        XCTAssertEqual(capture.statusLabel, "En la bandeja, por clasificar")
    }

    func testFailedTranscriptionIsReportedAsSuch() async throws {
        StubURLProtocol.handler = { _ in
            StubURLProtocol.Stub(status: 202, body: Data(
                #"{"id":"c3","status":"transcription_failed","transcript":null,"original_preserved":true}"#.utf8
            ))
        }

        let capture = try await makeClient().createAudioCapture(data: Data([0x01]), filename: "nota.m4a")

        XCTAssertTrue(capture.didFailTranscription)
        XCTAssertNil(capture.transcript)
        XCTAssertEqual(capture.statusLabel, "No se pudo transcribir")
    }
}
