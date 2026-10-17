import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var isChanging = false

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        statusMessage = status == .requiresApproval
            ? "Allow goodvibrations HQ in System Settings → General → Login Items."
            : nil
    }

    func setEnabled(_ enabled: Bool) {
        isChanging = true
        statusMessage = nil

        Task {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                statusMessage = error.localizedDescription
            }
            refresh()
            isChanging = false
        }
    }
}
