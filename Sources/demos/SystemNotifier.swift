import Foundation

/// Centralized macOS system notifications helper.
public enum SystemNotifier {
    /// Posts a native macOS Notification Center banner alert.
    public static func post(title: String, message: String) {
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMessage = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "display notification \"\(escapedMessage)\" with title \"\(escapedTitle)\""

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
        }
    }
}
