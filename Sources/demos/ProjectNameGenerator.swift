import Foundation

struct ProjectNameGenerator {
    private struct Vocabulary {
        var modifiers: [String]
        var subjects: [String]
        var endings: [String]
    }

    private static let fallback = Vocabulary(
        modifiers: ["Electric", "Soft", "Hidden", "Slow", "Wild", "Golden", "Open", "Last"],
        subjects: ["Signal", "Motion", "Echo", "Current", "Shape", "Memory", "Frequency", "Light"],
        endings: ["After Dark", "In Motion", "On Repeat", "From Here", "All Night", "Again", "Somewhere", "Forever"]
    )

    private static let vocabularies: [String: Vocabulary] = [
        "ukg": Vocabulary(modifiers: ["South", "Late", "Two Step", "Pirate"], subjects: ["Shuffle", "Dub", "Signal", "Pressure"], endings: ["On The Two", "In The Dance", "After The Rinse", "From London"]),
        "4x4": Vocabulary(modifiers: ["Four", "Locked", "Steady", "Warehouse"], subjects: ["Floor", "Kick", "Grid", "Rhythm"], endings: ["Four To The Floor", "All Night", "On The Grid", "In The Warehouse"]),
        "house": Vocabulary(modifiers: ["Deep", "Jackin", "Soulful", "Afterhours"], subjects: ["Groove", "Floor", "Body", "Rhythm"], endings: ["In The House", "All Night", "On The Floor", "After Two"]),
        "garage": Vocabulary(modifiers: ["Two Step", "Pirate", "Sub Low", "Late"], subjects: ["Shuffle", "Dub", "Pressure", "Frequency"], endings: ["In The Dance", "On The Two", "After The Rinse", "From The Underground"]),
        "breaks": Vocabulary(modifiers: ["Broken", "Cut Up", "Loose", "Rolling"], subjects: ["Break", "Drums", "Pattern", "Rush"], endings: ["Off The Grid", "In Pieces", "Keep It Rolling", "On The Break"]),
        "jungle": Vocabulary(modifiers: ["Ruff", "Amen", "Rapid", "Deep"], subjects: ["Breakbeat", "Junglist", "Pressure", "Bass"], endings: ["In The Jungle", "At 160", "Soundboy Down", "On The Run"]),
        "ambient": Vocabulary(modifiers: ["Weightless", "Distant", "Slow", "Endless"], subjects: ["Air", "Drift", "Field", "Tone"], endings: ["Without Time", "In The Distance", "At Rest", "Between Worlds"]),
        "pop": Vocabulary(modifiers: ["Perfect", "Teenage", "Bright", "Secret"], subjects: ["Hook", "Feeling", "Heart", "Radio"], endings: ["On Repeat", "For The Summer", "One More Time", "Forever"]),
        "dark": Vocabulary(modifiers: ["Midnight", "Black", "Shadow", "Velvet"], subjects: ["Static", "Room", "Pulse", "Silhouette"], endings: ["After Dark", "At Midnight", "Underneath", "Without A Trace"]),
        "dreamy": Vocabulary(modifiers: ["Lucid", "Floating", "Soft Focus", "Weightless"], subjects: ["Clouds", "Haze", "Mirage", "Daydream"], endings: ["Half Awake", "In A Dream", "Above The Clouds", "Out Of Focus"]),
        "energetic": Vocabulary(modifiers: ["Electric", "Full Speed", "Restless", "Redline"], subjects: ["Voltage", "Rush", "Motion", "Heartbeat"], endings: ["No Brakes", "All Night", "In Overdrive", "On Fire"]),
        "warm": Vocabulary(modifiers: ["Golden", "Honey", "Amber", "Sunlit"], subjects: ["Glow", "Air", "Embers", "Horizon"], endings: ["In The Sun", "Close To You", "Late Afternoon", "Still Glowing"]),
        "cold": Vocabulary(modifiers: ["Frozen", "Silver", "Pale", "Crystal"], subjects: ["Air", "Glass", "Ice", "Distance"], endings: ["Below Zero", "Far From Home", "In The Blue", "No Signal"]),
        "nostalgic": Vocabulary(modifiers: ["Faded", "Old", "Summer", "Polaroid"], subjects: ["Memory", "Photograph", "Cassette", "Yesterday"], endings: ["Like Before", "Back Then", "One More Time", "In Another Life"]),
        "euphoric": Vocabulary(modifiers: ["Higher", "Infinite", "Radiant", "Heavenly"], subjects: ["Feeling", "Sky", "Rush", "Light"], endings: ["Above It All", "Never Coming Down", "Into The Light", "Forever Young"]),
        "sad": Vocabulary(modifiers: ["Blue", "Empty", "Quiet", "Falling"], subjects: ["Goodbye", "Rain", "Distance", "Letters"], endings: ["Without You", "Too Late", "In The Rain", "When It Ends"]),
        "happy": Vocabulary(modifiers: ["Bright", "Lucky", "Sweet", "Sunlit"], subjects: ["Smile", "Feeling", "Colour", "Morning"], endings: ["Feels Like This", "All Day", "In The Sun", "For A While"]),
        "melancholic": Vocabulary(modifiers: ["Faded", "Tender", "Grey", "Distant"], subjects: ["Memory", "Rain", "Sunday", "Photograph"], endings: ["Almost Home", "When Summer Ends", "Somewhere Else", "Still Here"]),
        "angry": Vocabulary(modifiers: ["Burning", "Bitter", "Red", "Fractured"], subjects: ["Teeth", "Fire", "Friction", "Noise"], endings: ["Had Enough", "No Apologies", "Let It Burn", "Against The Wall"]),
        "lonely": Vocabulary(modifiers: ["Empty", "Last", "Distant", "Quiet"], subjects: ["Room", "Call", "Light", "Passenger"], endings: ["On My Own", "No One Home", "After You Left", "At The End"]),
        "hopeful": Vocabulary(modifiers: ["New", "Rising", "Open", "First"], subjects: ["Light", "Morning", "Horizon", "Promise"], endings: ["From Here", "On The Way Up", "After The Rain", "Not Too Late"]),
        "anxious": Vocabulary(modifiers: ["Restless", "Nervous", "Flickering", "Tight"], subjects: ["Thoughts", "Static", "Breath", "Room"], endings: ["Can't Sit Still", "At The Edge", "In My Head", "Too Close"]),
        "bittersweet": Vocabulary(modifiers: ["Last", "Golden", "Faded", "Tender"], subjects: ["Goodbye", "Summer", "Memory", "Smile"], endings: ["One Last Time", "Happy It Happened", "Before You Go", "Almost Forever"]),
        "mysterious": Vocabulary(modifiers: ["Unknown", "Hidden", "Veiled", "Secret"], subjects: ["Figure", "Door", "Message", "Signal"], endings: ["No One Knows", "Behind The Glass", "Without A Name", "In The Fog"]),
        "romantic": Vocabulary(modifiers: ["Tender", "Secret", "Endless", "Velvet"], subjects: ["Touch", "Heart", "Gravity", "Promise"], endings: ["Close To Me", "Only Us", "In Your Arms", "Until Morning"]),
        "club": Vocabulary(modifiers: ["Neon", "Low", "Body", "Afterhours"], subjects: ["Pressure", "Rhythm", "Basement", "Strobe"], endings: ["On The Floor", "After Two", "All Night", "In The Club"]),
        "summer": Vocabulary(modifiers: ["Golden", "Endless", "Coastal", "Barefoot"], subjects: ["Heat", "Sunset", "Waves", "July"], endings: ["By The Sea", "All Summer", "Until Sunset", "With The Windows Down"]),
        "night": Vocabulary(modifiers: ["Midnight", "Neon", "Late", "Moonlit"], subjects: ["City", "Drive", "Streetlights", "Sky"], endings: ["After Dark", "At 2AM", "Through The Night", "Before Sunrise"]),
        "space": Vocabulary(modifiers: ["Zero", "Distant", "Cosmic", "Satellite"], subjects: ["Orbit", "Signal", "Gravity", "Nova"], endings: ["Out Of Orbit", "Light Years Away", "Into The Void", "Beyond Earth"]),
        "nature": Vocabulary(modifiers: ["Wild", "Green", "Open", "Northern"], subjects: ["River", "Forest", "Weather", "Fields"], endings: ["Under The Pines", "Out West", "With The Tide", "Before The Storm"]),
        "minimal": Vocabulary(modifiers: ["Bare", "Still", "Single", "Clean"], subjects: ["Line", "Form", "Space", "Tone"], endings: ["In Between", "Less Is More", "Without Words", "At Rest"]),
        "aggressive": Vocabulary(modifiers: ["Broken", "Heavy", "Raw", "Razor"], subjects: ["Pressure", "Teeth", "Impact", "Friction"], endings: ["No Mercy", "At The Edge", "Burn It Down", "Out Of Control"]),
        "gritty": Vocabulary(modifiers: ["Dusty", "Rusted", "Concrete", "Grainy"], subjects: ["Static", "Basement", "Tape", "Friction"], endings: ["In The Red", "Under The Tracks", "No Polish", "From The Block"]),
        "raw": Vocabulary(modifiers: ["Bare", "Live", "Uncut", "Rough"], subjects: ["Take", "Nerve", "Room", "Signal"], endings: ["No Filter", "First Take", "As It Is", "Straight Through"]),
        "glossy": Vocabulary(modifiers: ["Chrome", "Crystal", "Perfect", "Polished"], subjects: ["Surface", "Flash", "Mirror", "Shine"], endings: ["In High Definition", "Like New", "Under The Lights", "Picture Perfect"]),
        "airy": Vocabulary(modifiers: ["Open", "Feather", "High", "Breathing"], subjects: ["Sky", "Space", "Cloud", "Air"], endings: ["Up Above", "Wide Open", "Barely There", "With The Wind"]),
        "heavy": Vocabulary(modifiers: ["Heavy", "Low", "Massive", "Crushing"], subjects: ["Weight", "Pressure", "Impact", "Ground"], endings: ["Down Below", "On Impact", "Too Much", "Under Pressure"]),
        "surprise": Vocabulary(modifiers: ["Unknown", "Lucky", "Strange", "New"], subjects: ["World", "Turn", "Colour", "Signal"], endings: ["Somewhere Else", "By Accident", "Out Of Nowhere", "For No Reason"])
    ]

