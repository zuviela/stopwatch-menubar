#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Renders a simple, friendly stopwatch icon as a .iconset directory of PNGs
// at all sizes macOS expects. Run from anywhere; writes next to scripts/.
//
// Usage: ./scripts/make-icon.swift
//
// Output: Resources/AppIcon.iconset/icon_<size>.png (and @2x variants).

let fm = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let outDir = projectRoot.appendingPathComponent("Resources/AppIcon.iconset", isDirectory: true)
try? fm.removeItem(at: outDir)
try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Background: rounded squircle in macOS app icon style
    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bgPath = CGPath(roundedRect: rect, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    let gradient = CGGradient(
        colorsSpace: cs,
        colors: [
            NSColor(calibratedRed: 0.20, green: 0.55, blue: 1.00, alpha: 1.0).cgColor,
            NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.85, alpha: 1.0).cgColor
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.saveGState()
    ctx.addPath(bgPath); ctx.clip()
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: s * 0.5, y: s),
        end: CGPoint(x: s * 0.5, y: 0),
        options: []
    )
    ctx.restoreGState()

    let cx = s * 0.5
    let cy = s * 0.46
    let face = s * 0.34   // clock face radius

    // Crown button (small rounded rect at the top)
    let crownW = s * 0.10
    let crownH = s * 0.07
    let crownRect = CGRect(
        x: cx - crownW / 2,
        y: cy + face + s * 0.06,
        width: crownW,
        height: crownH
    )
    let crownPath = CGPath(
        roundedRect: crownRect,
        cornerWidth: s * 0.02, cornerHeight: s * 0.02,
        transform: nil
    )
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
    ctx.addPath(crownPath); ctx.fillPath()

    // Stem connecting crown to face
    let stemRect = CGRect(
        x: cx - s * 0.012,
        y: cy + face + s * 0.012,
        width: s * 0.024,
        height: s * 0.05
    )
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
    ctx.fill(stemRect)

    // Outer ring (thicker dark border)
    let ring = CGRect(x: cx - face, y: cy - face, width: face * 2, height: face * 2)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: ring)

    let ringInset = s * 0.018
    let inner = ring.insetBy(dx: ringInset, dy: ringInset)
    ctx.setFillColor(NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.0, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: inner)

    // Tick marks: 12 around the face
    let tickColor = NSColor(calibratedWhite: 0.20, alpha: 1.0).cgColor
    ctx.setStrokeColor(tickColor)
    for i in 0..<12 {
        let angle = CGFloat(i) * .pi * 2.0 / 12.0 - .pi / 2.0
        let isMajor = (i % 3 == 0)
        let len = isMajor ? face * 0.16 : face * 0.09
        let lw  = isMajor ? s * 0.018 : s * 0.010
        let outerR = face - ringInset - s * 0.02
        let innerR = outerR - len
        let x1 = cx + cos(angle) * innerR
        let y1 = cy + sin(angle) * innerR
        let x2 = cx + cos(angle) * outerR
        let y2 = cy + sin(angle) * outerR
        ctx.setLineWidth(lw)
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: x1, y: y1))
        ctx.addLine(to: CGPoint(x: x2, y: y2))
        ctx.strokePath()
    }

    // Hand: pointing to ~ "2 o'clock" position for a friendly look
    let handAngle: CGFloat = -.pi / 2.0 + (.pi * 2.0) * (10.0 / 60.0) // 10 seconds past
    let handLen = face * 0.78
    let handX = cx + cos(handAngle) * handLen
    let handY = cy + sin(handAngle) * handLen
    ctx.setStrokeColor(NSColor(calibratedRed: 0.90, green: 0.20, blue: 0.30, alpha: 1.0).cgColor)
    ctx.setLineWidth(s * 0.028)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: cx, y: cy))
    ctx.addLine(to: CGPoint(x: handX, y: handY))
    ctx.strokePath()

    // Center pivot
    ctx.setFillColor(NSColor(calibratedRed: 0.15, green: 0.20, blue: 0.30, alpha: 1.0).cgColor)
    let pivotR = s * 0.028
    ctx.fillEllipse(in: CGRect(x: cx - pivotR, y: cy - pivotR, width: pivotR * 2, height: pivotR * 2))

    // Subtle inner shadow on the dial rim
    ctx.saveGState()
    ctx.addEllipse(in: inner)
    ctx.clip()
    ctx.setStrokeColor(NSColor(calibratedWhite: 0, alpha: 0.10).cgColor)
    ctx.setLineWidth(s * 0.012)
    ctx.strokeEllipse(in: inner)
    ctx.restoreGState()

    let cgImage = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])!
}

struct Variant { let name: String; let pixels: Int }
let variants: [Variant] = [
    Variant(name: "icon_16x16.png",       pixels: 16),
    Variant(name: "icon_16x16@2x.png",    pixels: 32),
    Variant(name: "icon_32x32.png",       pixels: 32),
    Variant(name: "icon_32x32@2x.png",    pixels: 64),
    Variant(name: "icon_128x128.png",     pixels: 128),
    Variant(name: "icon_128x128@2x.png",  pixels: 256),
    Variant(name: "icon_256x256.png",     pixels: 256),
    Variant(name: "icon_256x256@2x.png",  pixels: 512),
    Variant(name: "icon_512x512.png",     pixels: 512),
    Variant(name: "icon_512x512@2x.png",  pixels: 1024)
]

for v in variants {
    let data = render(size: v.pixels)
    let url = outDir.appendingPathComponent(v.name)
    try data.write(to: url)
    print("wrote \(v.name) (\(v.pixels)px)")
}

print("Iconset at \(outDir.path)")
