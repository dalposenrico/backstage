import SwiftUI

struct ProjectProgressSection: View {
    let project: Project
    @EnvironmentObject var progressStore: ProjectProgressStore
    @EnvironmentObject var metadataStore: ProjectMetadataStore
    @EnvironmentObject var collectionColors: CollectionColorStore

    private var progress: ProjectProgress { progressStore.progress(for: project) }
    private var metadata: ProjectMetadata { metadataStore.metadata(for: project) }
    private var visibleStages: [ProjectStage] {
        let allowed = collectionColors.allowedStages(for: project.folderURL)
        return allowed.contains(progress.stage) ? allowed : ([progress.stage] + allowed).sorted { $0.workflowIndex < $1.workflowIndex }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PROJECT ORGANIZATION")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(.tertiaryText)

                HStack(spacing: 7) {
                    Menu {
                        ForEach(visibleStages, id: \.rawValue) { stage in
                            Button {
                                progressStore.setStage(stage, for: project)
                            } label: {
                                Label(stage.title, systemImage: progress.stage == stage ? "checkmark" : "flag")
                            }
                        }
                    } label: {
                        organizationMenuLabel("Stage", value: progress.stage.title, icon: "flag")
                    }

                    Menu {
                        Button("No priority") { metadataStore.setPriority(nil, for: project) }
                        Divider()
                        ForEach(ProjectPriority.allCases) { priority in
                            Button {
                                metadataStore.setPriority(priority, for: project)
                            } label: {
                                Label(priority.title, systemImage: metadata.priority == priority ? "checkmark" : "exclamationmark")
                            }
                        }
                    } label: {
                        organizationMenuLabel("Priority", value: metadata.priority?.title ?? "None", icon: "exclamationmark")
                    }

                    Menu {
                        Button("No rating") { metadataStore.setRating(nil, for: project) }
                        Divider()
                        ForEach(ProjectRating.allCases) { rating in
                            Button {
                                metadataStore.setRating(rating, for: project)
                            } label: {
                                Label(rating.rawValue, systemImage: metadata.rating == rating ? "checkmark" : "medal")
                            }
                        }
                    } label: {
                        organizationMenuLabel("Rating", value: metadata.rating?.rawValue ?? "None", icon: "medal")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label(metadata.musicalKey.map { "KEY · \($0)" } ?? "KEY · NOT SET", systemImage: "music.note")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(metadata.musicalKey == nil ? .tertiaryText : .secondaryText)
                    ProjectMusicalKeyPicker(project: project)
                }
            }

            Divider().background(Color.divider)

            HStack {
                Text("FINISH RUNWAY")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundColor(.tertiaryText)
                Spacer()
            }

            HStack(spacing: 5) {
                ForEach(visibleStages, id: \.rawValue) { stage in
                    Button { progressStore.setStage(stage, for: project) } label: {
                        VStack(spacing: 5) {
                            Capsule()
                                .fill(stage.workflowIndex <= progress.stage.workflowIndex ? stageColor(stage) : Color.divider)
                                .frame(height: 7)
                            Text(stage.title)
                                .font(.system(size: 8, weight: stage == progress.stage ? .bold : .regular))
                                .foregroundColor(stage == progress.stage ? .primaryText : .tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(stageHelp(stage))
                }
            }
            .help("Completion stages are chosen by you; backups and work time do not advance them automatically")

            VStack(alignment: .leading, spacing: 5) {
                Text("NEXT MOVE")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                    .foregroundColor(.tertiaryText)
                TextField("One concrete action…", text: progressStore.nextMoveBinding(for: project))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .help("Write the smallest concrete action that would move this track forward next")
            }

            HStack(spacing: 7) {
                Text("EXCITEMENT")
                    .font(.system(size: 9, weight: .semibold)).tracking(0.6)
                    .foregroundColor(.tertiaryText)
                ForEach(1...5, id: \.self) { rating in
                    Button { progressStore.setSparkRating(rating, for: project) } label: {
                        Image(systemName: rating <= progress.sparkRating ? "sparkle" : "diamond")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(rating <= progress.sparkRating ? .accent : .tertiaryText)
                    }.buttonStyle(.plain).help(excitementHelp(rating))
                }
                Spacer()
                if progress.sparkRating > 0 {
                    Text("\(progress.sparkRating)/5")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondaryText)
                }
            }

        }
        .padding(14)
        .background(Color.white.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }

    private func organizationMenuLabel(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.tertiaryText)
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .frame(height: 42)
        .background(Color.elevatedBg)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).stroke(Color.subtleBorder) }
    }

    private func stageColor(_ stage: ProjectStage) -> Color {
        switch stage {
        case .spark: return Color(hex: "F39B3D")
        case .structure: return Color(hex: "F4C542")
        case .fullTrack: return Color(hex: "A7E84B")
        case .mix: return Color(hex: "45D6C8")
        case .master: return Color(hex: "5EA8FF")
        case .done: return Color(hex: "C4A3FF")
        }
    }

    private func stageHelp(_ stage: ProjectStage) -> String {
        switch stage {
        case .spark: return "Idea / Loop: the core song idea is strong enough to arrange"
        case .structure: return "Structure: the track has a meaningful beginning, middle, and end"
        case .fullTrack: return "Full Track: the production and arrangement are substantially complete"
        case .mix: return "Mix: focus on balance, transitions, detail, and translation"
        case .master: return "Master: make deliberate final processing and delivery decisions"
        case .done: return "Done: you have committed to a final version or release-ready export"
        }
    }

    private func excitementHelp(_ rating: Int) -> String {
        switch rating {
        case 1: return "1/5: little desire to return to this idea"
        case 2: return "2/5: something may be useful, but it is not pulling you back yet"
        case 3: return "3/5: promising enough to explore"
        case 4: return "4/5: genuinely exciting and worth prioritising"
        default: return "5/5: exceptional excitement—protect time to finish this"
        }
    }
}

