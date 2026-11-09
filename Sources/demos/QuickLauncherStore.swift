import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import SwiftUI

public struct QuickLauncherItem: Identifiable, Codable, Equatable {
    public var id: String
    public var title: String
    public var key: String
    public var category: String?
    public var colorHex: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        key: String,
        category: String? = nil,
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.key = key
        self.category = category
        self.colorHex = colorHex
    }
}

public enum KeyCodeHelper {
    public static func keyCode(for keyString: String) -> CGKeyCode? {
        let trimmed = keyString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "1": return CGKeyCode(kVK_ANSI_1) // 18
        case "2": return CGKeyCode(kVK_ANSI_2) // 19
        case "3": return CGKeyCode(kVK_ANSI_3) // 20
        case "4": return CGKeyCode(kVK_ANSI_4) // 21
        case "5": return CGKeyCode(kVK_ANSI_5) // 23
        case "6": return CGKeyCode(kVK_ANSI_6) // 22
        case "7": return CGKeyCode(kVK_ANSI_7) // 26
        case "8": return CGKeyCode(kVK_ANSI_8) // 28
        case "9": return CGKeyCode(kVK_ANSI_9) // 25
        case "0": return CGKeyCode(kVK_ANSI_0) // 29

        case "a": return CGKeyCode(kVK_ANSI_A)
        case "b": return CGKeyCode(kVK_ANSI_B)
        case "c": return CGKeyCode(kVK_ANSI_C)
        case "d": return CGKeyCode(kVK_ANSI_D)
        case "e": return CGKeyCode(kVK_ANSI_E)
        case "f": return CGKeyCode(kVK_ANSI_F)
        case "g": return CGKeyCode(kVK_ANSI_G)
        case "h": return CGKeyCode(kVK_ANSI_H)
        case "i": return CGKeyCode(kVK_ANSI_I)
        case "j": return CGKeyCode(kVK_ANSI_J)
        case "k": return CGKeyCode(kVK_ANSI_K)
        case "l": return CGKeyCode(kVK_ANSI_L)
        case "m": return CGKeyCode(kVK_ANSI_M)
        case "n": return CGKeyCode(kVK_ANSI_N)
        case "o": return CGKeyCode(kVK_ANSI_O)
        case "p": return CGKeyCode(kVK_ANSI_P)
        case "q": return CGKeyCode(kVK_ANSI_Q)
        case "r": return CGKeyCode(kVK_ANSI_R)
        case "s": return CGKeyCode(kVK_ANSI_S)
        case "t": return CGKeyCode(kVK_ANSI_T)
        case "u": return CGKeyCode(kVK_ANSI_U)
        case "v": return CGKeyCode(kVK_ANSI_V)
        case "w": return CGKeyCode(kVK_ANSI_W)
        case "x": return CGKeyCode(kVK_ANSI_X)
        case "y": return CGKeyCode(kVK_ANSI_Y)
        case "z": return CGKeyCode(kVK_ANSI_Z)

        case "f1": return CGKeyCode(kVK_F1)
        case "f2": return CGKeyCode(kVK_F2)
        case "f3": return CGKeyCode(kVK_F3)
        case "f4": return CGKeyCode(kVK_F4)
        case "f5": return CGKeyCode(kVK_F5)
        case "f6": return CGKeyCode(kVK_F6)
        case "f7": return CGKeyCode(kVK_F7)
        case "f8": return CGKeyCode(kVK_F8)
        case "f9": return CGKeyCode(kVK_F9)
        case "f10": return CGKeyCode(kVK_F10)
        case "f11": return CGKeyCode(kVK_F11)
        case "f12": return CGKeyCode(kVK_F12)

        case "space": return CGKeyCode(kVK_Space)
        case "return", "enter": return CGKeyCode(kVK_Return)
        case "tab": return CGKeyCode(kVK_Tab)
        case "escape", "esc": return CGKeyCode(kVK_Escape)

        default:
            return nil
        }
    }
}

@MainActor
public final class QuickLauncherStore: ObservableObject {
    private static let storageKey = "quickLauncherActions"
    private static let trayOpenKey = "quickLauncherTrayOpen"

