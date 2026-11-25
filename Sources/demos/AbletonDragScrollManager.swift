import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Intercepts 'W' and 'S' keypresses only while dragging (left mouse button down)
/// inside Ableton Live, converting them to Page Up and Page Down for lightning-fast
/// track and arrangement navigation.
///
/// Guaranteed never to interfere with normal typing (e.g. searching in Ableton)
/// or any other application.
@MainActor
final class AbletonDragScrollManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? start() : stop()
        }
    }

    static weak var shared: AbletonDragScrollManager?
    private static let enabledKey = "abletonDragScrollEnabled"

    private let backgroundTap = BackgroundCGEventTap()
    private var isTapStarted = false
    private var isAbletonFrontmost = false
    private var workspaceObserver: NSObjectProtocol?

    init() {
        let saved = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool
        self.isEnabled = saved ?? true
        Self.shared = self
        self.isAbletonFrontmost = DawFrontmostMatcher.isDaw(NSWorkspace.shared.frontmostApplication, includeBitwig: false)
        installWorkspaceObserver()
        if isEnabled { start() }
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        backgroundTap.stop()
    }

    private func installWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activeApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isAbleton = DawFrontmostMatcher.isDaw(activeApp, includeBitwig: false)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAbletonFrontmost = isAbleton
                if self.isTapStarted {
                    self.backgroundTap.setEnabled(self.isEnabled && isAbleton)
                }
            }
        }
    }

    func start() {
        guard !isTapStarted else {
            backgroundTap.setEnabled(isAbletonFrontmost)
            return
        }
        isTapStarted = true
        isAbletonFrontmost = DawFrontmostMatcher.isDaw(NSWorkspace.shared.frontmostApplication, includeBitwig: false)

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        backgroundTap.start(
            name: "com.enricodalpos.goodvibrationshq.drag-scroll-tap",
            eventsOfInterest: mask,
            initiallyEnabled: isAbletonFrontmost,
            handler: { _, _, event -> Unmanaged<CGEvent>? in
                // 1. Mouse button must be held down (actively dragging)
                let isDragging = CGEventSource.buttonState(.combinedSessionState, button: .left)
                guard isDragging else {
                    return Unmanaged.passRetained(event)
                }

                // 2. No modifier keys like Cmd/Ctrl/Option
                let flags = event.flags
                if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
                    return Unmanaged.passRetained(event)
                }

                // 3. Intercept 'W' (13) and 'S' (1)
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == 13 { // 'W' -> Page Up (116)
                    let source = CGEventSource(stateID: .combinedSessionState)
                    if let down = CGEvent(keyboardEventSource: source, virtualKey: 116, keyDown: true),
                       let up = CGEvent(keyboardEventSource: source, virtualKey: 116, keyDown: false) {
                        down.post(tap: .cghidEventTap)
                        up.post(tap: .cghidEventTap)
                    }
                    return nil // Swallow 'W' so it doesn't type
                } else if keyCode == 1 { // 'S' -> Page Down (121)
                    let source = CGEventSource(stateID: .combinedSessionState)
                    if let down = CGEvent(keyboardEventSource: source, virtualKey: 121, keyDown: true),
                       let up = CGEvent(keyboardEventSource: source, virtualKey: 121, keyDown: false) {
                        down.post(tap: .cghidEventTap)
                        up.post(tap: .cghidEventTap)
                    }
                    return nil // Swallow 'S' so it doesn't type
                }

                return Unmanaged.passRetained(event)
            },
            onInstalled: {
                AccountDiagnostics.record("Ableton drag-scroll tap installed on background thread (W -> Page Up, S -> Page Down while dragging in Live)")
            },
            onFailure: {
                AccountDiagnostics.record("Ableton drag-scroll: could not create CGEvent tap")
            }
        )
    }

    func stop() {
        isTapStarted = false
        backgroundTap.stop()
    }
}
