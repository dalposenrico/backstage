import XCTest
@testable import demos

final class AbletonAppDetectorTests: XCTestCase {
    private let testDefaultsKey = AbletonAppDetector.defaultsKey
    private var originalPath: String?

    override func setUp() {
        super.setUp()
        originalPath = UserDefaults.standard.string(forKey: testDefaultsKey)
    }

    override func tearDown() {
        if let original = originalPath {
            UserDefaults.standard.set(original, forKey: testDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: testDefaultsKey)
        }
        super.tearDown()
    }

    func testVersionParsingAndCleanVersion() {
        let releaseApp = AbletonAppInfo(
            name: "Ableton Live 12 Suite",
            path: "/Applications/Ableton Live 12 Suite.app",
            bundleURL: URL(fileURLWithPath: "/Applications/Ableton Live 12 Suite.app"),
            bundleIdentifier: "com.ableton.live",
            version: "12.4.16 (2026-10-30_e33287a1c7)",
            isBeta: false
        )
        XCTAssertEqual(releaseApp.cleanVersion, "12.4.16")
        XCTAssertEqual(releaseApp.majorVersionPrefix, "Live 12")
        XCTAssertEqual(releaseApp.displayName, "Ableton Live 12 Suite (12.4.16)")
        XCTAssertEqual(releaseApp.pickerLabel, "Ableton Live 12 Suite (12.4.16)")

        let betaApp = AbletonAppInfo(
            name: "Ableton Live 13 Beta",
            path: "/Applications/Ableton Live 13 Beta.app",
            bundleURL: URL(fileURLWithPath: "/Applications/Ableton Live 13 Beta.app"),
            bundleIdentifier: "com.ableton.live",
            version: "13.0b25",
            isBeta: true
        )
        XCTAssertEqual(betaApp.cleanVersion, "13.0b25")
        XCTAssertEqual(betaApp.majorVersionPrefix, "Live 13")
        XCTAssertEqual(betaApp.displayName, "Ableton Live 13 Beta (13.0b25)")
        XCTAssertEqual(betaApp.pickerLabel, "Ableton Live 13 Beta (13.0b25)")
    }

    func testMajorVersionPrefixFallbackFromName() {
        let app = AbletonAppInfo(
            name: "Ableton Live 13 Beta.app",
            path: "/Applications/Ableton Live 13 Beta.app",
            bundleURL: URL(fileURLWithPath: "/Applications/Ableton Live 13 Beta.app"),
            bundleIdentifier: "com.ableton.live",
            version: nil,
            isBeta: true
        )
        XCTAssertEqual(app.majorVersionPrefix, "Live 13")
        XCTAssertEqual(app.displayName, "Ableton Live 13 Beta")
    }

    func testSelectedAppPathDefaultsPersistence() {
        AbletonAppDetector.setSelectedAppPath(nil)
        XCTAssertNil(AbletonAppDetector.selectedAppPath())
        XCTAssertNil(AbletonAppDetector.selectedAppURL())

        AbletonAppDetector.setSelectedAppPath("")
        XCTAssertNil(AbletonAppDetector.selectedAppPath())

        // Non-existent path returns nil for selectedAppURL
        AbletonAppDetector.setSelectedAppPath("/NonExistent/Live.app")
        XCTAssertNil(AbletonAppDetector.selectedAppPath())
        XCTAssertNil(AbletonAppDetector.selectedAppURL())

        // If the path actually exists on disk (e.g. /Applications/Ableton Live 12 Suite.app)
        let live12Path = "/Applications/Ableton Live 12 Suite.app"
        if FileManager.default.fileExists(atPath: live12Path) {
            AbletonAppDetector.setSelectedAppPath(live12Path)
            XCTAssertEqual(AbletonAppDetector.selectedAppPath(), live12Path)
            XCTAssertEqual(AbletonAppDetector.selectedAppURL()?.path, live12Path)
        }
    }

    func testInspectRealOrMockBundle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let appDir = tempDir.appendingPathComponent("Ableton Live 13 Beta.app")
        let contentsDir = appDir.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plistData = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleName</key>
            <string>Live</string>
            <key>CFBundleDisplayName</key>
            <string>Ableton Live 13 Beta</string>
            <key>CFBundleExecutable</key>
            <string>Live</string>
            <key>CFBundleIdentifier</key>
            <string>com.ableton.live</string>
            <key>CFBundleShortVersionString</key>
            <string>13.0b25</string>
        </dict>
        </plist>
        """.data(using: .utf8)!

        let plistURL = contentsDir.appendingPathComponent("Info.plist")
        try plistData.write(to: plistURL)

        let info = AbletonAppDetector.appInfo(for: appDir)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.name, "Ableton Live 13 Beta")
        XCTAssertEqual(info?.version, "13.0b25")
        XCTAssertEqual(info?.cleanVersion, "13.0b25")
        XCTAssertEqual(info?.majorVersionPrefix, "Live 13")
        XCTAssertTrue(info?.isBeta == true)
    }
}