    @Published public var items: [QuickLauncherItem] {
        didSet {
            save()
        }
    }

    @Published public var isTrayOpen: Bool {
        didSet {
            UserDefaults.standard.set(isTrayOpen, forKey: Self.trayOpenKey)
            if isTrayOpen {
                QuickLauncherPanelPresenter.shared.show(launcherStore: self)
            } else {
                QuickLauncherPanelPresenter.shared.hide()
            }
        }
    }

    @Published public var lastTriggeredId: String? = nil
    @Published public var lastTriggeredMessage: String? = nil

    public static let defaultItems: [QuickLauncherItem] = [
        QuickLauncherItem(title: "SSL 4000 E", key: "1", category: "DYN", colorHex: "#3B82F6"),
        QuickLauncherItem(title: "Saturn 2", key: "2", category: "SAT", colorHex: "#EF4444"),
        QuickLauncherItem(title: "Pro-Q 3", key: "3", category: "EQ", colorHex: "#10B981"),
        QuickLauncherItem(title: "Pro-C 2", key: "4", category: "COMP", colorHex: "#6366F1"),
        QuickLauncherItem(title: "VintageVerb", key: "5", category: "REV", colorHex: "#8B5CF6"),
        QuickLauncherItem(title: "Decapitator", key: "6", category: "DIST", colorHex: "#F59E0B"),
        QuickLauncherItem(title: "OTT", key: "7", category: "DYN", colorHex: "#EC4899"),
        QuickLauncherItem(title: "Soothe 2", key: "8", category: "RES", colorHex: "#06B6D4"),
        QuickLauncherItem(title: "Utility", key: "9", category: "UTIL", colorHex: "#64748B")
    ]

    public init() {
        self.isTrayOpen = UserDefaults.standard.bool(forKey: Self.trayOpenKey)

        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([QuickLauncherItem].self, from: data),
           !decoded.isEmpty {
            self.items = decoded
        } else {
            self.items = Self.defaultItems
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        }
    }

    public func resetToDefaults() {
        self.items = Self.defaultItems
    }

    public func addItem(title: String, key: String, category: String? = nil, colorHex: String? = nil) {
        let newItem = QuickLauncherItem(title: title, key: key, category: category, colorHex: colorHex)
        items.append(newItem)
    }

    public func removeItem(id: String) {
        items.removeAll { $0.id == id }
    }

    public func updateItem(_ item: QuickLauncherItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        }
    }

    public var trayHeight: CGFloat {
        // Calculate based on 3-column rows
        let rowCount = max(1, (items.count + 2) / 3)
        // Header ~28pt, rows: rowCount * 38pt + spacing, close plugin button: ~48pt, bottom padding ~12pt
        return CGFloat(28 + (rowCount * 38) + ((rowCount - 1) * 6) + 48 + 12)
    }

    public func trigger(_ item: QuickLauncherItem) {
        lastTriggeredId = item.id
        lastTriggeredMessage = "\(item.title) (\(item.key))"

        if item.key.localizedCaseInsensitiveContains("close")
            || item.title.localizedCaseInsensitiveContains("Close Plugin") {
            PluginCloserManager.shared?.closePluginWindows()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                if self?.lastTriggeredId == item.id {
                    self?.lastTriggeredId = nil
                }
            }
            return
        }

        // Activate Ableton Live first
        _ = AbletonSessionDetector.activateAbleton()

        // Dispatch keypress slightly after activating so Live has focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Self.postKey(item.key)
        }

        // Reset visual flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if self?.lastTriggeredId == item.id {
                self?.lastTriggeredId = nil
            }
        }
    }

    public static func postKey(_ keyString: String) {
        let trimmed = keyString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let code = KeyCodeHelper.keyCode(for: trimmed) {
            let source = CGEventSource(stateID: .combinedSessionState)
            if let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
               let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
                return
            }
        }

        // AppleScript fallback
        postAppleScriptKeystroke(trimmed)
    }

    private static func postAppleScriptKeystroke(_ keyString: String) {
        let escaped = keyString.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            keystroke "\(escaped)"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
