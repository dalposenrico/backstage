import XCTest
@testable import demos

final class StudioWorkflowTests: XCTestCase {
    func testLegacyDoneRawValueAndWorkflowOrder() throws {
        let decoded = try JSONDecoder().decode(ProjectStage.self, from: Data("5".utf8))
        XCTAssertEqual(decoded, .done)
        XCTAssertEqual(ProjectStage.allCases, [.spark, .structure, .fullTrack, .mix, .master, .done])
        XCTAssertEqual(ProjectStage.mix.next, .master)
        XCTAssertEqual(ProjectStage.master.next, .done)
    }

    func testCoreProgressTrimsReflectionAnswersAndIgnoresGuidance() {
        let items = [
            item("check", kind: .checklist),
            item("question", kind: .reflection),
            item("guide", kind: .guidance)
        ]
        var state = ProjectWorkflowState(completedItemIDs: ["check"], answers: ["question": "   \n"])
        XCTAssertEqual(StudioWorkflowResolver.coreProgress(stage: .spark, items: items, state: state).resolved, 1)
        XCTAssertEqual(StudioWorkflowResolver.coreProgress(stage: .spark, items: items, state: state).total, 2)
        state.answers["question"] = "Make it feel urgent"
        XCTAssertEqual(StudioWorkflowResolver.coreProgress(stage: .spark, items: items, state: state).resolved, 2)
        XCTAssertNil(StudioWorkflowResolver.nextUnresolvedCore(stage: .spark, items: items, state: state))
    }

    func testIdeaLoopStageIncludesSketchReadinessChecklist() {
        let ids = Set(BuiltInStudioWorkflow.items.filter { $0.stage == .spark }.map(\.id))
        XCTAssertEqual(ProjectStage.spark.title, "Idea / Loop")
        XCTAssertTrue(ids.isSuperset(of: [
            "spark.drop-breakdown",
            "spark.musical-parts",
            "spark.groove",
            "spark.hook",
            "spark.memorable",
            "spark.raw-sounds"
        ]))
    }

    func testCustomizationMergesBuiltInsOverridesHiddenAndCustomItems() {
        let first = item("first", title: "Original", order: 10)
        let hidden = item("hidden", order: 20)
        let custom = item("custom.mine", title: "Mine", order: 30)
        let customization = StudioWorkflowCustomization(
            overrides: ["first": .init(title: "Edited")],
            hiddenBuiltInIDs: ["hidden"],
            customItems: [custom]
        )
        let resolved = StudioWorkflowResolver.resolve(defaults: [first, hidden], customization: customization)
        XCTAssertEqual(resolved.map(\.id), ["first", "custom.mine"])
        XCTAssertEqual(resolved.first?.title, "Edited")
    }

    func testOlderPersistenceShapesReceiveDefaults() throws {
        let customization = try JSONDecoder().decode(StudioWorkflowCustomization.self, from: Data("{}".utf8))
        XCTAssertEqual(customization, StudioWorkflowCustomization())
        let state = try JSONDecoder().decode(ProjectWorkflowState.self, from: Data("{\"answers\":{\"a\":\"b\"},\"futureField\":true}".utf8))
        XCTAssertEqual(state.answers["a"], "b")
        XCTAssertTrue(state.completedItemIDs.isEmpty)
        XCTAssertTrue(state.dismissedSuggestions.isEmpty)
    }

    @MainActor
    func testStorePersistsAndKeepsProjectsIsolated() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StudioWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let check = item("check", kind: .checklist)
        let question = item("question", kind: .reflection, order: 20)
        let first = project("First", path: "/tmp/first-project")
        let second = project("Second", path: "/tmp/second-project")

