import SwiftUI
import AppKit

struct StudioHubView: View {
    let project: Project
    @EnvironmentObject private var metadataStore: ProjectMetadataStore
    @EnvironmentObject private var player: AudioPlayer
    @ObservedObject private var dropbox = DropboxManager.shared

    @State private var clientNameDraft: String = ""
    @State private var shareLinkDraft: String = ""
    @State private var newDeliverableTitle: String = ""
    @State private var newRevisionText: String = ""
    @State private var manualTimestampDraft: String = ""
    @State private var showCopiedAlert = false
    @State private var isCreatingFolder = false
    @State private var folderCreationStatus: String? = nil
    @State private var showAllRevisions = true
    @State private var showCustomDeliverableField = false

    private var metadata: ProjectMetadata {
        metadataStore.metadata(for: project)
    }

    private var isClientProject: Bool {
        metadata.projectKind == .client
    }

    private var currentDeliverables: [DeliverableItem] {
        metadata.manualDeliverables ?? DeliverableItem.standardMixMasterDeliverables
    }

    private var completedDeliverablesCount: Int {
        currentDeliverables.filter(\.isCompleted).count
    }

    private var revisions: [ProjectRevisionItem] {
        let all = metadata.revisions ?? []
        if showAllRevisions {
            return all
        } else {
            return all.filter { !$0.isResolved }
        }
    }

    private var linkedDropboxFolderURL: URL? {
        if let stored = metadata.dropboxFolderPath, !stored.isEmpty {
            return URL(fileURLWithPath: stored)
        }
        return dropbox.recommendedFolderURL(
            clientName: metadata.clientName,
            projectName: project.name,
            isClientProject: isClientProject
        )
    }

