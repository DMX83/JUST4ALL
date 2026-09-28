import Foundation
import Darwin

public enum VolumeKind: String, Codable {
    case ssdLike = "SSDLike"
    case hddLike = "HDDLike"
    case networkLike = "NetworkLike"
    case unknown = "Unknown"
}

public struct VolumeProfileProbeResult: Hashable {
    public let url: URL
    public let mountPoint: String
    public let fileSystemType: String
    public let isReadOnly: Bool
    public let isRemovable: Bool
    public let isNetwork: Bool
    public let kind: VolumeKind

    public init(
        url: URL,
        mountPoint: String,
        fileSystemType: String,
        isReadOnly: Bool,
        isRemovable: Bool,
        isNetwork: Bool,
        kind: VolumeKind
    ) {
        self.url = url
        self.mountPoint = mountPoint
        self.fileSystemType = fileSystemType
        self.isReadOnly = isReadOnly
        self.isRemovable = isRemovable
        self.isNetwork = isNetwork
        self.kind = kind
    }

    public var isLikelyNTFS: Bool {
        fileSystemType.lowercased().contains("ntfs")
    }
}

public enum VolumeProfileProbe {
    public static func probe(for url: URL) -> VolumeProfileProbeResult? {
        let path = url.path
        var fs = statfs()
        let rc = path.withCString { statfs($0, &fs) }
        guard rc == 0 else { return nil }

        let fsType = withUnsafePointer(to: &fs.f_fstypename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSNAMELEN)) {
                String(cString: $0)
            }
        }

        let mount = withUnsafePointer(to: &fs.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MNAMELEN)) {
                String(cString: $0)
            }
        }

        let lower = fsType.lowercased()
        let isReadOnly = (fs.f_flags & UInt32(MNT_RDONLY)) != 0
        let isNetwork = lower.contains("smb") || lower.contains("nfs") || lower.contains("webdav") || lower.contains("afp")
        let isRemovable = (try? url.resourceValues(forKeys: [.volumeIsRemovableKey]).volumeIsRemovable) ?? false

        let kind: VolumeKind
        if isNetwork {
            kind = .networkLike
        } else if lower.contains("apfs") {
            kind = .ssdLike
        } else if lower.contains("hfs") || lower.contains("exfat") || lower.contains("msdos") || lower.contains("ntfs") {
            kind = .hddLike
        } else {
            kind = .unknown
        }

        return VolumeProfileProbeResult(
            url: url,
            mountPoint: mount,
            fileSystemType: fsType,
            isReadOnly: isReadOnly,
            isRemovable: isRemovable,
            isNetwork: isNetwork,
            kind: kind
        )
    }
}

public enum MountFlagsCheck {
    public static func ensureWritableDestination(_ dstURL: URL) throws {
        guard let profile = VolumeProfileProbe.probe(for: dstURL) else {
            throw NSError(
                domain: "J4FFileSystem",
                code: 3101,
                userInfo: [NSLocalizedDescriptionKey: "No se pudo inspeccionar el volumen de destino."]
            )
        }

        if profile.isReadOnly {
            var message = "El volumen destino esta en solo lectura (\(profile.fileSystemType))."
            if profile.isLikelyNTFS {
                message += " Posible volumen NTFS sin soporte de escritura."
            }
            throw NSError(domain: "J4FFileSystem", code: 3102, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