        var store: StudioWorkflowStore? = StudioWorkflowStore(supportDirectory: directory, builtInItems: [check, question])
        store?.toggle(check, for: first)
        store?.answerBinding(for: question, project: first).wrappedValue = "Dark but inviting"
        XCTAssertTrue(store?.isResolved(check, for: first) == true)
        XCTAssertFalse(store?.isResolved(check, for: second) == true)
        store = StudioWorkflowStore(supportDirectory: directory, builtInItems: [check, question])
        XCTAssertTrue(store?.isResolved(check, for: first) == true)
        XCTAssertEqual(store?.answer(for: question, project: first), "Dark but inviting")
        XCTAssertEqual(store?.coreProgress(for: first, stage: .spark).resolved, 2)
    }

    @MainActor
    func testSuggestionDismissalAndTemplateRestoration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StudioWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let builtIn = item("built-in", title: "Original")
        let project = project("First", path: "/tmp/suggestion-project")
        let store = StudioWorkflowStore(supportDirectory: directory, builtInItems: [builtIn])

        var edited = builtIn
        edited.title = "Personal edit"
        store.updateItem(edited)
        store.addCustomItem(stage: .spark)
        store.removeItem(edited)
        XCTAssertEqual(store.hiddenBuiltIns(for: .spark).map(\.id), ["built-in"])
        XCTAssertEqual(store.items(for: .spark).count, 1)

        store.restoreItem(builtIn)
        XCTAssertEqual(store.items(for: .spark).first(where: { $0.id == "built-in" })?.title, "Original")
        store.restoreStage(.spark)
        XCTAssertEqual(store.items(for: .spark), [builtIn])

        store.toggle(builtIn, for: project)
        XCTAssertTrue(store.shouldSuggestAdvance(for: project, stage: .spark))
        store.dismissSuggestion(for: project, stage: .spark)
        XCTAssertFalse(store.shouldSuggestAdvance(for: project, stage: .spark))
        store.toggle(builtIn, for: project)
        store.toggle(builtIn, for: project)
        XCTAssertTrue(store.shouldSuggestAdvance(for: project, stage: .spark))
    }

    func testNotesBlockIsTrimmedAndExplicit() {
        let block = StudioWorkflowResolver.notesBlock(stage: .mix, question: "What is the goal?", answer: "  Punch and clarity  ")
        XCTAssertTrue(block.hasPrefix("Production Checklist — Mix"))
        XCTAssertTrue(block.contains("What is the goal?\nPunch and clarity"))
        XCTAssertFalse(block.hasSuffix(" "))
    }

    @MainActor
    func testCollectionColorsPersistAndUseNearestAncestor() throws {
        let suiteName = "CollectionColorTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let parent = URL(fileURLWithPath: "/Music/Originals")
        let child = parent.appendingPathComponent("Album")
        let projectURL = child.appendingPathComponent("Track")

        var store: CollectionColorStore? = CollectionColorStore(defaults: defaults, storageKey: "testColors")
        store?.setColor(.pink, for: parent)
        store?.setColor(.blue, for: child)
        XCTAssertEqual(store?.resolvedColor(for: projectURL), .blue)
        store = CollectionColorStore(defaults: defaults, storageKey: "testColors")
        XCTAssertEqual(store?.resolvedColor(for: parent.appendingPathComponent("Another Track")), .pink)
        XCTAssertEqual(store?.resolvedColor(for: projectURL), .blue)
        store?.setColor(nil, for: child)
        XCTAssertEqual(store?.resolvedColor(for: projectURL), .pink)
    }

    private func item(
        _ id: String,
        title: String = "Item",
        kind: StudioWorkflowItemKind = .checklist,
        importance: StudioWorkflowImportance = .core,
        order: Int = 10
    ) -> StudioWorkflowItem {
        StudioWorkflowItem(id: id, stage: .spark, section: "Core", kind: kind, importance: importance, title: title, detail: "", order: order)
    }

    private func project(_ name: String, path: String) -> Project {
        Project(
            name: name,
            folderURL: URL(fileURLWithPath: path),
            tracks: [], versions: [], creationDate: nil, tags: [], bpm: nil, plugins: [], activity: ProjectActivity()
        )
    }
}
