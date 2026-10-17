import AppKit
import Foundation

enum AccountDiagnostics {
    private static let queue = DispatchQueue(label: "com.enricodalpos.goodvibrationshq.diagnostics")

    static func record(_ message: String) {
        queue.async {
            let formatter = ISO8601DateFormatter()
            let line = "\(formatter.string(from: Date())) \(message)\n"
            guard let url = logURL() else { return }
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    private static func logURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = support.appendingPathComponent("goodvibrations HQ", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("diagnostics.log")
    }
}

final class AppLifecycleDiagnostics: NSObject, NSApplicationDelegate {
    private let runningKey = "diagnostics.previousRunWasActive"
    private let watchdogQueue = DispatchQueue(label: "com.enricodalpos.goodvibrationshq.watchdog")
    private var watchdog: DispatchSourceTimer?
    private var lastMainThreadResponse = DispatchTime.now()
    private var reportedHang = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if UserDefaults.standard.bool(forKey: runningKey) {
            AccountDiagnostics.record("Previous run ended without a normal termination callback")
        }
        UserDefaults.standard.set(true, forKey: runningKey)
        AccountDiagnostics.record("Application launched")
        startResponsivenessWatchdog()
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: runningKey)
        AccountDiagnostics.record("Application terminated normally")
        watchdog?.cancel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AccountDiagnostics.record("Application reopen requested; visibleWindows=\(flag)")
        guard !flag else { return true }
        if let window = sender.windows.first(where: { !$0.title.isEmpty && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    private func startResponsivenessWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: watchdogQueue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let sentAt = DispatchTime.now()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.watchdogQueue.async {
                    self.lastMainThreadResponse = sentAt
                    if self.reportedHang {
                        self.reportedHang = false
                        AccountDiagnostics.record("Main interface became responsive again")
                    }
                }
            }

            let unresponsiveFor = Double(DispatchTime.now().uptimeNanoseconds - self.lastMainThreadResponse.uptimeNanoseconds) / 1_000_000_000
            if unresponsiveFor >= 6, !self.reportedHang {
                self.reportedHang = true
                AccountDiagnostics.record("Main interface unresponsive for at least 6 seconds")
            }
        }
        watchdog = timer
        timer.resume()
    }
}
