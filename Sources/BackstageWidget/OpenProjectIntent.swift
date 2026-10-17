import AppIntents
import AppKit

struct OpenProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Project in Finder"

    @Parameter(title: "Path")
    var path: String

    init() { self.path = "" }
    init(path: String) { self.path = path }

    func perform() async throws -> some IntentResult {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        return .result()
    }
}
