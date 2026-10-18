import SwiftUI
import AppKit

struct ReleasesHubView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var progressStore: ProjectProgressStore
    let openProject: () -> Void

    private var candidateProjects: [Project] {
        projects(in: [.fullTrack])
    }

    private var finalCheckProjects: [Project] {
        projects(in: [.mix, .master])
    }

    private var readyProjects: [Project] {
        projects(in: [.done])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Releases")
                    .font(.system(size: 24, weight: .bold))
                Text("Tracks moving from a complete production toward an approved final version.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondaryText)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider().background(Color.divider)

            if store.visibleProjects.isEmpty {
                ContentUnavailableView(
                    "No projects yet",
                    systemImage: "shippingbox",
                    description: Text("Choose a music folder in Library to start building the release view.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ReleaseLane(title: "Candidate", subtitle: "Full track", projects: candidateProjects, select: select)
                        ReleaseLane(title: "Final Check", subtitle: "Mix or master", projects: finalCheckProjects, select: select)
                        ReleaseLane(title: "Ready", subtitle: "Marked done", projects: readyProjects, select: select)
                    }
                    .padding(22)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBg)
    }

    private func projects(in stages: Set<ProjectStage>) -> [Project] {
        store.visibleProjects
            .filter { stages.contains(progressStore.progress(for: $0).stage) }
            .sorted { $0.latestModification > $1.latestModification }
    }

    private func select(_ project: Project) {
        store.selectedProject = project
        openProject()
    }
}

private struct ReleaseLane: View {
    let title: String
    let subtitle: String
    let projects: [Project]
    let select: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.tertiaryText)
                }
                Spacer()
                Text("\(projects.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.tertiaryText)
            }

            if projects.isEmpty {
                Text("No tracks here")
                    .font(.system(size: 11))
                    .foregroundColor(.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 74)
            } else {
                ForEach(projects) { project in
                    Button { select(project) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(project.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primaryText)
                                .lineLimit(2)
                            Text(project.sortedTracks.first?.displayName ?? "No audio export")
                                .font(.system(size: 10))
                                .foregroundColor(.secondaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(11)
                        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 245, alignment: .top)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.divider))
    }
}

struct ToolsHubView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var toolLaunchers: ToolLauncherStore
    @EnvironmentObject private var globalHotkey: GlobalHotkeyManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tools")
                    .font(.system(size: 24, weight: .bold))
                Text(store.selectedProject.map { "Working with \($0.name)" } ?? "Select a project in Library for project-aware tools.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondaryText)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider().background(Color.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    toolSection("PROJECT TOOLS") {
                        ToolHubButton(title: "Mixer & Inserts", detail: "Pro Tools rack, plugin overview & batch plugins", icon: "slider.vertical.3") {
                            if let p = store.selectedProject ?? store.projects.first {
                                store.openProjectMixer(p)
                            }
                        }
                        ToolHubButton(title: "Versions", detail: "Arrange and compare sections", icon: "rectangle.split.2x1") {
                            openWindow(id: "ab-compare")
                        }
                        ToolHubButton(title: "Project Notes", detail: "Capture decisions and next moves", icon: "note.text") {
                            openWindow(id: "project-notes")
                            WindowPresenter.showProjectNotes()
                        }
                        ToolHubButton(title: "[untitled] Handoff", detail: "Prepare an explicit export handoff", icon: "arrow.up.doc") {
                            openWindow(id: "untitled-automation")
                            WindowPresenter.showUntitledAutomation(dismissingMenuBarPanel: false)
                        }
                        ToolHubButton(title: "Ableton Auto-Export", detail: "F1 — version & export the active set", icon: "square.and.arrow.up.on.square") {
                            globalHotkey.triggerExport()
                        }
                    }

                    toolSection("UTILITIES") {
                        ToolHubButton(title: "Name Generator", detail: "Find project names from a vibe and tags", icon: "textformat.alt") {
                            openWindow(id: "name-generator")
                        }
                        ToolHubButton(title: "Ableton Crash Analyzer", detail: "Inspect a crash report locally", icon: "waveform.path.ecg") {
                            toolLaunchers.launchAbletonCrashAnalyzer()
                        }
                    }

                    if !toolLaunchers.tools.isEmpty {
                        toolSection("MY TOOLS") {
                            ForEach(toolLaunchers.tools) { tool in
                                ToolHubButton(title: tool.name, detail: tool.isKeyboardMaestroMacro ? "Keyboard Maestro macro" : tool.url.pathExtension.isEmpty ? "Folder or app" : tool.url.pathExtension.uppercased(), icon: tool.isKeyboardMaestroMacro ? "command" : "arrow.up.forward.app") {
                                    toolLaunchers.launch(tool)
                                }
                            }
                        }
                    }

                    Button("Add Tool…") { toolLaunchers.addTools() }
                        .buttonStyle(.bordered)
                }
                .padding(22)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBg)
    }

    private func toolSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundColor(.tertiaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 290), spacing: 12)], spacing: 12) {
                content()
            }
        }
    }
}

private struct ToolHubButton: View {
    let title: String
    let detail: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primaryText)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.tertiaryText)
            }
            .padding(12)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.divider))
        }
        .buttonStyle(.plain)
    }
}
