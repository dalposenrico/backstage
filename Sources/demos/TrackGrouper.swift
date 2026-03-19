import Foundation

enum TrackGrouper {
    // Patterns stripped from the END of a filename to find the base project name.
    // Applied iteratively until nothing changes.
    private static let suffixPatterns: [String] = [
        #"\s*[-_]\s*\d{4}[-_.]\d{2}[-_.]\d{2}$"#,         // - 2024-01-15
        #"\s*[-_]\s*\d{6,8}$"#,                             // _20240115
        #"\s*[-_]?\s*[vV]\d+(\.\d+)?\s*$"#,                // v1, V2, v1.2
        #"\s*[-_]?\s*[vV]ersion\s*\d+\s*$"#,               // version 2
        #"\s*\(\s*\d+\s*\)\s*$"#,                           // (1), ( 2 )
        #"\s*[-_]\s*\d+\s*$"#,                              // - 1, _3
        #"\s+\d+\s*$"#,                                     // trailing space + number
        #"\s*[-_]?\s*(final|master|mastered|mix|mixdown|rough|demo|export|bounce|preview|release|radio|edit|stem|render|out)\s*$"#,
    ]

    /// Groups tracks by detected base name. Groups with 2+ tracks indicate versions of the same project.
    static func group(_ tracks: [Track]) -> [TrackGroup] {
        // First pass: map each track to its base name key (lowercased for bucketing)
        // but preserve the original casing for display.
        var buckets: [String: [Track]] = [:]         // lowercased base → tracks
        var canonicalName: [String: String] = [:]    // lowercased base → display name

        for track in tracks {
            let base = strippedBase(track.displayName)
            let key = base.lowercased()
            buckets[key, default: []].append(track)
            if canonicalName[key] == nil { canonicalName[key] = base }
        }

        // Build sorted groups (newest modification first)
        return buckets.map { key, groupTracks in
            let sorted = groupTracks.sorted {
                ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast)
            }
            return TrackGroup(baseName: canonicalName[key] ?? key, tracks: sorted)
        }
        .sorted {
            let a = $0.tracks.compactMap(\.modificationDate).max() ?? .distantPast
            let b = $1.tracks.compactMap(\.modificationDate).max() ?? .distantPast
            return a > b
        }
    }

    /// Returns a short version label for display inside a group (e.g. "v2", "final", "mixdown").
    /// Returns nil if the track name equals the base (it's the "original").
    static func versionLabel(of trackName: String, baseName: String) -> String? {
        guard trackName.count > baseName.count else { return nil }
        // The track name should start with the base name (case-insensitive)
        let lower = trackName.lowercased()
        guard lower.hasPrefix(baseName.lowercased()) else { return nil }
        let suffix = String(trackName.dropFirst(baseName.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: " -_()"))
        return suffix.isEmpty ? nil : suffix
    }

    // MARK: - Private

    private static func strippedBase(_ name: String) -> String {
        var result = name
        var prev = ""
        while result != prev {
            prev = result
            for pattern in suffixPatterns {
                if let range = result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    let candidate = String(result[result.startIndex..<range.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        result = candidate
                        break
                    }
                }
            }
        }
        return result
    }
}