    private var isFolderCreatedOnDisk: Bool {
        guard let url = linkedDropboxFolderURL else { return false }
        return dropbox.folderExists(at: url)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Studio Context & Mode Switcher
                projectContextSection

                // 2. Dropbox & Cloud Storage Command Hub
                dropboxHubSection

                // 3. Deliverables Matrix
                deliverablesSection

                // 4. Timestamped Revision & Mix Notes Log
                revisionsSection
            }
            .padding(18)
        }
        .background(Color.appBg)
        .onAppear {
            clientNameDraft = metadata.clientName ?? ""
            shareLinkDraft = metadata.dropboxShareLink ?? ""
            dropbox.refreshDropboxStatus()
        }
        .onChange(of: metadata.clientName) { _, newName in
            clientNameDraft = newName ?? ""
        }
        .onChange(of: metadata.dropboxShareLink) { _, newLink in
            shareLinkDraft = newLink ?? ""
        }
    }

    // MARK: - 1. Studio Context Section
    private var projectContextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.2.square.on.square")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accent)
                        Text("STUDIO WORKFLOW")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.tertiaryText)
                    }
                    Text(isClientProject ? "Client Production & Engineering" : "Personal Music Project")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primaryText)
                }
                Spacer()

                // Mode Picker Pill
                HStack(spacing: 2) {
                    modeButton(title: "Personal", kind: .personal, icon: "music.note")
                    modeButton(title: "Client", kind: .client, icon: "person.crop.circle")
                }
                .padding(3)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }

            if isClientProject {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        // Client / Artist Name
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CLIENT / ARTIST NAME")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundColor(.tertiaryText)
                            HStack {
                                Image(systemName: "person.text.rectangle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondaryText)
                                TextField("e.g. Francisco Luz, Alec, Sony...", text: $clientNameDraft)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, weight: .medium))
                                    .onSubmit {
                                        metadataStore.setClientName(clientNameDraft, for: project)
                                    }
                                if clientNameDraft != (metadata.clientName ?? "") {
                                    Button("Save") {
                                        metadataStore.setClientName(clientNameDraft, for: project)
                                    }
                                    .font(.system(size: 10, weight: .bold))
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.mini)
                                }
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                        }

                        // Service Type Selector
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SERVICE TYPE")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundColor(.tertiaryText)
                            Menu {
                                ForEach(AudioServiceType.allCases) { s in
                                    Button(s.rawValue) {
                                        metadataStore.setServiceType(s, for: project)
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(metadata.serviceType?.rawValue ?? "Select Service")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(metadata.serviceType != nil ? .primaryText : .secondaryText)
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 9))
                                        .foregroundColor(.tertiaryText)
                                }
                                .padding(8)
                                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }

                    // Deadline and Target LUFS
                    HStack(spacing: 12) {
                        // Target Deadline
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DELIVERY DEADLINE")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundColor(.tertiaryText)
                            HStack {
                                Image(systemName: "calendar")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondaryText)
                                if let deadline = metadata.targetDeadline {
                                    Text(deadlineFormatted(deadline))
                                        .font(.system(size: 11, weight: .medium))
                                    Spacer()
                                    Button {
                                        metadataStore.setTargetDeadline(nil, for: project)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.tertiaryText)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    DatePicker(
                                        "",
                                        selection: Binding(
                                            get: { metadata.targetDeadline ?? Date() },
                                            set: { metadataStore.setTargetDeadline($0, for: project) }
                                        ),
                                        displayedComponents: [.date]
                                    )
                                    .labelsHidden()
                                    .controlSize(.small)
                                    Spacer()
                                }
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                        }

                        // Target LUFS spec
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TARGET LOUDNESS")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.6)
                                .foregroundColor(.tertiaryText)
                            HStack {
                                Image(systemName: "speaker.wave.3")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondaryText)
                                Text(metadata.targetLUFS != nil ? "\(String(format: "%.1f", metadata.targetLUFS!)) LUFS" : "Not set")
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Menu {
                                    Button("-14.0 LUFS (Streaming Standard)") {
                                        metadataStore.setTargetLUFS(-14.0, for: project)
                                    }
                                    Button("-11.0 LUFS (Club / Dynamic EDM)") {
                                        metadataStore.setTargetLUFS(-11.0, for: project)
                                    }
                                    Button("-9.0 LUFS (Commercial / Bass Heavy)") {
                                        metadataStore.setTargetLUFS(-9.0, for: project)
                                    }
                                    Button("-6.0 LUFS (Maximum Loudness)") {
                                        metadataStore.setTargetLUFS(-6.0, for: project)
                                    }
                                    if metadata.targetLUFS != nil {
                                        Divider()
                                        Button("Clear") {
                                            metadataStore.setTargetLUFS(nil, for: project)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "slider.vertical.3")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondaryText)
                                }
                                .menuStyle(.borderlessButton)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
            } else {
                // Personal project context banner
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13))
                        .foregroundColor(.accent)
                    Text("Personal project · Synced with your library folder and Dropbox Music Projects.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                    Spacer()
                }
                .padding(10)
                .background(Color.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func modeButton(title: String, kind: ProjectKind, icon: String) -> some View {
        let active = (kind == .personal && metadata.projectKind != .client) ||
                     (kind == .client && metadata.projectKind == .client)
        return Button {
            metadataStore.setProjectKind(kind, for: project)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
            }
            .foregroundColor(active ? .white : .secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(active ? Color.accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Dropbox Hub Section
    private var dropboxHubSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    Text("DROPBOX INTEGRATION")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.7)
                        .foregroundColor(.tertiaryText)
                }

                Spacer()

                if isFolderCreatedOnDisk {
                    HStack(spacing: 4) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Synced Locally")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle().fill(Color.orange).frame(width: 6, height: 6)
                        Text("Not Created Yet")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                // Folder Path Row
                if let folderURL = linkedDropboxFolderURL {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FOLDER PATH")
                                .font(.system(size: 8.5, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(.tertiaryText)
                            Text(folderURL.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primaryText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        if !isFolderCreatedOnDisk {
                            Button {
                                createDropboxFolder(at: folderURL)
                            } label: {
                                HStack(spacing: 4) {
                                    if isCreatingFolder {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: "folder.badge.plus")
                                    }
                                    Text("Create on Dropbox")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            HStack(spacing: 6) {
                                Button {
                                    dropbox.revealInFinder(url: folderURL)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.up.forward.app")
                                        Text("Finder")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    dropbox.openInDropboxWeb(localURL: folderURL)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "globe")
                                        Text("Web")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                if let status = folderCreationStatus {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }

                Divider().background(Color.white.opacity(0.08))

                // Dropbox Shareable Link Bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("SHAREABLE DROPBOX LINK (CLIENT / STEMS)")
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(.tertiaryText)
                        Spacer()
                        if showCopiedAlert {
                            Text("Copied to clipboard!")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                                .transition(.opacity)
                        }
                    }

                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "link")
                                .font(.system(size: 10))
                                .foregroundColor(.secondaryText)
                            TextField("Paste public Dropbox link here...", text: $shareLinkDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .onSubmit {
                                    metadataStore.setDropboxShareLink(shareLinkDraft, for: project)
                                }
                        }
                        .padding(7)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

                        if shareLinkDraft != (metadata.dropboxShareLink ?? "") {
                            Button("Save") {
                                metadataStore.setDropboxShareLink(shareLinkDraft, for: project)
                            }
                            .font(.system(size: 10, weight: .bold))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        if let link = metadata.dropboxShareLink, !link.isEmpty {
                            Button {
                                copyToPasteboard(link)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showCopiedAlert ? "checkmark" : "doc.on.doc")
                                    Text("Copy Link")
                                }
                                .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else if let local = linkedDropboxFolderURL, let web = dropbox.dropboxWebURL(for: local) {
                            Button {
                                copyToPasteboard(web.absoluteString)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy Web Link")
                                }
                                .font(.system(size: 11, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Copy web folder URL to clipboard")
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    private func createDropboxFolder(at url: URL) {
        isCreatingFolder = true
        folderCreationStatus = nil
        do {
            try dropbox.createProjectFolder(at: url, createStudioSubfolders: true)
            metadataStore.setDropboxFolderPath(url.path, for: project)
            folderCreationStatus = "Created folder with Stems, Mix Bounces, & Deliverables"
            isCreatingFolder = false
        } catch {
            folderCreationStatus = "Failed to create folder: \(error.localizedDescription)"
            isCreatingFolder = false
        }
    }

    // MARK: - 3. Deliverables Section
    private var deliverablesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("DELIVERABLES & STEMS MATRIX")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.7)
                            .foregroundColor(.tertiaryText)
                    }
                    Text("Manual checklist for mix bounces and final client deliverables.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                }
                Spacer()
                Text("\(completedDeliverablesCount)/\(currentDeliverables.count) ready")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(completedDeliverablesCount == currentDeliverables.count ? .green : .secondaryText)
            }

            VStack(spacing: 6) {
                ForEach(currentDeliverables) { item in
                    HStack(spacing: 8) {
                        Button {
                            metadataStore.toggleDeliverable(item.id, for: project)
                        } label: {
                            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundColor(item.isCompleted ? .green : .tertiaryText)
                        }
                        .buttonStyle(.plain)

                        Text(item.title)
                            .font(.system(size: 12, weight: item.isCompleted ? .regular : .medium))
                            .foregroundColor(item.isCompleted ? .secondaryText : .primaryText)
                            .strikethrough(item.isCompleted, color: .secondaryText)

                        Spacer()

                        Button {
                            metadataStore.deleteDeliverable(item.id, for: project)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                                .foregroundColor(.tertiaryText.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(item.isCompleted ? 0.02 : 0.04), in: RoundedRectangle(cornerRadius: 6))
                }

                // Add Custom Deliverable
                if showCustomDeliverableField {
                    HStack {
                        TextField("e.g. 16-bit 44.1k Master, Radio Edit...", text: $newDeliverableTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .onSubmit {
                                addDeliverable()
                            }
                        Button("Add") {
                            addDeliverable()
                        }
                        .font(.system(size: 10, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)

                        Button("Cancel") {
                            showCustomDeliverableField = false
                            newDeliverableTitle = ""
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    HStack {
                        Button {
                            showCustomDeliverableField = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                Text("Add Custom Deliverable")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.accent)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if currentDeliverables.isEmpty {
                            Button("Reset Standard List") {
                                metadataStore.setDeliverables(DeliverableItem.standardMixMasterDeliverables, for: project)
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.secondaryText)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    private func addDeliverable() {
        guard !newDeliverableTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        metadataStore.addDeliverable(title: newDeliverableTitle, for: project)
        newDeliverableTitle = ""
        showCustomDeliverableField = false
    }

    // MARK: - 4. Timestamped Revision Log
    private var revisionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "waveform.badge.exclamationmark")
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                        Text("REVISION LOG & MIX FEEDBACK")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.7)
                            .foregroundColor(.tertiaryText)
                    }
                    Text("Pin feedback to timestamps. Clicking a timestamp seeks the audio player.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondaryText)
                }

                Spacer()

                Button {
                    showAllRevisions.toggle()
                } label: {
                    Text(showAllRevisions ? "Showing All" : "Open Only")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondaryText)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                // Quick Composer
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Button {
                            stampCurrentPlayhead()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "timer")
                                Text(manualTimestampDraft.isEmpty ? "Stamp Playhead" : manualTimestampDraft)
                            }
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Capture current player timestamp")

                        TextField("Add revision note (e.g. '01:24 Snare down 1dB in chorus')...", text: $newRevisionText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .onSubmit {
                                addRevision()
                            }

                        Button {
                            addRevision()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(newRevisionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                }

                // List of Revisions
                if revisions.isEmpty {
                    Text("No revision items yet. Add feedback from clients or notes during mixing.")
                        .font(.system(size: 11))
                        .foregroundColor(.tertiaryText)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    VStack(spacing: 6) {
                        ForEach(revisions) { rev in
                            HStack(spacing: 8) {
                                Button {
                                    metadataStore.toggleRevision(rev.id, for: project)
                                } label: {
                                    Image(systemName: rev.isResolved ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 13))
                                        .foregroundColor(rev.isResolved ? .accent : .tertiaryText)
                                }
                                .buttonStyle(.plain)

                                if let seconds = rev.timestampSeconds {
                                    let label = rev.timestampLabel ?? formatSeconds(seconds)
                                    Button {
                                        player.seek(to: seconds)
                                    } label: {
                                        Text(label)
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accent.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Jump audio playback to \(label)")
                                }

                                Text(rev.text)
                                    .font(.system(size: 12))
                                    .foregroundColor(rev.isResolved ? .secondaryText : .primaryText)
                                    .strikethrough(rev.isResolved, color: .secondaryText)

                                Spacer()

                                Button {
                                    metadataStore.deleteRevision(rev.id, for: project)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundColor(.tertiaryText.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(rev.isResolved ? 0.02 : 0.04), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    private func stampCurrentPlayhead() {
        let sec = player.currentTime
        if sec > 0 {
            manualTimestampDraft = formatSeconds(sec)
        } else {
            manualTimestampDraft = "00:00"
        }
    }

    private func addRevision() {
        let text = newRevisionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var finalSeconds: Double? = nil
        var finalLabel: String? = nil

        // If manual timestamp was stamped:
        if !manualTimestampDraft.isEmpty {
            finalLabel = manualTimestampDraft
            finalSeconds = parseTimestamp(manualTimestampDraft)
        } else {
            // Check if user included timestamp in text, e.g. "01:23 fix vocal"
            if let extracted = extractTimestampFromText(text) {
                finalSeconds = extracted.seconds
                finalLabel = extracted.label
            }
        }

        metadataStore.addRevision(
            text: text,
            timestampSeconds: finalSeconds,
            timestampLabel: finalLabel,
            for: project
        )

        newRevisionText = ""
        manualTimestampDraft = ""
    }

    // MARK: - Helpers
    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation {
            showCopiedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showCopiedAlert = false
            }
        }
    }

    private func deadlineFormatted(_ date: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: date)).day ?? 0
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let dateString = formatter.string(from: date)

        if days < 0 {
            return "\(dateString) (\(abs(days))d overdue)"
        } else if days == 0 {
            return "\(dateString) (Today)"
        } else if days == 1 {
            return "\(dateString) (Tomorrow)"
        } else {
            return "\(dateString) (in \(days) days)"
        }
    }

    private func formatSeconds(_ sec: Double) -> String {
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func parseTimestamp(_ str: String) -> Double? {
        let parts = str.components(separatedBy: ":")
        if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
            return m * 60 + s
        }
        return nil
    }

    private func extractTimestampFromText(_ text: String) -> (seconds: Double, label: String)? {
        let pattern = #"(\d{1,2}):(\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsString = text as NSString
        if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)) {
            let label = nsString.substring(with: match.range)
            if let sec = parseTimestamp(label) {
                return (seconds: sec, label: label)
            }
        }
        return nil
    }
}
