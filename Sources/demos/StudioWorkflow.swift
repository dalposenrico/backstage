import Foundation

enum StudioWorkflowItemKind: String, Codable, CaseIterable, Identifiable {
    case checklist, reflection, guidance
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum StudioWorkflowImportance: String, Codable, CaseIterable, Identifiable {
    case core, optional
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct StudioWorkflowItem: Codable, Identifiable, Equatable {
    var id: String
    var stage: ProjectStage
    var section: String
    var kind: StudioWorkflowItemKind
    var importance: StudioWorkflowImportance
    var title: String
    var detail: String
    var order: Int
}

struct StudioWorkflowItemOverride: Codable, Equatable {
    var stage: ProjectStage?
    var section: String?
    var kind: StudioWorkflowItemKind?
    var importance: StudioWorkflowImportance?
    var title: String?
    var detail: String?
    var order: Int?

    func applying(to item: StudioWorkflowItem) -> StudioWorkflowItem {
        var result = item
        result.stage = stage ?? result.stage
        result.section = section ?? result.section
        result.kind = kind ?? result.kind
        result.importance = importance ?? result.importance
        result.title = title ?? result.title
        result.detail = detail ?? result.detail
        result.order = order ?? result.order
        return result
    }
}

struct StudioWorkflowCustomization: Codable, Equatable {
    var version = 1
    var overrides: [String: StudioWorkflowItemOverride] = [:]
    var hiddenBuiltInIDs: Set<String> = []
    var customItems: [StudioWorkflowItem] = []

    private enum CodingKeys: String, CodingKey { case version, overrides, hiddenBuiltInIDs, customItems }

    init(version: Int = 1, overrides: [String: StudioWorkflowItemOverride] = [:], hiddenBuiltInIDs: Set<String> = [], customItems: [StudioWorkflowItem] = []) {
        self.version = version
        self.overrides = overrides
        self.hiddenBuiltInIDs = hiddenBuiltInIDs
        self.customItems = customItems
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        overrides = try values.decodeIfPresent([String: StudioWorkflowItemOverride].self, forKey: .overrides) ?? [:]
        hiddenBuiltInIDs = try values.decodeIfPresent(Set<String>.self, forKey: .hiddenBuiltInIDs) ?? []
        customItems = try values.decodeIfPresent([StudioWorkflowItem].self, forKey: .customItems) ?? []
    }
}

struct ProjectWorkflowState: Codable, Equatable {
    var completedItemIDs: Set<String> = []
    var answers: [String: String] = [:]
    var dismissedSuggestions: Set<ProjectStage> = []

    private enum CodingKeys: String, CodingKey { case completedItemIDs, answers, dismissedSuggestions }

    init(completedItemIDs: Set<String> = [], answers: [String: String] = [:], dismissedSuggestions: Set<ProjectStage> = []) {
        self.completedItemIDs = completedItemIDs
        self.answers = answers
        self.dismissedSuggestions = dismissedSuggestions
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        completedItemIDs = try values.decodeIfPresent(Set<String>.self, forKey: .completedItemIDs) ?? []
        answers = try values.decodeIfPresent([String: String].self, forKey: .answers) ?? [:]
        dismissedSuggestions = try values.decodeIfPresent(Set<ProjectStage>.self, forKey: .dismissedSuggestions) ?? []
    }
}

enum StudioWorkflowResolver {
    static func resolve(defaults: [StudioWorkflowItem], customization: StudioWorkflowCustomization) -> [StudioWorkflowItem] {
        let builtIns = defaults.compactMap { item -> StudioWorkflowItem? in
            guard !customization.hiddenBuiltInIDs.contains(item.id) else { return nil }
            return customization.overrides[item.id]?.applying(to: item) ?? item
        }
        return (builtIns + customization.customItems).sorted(by: sortItems)
    }

    static func sortItems(_ lhs: StudioWorkflowItem, _ rhs: StudioWorkflowItem) -> Bool {
        if lhs.stage.workflowIndex != rhs.stage.workflowIndex { return lhs.stage.workflowIndex < rhs.stage.workflowIndex }
        if lhs.order != rhs.order { return lhs.order < rhs.order }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    static func isResolved(_ item: StudioWorkflowItem, state: ProjectWorkflowState) -> Bool {
        switch item.kind {
        case .checklist: return state.completedItemIDs.contains(item.id)
        case .reflection: return !(state.answers[item.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .guidance: return false
        }
    }

    static func coreProgress(stage: ProjectStage, items: [StudioWorkflowItem], state: ProjectWorkflowState) -> (resolved: Int, total: Int) {
        let core = items.filter { $0.stage == stage && $0.importance == .core && $0.kind != .guidance }
        return (core.filter { isResolved($0, state: state) }.count, core.count)
    }

    static func nextUnresolvedCore(stage: ProjectStage, items: [StudioWorkflowItem], state: ProjectWorkflowState) -> StudioWorkflowItem? {
        items.first { $0.stage == stage && $0.importance == .core && $0.kind != .guidance && !isResolved($0, state: state) }
    }

    static func notesBlock(stage: ProjectStage, question: String, answer: String, date: Date = Date()) -> String {
        let stamp = date.formatted(.dateTime.day().month(.abbreviated).year())
        return "Production Checklist — \(stage.title) · \(stamp)\n\(question)\n\(answer.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

enum BuiltInStudioWorkflow {
    static let items: [StudioWorkflowItem] = {
        var result: [StudioWorkflowItem] = []
        func add(_ id: String, _ stage: ProjectStage, _ order: Int, _ kind: StudioWorkflowItemKind, _ importance: StudioWorkflowImportance, _ title: String, _ detail: String = "", section: String = "Core") {
            result.append(.init(id: id, stage: stage, section: section, kind: kind, importance: importance, title: title, detail: detail, order: order))
        }

        add("spark.feeling", .spark, 10, .reflection, .core, "What should this track make someone feel?", "Name the emotional destination before choosing more sounds.")
        add("spark.context", .spark, 20, .reflection, .core, "Where and for whom should it work?", "Picture the room, time, and listener: club, headphones, festival, after-hours, or something else.")
        add("spark.idea", .spark, 30, .reflection, .core, "What is the one idea people should remember?", "Protect the hook, groove, texture, or gesture that gives the track an identity.")
        add("spark.references", .spark, 40, .checklist, .core, "Choose one or two useful references", "Use references for direction and decisions, not imitation.")
        add("spark.themes", .spark, 50, .reflection, .core, "Choose three themes", "Mix musical words with images or places, such as driving, euphoric, midnight, or northern lights.")
        add("spark.experiment", .spark, 60, .checklist, .core, "Run one time-boxed experiment", "Give one uncertain idea a short focused attempt, then decide whether it belongs.")
        add("spark.drop-breakdown", .spark, 70, .checklist, .core, "The sketch has at least a drop and a breakdown", "Build enough contrast to hear how the central idea behaves at high and low energy.", section: "Loop readiness")
        add("spark.musical-parts", .spark, 80, .checklist, .core, "The essential musical parts are present", "Make sure the song has the musical ingredients it needs before expanding the arrangement.", section: "Loop readiness")
        add("spark.groove", .spark, 90, .checklist, .core, "The groove feels irresistibly infectious", "Listen for timing, interaction, and movement before adding more layers.", section: "Loop readiness")
        add("spark.hook", .spark, 100, .checklist, .core, "The hook feels irresistibly catchy", "The hook can be melodic, rhythmic, vocal, or textural, but it should pull you back in.", section: "Loop readiness")
        add("spark.memorable", .spark, 110, .checklist, .core, "The song idea feels memorable", "After stepping away, check whether the central idea still stays with you.", section: "Loop readiness")
        add("spark.raw-sounds", .spark, 120, .checklist, .core, "The raw sounds are strong and naturally complement each other", "Favor sound selection and natural fit before relying on heavy processing.", section: "Loop readiness")
        add("spark.inspiration", .spark, 130, .guidance, .optional, "Inspiration can be non-musical", "An image, memory, movement, color, or environment can be a better compass than another plugin.", section: "Ideas")
        add("spark.constraint", .spark, 140, .reflection, .optional, "What constraint could make this easier?", "Try a limited palette, one synth, a time limit, or a single rhythmic rule.", section: "Ideas")

        add("structure.map", .structure, 10, .checklist, .core, "The track has a complete beginning-to-end map", "A rough full arrangement is more useful than a perfect eight-bar loop.")
        add("structure.energy", .structure, 20, .reflection, .core, "Describe the energy curve", "Where does tension rise, release, reset, and peak?")
        add("structure.transitions", .structure, 30, .checklist, .core, "Transitions feel intentional and natural", "Check entries, exits, builds, resets, and abrupt energy changes.")
        add("structure.contrast", .structure, 40, .checklist, .core, "Sections have enough contrast", "Contrast can come from density, register, rhythm, space, or silence.")
        add("structure.variation", .structure, 50, .checklist, .core, "Repetition contains meaningful variation", "Small changes and fills should keep attention without weakening the identity.")
        add("structure.evolution", .structure, 60, .checklist, .core, "Important sounds evolve over time", "This matters especially when the arrangement is minimal.")
        add("structure.surprise", .structure, 70, .reflection, .optional, "Where is the memorable surprise?", "Find one turn, silence, fill, or texture that rewards attention.", section: "Ideas")
        add("structure.first10", .structure, 80, .guidance, .optional, "Let the opening sell the world quickly", "The first moments should establish confidence and invite the listener in.", section: "Ideas")

        add("full.essential", .fullTrack, 10, .reflection, .core, "Which elements are truly essential?", "Name the sounds that carry the message; supporting parts should help them.")
        add("full.role", .fullTrack, 20, .checklist, .core, "Every remaining part has a clear role", "Mute uncertain parts. If the track improves or nothing is lost, remove them.")
        add("full.selection", .fullTrack, 30, .checklist, .core, "Sound choice is solved before heavy processing", "If a sound needs extreme repair, replace or reposition it before building a large chain.")
        add("full.lowend", .fullTrack, 40, .checklist, .core, "Kick and sub work together", "Check timing, envelopes, level, tuning, and phase interaction before final loudness processing.")
        add("full.automation", .fullTrack, 50, .checklist, .core, "Automation supports energy and movement", "Use purposeful section automation, modulation, builds, and resets.")
        add("full.demo", .fullTrack, 60, .checklist, .core, "Bounce a demo and listen away from the session", "A detached listen reveals structural problems faster than staring at the arrangement.")
        add("full.todo", .fullTrack, 70, .reflection, .optional, "What is the smallest remaining production task?", "Turn vague dissatisfaction into one concrete next move.", section: "Ideas")
        add("full.organize", .fullTrack, 80, .checklist, .optional, "Prepare a clear mix session", "Label, color, route, and gain-stage enough to avoid confusion later.", section: "Ideas")

        add("mix.goal", .mix, 10, .reflection, .core, "What is the end goal for this mix?", "Describe the feeling, hierarchy, punch, depth, and width before reaching for processors.")
        add("mix.reference", .mix, 20, .checklist, .core, "References are level-matched and used often", "Compare direction, balance, and translation at similar perceived loudness.")
        add("mix.balance", .mix, 30, .checklist, .core, "The static balance works in mono", "Start quietly, establish the foundation, and make the important elements readable without stereo tricks.")
        add("mix.lowend", .mix, 40, .checklist, .core, "Kick and bass establish the foundation", "Balance the low end first, then drums, then the most important melodic or vocal element.")
        add("mix.eq", .mix, 50, .checklist, .core, "EQ decisions work in context and are gain-matched", "Listen before looking, avoid habitual filtering, and prefer a better source when repair becomes excessive.")
        add("mix.dynamics", .mix, 60, .checklist, .core, "Dynamics and peaks are controlled without losing movement", "Choose attack and release for a reason; compare at unity gain and avoid compression by habit.")
        add("mix.stereo", .mix, 70, .checklist, .core, "Width, depth, and automation are deliberate", "Keep the center focused, protect low-frequency compatibility, and use stereo as enhancement rather than rescue.")
        add("mix.translation", .mix, 80, .checklist, .core, "The mix translates across useful listening systems", "Check mono, low volume, headphones, and at least one contrasting speaker without endlessly switching.")
        add("mix.phase", .mix, 90, .guidance, .optional, "Investigate phase when the evidence points there", "Check kick/sub, parallel paths, returns, correlation, and unexplained peaks before using clipping as a repair.", section: "Deep checks")
        add("mix.solo", .mix, 100, .guidance, .optional, "Make fitting decisions in context", "Solo can diagnose a problem, but balance, EQ, and character should serve the full track.", section: "Deep checks")

        add("master.mixready", .master, 10, .checklist, .core, "No known mix problem is being handed to mastering", "Return to the mix for balance, arrangement, or sound-selection issues that mastering cannot solve cleanly.")
        add("master.fresh", .master, 20, .checklist, .core, "Listen with fresh ears at a dependable level", "Avoid making final decisions through fatigue or constantly changing monitoring volume.")
        add("master.reference", .master, 30, .checklist, .core, "Level-match relevant masters before comparing", "Judge tone, movement, punch, and density without louder automatically winning.")
        add("master.problem", .master, 40, .reflection, .core, "What specific problem should each processor solve?", "If there is no audible reason, bypass it. Mastering is deliberate problem solving, not a mandatory chain.")
        add("master.balance", .master, 50, .checklist, .core, "Tone, dynamics, punch, and stereo image still serve the song", "Use meters as evidence while keeping the musical result in charge.")
        add("master.export", .master, 60, .checklist, .core, "Verify the rendered master and required deliverables", "Listen to the actual exported file, check starts and endings, and keep an appropriate clean version.")
        add("master.stress", .master, 70, .checklist, .optional, "Try a restrained translation or stress check", "Check whether the master stays convincing at low level, in mono, or through a deliberately revealing system.", section: "Deep checks")
        add("master.objective", .master, 80, .guidance, .optional, "Fresh objectivity can be more valuable than more processing", "When uncertainty remains, a trusted second listener or mastering engineer may reveal more than another plugin.", section: "Deep checks")

        add("done.feeling", .done, 10, .reflection, .core, "Does the finished track communicate the intended feeling?", "Compare the result with the intention you wrote at the start, not with an imaginary perfect song.")
        add("done.systems", .done, 20, .checklist, .core, "It survives the listening systems that matter", "Translation should support the intended context, not sound identical everywhere.")
        add("done.feedback", .done, 30, .checklist, .core, "Useful outside feedback has been considered", "Ask people who understand the goal; you do not have to implement every opinion.")
        add("done.issue", .done, 40, .reflection, .core, "What clearly audible issue still prevents release?", "Name it precisely. If you cannot, the discomfort may be uncertainty rather than a musical problem.")
        add("done.commit", .done, 50, .checklist, .core, "Commit to this version as finished", "Finishing is a decision supported by evidence, not the absence of every possible alternative.")
        add("done.archive", .done, 60, .checklist, .core, "The final version is identifiable and safely kept", "Make the chosen export easy to find without changing the project's existing folder structure.")
        add("done.learn", .done, 70, .reflection, .optional, "What will you carry into the next track?", "Capture one lesson without reopening this song to fix it.", section: "Review")
        add("done.celebrate", .done, 80, .guidance, .optional, "Acknowledge the finish", "A completed track teaches more than an endlessly protected work in progress.", section: "Review")
        return result
    }()
}
