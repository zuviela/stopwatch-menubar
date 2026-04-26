import AppKit
import SwiftUI

enum FireworkStyle {
    case small
    case grand

    var burstCount: Int { self == .small ? 3 : 4 }
    var particleRange: ClosedRange<Int> { self == .small ? 8...10 : 12...16 }
    var startDelayStep: Double { self == .small ? 0.22 : 0.32 }
    var maxRadiusRange: ClosedRange<Double> { self == .small ? 50...75 : 65...100 }
    var lifeSpanRange: ClosedRange<Double> { self == .small ? 1.0...1.2 : 1.2...1.5 }
    var spreadX: Double { self == .small ? 55 : 90 }
    var spreadY: Double { self == .small ? 20 : 30 }
    var sparkleCount: Int { self == .small ? 0 : 70 }
    var totalDuration: Double { self == .small ? 1.4 : 2.6 }
    var displayDuration: TimeInterval { self == .small ? 1.8 : 3.2 }
    var windowSize: CGSize {
        self == .small ? CGSize(width: 320, height: 180) : CGSize(width: 440, height: 260)
    }

    var palettes: [[Color]] {
        switch self {
        case .small:
            return [
                [.red, .yellow],
                [.cyan, .white],
                [.green, .yellow],
                [Color(red: 1.0, green: 0.2, blue: 0.7), .white],
                [.orange, .yellow],
                [.purple, .pink]
            ]
        case .grand:
            return [
                [.red, .yellow, .white],
                [.cyan, .white, .blue],
                [.green, .yellow, .white],
                [Color(red: 1.0, green: 0.2, blue: 0.7), .white, .yellow],
                [.orange, .yellow, .red],
                [.purple, .pink, .white]
            ]
        }
    }

    var burstSoundFile: String { self == .small ? "Pop" : "Bottle" }
    var burstSoundTimes: [TimeInterval] {
        switch self {
        case .small: return [0.0, 0.22]
        case .grand: return [0.0, 0.32, 0.64, 0.96]
        }
    }
    var trailingSound: (name: String, delay: TimeInterval)? {
        nil
    }
}

private struct Burst {
    let centerOffset: CGPoint
    let colors: [Color]
    let particleCount: Int
    let startDelay: Double
    let maxRadius: Double
    let angleJitter: Double
    let lifeSpan: Double
}

private struct Sparkle {
    let originOffset: CGPoint
    let color: Color
    let startDelay: Double
    let fallSpeed: Double
    let lifetime: Double
}

struct FireworkView: View {
    let style: FireworkStyle
    private let bursts: [Burst]
    private let sparkles: [Sparkle]
    private let pixelSize: CGFloat = 8
    private let frameRate: Double = 12
    @State private var startTime = Date()

