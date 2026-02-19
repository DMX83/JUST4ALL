import Foundation

public struct VolumeInfo: Hashable {
    public let fileSystemType: String
    public let isReadOnly: Bool
    public let isLikelyNTFS: Bool

    public init(fileSystemType: String, isReadOnly: Bool, isLikelyNTFS: Bool) {
        self.fileSystemType = fileSystemType
        self.isReadOnly = isReadOnly
        self.isLikelyNTFS = isLikelyNTFS
    }
}

public enum VolumeInspector {
    public static func inspect(url: URL) -> VolumeInfo? {
        guard let profile = VolumeProfileProbe.probe(for: url) else { return nil }

        return VolumeInfo(
            fileSystemType: profile.fileSystemType,
            isReadOnly: profile.isReadOnly,
            isLikelyNTFS: profile.isLikelyNTFS
        )
    }
}
