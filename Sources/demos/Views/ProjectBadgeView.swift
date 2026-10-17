import SwiftUI

/// Meaningful project badge replacing the redundant [AL] badge.
/// Displays production stage (MIX, MST, DONE, IDEA), version iteration (v2, v8, 3v),
/// or demo status (DEMO) with crisp DAW-style color coding.
struct ProjectBadgeView: View {
    let project: Project
    @EnvironmentObject private var progressStore: ProjectProgressStore

    private var badgeData: (text: String, bg: Color, textCol: Color, border: Color) {
        let progress = progressStore.progress(for: project)

        // 1. Production Stage if progressed past initial idea
        switch progress.stage {
        case .done:
            return ("DONE", Color(red: 0.10, green: 0.26, blue: 0.16), Color(red: 0.40, green: 0.90, blue: 0.55), Color.green.opacity(0.4))
        case .master:
            return ("MST", Color(red: 0.24, green: 0.14, blue: 0.32), Color(red: 0.85, green: 0.65, blue: 1.0), Color.purple.opacity(0.4))
        case .mix:
            return ("MIX", Color(red: 0.10, green: 0.22, blue: 0.32), Color(red: 0.45, green: 0.80, blue: 1.0), Color.blue.opacity(0.4))
        case .fullTrack:
            return ("ARRG", Color(red: 0.24, green: 0.20, blue: 0.12), Color(red: 0.95, green: 0.80, blue: 0.45), Color.orange.opacity(0.4))
        case .structure:
            return ("STRUC", Color(red: 0.22, green: 0.18, blue: 0.14), Color(red: 0.90, green: 0.70, blue: 0.50), Color.orange.opacity(0.35))
        case .spark:
            break
        }

        // 2. Version Iteration extracted from filename / project name (e.g. "v3", "v8", "v2.1")
        if let extracted = extractVersionNumber(from: project.name) {
            return (extracted, Color(red: 0.18, green: 0.19, blue: 0.22), Color.white, Color.white.opacity(0.18))
        }

        if let newest = project.newestAbletonVersion,
           let extracted = extractVersionNumber(from: newest.displayName) {
            return (extracted, Color(red: 0.18, green: 0.19, blue: 0.22), Color.white, Color.white.opacity(0.18))
        }

        // 3. Multi-version count (e.g. "3v", "5v")
        if project.versions.count > 1 {
            return ("\(project.versions.count)v", Color(red: 0.18, green: 0.19, blue: 0.22), Color.white, Color.white.opacity(0.18))
        }

        // 4. Has Audio Demo / Export
        if project.hasExports {
            return ("DEMO", Color(red: 0.26, green: 0.18, blue: 0.10), Color.accent, Color.accent.opacity(0.4))
        }

        // 5. Default initial version
        return ("v1", Color(red: 0.18, green: 0.19, blue: 0.22), Color.secondaryText, Color.white.opacity(0.14))
    }

    private func extractVersionNumber(from string: String) -> String? {
        let pattern = #"(?i)(?:^|[\s_\-\.])v([0-9]+(?:\.[0-9]+)?)(?:[\s_\-\.]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length)),
              match.range(at: 1).location != NSNotFound else {
            return nil
        }
        let num = (string as NSString).substring(with: match.range(at: 1))
        return "v\(num)"
    }

    var body: some View {
        let info = badgeData
        Text(info.text)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundColor(info.textCol)
            .padding(.horizontal, 4.5)
            .padding(.vertical, 2)
            .background(info.bg)
            .clipShape(RoundedRectangle(cornerRadius: 3.5))
            .overlay {
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(info.border, lineWidth: 0.6)
            }
    }
}