    static func generate(vibe: String, tags: [String], count: Int = 12, variation: Int = 0) -> [String] {
        let inputs = ([vibe] + tags)
            .flatMap { $0.split(separator: ",") }
            .map { clean(String($0)) }
            .filter { !$0.isEmpty }

        guard !inputs.isEmpty, count > 0 else { return [] }

        let keys = inputs.flatMap { input -> [String] in
            let lowered = input.lowercased()
            let tokens = lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            return [lowered] + tokens
        }
        let matches = keys.compactMap { vocabularies[$0] }
        let customWords = inputs.map(titleCase)
        var vocabulary = fallback

        for match in matches {
            vocabulary.modifiers.append(contentsOf: match.modifiers)
            vocabulary.subjects.append(contentsOf: match.subjects)
            vocabulary.endings.append(contentsOf: match.endings)
        }

        vocabulary.modifiers.append(contentsOf: customWords)
        vocabulary.subjects.append(contentsOf: customWords)

        var random = NameGeneratorRandom(seed: stableSeed(for: inputs, variation: variation))
        var results: [String] = []
        var seen = Set<String>()
        let attempts = max(count * 12, 48)

        for _ in 0..<attempts where results.count < count {
            let modifier = vocabulary.modifiers.randomElement(using: &random) ?? "Hidden"
            let subject = vocabulary.subjects.randomElement(using: &random) ?? "Signal"
            let ending = vocabulary.endings.randomElement(using: &random) ?? "After Dark"
            let input = customWords.randomElement(using: &random) ?? subject
            let candidates = [
                "\(modifier) \(subject)",
                "\(subject) \(ending)",
                "\(input) In Motion",
                "The \(subject)",
                "\(modifier) \(input)",
                "\(input), Again"
            ]
            let candidate = candidates.randomElement(using: &random) ?? "\(modifier) \(subject)"
            if seen.insert(candidate.lowercased()).inserted {
                results.append(candidate)
            }
        }

        return results
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }

    private static func titleCase(_ value: String) -> String {
        value.split(separator: " ").map { word in
            let text = String(word)
            guard let first = text.first else { return text }
            return first.uppercased() + text.dropFirst().lowercased()
        }.joined(separator: " ")
    }

    private static func stableSeed(for inputs: [String], variation: Int) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in (inputs.joined(separator: "|") + "|\(variation)").utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}

struct ProjectNameWorld: Equatable {
    let tags: [String]
    let suggestions: [String]
}

struct ProjectNameWorldHistory {
    private(set) var worlds: [ProjectNameWorld] = []
    private(set) var currentIndex = -1

    var current: ProjectNameWorld? {
        guard worlds.indices.contains(currentIndex) else { return nil }
        return worlds[currentIndex]
    }

    var canGoBack: Bool { currentIndex > 0 }
    var position: Int { currentIndex + 1 }

    mutating func add(_ world: ProjectNameWorld) {
        if currentIndex + 1 < worlds.count {
            worlds.removeSubrange((currentIndex + 1)..<worlds.count)
        }
        worlds.append(world)
        currentIndex = worlds.count - 1
    }

    @discardableResult
    mutating func goBack() -> ProjectNameWorld? {
        guard canGoBack else { return current }
        currentIndex -= 1
        return current
    }

    mutating func clear() {
        worlds = []
        currentIndex = -1
    }
}

private struct NameGeneratorRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
