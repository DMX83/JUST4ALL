import Foundation
import J4FOps

struct DiagnosticsExportResult {
    let archiveURL: URL
    let tempDirectoryURL: URL
}

final class DiagnosticsExporter {
    func createArchive(statusText: String, leftPath: String, rightPath: String) throws -> DiagnosticsExportResult {
        let fm = FileManager.default
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let folder = tempRoot.appendingPathComponent("j4f-diagnostics-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        try writeSummary(to: folder, statusText: statusText, leftPath: leftPath, rightPath: rightPath)
        try writePreferences(to: folder)
        try copyJobSnapshots(to: folder)

        let archive = tempRoot.appendingPathComponent("just4folders-diagnostics-\(timestamp()).zip")
        try zipDirectory(at: folder, into: archive)
        return DiagnosticsExportResult(archiveURL: archive, tempDirectoryURL: folder)
    }

    private func writeSummary(to folder: URL, statusText: String, leftPath: String, rightPath: String) throws {
        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "status": statusText,
            "leftPanelPath": leftPath,
            "rightPanelPath": rightPath,
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
            "buildVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
        ]
        try writeJSON(payload, to: folder.appendingPathComponent("summary.json"))
    }

    private func writePreferences(to folder: URL) throws {
        let prefs = J4FPreferences.load()
        let payload: [String: Any] = [
            "deleteBehavior": prefs.deleteBehavior.rawValue,
            "showHiddenFiles": prefs.showHiddenFiles,
            "preferredBigBufferMB": prefs.preferredBigBufferMB
        ]
        try writeJSON(payload, to: folder.appendingPathComponent("preferences.json"))
    }

    private func copyJobSnapshots(to folder: URL) throws {
        let snapshotsURL = JobSnapshotStore().storageURL
        guard FileManager.default.fileExists(atPath: snapshotsURL.path) else { return }
        let target = folder.appendingPathComponent("job-snapshots.json")
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: snapshotsURL, to: target)
    }

    private func writeJSON(_ payload: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func zipDirectory(at folder: URL, into archive: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: archive.path) {
            try fm.removeItem(at: archive)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = folder.deletingLastPathComponent()
        process.arguments = ["-r", archive.path, folder.lastPathComponent]

        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? "zip failed"
            throw NSError(
                domain: "JUST4FOLDERS",
                code: 5201,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo crear zip de diagnostico: \(errText)"]
            )
        }
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
