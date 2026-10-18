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

enum PetPuckSize: String, CaseIterable, Identifiable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case extraLarge = "extraLarge"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small (40 pt)"
        case .medium: return "Medium (52 pt)"
        case .large: return "Large (68 pt)"
        case .extraLarge: return "Extra Large (88 pt)"
        }
    }

    var dimension: CGFloat {
        switch self {
        case .small: return 40
        case .medium: return 52
        case .large: return 68
        case .extraLarge: return 88
        }
    }

    var iconDimension: CGFloat {
        switch self {
        case .small: return 36
        case .medium: return 48
        case .large: return 62
        case .extraLarge: return 80
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small: return 8
        case .medium: return 11
        case .large: return 14
        case .extraLarge: return 18
        }
    }

    var dotSize: CGFloat {
        switch self {
        case .small: return 7
        case .medium: return 10
        case .large: return 12
        case .extraLarge: return 15
        }
    }

    var dotOffset: (x: CGFloat, y: CGFloat) {
        switch self {
        case .small: return (13, -13)
        case .medium: return (17, -17)
        case .large: return (22, -22)
        case .extraLarge: return (28, -28)
        }
    }

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var cueIconSize: CGFloat {
        switch self {
        case .small: return 9
        case .medium: return 11
        case .large: return 14
        case .extraLarge: return 18
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
    @Published var showInlineWaveforms: Bool {
        didSet { UserDefaults.standard.set(showInlineWaveforms, forKey: "showInlineWaveforms") }
    }
    @Published var isFloatingWidgetActive: Bool {
        didSet { UserDefaults.standard.set(isFloatingWidgetActive, forKey: "isFloatingWidgetActive") }
    }
    @Published var isFloatingWidgetPinned: Bool {
        didSet { UserDefaults.standard.set(isFloatingWidgetPinned, forKey: "isFloatingWidgetPinned") }
    }
    @Published var isFloatingWidgetCollapsed: Bool {
        didSet { UserDefaults.standard.set(isFloatingWidgetCollapsed, forKey: "isFloatingWidgetCollapsed") }
    }
    @Published var petPuckSize: PetPuckSize {
        didSet {
            UserDefaults.standard.set(petPuckSize.rawValue, forKey: "petPuckSize")
            DispatchQueue.main.async {
                WindowPresenter.updateFloatingWidgetPuckSize(self.petPuckSize.dimension)
            }
        }
    }

    init() {
        let rawMode  = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        let rawWidth = UserDefaults.standard.double(forKey: "sidebarWidth")
        let storedWaveforms = UserDefaults.standard.object(forKey: "showInlineWaveforms") as? Bool

        appearanceMode = AppearanceMode(rawValue: rawMode) ?? .system
        sidebarWidth   = rawWidth > 0 ? CGFloat(rawWidth) : 260
        showInlineWaveforms = storedWaveforms ?? true

        if let storedActive = UserDefaults.standard.object(forKey: "isFloatingWidgetActive") as? Bool {
            isFloatingWidgetActive = storedActive
        } else {
            isFloatingWidgetActive = true
        }

        if let storedPinned = UserDefaults.standard.object(forKey: "isFloatingWidgetPinned") as? Bool {
            isFloatingWidgetPinned = storedPinned
        } else {
            isFloatingWidgetPinned = true
        }

        if let storedCollapsed = UserDefaults.standard.object(forKey: "isFloatingWidgetCollapsed") as? Bool {
            isFloatingWidgetCollapsed = storedCollapsed
        } else {
            isFloatingWidgetCollapsed = false
        }

        let rawPuckSize = UserDefaults.standard.string(forKey: "petPuckSize") ?? "medium"
        petPuckSize = PetPuckSize(rawValue: rawPuckSize) ?? .medium
    }
}

