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
        case .small: return "Small (52 pt)"
        case .medium: return "Medium (72 pt)"
        case .large: return "Large (96 pt)"
        case .extraLarge: return "Extra Large (128 pt)"
        }
    }

    var dimension: CGFloat {
        switch self {
        case .small: return 52
        case .medium: return 72
        case .large: return 96
        case .extraLarge: return 128
        }
    }

    var iconDimension: CGFloat {
        switch self {
        case .small: return 48
        case .medium: return 66
        case .large: return 88
        case .extraLarge: return 118
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small: return 11
        case .medium: return 15
        case .large: return 20
        case .extraLarge: return 26
        }
    }

    var dotSize: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 13
        case .large: return 16
        case .extraLarge: return 20
        }
    }

    var dotOffset: (x: CGFloat, y: CGFloat) {
        switch self {
        case .small: return (17, -17)
        case .medium: return (24, -24)
        case .large: return (31, -31)
        case .extraLarge: return (40, -40)
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
        case .small: return 11
        case .medium: return 15
        case .large: return 19
        case .extraLarge: return 24
        }
    }

    var capsuleWidth: CGFloat {
        switch self {
        case .small: return 175
        case .medium: return 210
        case .large: return 245
        case .extraLarge: return 280
        }
    }

    var capsuleHeight: CGFloat {
        switch self {
        case .small: return 34
        case .medium: return 38
        case .large: return 44
        case .extraLarge: return 50
        }
    }

    var capsuleTitleFontSize: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 13
        case .large: return 14.5
        case .extraLarge: return 16
        }
    }

    var capsuleSubtitleFontSize: CGFloat {
        switch self {
        case .small: return 9.5
        case .medium: return 10
        case .large: return 11
        case .extraLarge: return 12.5
        }
    }

    func totalCollapsedWidth(hasIcon: Bool) -> CGFloat {
        hasIcon ? (dimension + capsuleWidth + 8) : capsuleWidth
    }

    func totalCollapsedHeight(hasIcon: Bool) -> CGFloat {
        hasIcon ? dimension : capsuleHeight
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
    @Published var showAppIconOnPuck: Bool {
        didSet { UserDefaults.standard.set(showAppIconOnPuck, forKey: "showAppIconOnPuck") }
    }
    @Published var showPetPuckProjectCapsule: Bool {
        didSet { UserDefaults.standard.set(showPetPuckProjectCapsule, forKey: "showPetPuckProjectCapsule") }
    }
    @Published var notifyOnAbletonReady: Bool {
        didSet { UserDefaults.standard.set(notifyOnAbletonReady, forKey: "notifyOnAbletonReady") }
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
            isFloatingWidgetCollapsed = true
        }

        if let storedAppIcon = UserDefaults.standard.object(forKey: "showAppIconOnPuck") as? Bool {
            showAppIconOnPuck = storedAppIcon
        } else {
            showAppIconOnPuck = false
        }

        if let storedCapsule = UserDefaults.standard.object(forKey: "showPetPuckProjectCapsule") as? Bool {
            showPetPuckProjectCapsule = storedCapsule
        } else {
            showPetPuckProjectCapsule = true
        }

        if let storedNotify = UserDefaults.standard.object(forKey: "notifyOnAbletonReady") as? Bool {
            notifyOnAbletonReady = storedNotify
        } else {
            notifyOnAbletonReady = true
        }

        let rawPuckSize = UserDefaults.standard.string(forKey: "petPuckSize") ?? "medium"
        petPuckSize = PetPuckSize(rawValue: rawPuckSize) ?? .medium
    }
}

