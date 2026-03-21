import Foundation

enum BuildInfo {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "debug"
    }

    static var buildStamp: String {
        Bundle.main.object(forInfoDictionaryKey: "J4ABuildStamp") as? String ?? "local"
    }

    static var displayLabel: String {
        "v\(marketingVersion) · build \(buildVersion) · \(buildStamp) · AE-AUTO"
    }
}
