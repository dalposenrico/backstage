import AppKit
import CoreGraphics
import Foundation

enum DawFrontmostMatcher {
    static func isDaw(_ app: NSRunningApplication?, includeBitwig: Bool) -> Bool {
        guard let app, let name = app.localizedName else { return false }
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        if name.localizedCaseInsensitiveContains("Live")
            || name.localizedCaseInsensitiveContains("Ableton")
            || bundle.hasPrefix("com.ableton.live") {
            return true
        }
        if includeBitwig && (name.localizedCaseInsensitiveContains("Bitwig")
            || bundle.hasPrefix("com.bitwig.studio")) {
            return true
        }
        return false
    }
}

/// Runs a `CGEventTap` on a dedicated `.userInteractive` background `CFRunLoop` thread
/// instead of `CFRunLoopGetMain()`. This ensures main-thread UI work never stalls
/// system-wide keyboard/mouse input, and lets callers disable the tap at the window-server
/// level whenever a non-DAW app is frontmost.
final class BackgroundCGEventTap: @unchecked Sendable {
    typealias EventHandler = (CGEventTapProxy, CGEventType, CGEvent) -> Unmanaged<CGEvent>?

    private final class CallbackBox: @unchecked Sendable {
        let handler: EventHandler
        weak var owner: BackgroundCGEventTap?

        init(handler: @escaping EventHandler, owner: BackgroundCGEventTap) {
            self.handler = handler
            self.owner = owner
        }
    }

    private let lock = NSLock()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var shouldBeEnabled = true
    private var isStopped = false

    func start(
        name: String,
        eventsOfInterest: CGEventMask,
        initiallyEnabled: Bool = true,
        handler: @escaping EventHandler,
        onInstalled: (@Sendable () -> Void)? = nil,
        onFailure: (@Sendable () -> Void)? = nil
    ) {
        lock.lock()
        guard thread == nil else {
            shouldBeEnabled = initiallyEnabled
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: initiallyEnabled)
            }
            lock.unlock()
            return
        }
        isStopped = false
        shouldBeEnabled = initiallyEnabled
        lock.unlock()

        let box = CallbackBox(handler: handler, owner: self)

        let worker = Thread { [weak self, box] in
            let retainedRefcon = Unmanaged.passRetained(box).toOpaque()
            defer {
                Unmanaged<CallbackBox>.fromOpaque(retainedRefcon).release()
            }

            guard let self else { return }
            self.lock.lock()
            let stoppedBeforeStart = self.isStopped
            self.lock.unlock()
            if stoppedBeforeStart { return }

            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventsOfInterest,
                callback: { proxy, type, event, refcon in
                    guard let refcon else { return Unmanaged.passRetained(event) }
                    let box = Unmanaged<CallbackBox>.fromOpaque(refcon).takeUnretainedValue()
                    guard let owner = box.owner else { return Unmanaged.passRetained(event) }

                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        owner.reenableTapIfDesired()
                        return Unmanaged.passRetained(event)
                    }

                    return box.handler(proxy, type, event)
                },
                userInfo: retainedRefcon
            ) else {
                onFailure?()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let currentRL = CFRunLoopGetCurrent()

            self.lock.lock()
            if self.isStopped {
                self.lock.unlock()
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
                return
            }
            self.eventTap = tap
            self.runLoopSource = source
            self.runLoop = currentRL
            let desiredEnabled = self.shouldBeEnabled
            self.lock.unlock()

            CFRunLoopAddSource(currentRL, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: desiredEnabled)
            onInstalled?()

            CFRunLoopRun()

            self.lock.lock()
            if let source = self.runLoopSource, let rl = self.runLoop {
                CFRunLoopRemoveSource(rl, source, .commonModes)
            }
            if let tap = self.eventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            self.eventTap = nil
            self.runLoopSource = nil
            self.runLoop = nil
            self.thread = nil
            self.lock.unlock()
        }
        worker.name = name
        worker.qualityOfService = .userInteractive

        lock.lock()
        self.thread = worker
        lock.unlock()

        worker.start()
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        shouldBeEnabled = enabled
        let tap = eventTap
        lock.unlock()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: enabled)
        }
    }

    func stop() {
        lock.lock()
        isStopped = true
        shouldBeEnabled = false
        let tap = eventTap
        let rl = runLoop
        let source = runLoopSource
        lock.unlock()

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let rl {
            if let source {
                CFRunLoopRemoveSource(rl, source, .commonModes)
            }
            CFRunLoopStop(rl)
        }
    }

    deinit {
        stop()
    }

    private func reenableTapIfDesired() {
        lock.lock()
        let shouldEnable = !isStopped && shouldBeEnabled
        let tap = eventTap
        lock.unlock()
        if shouldEnable, let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}
