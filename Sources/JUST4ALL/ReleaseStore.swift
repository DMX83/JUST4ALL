import Foundation

struct SubAppReleaseAsset: Hashable {
    let version: SemVer
    let fileName: String
    let downloadURL: URL
    let sha256: String
}

@MainActor
final class ReleaseStore: ObservableObject {
    @Published private(set) var assetsByPrefix: [String: SubAppReleaseAsset] = [:]
    @Published private(set) var lastError: String? = nil

    func refresh() async {
        lastError = nil

        guard let releasesURL = AppInfo.githubApiReleasesURL else {
            lastError = "URL de GitHub API invalida."
            return
        }

        do {
            var request = URLRequest(url: releasesURL)
            request.setValue("JUST4ALL", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                lastError = "GitHub API error HTTP \(http.statusCode)."
                return
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let releases = try decoder.decode([GitHubRelease].self, from: data)

            // Pick the best (highest SemVer) DMG per prefix across the releases list.
            var best: [String: (SemVer, GitHubRelease.Asset, GitHubRelease)] = [:]
            let prefixes = Set(SubAppsCatalog.items.map(\.assetPrefix))

            for release in releases {
                if release.draft || release.prerelease { continue }
                for asset in release.assets {
                    guard let match = parseDmgAsset(asset.name, allowedPrefixes: prefixes) else { continue }
                    let existing = best[match.prefix]
                    if existing == nil || match.version > existing!.0 {
                        best[match.prefix] = (match.version, asset, release)
                    }
                }
            }

            // Fetch SHA256SUMS for each selected release (small file), then publish assets.
            var resolved: [String: SubAppReleaseAsset] = [:]
            for (prefix, (ver, asset, release)) in best {
                guard let sumsAsset = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }),
                      let sumsURL = URL(string: sumsAsset.browserDownloadUrl)
                else { continue }

                let sumsText = try await fetchText(url: sumsURL)
                let sums = parseSha256Sums(sumsText)
                guard let sha = sums[asset.name],
                      let dmgURL = URL(string: asset.browserDownloadUrl)
                else { continue }

                resolved[prefix] = SubAppReleaseAsset(
                    version: ver,
                    fileName: asset.name,
                    downloadURL: dmgURL,
                    sha256: sha
                )
            }

            assetsByPrefix = resolved
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func fetchText(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("JUST4ALL", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(domain: "ReleaseStore", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func parseSha256Sums(_ text: String) -> [String: String] {
        // Format: "<hex>  <filename>"
        var out: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if parts.count < 2 { continue }
            let hex = String(parts[0]).lowercased()
            let file = String(parts[1])
            if hex.count == 64 {
                out[file] = hex
            }
        }
        return out
    }

    private struct DmgMatch {
        let prefix: String
        let version: SemVer
    }

    private func parseDmgAsset(_ name: String, allowedPrefixes: Set<String>) -> DmgMatch? {
        guard name.hasSuffix(".dmg") else { return nil }
        // Example: JUST4PDF-0.1.0.dmg
        for prefix in allowedPrefixes {
            let needle = prefix + "-"
            guard name.hasPrefix(needle) else { continue }
            let verStr = String(name.dropFirst(needle.count).dropLast(".dmg".count))
            guard let ver = SemVer(verStr) else { continue }
            return DmgMatch(prefix: prefix, version: ver)
        }
        return nil
    }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String
        let size: Int?
    }

    let tagName: String
    let prerelease: Bool
    let draft: Bool
    let assets: [Asset]
}
