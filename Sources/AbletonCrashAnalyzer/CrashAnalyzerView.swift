import SwiftUI
import UniformTypeIdentifiers

struct CrashAnalyzerView: View {
    @State private var reports = CrashAnalyzer.reports()
    @State private var selected: CrashReport?
    @State private var analysis: CrashAnalysis?
    @State private var errorMessage: String?
    @State private var isTargeted = false

    var body: some View {
        NavigationSplitView {
            List(reports, selection: $selected) { report in
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.name).lineLimit(2)
                    Text(report.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }.tag(report)
            }
            .navigationTitle("Crash History")
            .toolbar { Button { reports = CrashAnalyzer.reports() } label: { Image(systemName: "arrow.clockwise") } }
        } detail: {
            ZStack {
                detail
                if isTargeted {
                    RoundedRectangle(cornerRadius: 18).fill(.tint.opacity(0.12)).stroke(.tint, lineWidth: 3).padding(18)
                    Text("Drop Ableton crash report ZIP").font(.title2.bold())
                }
            }
        }
        .onChange(of: selected) { analyzeSelected() }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.pathExtension.lowercased() == "zip" else { return false }
            selected = CrashReport(url: url, modifiedAt: .now)
            return true
        } isTargeted: { isTargeted = $0 }
        .onAppear { selected = reports.first }
    }

    @ViewBuilder private var detail: some View {
        if let analysis {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: analysis.confidence == "High" ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                            .font(.largeTitle).foregroundStyle(analysis.confidence == "High" ? .orange : .blue)
                        VStack(alignment: .leading) {
                            Text(analysis.pluginName).font(.title.bold())
                            if let developer = analysis.developer { Text(developer).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text("\(analysis.confidence) confidence").padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.thinMaterial, in: Capsule())
                    }
                    GroupBox("Crash") {
                        LabeledContent("Exception", value: analysis.exception)
                        LabeledContent("Crash log", value: analysis.crashFile)
                    }
                    GroupBox("Why this is suspected") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(analysis.evidence, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("What to try") { Text(analysis.recommendation).frame(maxWidth: .infinity, alignment: .leading) }
                    Text("This is evidence-based diagnosis, not certainty. Memory corruption can make a different component appear in the final stack.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(28)
            }
        } else if let errorMessage {
            ContentUnavailableView("Couldn’t analyze report", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else {
            ContentUnavailableView("Choose a crash report", systemImage: "doc.zipper", description: Text("Select a report from the history or drop a ZIP here."))
        }
    }

    private func analyzeSelected() {
        guard let selected else { analysis = nil; return }
        do { analysis = try CrashAnalyzer.analyze(selected.url); errorMessage = nil }
        catch { analysis = nil; errorMessage = error.localizedDescription }
    }
}