struct CompactRunway: View {
    let progress: ProjectProgress
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ProjectStage.allCases, id: \.rawValue) { stage in
                Capsule()
                    .fill(stage.workflowIndex <= progress.stage.workflowIndex ? color(stage) : Color.divider)
                    .frame(width: 15, height: 4)
            }
            if progress.sparkRating > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .semibold))
                    Text("Excitement \(progress.sparkRating)/5")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                }
                .foregroundColor(.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondaryText.opacity(colorScheme == .light ? 0.10 : 0.12))
                .clipShape(Capsule())
                .overlay { Capsule().stroke(Color.divider, lineWidth: 0.75) }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .help("Finish runway: \(progress.stage.title)")
    }

    private func color(_ stage: ProjectStage) -> Color {
        [Color(hex: "F39B3D"), Color(hex: "F4C542"), Color(hex: "A7E84B"), Color(hex: "45D6C8"), Color(hex: "5EA8FF"), Color(hex: "C4A3FF")][stage.workflowIndex]
    }
}

struct ProjectDirectionBadge: View {
    let project: Project
    let progress: ProjectProgress
    let compact: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var direction: ProjectDirection { .evaluate(project: project, progress: progress) }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: direction.icon)
                .font(.system(size: 8, weight: .bold))
            if !compact {
                Text(direction.title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
        }
        .foregroundColor(foreground)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 3)
        .background(direction.color.opacity(colorScheme == .light ? 0.16 : 0.13))
        .clipShape(Capsule())
        .overlay { Capsule().stroke(direction.color.opacity(0.35), lineWidth: 0.75) }
        .help("\(direction.title): \(direction.explanation(project: project, progress: progress))")
    }

    private var foreground: Color {
        colorScheme == .light ? direction.color.opacity(0.95) : direction.color
    }
}
