import SwiftUI

struct ABMeterView: View {
    @ObservedObject var controller: ComparisonAudioPlayer
    let allSources: [CompareSource]
    let loudnessResults: [String: LoudnessResult]
    let onSwitch: (CompareSource) -> Void

    private var sourceA: CompareSource? {
        controller.meterSourceA ?? allSources.first
    }

    private var sourceB: CompareSource? {
        if let b = controller.meterSourceB, b != sourceA {
            return b
        }
        return allSources.first(where: { $0.url != sourceA?.url }) ?? allSources.dropFirst().first
    }

    private var isAActive: Bool {
        controller.activeSource?.url == sourceA?.url
    }

    private var isBActive: Bool {
        controller.activeSource?.url == sourceB?.url
    }

    var body: some View {
        VStack(spacing: 8) {
            // Header / Title
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "5AC8FA"))
                Text("A/B METERS")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()

                Button {
                    controller.resetMeterPeaks()
                } label: {
                    Text("RESET")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondaryText)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                }
                .buttonStyle(.plain)
                .help("Reset held peak and RMS levels")
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            // Track A & Track B Switcher Pills
            HStack(spacing: 6) {
                // Track A Selector
                trackSlotPill(
                    slotLetter: "A",
                    source: sourceA,
                    isActive: isAActive,
                    tint: Color(hex: "5AC8FA"),
                    onSelect: {
                        if let s = sourceA { onSwitch(s) }
                    },
                    onAssign: { newSource in
                        controller.meterSourceA = newSource
                    }
                )

                // Track B Selector
                trackSlotPill(
                    slotLetter: "B",
                    source: sourceB,
                    isActive: isBActive,
                    tint: Color(hex: "FF9F0A"),
                    onSelect: {
                        if let s = sourceB { onSwitch(s) }
                    },
                    onAssign: { newSource in
                        controller.meterSourceB = newSource
                    }
                )
            }
            .padding(.horizontal, 8)

            // Digital Peak & RMS Readouts (Metric AB Style)
            let levelsA = controller.levels(for: sourceA)
            let levelsB = controller.levels(for: sourceB)

            VStack(spacing: 4) {
                // Peak Row
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text(formatDB(levelsA.maxPeakL))
                        Text(formatDB(levelsA.maxPeakR))
                    }
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "5AC8FA"))
                    .frame(width: 70, alignment: .center)

                    Text("Peak")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.40))
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 6) {
                        Text(formatDB(levelsB.maxPeakL))
                        Text(formatDB(levelsB.maxPeakR))
                    }
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "FF9F0A"))
                    .frame(width: 70, alignment: .center)
                }

                // RMS Row
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text(formatDB(levelsA.rmsL))
                        Text(formatDB(levelsA.rmsR))
                    }
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "5AC8FA").opacity(0.85))
                    .frame(width: 70, alignment: .center)

                    Text("RMS")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.40))
                        .frame(maxWidth: .infinity)

                    HStack(spacing: 6) {
                        Text(formatDB(levelsB.rmsL))
                        Text(formatDB(levelsB.rmsR))
                    }
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "FF9F0A").opacity(0.85))
                    .frame(width: 70, alignment: .center)
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(Color(hex: "101214"))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 8)
            .onTapGesture {
                controller.resetMeterPeaks()
            }
            .help("Click to reset peak hold readouts")

            // Dual Stereo Meters & Center Scale
            meterCanvas(levelsA: levelsA, levelsB: levelsB)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 8)

            // Bottom Monitoring Bar
            HStack(spacing: 8) {
                Button {
                    controller.isMonoMonitoring.toggle()
                } label: {
                    Text("Mono")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(controller.isMonoMonitoring ? .black : .secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            controller.isMonoMonitoring
                                ? Color(hex: "5AC8FA")
                                : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 3.5)
                        )
                }
                .buttonStyle(.plain)
                .help("Monitor audio summed to mono")

                Spacer()

                Button {
                    controller.resetMeterPeaks()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondaryText)
                }
                .buttonStyle(.plain)
                .help("Clear peak hold lines")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .frame(width: 215)
        .background(Color(hex: "141619"))
    }

    // MARK: - Track Slot Pill

    private func trackSlotPill(
        slotLetter: String,
        source: CompareSource?,
        isActive: Bool,
        tint: Color,
        onSelect: @escaping () -> Void,
        onAssign: @escaping (CompareSource) -> Void
    ) -> some View {
        Menu {
            ForEach(allSources, id: \.url) { s in
                Button {
                    onAssign(s)
                } label: {
                    HStack {
                        if s.url == source?.url {
                            Image(systemName: "checkmark")
                        }
                        Text(s.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(slotLetter)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(isActive ? .black : tint)

                if isActive {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(.black)
                }

                Text(source?.name ?? "None")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundColor(isActive ? .black : Color.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 6)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 4.5)
                    .fill(isActive ? tint : Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4.5)
                    .stroke(isActive ? tint : tint.opacity(0.4), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .simultaneousGesture(TapGesture().onEnded {
            onSelect()
        })
        .help("Click to audition \(slotLetter). Click arrow to assign a different version.")
    }

    // MARK: - Meter Canvas

    private func meterCanvas(levelsA: ChannelLevels, levelsB: ChannelLevels) -> some View {
        GeometryReader { geo in
            let availableHeight = max(100, geo.size.height - 24) // reserve space for bottom labels
            let gainA = sourceA.flatMap { controller.gainDB(for: $0.url.path) } ?? 0.0
            let gainB = sourceB.flatMap { controller.gainDB(for: $0.url.path) } ?? 0.0

            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 5) {
                    // Left Fader for Track A
                    VStack(spacing: 2) {
                        VerticalMeterFader(
                            gainDB: gainA,
                            tint: Color(hex: "5AC8FA"),
                            onGainChanged: { newGain in
                                if let s = sourceA {
                                    controller.setGainDB(newGain, for: s.url.path)
                                }
                            }
                        )
                        .frame(width: 14, height: availableHeight)

                        Text(formatGainDB(gainA))
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "5AC8FA"))
                            .frame(width: 28)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if let s = sourceA { controller.resetGain(for: s.url.path) }
                            }
                            .help("Double-click to reset Track A volume to 0.0 dB")
                    }

                    // Track A Stereo Bar
                    VStack(spacing: 3) {
                        HStack(spacing: 2.5) {
                            SingleMeterBar(
                                liveRMS: levelsA.rmsL,
                                livePeak: levelsA.livePeakL,
                                maxPeak: levelsA.maxPeakL,
                                peakColor: Color(hex: "4DA2FF").opacity(0.45),
                                rmsColor: Color(hex: "5AC8FA"),
                                troughColor: Color(hex: "101620")
                            )
                            SingleMeterBar(
                                liveRMS: levelsA.rmsR,
                                livePeak: levelsA.livePeakR,
                                maxPeak: levelsA.maxPeakR,
                                peakColor: Color(hex: "4DA2FF").opacity(0.45),
                                rmsColor: Color(hex: "5AC8FA"),
                                troughColor: Color(hex: "101620")
                            )
                        }
                        .frame(width: 25, height: availableHeight)

                        HStack(spacing: 8) {
                            Text("L").font(.system(size: 7.5, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: "5AC8FA"))
                            Text("R").font(.system(size: 7.5, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: "5AC8FA"))
                        }
                    }

                    // Center dB Scale
                    CenterDBScale(height: availableHeight)
                        .frame(width: 44, height: availableHeight)

                    // Track B Stereo Bar
                    VStack(spacing: 3) {
                        HStack(spacing: 2.5) {
                            SingleMeterBar(
                                liveRMS: levelsB.rmsL,
                                livePeak: levelsB.livePeakL,
                                maxPeak: levelsB.maxPeakL,
                                peakColor: Color(hex: "FF9F0A").opacity(0.45),
                                rmsColor: Color(hex: "FF9F0A"),
                                troughColor: Color(hex: "201610")
                            )
                            SingleMeterBar(
                                liveRMS: levelsB.rmsR,
                                livePeak: levelsB.livePeakR,
                                maxPeak: levelsB.maxPeakR,
                                peakColor: Color(hex: "FF9F0A").opacity(0.45),
                                rmsColor: Color(hex: "FF9F0A"),
                                troughColor: Color(hex: "201610")
                            )
                        }
                        .frame(width: 25, height: availableHeight)

                        HStack(spacing: 8) {
                            Text("L").font(.system(size: 7.5, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: "FF9F0A"))
                            Text("R").font(.system(size: 7.5, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: "FF9F0A"))
                        }
                    }

                    // Right Fader for Track B
                    VStack(spacing: 2) {
                        VerticalMeterFader(
                            gainDB: gainB,
                            tint: Color(hex: "FF9F0A"),
                            onGainChanged: { newGain in
                                if let s = sourceB {
                                    controller.setGainDB(newGain, for: s.url.path)
                                }
                            }
                        )
                        .frame(width: 14, height: availableHeight)

                        Text(formatGainDB(gainB))
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "FF9F0A"))
                            .frame(width: 28)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if let s = sourceB { controller.resetGain(for: s.url.path) }
                            }
                            .help("Double-click to reset Track B volume to 0.0 dB")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Helpers

    private func formatDB(_ db: Float) -> String {
        if db <= -59.5 {
            return "-inf"
        }
        return String(format: "%.1f", db)
    }

    private func formatGainDB(_ db: Float) -> String {
        if abs(db) < 0.05 {
            return "0.0 dB"
        } else if db > 0 {
            return String(format: "+%.1f", db)
        } else {
            return String(format: "%.1f", db)
        }
    }
}

// MARK: - Single Meter Bar

private struct SingleMeterBar: View {
    let liveRMS: Float
    let livePeak: Float
    let maxPeak: Float
    let peakColor: Color
    let rmsColor: Color
    let troughColor: Color

    private let minDB: Float = -48.0
    private let maxDB: Float = 0.0

    private func fraction(for db: Float) -> CGFloat {
        if db >= maxDB { return 1.0 }
        if db <= minDB { return 0.0 }
        return CGFloat((db - minDB) / (maxDB - minDB))
    }

    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let rmsHeight = max(0, totalHeight * fraction(for: liveRMS))
            let peakHeight = max(0, totalHeight * fraction(for: livePeak))
            let peakHoldY = totalHeight * (1.0 - fraction(for: maxPeak))

            ZStack(alignment: .bottom) {
                // Background Trough
                RoundedRectangle(cornerRadius: 2)
                    .fill(troughColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )

                // Translucent Peak segment
                RoundedRectangle(cornerRadius: 2)
                    .fill(peakColor)
                    .frame(height: peakHeight)

                // Solid RMS segment
                RoundedRectangle(cornerRadius: 2)
                    .fill(rmsColor)
                    .frame(height: rmsHeight)

                // Peak hold indicator line
                if maxPeak > minDB {
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(height: 1.5)
                        .position(x: geo.size.width / 2, y: min(max(1, peakHoldY), totalHeight - 1))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

// MARK: - Center Decibel Scale

private struct CenterDBScale: View {
    let height: CGFloat
    private let minDB: Float = -48.0
    private let maxDB: Float = 0.0
    private let majorSteps: [Int] = [0, -6, -12, -18, -24, -30, -36, -42, -48]

    var body: some View {
        ZStack {
            // Ticks Canvas
            Canvas { context, size in
                for db in stride(from: 0, through: -48, by: -2) {
                    let fraction = CGFloat((Float(db) - minDB) / (maxDB - minDB))
                    let y = size.height * (1.0 - fraction)
                    let isMajor = (db % 6 == 0)

                    // Left ticks
                    var leftPath = Path()
                    leftPath.move(to: CGPoint(x: 0, y: y))
                    leftPath.addLine(to: CGPoint(x: isMajor ? 5 : 2.5, y: y))
                    context.stroke(
                        leftPath,
                        with: .color(.white.opacity(isMajor ? 0.35 : 0.14)),
                        lineWidth: 1
                    )

                    // Right ticks
                    var rightPath = Path()
                    rightPath.move(to: CGPoint(x: size.width, y: y))
                    rightPath.addLine(to: CGPoint(x: size.width - (isMajor ? 5 : 2.5), y: y))
                    context.stroke(
                        rightPath,
                        with: .color(.white.opacity(isMajor ? 0.35 : 0.14)),
                        lineWidth: 1
                    )
                }
            }

            // Labels in center
            ForEach(majorSteps, id: \.self) { db in
                let fraction = CGFloat((Float(db) - minDB) / (maxDB - minDB))
                let y = height * (1.0 - fraction)

                Text("\(db)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.50))
                    .position(x: 22, y: y)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Vertical Meter Fader

private struct VerticalMeterFader: View {
    let gainDB: Float
    let tint: Color
    let onGainChanged: (Float) -> Void

    private let minGain: Float = -24.0
    private let maxGain: Float = 6.0

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let fraction = CGFloat((gainDB - minGain) / (maxGain - minGain))
            let thumbY = height * (1.0 - fraction)

            ZStack(alignment: .top) {
                // Vertical slider line
                Rectangle()
                    .fill(tint.opacity(0.35))
                    .frame(width: 1.5, height: height)
                    .position(x: geo.size.width / 2, y: height / 2)

                // Draggable thumb
                Circle()
                    .stroke(tint, lineWidth: 2)
                    .background(Circle().fill(Color(hex: "141619")))
                    .frame(width: 11, height: 11)
                    .position(x: geo.size.width / 2, y: min(max(5.5, thumbY), height - 5.5))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let clampedY = min(max(0, gesture.location.y), height)
                        let newFraction = 1.0 - Float(clampedY / height)
                        let newGain = minGain + newFraction * (maxGain - minGain)
                        let rounded = (newGain * 10).rounded() / 10
                        onGainChanged(rounded)
                    }
            )
        }
    }
}
