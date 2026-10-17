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

    static let appBg         = adaptive(dark: "12141A", light: "F7F8FA")
    static let sidebarBg     = adaptive(dark: "0D0F14", light: "EEF1F5")
    static let hoverBg       = adaptive(dark: "20242D", light: "E7EBF1")
    static let selectedBg    = adaptive(dark: "292F3B", light: "DCE5F2")
    static let playerBg      = adaptive(dark: "0B0D12", light: "F1F3F6")
    static let surfaceBg     = adaptive(dark: "191C23", light: "FFFFFF")
    static let elevatedBg    = adaptive(dark: "20242D", light: "F8FAFC")
    static let primaryText   = adaptive(dark: "F4F6F8", light: "171A21")
    static let secondaryText = adaptive(dark: "B2B8C2", light: "505866")
    static let tertiaryText  = adaptive(dark: "7F8794", light: "778190")
    static let accent        = adaptive(dark: "7EB1FF", light: "2868B2")
    static let divider       = adaptive(dark: "292D36", light: "D8DEE7")
    static let subtleBorder  = adaptive(dark: "303641", light: "DCE2EA")

    // Play button: inverted bg so it always pops against the player bar
    static let playBtnBg     = adaptive(dark: "F4F6F8", light: "1D2633")
    static let playBtnFg     = adaptive(dark: "12141A", light: "FFFFFF")

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
    var compactAge: String {
        let seconds = max(0, -timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if seconds < 3600 { return "\(minutes) \(minutes == 1 ? "minute" : "minutes") ago" }
        let hours = Int(seconds / 3600)
        if seconds < 86_400 { return "\(hours) \(hours == 1 ? "hour" : "hours") ago" }
        let days = Int(seconds / 86_400)
        if days < 14 { return "\(days) \(days == 1 ? "day" : "days") ago" }
        let weeks = days / 7
        if days < 30 { return "\(weeks) \(weeks == 1 ? "week" : "weeks") ago" }
        let months = days / 30
        if days < 730 { return "\(months) \(months == 1 ? "month" : "months") ago" }
        let years = days / 365
        return "\(years) \(years == 1 ? "year" : "years") ago"
    }

    var compactCalendarDate: String {
        Calendar.current.isDate(self, equalTo: Date(), toGranularity: .year)
            ? formatted(.dateTime.month(.abbreviated).day())
            : formatted(.dateTime.month(.abbreviated).day().year())
    }

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

    /// Compact menu-bar timestamp: "Today at 14:32", "Yesterday at 09:10", or "17 Aug at 18:45".
    var menuSavedDate: String {
        let calendar = Calendar.current
        let time = formatted(.dateTime.hour().minute())
        if calendar.isDateInToday(self) { return "today at \(time)" }
        if calendar.isDateInYesterday(self) { return "yesterday at \(time)" }
        let sameYear = calendar.isDate(self, equalTo: Date(), toGranularity: .year)
        let day = sameYear
            ? formatted(.dateTime.day().month(.abbreviated))
            : formatted(.dateTime.day().month(.abbreviated).year())
        return "\(day) at \(time)"
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

    var estimatedWorkLabel: String {
        guard self > 0 else { return "—" }
        let minutes = max(15, Int((self / 900).rounded()) * 15)
        if minutes < 60 { return "~\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "~\(hours)h" : "~\(hours)h \(remainder)m"
    }
}

// MARK: - KeyEquivalent helpers

extension KeyEquivalent {
    static let f1 = KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey)!))
}