    init(style: FireworkStyle) {
        self.style = style
        let palettes = style.palettes
        var burstList: [Burst] = []
        for i in 0..<style.burstCount {
            burstList.append(Burst(
                centerOffset: CGPoint(
                    x: .random(in: -style.spreadX...style.spreadX),
                    y: .random(in: -10...style.spreadY)
                ),
                colors: palettes.randomElement() ?? [.white],
                particleCount: Int.random(in: style.particleRange),
                startDelay: Double(i) * style.startDelayStep,
                maxRadius: .random(in: style.maxRadiusRange),
                angleJitter: .random(in: 0...(2 * .pi)),
                lifeSpan: .random(in: style.lifeSpanRange)
            ))
        }
        bursts = burstList

        let sparkleColors: [Color] = [
            .yellow, .white, .orange, .red, .cyan,
            Color(red: 1.0, green: 0.8, blue: 0.4)
        ]
        var sparkleList: [Sparkle] = []
        for _ in 0..<style.sparkleCount {
            sparkleList.append(Sparkle(
                originOffset: CGPoint(
                    x: .random(in: -150...150),
                    y: .random(in: -60...40)
                ),
                color: sparkleColors.randomElement() ?? .white,
                startDelay: .random(in: 0.6...2.0),
                fallSpeed: .random(in: 35...90),
                lifetime: .random(in: 0.7...1.1)
            ))
        }
        sparkles = sparkleList
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / frameRate, paused: false)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(startTime)
            Canvas { gc, size in
                let centerBase = CGPoint(x: size.width / 2, y: size.height / 2)
                for burst in bursts {
                    let local = elapsed - burst.startDelay
                    if local < 0 { continue }
                    let raw = min(local / burst.lifeSpan, 1.0)
                    let stepped = floor(raw * frameRate) / frameRate
                    drawBurst(burst, in: gc, base: centerBase, progress: stepped)
                }
                for sparkle in sparkles {
                    let local = elapsed - sparkle.startDelay
                    if local < 0 || local > sparkle.lifetime { continue }
                    drawSparkle(
                        sparkle,
                        in: gc,
                        base: centerBase,
                        elapsed: local,
                        lifeProgress: local / sparkle.lifetime
                    )
                }
            }
        }
    }

    private func drawBurst(_ burst: Burst, in gc: GraphicsContext, base: CGPoint, progress: Double) {
        let alpha: Double
        switch progress {
        case ..<0.6:  alpha = 1.0
        case ..<0.85: alpha = 0.6
        case ..<1.0:  alpha = 0.3
        default:      return
        }
        let radius = burst.maxRadius * sqrt(progress)
        let gravity = progress * progress * 32
        let center = CGPoint(x: base.x + burst.centerOffset.x, y: base.y + burst.centerOffset.y)
        for i in 0..<burst.particleCount {
            let angle = Double(i) / Double(burst.particleCount) * 2 * .pi + burst.angleJitter
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius + gravity
            drawPixel(in: gc, at: CGPoint(x: x, y: y), color: burst.colors[i % burst.colors.count].opacity(alpha))
        }
    }

    private func drawSparkle(_ sparkle: Sparkle, in gc: GraphicsContext, base: CGPoint, elapsed: Double, lifeProgress: Double) {
        let alpha: Double
        switch lifeProgress {
        case ..<0.35: alpha = 1.0
        case ..<0.7:  alpha = 0.55
        case ..<1.0:  alpha = 0.25
        default:      return
        }
        let x = base.x + sparkle.originOffset.x
        let y = base.y + sparkle.originOffset.y + sparkle.fallSpeed * elapsed
        drawPixel(in: gc, at: CGPoint(x: x, y: y), color: sparkle.color.opacity(alpha))
    }

    private func drawPixel(in gc: GraphicsContext, at point: CGPoint, color: Color) {
        let snappedX = floor(point.x / pixelSize) * pixelSize
        let snappedY = floor(point.y / pixelSize) * pixelSize
        let rect = CGRect(x: snappedX, y: snappedY, width: pixelSize, height: pixelSize)
        gc.fill(Path(rect), with: .color(color))
    }
}

final class FireworkWindowController {
    private var window: NSWindow?

    func play(style: FireworkStyle, near anchor: NSRect?) {
        guard let anchor else { return }
        let size = style.windowSize
        let originX = anchor.midX - size.width / 2
        let originY = anchor.minY - size.height
        let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.level = .statusBar
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.contentView = NSHostingView(rootView: FireworkView(style: style))
        win.orderFrontRegardless()

        window?.orderOut(nil)
        window = win

        playSound(for: style)

        DispatchQueue.main.asyncAfter(deadline: .now() + style.displayDuration) { [weak self, weak win] in
            win?.orderOut(nil)
            if self?.window === win { self?.window = nil }
        }
    }

    private func playSound(for style: FireworkStyle) {
        let burstFile = "/System/Library/Sounds/\(style.burstSoundFile).aiff"
        for t in style.burstSoundTimes {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                NSSound(contentsOfFile: burstFile, byReference: true)?.play()
            }
        }
        if let trailing = style.trailingSound {
            let path = "/System/Library/Sounds/\(trailing.name).aiff"
            DispatchQueue.main.asyncAfter(deadline: .now() + trailing.delay) {
                NSSound(contentsOfFile: path, byReference: true)?.play()
            }
        }
    }
}
