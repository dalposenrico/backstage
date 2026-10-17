import CoreServices
import Foundation

final class ProjectLibraryWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.enricodalpos.goodvibrations.library-watcher")
    private var changeHandler: (([URL]) -> Void)?

    func start(watching rootURL: URL, onChange: @escaping ([URL]) -> Void) {
        stop()
        changeHandler = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ProjectLibraryWatcher>.fromOpaque(info).takeUnretainedValue()
            let pathArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            let paths = (pathArray as NSArray).compactMap { $0 as? String }
            watcher.changeHandler?(paths.map { URL(fileURLWithPath: $0) })
        }

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [rootURL.standardizedFileURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.8,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagNoDefer
            )
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        changeHandler = nil
    }

    deinit { stop() }
}

enum ProjectLibraryChangeRouter {
    /// Returns nil when the folder structure may have changed and a full scan is needed.
    /// An empty set means the events were ignorable hidden-file noise.
    static func projectFoldersToRefresh(
        changedURLs: [URL],
        projectFolderURLs: [URL],
        rootURL: URL
    ) -> Set<URL>? {
        let meaningfulChanges = changedURLs.map(\.standardizedFileURL).filter {
            !$0.lastPathComponent.hasPrefix(".")
        }
        guard !meaningfulChanges.isEmpty else { return [] }

        var affected = Set<URL>()
        for changedURL in meaningfulChanges {
            let changedPath = changedURL.path
            guard changedPath != rootURL.standardizedFileURL.path else { return nil }
            let matches = projectFolderURLs.filter { projectURL in
                let projectPath = projectURL.standardizedFileURL.path
                return changedPath == projectPath || changedPath.hasPrefix(projectPath + "/")
            }
            guard let projectURL = matches.max(by: { $0.path.count < $1.path.count }) else {
                return nil
            }
            affected.insert(projectURL)
        }
        return affected
    }
}
