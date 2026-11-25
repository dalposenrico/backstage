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
            syncTapConfiguration()
        }
    }

    @Published public var useCommand: Bool {
        didSet {
            UserDefaults.standard.set(useCommand, forKey: Self.commandKey)
            syncTapConfiguration()
        }
    }

    @Published public var useOption: Bool {
        didSet {
            UserDefaults.standard.set(useOption, forKey: Self.optionKey)
            syncTapConfiguration()
        }
    }

    @Published public var useShift: Bool {
        didSet {
            UserDefaults.standard.set(useShift, forKey: Self.shiftKey)
            syncTapConfiguration()
        }
    }

    @Published public var useControl: Bool {
        didSet {
            UserDefaults.standard.set(useControl, forKey: Self.controlKey)
            syncTapConfiguration()
        }
    }

    @Published public var onlyWhenAbletonActive: Bool {
        didSet {
            UserDefaults.standard.set(onlyWhenAbletonActive, forKey: Self.onlyAbletonKey)
            syncTapConfiguration()
        }
    }

    @Published public private(set) var lastResult: PluginCloseResult?
    @Published public private(set) var lastStatus: String?
    @Published public private(set) var isExecuting: Bool = false

    // MARK: - Internal Monitoring & Hotkey Handles
    private struct TapConfiguration: Sendable {
        var isEnabled: Bool
        var targetKeyCode: CGKeyCode
        var useCommand: Bool
        var useOption: Bool
        var useShift: Bool
        var useControl: Bool
        var onlyWhenAbletonActive: Bool
        var isDawFrontmost: Bool

        var shouldTapBeActive: Bool {
            isEnabled && (!onlyWhenAbletonActive || isDawFrontmost)
        }
    }

    private final class TapStateBox: @unchecked Sendable {
        private let lock = NSLock()
        private var config: TapConfiguration

        init(_ config: TapConfiguration) {
            self.config = config
        }

        func update(_ config: TapConfiguration) {
            lock.lock()
            self.config = config
            lock.unlock()
        }

        func snapshot() -> TapConfiguration {
            lock.lock()
            defer { lock.unlock() }
            return config
        }
    }

    private let backgroundTap = BackgroundCGEventTap()
    private var isTapStarted = false
    private var isDawFrontmost = false
    private let tapState: TapStateBox
    private var workspaceObserver: NSObjectProtocol?
    private var localMonitor: Any?

    public init() {
        let defaults = UserDefaults.standard
        let initialEnabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        let initialKey = defaults.string(forKey: Self.keyKey) ?? "w"
        let initialCmd = defaults.object(forKey: Self.commandKey) as? Bool ?? true
        let initialOpt = defaults.object(forKey: Self.optionKey) as? Bool ?? true
        let initialShift = defaults.object(forKey: Self.shiftKey) as? Bool ?? false
        let initialCtrl = defaults.object(forKey: Self.controlKey) as? Bool ?? false
        let initialOnlyAbleton = defaults.object(forKey: Self.onlyAbletonKey) as? Bool ?? true
        let frontDaw = DawFrontmostMatcher.isDaw(NSWorkspace.shared.frontmostApplication, includeBitwig: true)

        self.isEnabled = initialEnabled
        self.key = initialKey
        self.useCommand = initialCmd
        self.useOption = initialOpt
        self.useShift = initialShift
        self.useControl = initialCtrl
        self.onlyWhenAbletonActive = initialOnlyAbleton
        self.isDawFrontmost = frontDaw
        self.tapState = TapStateBox(TapConfiguration(
            isEnabled: initialEnabled,
            targetKeyCode: KeyCodeHelper.keyCode(for: initialKey) ?? CGKeyCode(kVK_ANSI_W),
            useCommand: initialCmd,
            useOption: initialOpt,
            useShift: initialShift,
            useControl: initialCtrl,
            onlyWhenAbletonActive: initialOnlyAbleton,
            isDawFrontmost: frontDaw
        ))

        Self.shared = self
        installWorkspaceObserver()
        if isEnabled {
            installHotkeys()
        }
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        backgroundTap.stop()
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

    private func installWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activeApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isDaw = DawFrontmostMatcher.isDaw(activeApp, includeBitwig: true)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isDawFrontmost = isDaw
                self.syncTapConfiguration()
            }
        }
    }

    private func currentTapConfiguration() -> TapConfiguration {
        TapConfiguration(
            isEnabled: isEnabled,
            targetKeyCode: KeyCodeHelper.keyCode(for: key) ?? CGKeyCode(kVK_ANSI_W),
            useCommand: useCommand,
            useOption: useOption,
            useShift: useShift,
            useControl: useControl,
            onlyWhenAbletonActive: onlyWhenAbletonActive,
            isDawFrontmost: isDawFrontmost
        )
    }

    private func syncTapConfiguration() {
        let config = currentTapConfiguration()
        tapState.update(config)
        if isTapStarted {
            backgroundTap.setEnabled(config.shouldTapBeActive)
        }
    }

    private func reinstallHotkeys() {
        syncTapConfiguration()
        uninstallHotkeys()
        if isEnabled {
            installHotkeys()
        }
    }

    private func installHotkeys() {
        isDawFrontmost = DawFrontmostMatcher.isDaw(NSWorkspace.shared.frontmostApplication, includeBitwig: true)
        let config = currentTapConfiguration()
        tapState.update(config)

        if !isTapStarted {
            isTapStarted = true
            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            let stateBox = tapState
            backgroundTap.start(
                name: "com.enricodalpos.goodvibrationshq.plugin-closer-tap",
                eventsOfInterest: mask,
                initiallyEnabled: config.shouldTapBeActive,
                handler: { _, _, event -> Unmanaged<CGEvent>? in
                    let snapshot = stateBox.snapshot()
                    guard snapshot.shouldTapBeActive else {
                        return Unmanaged.passRetained(event)
                    }

                    let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                    guard eventKeyCode == snapshot.targetKeyCode else {
                        return Unmanaged.passRetained(event)
                    }

                    let flags = event.flags
                    let hasCmd = flags.contains(.maskCommand)
                    let hasOpt = flags.contains(.maskAlternate)
                    let hasShift = flags.contains(.maskShift)
                    let hasCtrl = flags.contains(.maskControl)

                    if hasCmd == snapshot.useCommand &&
                       hasOpt == snapshot.useOption &&
                       hasShift == snapshot.useShift &&
                       hasCtrl == snapshot.useControl {
                        // Match found! Consume the keystroke so Ableton does NOT close the set.
                        DispatchQueue.main.async {
                            PluginCloserManager.shared?.closePluginWindows()
                        }
                        return nil
                    }

                    return Unmanaged.passRetained(event)
                }
            )
        } else {
            backgroundTap.setEnabled(config.shouldTapBeActive)
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
        isTapStarted = false
        backgroundTap.stop()
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

    /// Finds and actually closes every open plugin window in Ableton Live (or Bitwig) by triggering
    /// the native accessibility close button ('AXPress' on 'kAXCloseButtonAttribute') on each floating window.
    ///
    /// This matches the exact mechanism used by dedicated tools like StudiOS Plugin Closer:
    /// - Operating via macOS Accessibility (AXUIElement) directly on the DAW's window tree.
    /// - Completely independent of screen coordinates, display resolution, or multi-monitor arrangements.
    /// - Does not move or hijack the user's mouse cursor.
    /// - Strictly filters for 'AXFloatingWindow' subrole, making it mathematically impossible to close
    ///   the main Ableton Live set/document window (which is always 'AXStandardWindow').
    private static func performCloseOffMainActor() async -> PluginCloseResult {
        return await Task.detached(priority: .userInitiated) {
            let runningApps = NSWorkspace.shared.runningApplications
            guard let dawApp = runningApps.first(where: { app in
                if let preferred = AbletonAppDetector.selectedAppURL(),
                   app.bundleURL?.standardizedFileURL.path == preferred.standardizedFileURL.path {
                    return true
                }
                let bundle = app.bundleIdentifier?.lowercased() ?? ""
                let name = app.localizedName?.lowercased() ?? ""
                return bundle.hasPrefix("com.ableton.live") || name.contains("live")
                    || bundle.hasPrefix("com.bitwig.studio") || name.contains("bitwig")
            }) else {
                return .notRunning
            }

            // Step 1: Ensure the DAW is frontmost so that floating plugin windows
            // (which macOS Cocoa panels automatically hide when deactivated) are visible and in the AX hierarchy.
            if !dawApp.isActive {
                _ = AbletonSessionDetector.activateAbleton()
                for _ in 0..<15 {
                    if dawApp.isActive { break }
                    usleep(20_000) // 20ms
                }
                // Allow the macOS window server to surface and attach the floating panels
                usleep(100_000) // 100ms
            }

            let dawPID = dawApp.processIdentifier
            let dawElement = AXUIElementCreateApplication(dawPID)

            // Step 2: Query the DAW's window list via Accessibility API
            var windowsRef: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(dawElement, kAXWindowsAttribute as CFString, &windowsRef)
            guard err == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty else {
                return .alreadyClosed
            }

            var closedCount = 0

            for window in windows {
                // Check window role and subrole
                var subroleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
                let subrole = subroleRef as? String ?? ""

                // CRITICAL SAFETY FILTER:
                // Only target floating plugin windows ('AXFloatingWindow').
                // Standard windows ('AXStandardWindow') represent your actual Ableton project set and are strictly preserved!
                guard subrole == "AXFloatingWindow" else { continue }

                var didClose = false

                // 1. Direct kAXCloseButtonAttribute action
                var closeBtnRef: CFTypeRef?
                let closeErr = AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeBtnRef)
                if closeErr == .success, let closeBtn = closeBtnRef {
                    let pressErr = AXUIElementPerformAction(closeBtn as! AXUIElement, kAXPressAction as CFString)
                    if pressErr == .success {
                        didClose = true
                        closedCount += 1
                    }
                }

                // 2. Fallback: Search window children for the AXCloseButton element
                if !didClose {
                    var childrenRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                       let children = childrenRef as? [AXUIElement] {
                        for child in children {
                            var childSubroleRef: CFTypeRef?
                            AXUIElementCopyAttributeValue(child, kAXSubroleAttribute as CFString, &childSubroleRef)
                            if (childSubroleRef as? String) == "AXCloseButton" {
                                if AXUIElementPerformAction(child, kAXPressAction as CFString) == .success {
                                    didClose = true
                                    closedCount += 1
                                    break
                                }
                            }
                        }
                    }
                }

                if didClose {
                    usleep(15_000) // 15ms breath between windows
                }
            }

            return closedCount > 0 ? .closed(count: closedCount) : .alreadyClosed
        }.value
    }
}
