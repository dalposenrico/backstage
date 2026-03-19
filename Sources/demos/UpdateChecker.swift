import Foundation
import SwiftUI

// ── Change this to match your GitHub repo once it's created ──────────────────
private let githubRepo = "enricodalpos/backstage"
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class UpdateChecker: ObservableObject {
    @Published var availableVersion: String? = nil
    @Published var releasePageURL: URL?       = nil
    @Published var isDismissed: Bool          = false

    private let currentVersion: String

    init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        Task { await check() }
    }

    func check() async {
        guard let apiURL = URL(string: "https://api.github.com/repos/\(githubRepo)/releases/latest")
        else { return }

        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let release   = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remote    = release.tagName.trimmingCharacters(in: .init(charactersIn: "vV"))

            if isNewer(remote, than: currentVersion) {
                availableVersion = remote
                releasePageURL   = URL(string: release.htmlURL)
            }
        } catch {
            // Silently ignore — no network, private repo, etc.
        }
    }

    func dismiss() { isDismissed = true }

    // Simple semantic-version comparison: "1.2.0" > "1.1.3"
    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator:  ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
