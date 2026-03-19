import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case dark   = "Dark"
    case light  = "Light"

    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    // Cycles system → dark → light → system
    var next: AppearanceMode {
        switch self {
        case .system: return .dark
        case .dark:   return .light
        case .light:  return .system
        }
    }
}

class SettingsStore: ObservableObject {
    @Published var appearanceMode: AppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode") }
    }
    @Published var sidebarWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(sidebarWidth), forKey: "sidebarWidth") }
    }

    init() {
        let rawMode  = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        let rawWidth = UserDefaults.standard.double(forKey: "sidebarWidth")

        appearanceMode = AppearanceMode(rawValue: rawMode) ?? .system
        sidebarWidth   = rawWidth > 0 ? CGFloat(rawWidth) : 260
    }
}
