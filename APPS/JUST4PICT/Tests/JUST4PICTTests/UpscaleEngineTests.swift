import XCTest
@testable import JUST4PICT

final class UpscaleEngineTests: XCTestCase {
    func testResolveBackendFallsBackToLocalWhenBinaryIsUnavailable() {
        let resolution = UpscaleEngine.resolveBackend(
            environment: [:],
            currentLongSide: 900,
            targetLongSide: 2200
        )

        XCTAssertEqual(resolution, UpscaleBackendResolution(backend: .localLanczos, scaleFactor: nil))
    }

    func testResolveBackendPrefersRealESRGANForSmallImagesWhenBinaryExists() throws {
        let fakeBinary = try makeFakeExecutable()
        let fakeModels = try makeFakeModels()
        defer { try? FileManager.default.removeItem(at: fakeBinary) }
        defer { try? FileManager.default.removeItem(at: fakeModels) }

        let resolution = UpscaleEngine.resolveBackend(
            environment: [
                "JUST4PICT_REAL_ESRGAN_BIN": fakeBinary.path,
                "JUST4PICT_REAL_ESRGAN_MODELS": fakeModels.path
            ],
            currentLongSide: 900,
            targetLongSide: 2200
        )

        XCTAssertEqual(resolution, UpscaleBackendResolution(backend: .realESRGAN, scaleFactor: 4))
    }

    func testResolveBackendKeepsLocalForLargeInputsEvenIfBinaryExists() throws {
        let fakeBinary = try makeFakeExecutable()
        let fakeModels = try makeFakeModels()
        defer { try? FileManager.default.removeItem(at: fakeBinary) }
        defer { try? FileManager.default.removeItem(at: fakeModels) }

        let resolution = UpscaleEngine.resolveBackend(
            environment: [
                "JUST4PICT_REAL_ESRGAN_BIN": fakeBinary.path,
                "JUST4PICT_REAL_ESRGAN_MODELS": fakeModels.path
            ],
            currentLongSide: 1800,
            targetLongSide: 2600
        )

        XCTAssertEqual(resolution, UpscaleBackendResolution(backend: .localLanczos, scaleFactor: nil))
    }

    private func makeFakeExecutable() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makeFakeModels() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("param".utf8).write(to: directory.appendingPathComponent("realesrgan-x4plus.param"))
        try Data("bin".utf8).write(to: directory.appendingPathComponent("realesrgan-x4plus.bin"))
        return directory
    }
}
