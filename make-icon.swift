#!/usr/bin/swift
// Generates the goodvibrations HQ app icon — dark background + white waveform bars.
// Usage: swift make-icon.swift <output-iconset-dir>
// Then run: iconutil -c icns <output-iconset-dir> -o AppIcon.icns

import CoreGraphics
import Foundation
import ImageIO

func renderIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // ── Background ────────────────────────────────────────────────────────────
    // Deep dark, slightly warm-tinted
    let bgRadius = s * 0.22
    ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0))
    let bg = CGMutablePath()
    bg.addRoundedRect(
        in: CGRect(x: 0, y: 0, width: s, height: s),
        cornerWidth: bgRadius, cornerHeight: bgRadius
    )
    ctx.addPath(bg)
    ctx.fillPath()

    // Subtle inner vignette: slightly lighter inner circle
    if let grad = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.18, green: 0.18, blue: 0.22, alpha: 0.55),
            CGColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 0.00)
        ] as CFArray,
        locations: [0, 1]
    ) {
        ctx.saveGState()
        ctx.addPath(bg)
        ctx.clip()
        ctx.drawRadialGradient(
            grad,
            startCenter: CGPoint(x: s * 0.5, y: s * 0.52),
            startRadius: 0,
            endCenter:   CGPoint(x: s * 0.5, y: s * 0.52),
            endRadius:   s * 0.62,
            options: []
        )
        ctx.restoreGState()
    }

    // ── Waveform bars ─────────────────────────────────────────────────────────
    // 5 bars, tallest in centre, symmetric
    let relHeights: [CGFloat] = [0.30, 0.55, 0.78, 0.55, 0.30]
    let barW   = s * 0.092
    let gap    = s * 0.048
    let totalW = CGFloat(relHeights.count) * barW + CGFloat(relHeights.count - 1) * gap
    var x      = (s - totalW) / 2.0

    for relH in relHeights {
        let barH = s * relH
        let y    = (s - barH) / 2.0
        ctx.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 0.93))
        let bar = CGMutablePath()
        bar.addRoundedRect(
            in: CGRect(x: x, y: y, width: barW, height: barH),
            cornerWidth: barW / 2, cornerHeight: barW / 2
        )
        ctx.addPath(bar)
        ctx.fillPath()
        x += barW + gap
    }

    return ctx.makeImage()
}

func savePNG(_ image: CGImage, to path: String) {
    let url  = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        print("✗ Could not create destination for \(path)"); return
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// ── Main ──────────────────────────────────────────────────────────────────────

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift make-icon.swift <output.iconset>")
    exit(1)
}

let iconsetDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let specs: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (sz, name) in specs {
    guard let img = renderIcon(size: sz) else {
        print("✗ Failed to render \(name)"); continue
    }
    savePNG(img, to: "\(iconsetDir)/\(name)")
    print("  ✓ \(name)")
}

print("Done — run: iconutil -c icns \"\(iconsetDir)\" -o AppIcon.icns")
