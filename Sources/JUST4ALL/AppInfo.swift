import Foundation

enum AppInfo {
    static let githubOwner = "DMX83"
    static let githubRepo = "JUST4ALL"

    static var suiteVersion: String {
        // Driven by Xcode MARKETING_VERSION / Info.plist substitution.
        let dict = Bundle.main.infoDictionary
        return (dict?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    static var suiteReleaseTag: String { "v" + suiteVersion }

    static var githubReleaseDownloadBaseURL: String {
        "https://github.com/\(githubOwner)/\(githubRepo)/releases/download/"
    }

    static var githubApiReleasesURL: URL? {
        URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases")
    }
}

