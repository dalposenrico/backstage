import AppKit

@MainActor
enum WindowPresenter {
    static func showABCompare() {
        NSApp.activate(ignoringOtherApps: true)
        bringWindowForward(titled: "Versions", attemptsRemaining: 8)
    }

    static func showFocusPlanner() {
        NSApp.activate(ignoringOtherApps: true)
        bringWindowForward(titled: "Focus Planner", attemptsRemaining: 8)
    }

    static func showFocusTimer(pinned: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        configureFocusTimer(pinned: pinned, attemptsRemaining: 8)
    }

    static func configureFocusTimer(pinned: Bool) {
        configureFocusTimer(pinned: pinned, attemptsRemaining: 8)
    }

    static func showProjectNotes() {
        NSApp.activate(ignoringOtherApps: true)
        bringWindowForward(titled: "Project Notes", attemptsRemaining: 8)
    }

    static func showWorkflowEditor() {
        NSApp.activate(ignoringOtherApps: true)
        bringWindowForward(titled: "Workflow Editor", attemptsRemaining: 8)
    }

    static func showNameGenerator(dismissingMenuBarPanel: Bool) {
        if dismissingMenuBarPanel {
            NSApp.keyWindow?.orderOut(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        bringWindowForward(titled: "Name Generator", attemptsRemaining: 8)
    }

    static func showUntitledAutomation(dismissingMenuBarPanel: Bool) {
        if dismissingMenuBarPanel {
            NSApp.keyWindow?.orderOut(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        bringUntitledAutomationForward(attemptsRemaining: 8)
    }

    private static func bringUntitledAutomationForward(attemptsRemaining: Int) {
        guard let window = NSApp.windows.first(where: { $0.title == "[untitled] Automation" }) else {
            guard attemptsRemaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                bringUntitledAutomationForward(attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func bringWindowForward(titled title: String, attemptsRemaining: Int) {
        guard let window = NSApp.windows.first(where: { $0.title == title }) else {
            guard attemptsRemaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                bringWindowForward(titled: title, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private static func configureFocusTimer(pinned: Bool, attemptsRemaining: Int) {
        guard let window = NSApp.windows.first(where: { $0.title == "Focus Timer" }) else {
            guard attemptsRemaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                configureFocusTimer(pinned: pinned, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        window.level = pinned ? .floating : .normal
        window.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace]
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.makeKeyAndOrderFront(nil)
        if pinned { window.orderFrontRegardless() }
    }
}
