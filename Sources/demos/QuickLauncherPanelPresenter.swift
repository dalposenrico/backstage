import AppKit
import SwiftUI

@MainActor
final class QuickLauncherPanelPresenter {
    static let shared = QuickLauncherPanelPresenter()
    private var panel: NSPanel?

    private init() {}

    func show(launcherStore: QuickLauncherStore) {
        guard let hudWindow = NSApp.windows.first(where: { $0.title == "goodvibrations HUD" }) else { return }

        let panelWidth: CGFloat = 330
        let panelHeight = launcherStore.trayHeight
        let pillFrame = hudWindow.frame

        let screen = hudWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = pillFrame.minX + (pillFrame.width - panelWidth) / 2
        x = max(visible.minX + 8, min(x, visible.maxX - panelWidth - 8))

        var y = pillFrame.minY - panelHeight - 8
        if y < visible.minY + 8 {
            // If near bottom of screen, pop open above the pill
            y = pillFrame.maxY + 8
        }

        let frame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)

        if let existing = panel {
            existing.setFrame(frame, display: true)
            existing.alphaValue = 0
            existing.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                existing.animator().alphaValue = 1.0
            }
            return
        }

        let newPanel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.title = "Quick Launcher Panel"
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        newPanel.hasShadow = true
        newPanel.isMovable = true
        newPanel.isMovableByWindowBackground = true

        let closer = PluginCloserManager.shared ?? PluginCloserManager()
        let rootView = QuickLauncherTrayView()
            .environmentObject(launcherStore)
            .environmentObject(closer)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        newPanel.contentView = hostingView
        newPanel.alphaValue = 0
        newPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            newPanel.animator().alphaValue = 1.0
        }

        self.panel = newPanel
    }

    func hide() {
        guard let panel = panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel?.orderOut(nil)
                self?.panel = nil
            }
        })
    }

    func updatePosition(hudWindow: NSWindow, launcherStore: QuickLauncherStore) {
        guard let panel = panel, panel.isVisible else { return }
        let panelWidth: CGFloat = 330
        let panelHeight = launcherStore.trayHeight
        let pillFrame = hudWindow.frame

        let screen = hudWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = pillFrame.minX + (pillFrame.width - panelWidth) / 2
        x = max(visible.minX + 8, min(x, visible.maxX - panelWidth - 8))

        var y = pillFrame.minY - panelHeight - 8
        if y < visible.minY + 8 {
            y = pillFrame.maxY + 8
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
