import SwiftUI
import AppKit

// MARK: - Adaptive colour helpers

extension Color {
    /// Creates a Color that automatically picks between dark/light hex values
    /// based on the current macOS appearance — responds to SwiftUI's .preferredColorScheme().
    static func adaptive(dark darkHex: String, light lightHex: String) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsColor(hex: isDark ? darkHex : lightHex)
        }))
    }

    private static func nsColor(hex: String) -> NSColor {
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        return NSColor(
            srgbRed:   CGFloat((int >> 16) & 0xFF) / 255,
            green:     CGFloat((int >> 8)  & 0xFF) / 255,
            blue:      CGFloat( int        & 0xFF) / 255,
            alpha: 1
        )
    }

    init(hex: String) {
        var int: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8)*17, (int >> 4 & 0xF)*17, (int & 0xF)*17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:(a, r, g, b) = (255, 255, 255, 255)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }

    // MARK: - App palette (adaptive dark ↔ light)

    static let appBg         = adaptive(dark: "111111", light: "F5F5F7")
    static let sidebarBg     = adaptive(dark: "0C0C0C", light: "ECEEF0")
    static let hoverBg       = adaptive(dark: "1E1E1E", light: "E2E4E7")
    static let selectedBg    = adaptive(dark: "272727", light: "D8DADD")
    static let playerBg      = adaptive(dark: "0A0A0A", light: "E8E8EA")
    static let primaryText   = adaptive(dark: "EFEFEF", light: "1C1C1E")
    static let secondaryText = adaptive(dark: "6E6E6E", light: "52525A")  // improved contrast
    static let tertiaryText  = adaptive(dark: "4A4A4A", light: "9A9A9E")  // improved contrast
    static let accent        = adaptive(dark: "C4A3FF", light: "7048D4")  // lavender → deep purple
    static let divider       = adaptive(dark: "1E1E1E", light: "D1D1D6")

    // Play button: inverted bg so it always pops against the player bar
    static let playBtnBg     = adaptive(dark: "EFEFEF", light: "1C1C1E")
    static let playBtnFg     = adaptive(dark: "111111", light: "F5F5F7")

    // Seek bar track
    static let seekTrack      = adaptive(dark: "FFFFFF0D", light: "0000001A")  // 5 % white / 10 % black

    // MARK: - Finder tag colours (not appearance-adaptive — always saturated)
    static func finderTagColor(_ tagName: String) -> Color? {
        switch tagName {
        case "Red":    return Color(hex: "FF453A")
        case "Orange": return Color(hex: "FF9F0A")
        case "Yellow": return Color(hex: "FFD60A")
        case "Green":  return Color(hex: "30D158")
        case "Blue":   return Color(hex: "0A84FF")
        case "Purple": return Color(hex: "BF5AF2")
        case "Gray":   return Color(hex: "98989D")
        default:       return nil
        }
    }
}

// MARK: - Date formatting

extension Date {
    /// Compact sidebar label: "2h ago", "3d ago", "Jan 15", "2023"
    var relativeShort: String {
        let secs = -timeIntervalSinceNow
        if secs < 60     { return "just now" }
        if secs < 3600   { return "\(Int(secs / 60))m ago" }
        if secs < 86400  { return "\(Int(secs / 3600))h ago" }
        if secs < 604800 { return "\(Int(secs / 86400))d ago" }
        let cal = Calendar.current
        if cal.isDate(self, equalTo: Date(), toGranularity: .year) {
            return formatted(.dateTime.month(.abbreviated).day())
        }
        return formatted(.dateTime.year())
    }

    /// Verbose relative; shows parenthetical date once older than a week.
    /// "3 days ago" · "2 weeks ago (March 2)" · "4 months ago (November 5, 2024)"
    var relativeFull: String {
        let secs = -timeIntervalSinceNow
        if secs < 60    { return "just now" }
        let mins = Int(secs / 60)
        if secs < 3600  { return "\(mins) \(mins == 1 ? "minute" : "minutes") ago" }
        let hrs  = Int(secs / 3600)
        if secs < 86400 { return "\(hrs) \(hrs == 1 ? "hour" : "hours") ago" }
        let days = Int(secs / 86400)
        if days == 1    { return "yesterday" }
        if days < 7     { return "\(days) days ago" }

        let sameYear = Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year)
        let dateStr  = sameYear
            ? formatted(.dateTime.month(.wide).day())
            : formatted(.dateTime.month(.wide).day().year())

        let weeks  = days / 7
        if days < 14  { return "1 week ago (\(dateStr))" }
        if days < 30  { return "\(weeks) weeks ago (\(dateStr))" }
        let months = days / 30
        if days < 60  { return "1 month ago (\(dateStr))" }
        if days < 365 { return "\(months) months ago (\(dateStr))" }
        let years  = days / 365
        if days < 730 { return "1 year ago (\(dateStr))" }
        return "\(years) years ago (\(dateStr))"
    }

    /// Full absolute date + time: "March 16, 2025 at 3:45 PM"
    var fullDateTime: String {
        formatted(.dateTime.month(.wide).day().year().hour().minute())
    }
}

// MARK: - TimeInterval

extension TimeInterval {
    var mmss: String {
        guard isFinite && self >= 0 else { return "--:--" }
        let m = Int(self) / 60
        let s = Int(self) % 60
        return String(format: "%d:%02d", m, s)
    }
}
