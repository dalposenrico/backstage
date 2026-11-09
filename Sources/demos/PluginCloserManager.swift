import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import Foundation

public enum PluginCloseResult: Equatable {
    case closed(count: Int)
    case alreadyClosed
    case notRunning
    case failed

    public var userMessage: String {
        switch self {
        case .closed(let count):
            return "Closed \(count) plugin window\(count == 1 ? "" : "s")"
        case .alreadyClosed:
            return "Plugin windows are already closed"
        case .notRunning:
            return "Ableton Live is not running"
        case .failed:
            return "Could not close plugin windows"
        }
    }
}

/// Manages closing all floating plugin windows (VST / AU) in Ableton Live,
/// with a customizable global shortcut (default: ⌥⌘W).
///
/// Crucially, this actually closes the plugin windows (as if clicking each window's red 'x' close button),
/// and never touches or closes the main Ableton Live set window.
@MainActor
public final class PluginCloserManager: ObservableObject {
    public static weak var shared: PluginCloserManager?

    // Keys for persistence
    private static let enabledKey = "pluginCloserEnabled"
    private static let keyKey = "pluginCloserKey"
    private static let commandKey = "pluginCloserCommand"
    private static let optionKey = "pluginCloserOption"
    private static let shiftKey = "pluginCloserShift"
    private static let controlKey = "pluginCloserControl"
    private static let onlyAbletonKey = "pluginCloserOnlyWhenAbletonActive"

