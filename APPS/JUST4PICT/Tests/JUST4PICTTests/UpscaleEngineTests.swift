import XCTest
@testable import JUST4PICT

final class UpscaleEngineTests: XCTestCase {
    func testResolveBackendFallsBackToLocalWhenBinaryIsUnavailable() {
        let emptyRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyRoot) }

        let resolution = UpscaleEngine.resolveBackend(
            environment: [:],
            currentDirectoryPath: emptyRoot.path,
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

    func testResolveBackendKeepsLocalWhenExternalBackendIsDisabled() throws {
        let fakeBinary = try makeFakeExecutable()
        let fakeModels = try makeFakeModels()
        defer { try? FileManager.default.removeItem(at: fakeBinary) }
        defer { try? FileManager.default.removeItem(at: fakeModels) }

        let resolution = UpscaleEngine.resolveBackend(
            environment: [
                "JUST4PICT_REAL_ESRGAN_BIN": fakeBinary.path,
                "JUST4PICT_REAL_ESRGAN_MODELS": fakeModels.path
            ],
            preferExternalBackend: false,
            currentLongSide: 900,
            targetLongSide: 2200
        )

        XCTAssertEqual(resolution, UpscaleBackendResolution(backend: .localLanczos, scaleFactor: nil))
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

    func testResolveBackendUsesX4ForModerateUpscaleWhenExternalBackendIsEnabled() throws {
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
            targetLongSide: 1500
        )

        XCTAssertEqual(resolution, UpscaleBackendResolution(backend: .realESRGAN, scaleFactor: 4))
    }

    func testResolveBackendFindsBundledProjectCacheWithoutEnvironmentExports() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let binaryDirectory = root
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("realesrgan", isDirectory: true)
            .appendingPathComponent("realesrgan-ncnn-vulkan-20220424-macos", isDirectory: true)
        let modelsDirectory = binaryDirectory.appendingPathComponent("models", isDirectory: true)
        try FileManager.default.createDirectory(at: binaryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let binaryURL = binaryDirectory.appendingPathComponent("realesrgan-ncnn-vulkan")
        try "#!/bin/sh\nexit 0\n".write(to: binaryURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
        try Data("param".utf8).write(to: modelsDirectory.appendingPathComponent("realesrgan-x4plus.param"))
        try Data("bin".utf8).write(to: modelsDirectory.appendingPathComponent("realesrgan-x4plus.bin"))

        defer { try? FileManager.default.removeItem(at: root) }

        let resolution = UpscaleEngine.resolveBackend(
            environment: [:],
            currentDirectoryPath: root.path,
            allowLocalCacheAutodiscovery: true,
            currentLongSide: 900,
            targetLongSide: 2200
        )

        XCTAssertEqual(resolution, UpscaleBackendResolution(backend: .realESRGAN, scaleFactor: 4))
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
