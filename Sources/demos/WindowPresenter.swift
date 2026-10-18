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

    static func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow = NSApp.windows.first(where: { $0.title.contains("goodvibrations HQ") && $0.canBecomeMain }) {
            mainWindow.deminiaturize(nil)
            mainWindow.makeKeyAndOrderFront(nil)
            mainWindow.orderFrontRegardless()
        } else {
            if let url = URL(string: "goodvibrations://open-project") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private static var savedExpandedSize: NSSize = NSSize(width: 330, height: 580)

    static func showFloatingWidget(pinned: Bool = true, collapsed: Bool = false) {
        NSApp.activate(ignoringOtherApps: false)
        configureFloatingWidget(pinned: pinned, collapsed: collapsed, attemptsRemaining: 8)
    }

    static func hideFloatingWidget() {
        if let window = NSApp.windows.first(where: { $0.title == "goodvibrations HUD" }) {
            window.orderOut(nil)
        }
    }

    static func toggleFloatingWidget(pinned: Bool = true, collapsed: Bool = false) {
        if let window = NSApp.windows.first(where: { $0.title == "goodvibrations HUD" }), window.isVisible {
            hideFloatingWidget()
        } else {
            showFloatingWidget(pinned: pinned, collapsed: collapsed)
        }
    }

    static func setFloatingWidgetCollapsed(_ collapsed: Bool, pinned: Bool = true) {
        guard let window = NSApp.windows.first(where: { $0.title == "goodvibrations HUD" }) else { return }

        window.backgroundColor = .clear
        window.isOpaque = false

        if collapsed {
            window.styleMask.remove(.titled)
            window.hasShadow = false
            if window.frame.width > 100 && window.frame.height > 100 {
                savedExpandedSize = window.frame.size
            }
            window.minSize = NSSize(width: 52, height: 52)
            window.maxSize = NSSize(width: 52, height: 52)

            var newFrame = window.frame
            let oldHeight = newFrame.height
            newFrame.size = NSSize(width: 52, height: 52)
            newFrame.origin.y += (oldHeight - 52)
            window.setFrame(newFrame, display: true, animate: false)
        } else {
            window.styleMask.insert(.titled)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.hasShadow = true
            let targetSize = savedExpandedSize
            window.minSize = NSSize(width: 280, height: 420)
            window.maxSize = NSSize(width: 600, height: 1100)

            var newFrame = window.frame
            let oldHeight = newFrame.height
            newFrame.size = targetSize
            newFrame.origin.y -= (targetSize.height - oldHeight)

            if let screen = window.screen {
                let visible = screen.visibleFrame
                if newFrame.minY < visible.minY {
                    newFrame.origin.y = visible.minY + 8
                }
                if newFrame.maxY > visible.maxY {
                    newFrame.origin.y = visible.maxY - newFrame.height - 8
                }
                if newFrame.minX < visible.minX {
                    newFrame.origin.x = visible.minX + 8
                }
                if newFrame.maxX > visible.maxX {
                    newFrame.origin.x = visible.maxX - newFrame.width - 8
                }
            }

            window.setFrame(newFrame, display: true, animate: false)
        }
    }

    static func configureFloatingWidget(pinned: Bool, collapsed: Bool = false, attemptsRemaining: Int = 8) {
        guard let window = NSApp.windows.first(where: { $0.title == "goodvibrations HUD" }) else {
            guard attemptsRemaining > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                configureFloatingWidget(pinned: pinned, collapsed: collapsed, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        window.level = pinned ? .floating : .normal
        window.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.moveToActiveSpace]
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false

        if collapsed {
            window.styleMask.remove(.titled)
            window.hasShadow = false
            window.minSize = NSSize(width: 52, height: 52)
            window.maxSize = NSSize(width: 52, height: 52)
            var f = window.frame
            let oldH = f.height
            f.size = NSSize(width: 52, height: 52)
            f.origin.y += (oldH - 52)
            window.setFrame(f, display: true, animate: false)
        } else {
            window.styleMask.insert(.titled)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.hasShadow = true
            window.minSize = NSSize(width: 280, height: 420)
            window.maxSize = NSSize(width: 600, height: 1100)
        }

        window.makeKeyAndOrderFront(nil)
        if pinned { window.orderFrontRegardless() }
    }
}
