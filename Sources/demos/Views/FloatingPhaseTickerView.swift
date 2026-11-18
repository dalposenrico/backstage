import AppKit
import SwiftUI

/// Horizontal scrolling marquee ticker for project workflow phases.
/// Uses hardware CoreAnimation for 120Hz/60Hz buttery smoothness,
/// a calm readable speed, and clean rounded typography.
struct FloatingPhaseTickerView: View {
    let phase: ProductionPhase
    let isClient: Bool
    let size: PetPuckSize
    var onNextPhase: (() -> Void)? = nil

    @State private var isHovered = false

    private var themeColor: Color {
        isClient ? Color(hex: "FB923C") : Color(hex: "34D399")
    }

    private var nsThemeColor: NSColor {
        if isClient {
            return NSColor(red: 1.0, green: 0.60, blue: 0.22, alpha: 1.0)
        } else {
            return NSColor(red: 0.20, green: 0.88, blue: 0.58, alpha: 1.0)
        }
    }

    private var tickerWidth: CGFloat {
        switch size {
        case .small: return 88
        case .medium: return 104
        case .large: return 118
        case .extraLarge: return 132
        }
    }

    private var tickerHeight: CGFloat {
        size.capsuleHeight * 0.58
    }

    private var fontSize: CGFloat {
        switch size {
        case .small: return 8.5
        case .medium: return 9.5
        case .large: return 10.5
        case .extraLarge: return 12.0
        }
    }

    var body: some View {
        Button {
            onNextPhase?()
        } label: {
            ZStack {
                // High-contrast dark pill with tint
                Capsule()
                    .fill(Color(hex: "111418"))

                Capsule()
                    .fill(themeColor.opacity(isHovered ? 0.20 : 0.12))

                // Hardware-accelerated smooth marquee
                HardwareMarqueeRepresentable(
                    text: "\(phase.rawValue)   •   ",
                    textColor: nsThemeColor,
                    fontSize: fontSize,
                    speed: 13.0
                )
                .padding(.horizontal, 6)
                .mask(
                    HStack(spacing: 0) {
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 6)

                        Rectangle().fill(Color.black)

                        LinearGradient(
                            colors: [.black, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: 6)
                    }
                )
            }
            .frame(width: tickerWidth, height: tickerHeight)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(themeColor.opacity(isHovered ? 0.65 : 0.38), lineWidth: 0.9)
            )
            .shadow(color: themeColor.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 3 : 1.5)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Workflow Phase: \(phase.rawValue) (\(isClient ? "Client Project" : "Personal Project")) — Click to advance phase")
    }
}

// MARK: - Hardware CoreAnimation Marquee (120Hz/60Hz GPU composited)

private struct HardwareMarqueeRepresentable: NSViewRepresentable {
    let text: String
    let textColor: NSColor
    let fontSize: CGFloat
    let speed: CGFloat

    func makeNSView(context: Context) -> HardwareMarqueeNSView {
        let view = HardwareMarqueeNSView()
        view.configure(text: text, textColor: textColor, fontSize: fontSize, speed: speed)
        return view
    }

    func updateNSView(_ nsView: HardwareMarqueeNSView, context: Context) {
        nsView.configure(text: text, textColor: textColor, fontSize: fontSize, speed: speed)
    }
}

private final class HardwareMarqueeNSView: NSView {
    private let scrollLayer = CALayer()
    private var textLayers: [CATextLayer] = []

    private var currentText: String = ""
    private var currentTextColor: NSColor = .white
    private var currentFontSize: CGFloat = 9.5
    private var currentSpeed: CGFloat = 13.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(scrollLayer)
    }

    func configure(text: String, textColor: NSColor, fontSize: CGFloat, speed: CGFloat) {
        let needsRebuild = (text != currentText) || (fontSize != currentFontSize) || (speed != currentSpeed)
        let needsColorUpdate = (textColor != currentTextColor)

        currentText = text
        currentTextColor = textColor
        currentFontSize = fontSize
        currentSpeed = speed

        if needsRebuild {
            updateContent()
        } else if needsColorUpdate {
            updateColors()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateContent()
        }
    }

    override func layout() {
        super.layout()
        updateContent()
    }

    private var font: NSFont {
        let base = NSFont.systemFont(ofSize: currentFontSize, weight: .bold)
        if let desc = base.fontDescriptor.withDesign(.rounded), let rounded = NSFont(descriptor: desc, size: currentFontSize) {
            return rounded
        }
        return base
    }

    private func measureCycleWidth() -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: 0.4
        ]
        let width = (currentText as NSString).size(withAttributes: attrs).width
        return max(ceil(width), 10)
    }

    private func updateContent() {
        guard bounds.width > 0, bounds.height > 0, !currentText.isEmpty else { return }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let cycleWidth = measureCycleWidth()
        let neededCopies = max(Int(ceil(bounds.width / cycleWidth)) + 2, 3)

        // Clear existing layers
        for layer in textLayers {
            layer.removeFromSuperlayer()
        }
        textLayers.removeAll()
        scrollLayer.removeAllAnimations()

        scrollLayer.frame = NSRect(x: 0, y: 0, width: cycleWidth * CGFloat(neededCopies), height: bounds.height)

        let attrString = NSAttributedString(string: currentText, attributes: [
            .font: font,
            .foregroundColor: currentTextColor,
            .kern: 0.4
        ])

        // Vertical centering offset for CATextLayer font metrics
        let textHeight = ceil(font.ascender - font.descender)
        let yOffset = max(0, (bounds.height - textHeight) / 2.0 + font.descender * 0.4)

        for i in 0..<neededCopies {
            let tLayer = CATextLayer()
            tLayer.contentsScale = scale
            tLayer.string = attrString
            tLayer.alignmentMode = .left
            tLayer.isWrapped = false
            tLayer.truncationMode = .none
            tLayer.frame = CGRect(
                x: CGFloat(i) * cycleWidth,
                y: yOffset,
                width: cycleWidth,
                height: bounds.height
            )
            scrollLayer.addSublayer(tLayer)
            textLayers.append(tLayer)
        }

        restartAnimation(cycleWidth: cycleWidth)
    }

    private func updateColors() {
        let attrString = NSAttributedString(string: currentText, attributes: [
            .font: font,
            .foregroundColor: currentTextColor,
            .kern: 0.4
        ])
        for layer in textLayers {
            layer.string = attrString
        }
    }

    private func restartAnimation(cycleWidth: CGFloat? = nil) {
        let cycle = cycleWidth ?? measureCycleWidth()
        scrollLayer.removeAnimation(forKey: "marqueeGlide")

        guard cycle > 0, currentSpeed > 0 else { return }

        let anim = CABasicAnimation(keyPath: "transform.translation.x")
        anim.fromValue = 0
        anim.toValue = -cycle
        anim.duration = Double(cycle / currentSpeed)
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.isRemovedOnCompletion = false

        scrollLayer.add(anim, forKey: "marqueeGlide")
    }
}
