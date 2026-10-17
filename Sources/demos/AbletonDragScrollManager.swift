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

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init() {
        let saved = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool
        self.isEnabled = saved ?? true
        Self.shared = self
        if isEnabled { start() }
    }

    deinit {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    func start() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Handle system tap disable events
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let refcon = refcon {
                        let manager = Unmanaged<AbletonDragScrollManager>.fromOpaque(refcon).takeUnretainedValue()
                        if let tap = manager.eventTap {
                            CGEvent.tapEnable(tap: tap, enable: true)
                        }
                    }
                    return Unmanaged.passRetained(event)
                }

                // 1. Must be Ableton Live active in the foreground
                guard let frontApp = NSWorkspace.shared.frontmostApplication,
                      let name = frontApp.localizedName,
                      name.contains("Live") || name.contains("Ableton") else {
                    return Unmanaged.passRetained(event)
                }

                // 2. Mouse button must be held down (actively dragging)
                let isDragging = (NSEvent.pressedMouseButtons & 1) != 0
                    || CGEventSource.buttonState(.combinedSessionState, button: .left)
                guard isDragging else {
                    // Normal typing in Ableton (search bar, renaming, etc.) passes through untouched
                    return Unmanaged.passRetained(event)
                }

                // 3. No modifier keys like Cmd/Ctrl/Option
                let flags = event.flags
                if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
                    return Unmanaged.passRetained(event)
                }

                // 4. Intercept 'W' (13) and 'S' (1)
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
            userInfo: refcon
        ) else {
            AccountDiagnostics.record("Ableton drag-scroll: could not create CGEvent tap")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        AccountDiagnostics.record("Ableton drag-scroll tap installed (W -> Page Up, S -> Page Down while dragging in Live)")
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }
}