    // MARK: - Published Settings
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            reinstallHotkeys()
        }
    }

    @Published public var key: String {
        didSet {
            let sanitized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if sanitized != key {
                key = sanitized
                return
            }
            UserDefaults.standard.set(key, forKey: Self.keyKey)
            reinstallHotkeys()
        }
    }

    @Published public var useCommand: Bool {
        didSet {
            UserDefaults.standard.set(useCommand, forKey: Self.commandKey)
            reinstallHotkeys()
        }
    }

    @Published public var useOption: Bool {
        didSet {
            UserDefaults.standard.set(useOption, forKey: Self.optionKey)
            reinstallHotkeys()
        }
    }

    @Published public var useShift: Bool {
        didSet {
            UserDefaults.standard.set(useShift, forKey: Self.shiftKey)
            reinstallHotkeys()
        }
    }

    @Published public var useControl: Bool {
        didSet {
            UserDefaults.standard.set(useControl, forKey: Self.controlKey)
            reinstallHotkeys()
        }
    }

    @Published public var onlyWhenAbletonActive: Bool {
        didSet {
            UserDefaults.standard.set(onlyWhenAbletonActive, forKey: Self.onlyAbletonKey)
        }
    }

    @Published public private(set) var lastResult: PluginCloseResult?
    @Published public private(set) var lastStatus: String?
    @Published public private(set) var isExecuting: Bool = false

    // MARK: - Internal Monitoring & Hotkey Handles
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var localMonitor: Any?

    public init() {
        let defaults = UserDefaults.standard
        self.isEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        self.key = defaults.string(forKey: Self.keyKey) ?? "w"
        self.useCommand = defaults.object(forKey: Self.commandKey) as? Bool ?? true
        self.useOption = defaults.object(forKey: Self.optionKey) as? Bool ?? true
        self.useShift = defaults.object(forKey: Self.shiftKey) as? Bool ?? false
        self.useControl = defaults.object(forKey: Self.controlKey) as? Bool ?? false
        self.onlyWhenAbletonActive = defaults.object(forKey: Self.onlyAbletonKey) as? Bool ?? true

        Self.shared = self
        if isEnabled {
            installHotkeys()
        }
    }

    deinit {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }

    // MARK: - Hotkey Display String

    public var shortcutDisplayString: String {
        var parts = ""
        if useControl { parts += "⌃" }
        if useOption  { parts += "⌥" }
        if useShift   { parts += "⇧" }
        if useCommand { parts += "⌘" }
        parts += key.uppercased().isEmpty ? "W" : key.uppercased()
        return parts
    }

    public func resetToDefaults() {
        isEnabled = true
        key = "w"
        useCommand = true
        useOption = true
        useShift = false
        useControl = false
        onlyWhenAbletonActive = true
    }

    // MARK: - Event Tap / Hotkey Installation

    private func reinstallHotkeys() {
        uninstallHotkeys()
        if isEnabled {
            installHotkeys()
        }
    }

    private func installHotkeys() {
        guard eventTap == nil else { return }

        // Session Event Tap intercepts keystrokes system-wide so Ableton never receives Cmd+W
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon = refcon {
                        let manager = Unmanaged<PluginCloserManager>.fromOpaque(refcon).takeUnretainedValue()
                        if let tap = manager.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                        }
                    }
                    return Unmanaged.passRetained(event)
                }

                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<PluginCloserManager>.fromOpaque(refcon).takeUnretainedValue()

                guard manager.isEnabled else {
                    return Unmanaged.passRetained(event)
                }

                // If onlyWhenAbletonActive is set, check if frontmost app is Ableton Live
                if manager.onlyWhenAbletonActive {
                    guard let frontApp = NSWorkspace.shared.frontmostApplication,
                          let name = frontApp.localizedName,
                          name.localizedCaseInsensitiveContains("Live") || name.localizedCaseInsensitiveContains("Ableton") else {
                        return Unmanaged.passRetained(event)
                    }
                }

                // Check key code match
                let targetKeyCode = KeyCodeHelper.keyCode(for: manager.key) ?? CGKeyCode(kVK_ANSI_W)
                let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                guard eventKeyCode == targetKeyCode else {
                    return Unmanaged.passRetained(event)
                }

                // Check modifiers match
                let flags = event.flags
                let hasCmd = flags.contains(.maskCommand)
                let hasOpt = flags.contains(.maskAlternate)
                let hasShift = flags.contains(.maskShift)
                let hasCtrl = flags.contains(.maskControl)

                if hasCmd == manager.useCommand &&
                   hasOpt == manager.useOption &&
                   hasShift == manager.useShift &&
                   hasCtrl == manager.useControl {
                    // Match found! Consume the keystroke so Ableton does NOT close the set.
                    DispatchQueue.main.async {
                        manager.closePluginWindows()
                    }
                    return nil
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        ) {
            self.eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        // Local monitor when goodvibrations HQ itself is in foreground
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self, self.isEnabled else { return event }

                let targetKeyCode = KeyCodeHelper.keyCode(for: self.key) ?? CGKeyCode(kVK_ANSI_W)
                if event.keyCode == UInt16(targetKeyCode) {
                    let hasCmd = event.modifierFlags.contains(.command)
                    let hasOpt = event.modifierFlags.contains(.option)
                    let hasShift = event.modifierFlags.contains(.shift)
                    let hasCtrl = event.modifierFlags.contains(.control)

                    if hasCmd == self.useCommand &&
                       hasOpt == self.useOption &&
                       hasShift == self.useShift &&
                       hasCtrl == self.useControl {
                        self.closePluginWindows()
                        return nil // Swallow event
                    }
                }
                return event
            }
        }
    }

    private func uninstallHotkeys() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    // MARK: - Execute Close

    @discardableResult
    public func closePluginWindows() -> Task<PluginCloseResult, Never> {
        return Task { @MainActor in
            guard !isExecuting else { return lastResult ?? .alreadyClosed }
            isExecuting = true
            defer { isExecuting = false }

            let result = await Self.performCloseOffMainActor()
            self.lastResult = result
            self.lastStatus = result.userMessage
            AccountDiagnostics.record("PluginCloser: \(result.userMessage)")
            return result
        }
    }

    /// Finds and actually closes every open plugin window in Ableton Live by triggering the
    /// native macOS close button 'x' on each floating plugin window.
    ///
    /// CRITICAL: The main Ableton Live set/document window is ALWAYS at Layer 0 and is strictly
    /// excluded from matching, ensuring your session is never closed or interrupted.
    private static func performCloseOffMainActor() async -> PluginCloseResult {
        return await Task.detached(priority: .userInitiated) {
            let runningApps = NSWorkspace.shared.runningApplications
            guard let liveApp = runningApps.first(where: { app in
                app.bundleIdentifier?.lowercased().hasPrefix("com.ableton.live") == true
                    || app.localizedName?.localizedCaseInsensitiveContains("Live") == true
            }) else {
                return .notRunning
            }

            let livePID = liveApp.processIdentifier

            guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
                return .alreadyClosed
            }

            var targets: [(name: String, clickPoint: CGPoint)] = []

            for win in windowList {
                let pid = win[kCGWindowOwnerPID as String] as? Int ?? 0
                let layer = win[kCGWindowLayer as String] as? Int ?? 0
                let name = win[kCGWindowName as String] as? String ?? ""

                // CRITICAL SAFETY FILTER:
                // Only target floating windows (layer == 3) owned by Live.
                // The main Ableton project window is ALWAYS layer 0, so it is mathematically impossible to match.
                guard pid == livePID, layer == 3, !name.isEmpty else { continue }

                let bounds = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
                let x = bounds["X"] as? Double ?? 0
                let y = bounds["Y"] as? Double ?? 0
                let w = bounds["Width"] as? Double ?? 0
                let h = bounds["Height"] as? Double ?? 0

                // Exclude tiny UI utility frames / tooltips
                guard w > 60 && h > 60 else { continue }

                // The standard macOS traffic light close button is at (x + 14, y + 14)
                let clickPoint = CGPoint(x: x + 14.0, y: y + 14.0)
                targets.append((name: name, clickPoint: clickPoint))
            }

            guard !targets.isEmpty else {
                return .alreadyClosed
            }

            // Save original cursor position so the producer's mouse does not wander
            let originalPos = CGEvent(source: nil)?.location ?? CGPoint.zero
            let source = CGEventSource(stateID: .hidSystemState)

            for target in targets {
                let pt = target.clickPoint

                // Move cursor to close button to activate hover/traffic light
                let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)
                move?.post(tap: .cghidEventTap)
                usleep(25000) // 25ms

                // Left click down and up on the close button
                let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)
                down?.post(tap: .cghidEventTap)
                usleep(30000) // 30ms

                let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)
                up?.post(tap: .cghidEventTap)
                usleep(35000) // 35ms between windows
            }

            // Restore original cursor position immediately
            if originalPos != .zero {
                let restore = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: originalPos, mouseButton: .left)
                restore?.post(tap: .cghidEventTap)
            }

            return .closed(count: targets.count)
        }.value
    }
}
