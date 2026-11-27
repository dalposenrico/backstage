import AppKit

enum MainWindowPlaybackShortcut {
    static let spaceKeyCode: UInt16 = 49
    static let mainWindowTitle = "goodvibrations HQ"

    static func shouldHandleSpacebar(
        windowTitle: String?,
        canBecomeMain: Bool,
        hasAttachedSheet: Bool,
        isEditingText: Bool,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> Bool {
        guard keyCode == spaceKeyCode, !isRepeat else { return false }

        let relevantModifiers = modifierFlags.intersection([.command, .control, .option, .shift])
        guard relevantModifiers.isEmpty else { return false }

        guard canBecomeMain, windowTitle == mainWindowTitle else { return false }
        guard !hasAttachedSheet, !isEditingText else { return false }
        return true
    }

    @MainActor
    static func shouldHandleSpacebar(event: NSEvent, keyWindow: NSWindow?) -> Bool {
        guard event.type == .keyDown, let window = keyWindow else { return false }
        let responder = window.firstResponder
        let isEditingText = (responder is NSTextView) || (responder is NSTextField)
        return shouldHandleSpacebar(
            windowTitle: window.title,
            canBecomeMain: window.canBecomeMain,
            hasAttachedSheet: window.attachedSheet != nil,
            isEditingText: isEditingText,
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            isRepeat: event.isARepeat
        )
    }
}

@MainActor
final class SpacebarPlaybackMonitor: ObservableObject {
    nonisolated(unsafe) private var monitor: Any?

    func start(audioPlayer: AudioPlayer) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak audioPlayer] event in
            guard let audioPlayer else { return event }
            guard MainWindowPlaybackShortcut.shouldHandleSpacebar(event: event, keyWindow: NSApp.keyWindow) else {
                return event
            }
            audioPlayer.togglePlayPause()
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
