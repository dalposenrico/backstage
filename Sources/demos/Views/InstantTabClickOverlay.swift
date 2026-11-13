import SwiftUI
import AppKit

/// An invisible NSView overlay that intercepts left mouse-down events to switch tabs instantly (0ms latency),
/// eliminating the physical 100ms mouse-up delay of standard SwiftUI Buttons while preserving full hover tracking
/// and first-mouse window activation.
struct InstantTabClickOverlay: NSViewRepresentable {
    let action: () -> Void
    var onHover: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> InstantTabClickNSView {
        let view = InstantTabClickNSView()
        view.action = action
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: InstantTabClickNSView, context: Context) {
        nsView.action = action
        nsView.onHover = onHover
    }
}

final class InstantTabClickNSView: NSView {
    var action: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if bounds.contains(point) {
            return self
        }
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        action?()
    }
}
