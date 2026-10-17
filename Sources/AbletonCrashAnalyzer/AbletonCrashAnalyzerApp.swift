import SwiftUI

@main
struct AbletonCrashAnalyzerApp: App {
    var body: some Scene {
        WindowGroup { CrashAnalyzerView() }
            .defaultSize(width: 900, height: 600)
    }
}
