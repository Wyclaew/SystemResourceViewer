import SwiftUI

/// Particle simulation model for celebratory confetti animation.
public struct ConfettiParticle: Identifiable, Sendable {
    public let id: Int
    public let initialFractionX: Double
    public let initialFractionY: Double
    public let vx: Double
    public let vy: Double
    public let gravity: Double
    public let swayAmplitude: Double
    public let swayFrequency: Double
    public let rotationSpeed: Double
    public let initialRotation: Double
    public let width: CGFloat
    public let height: CGFloat
    public let isCircle: Bool
    public let colorIndex: Int
}

/// A celebratory particle animation view rendering colorful fluttering confetti bursting and falling with physics.
public struct ConfettiView: View {
    private static let colors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .cyan, .blue, .purple, .pink
    ]

    public let particles: [ConfettiParticle]
    public let duration: Double
    public let onFinished: (@Sendable () -> Void)?

    @State private var startTime: Date = Date()
    @State private var isCompleted: Bool = false

    public init(
        particleCount: Int = 80,
        duration: Double = 3.0,
        onFinished: (@Sendable () -> Void)? = nil
    ) {
        self.duration = duration
        self.onFinished = onFinished

        // Deterministic pseudo-random generation using 64-bit LCG
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func nextRandomDouble() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 32) / Double(UInt32.max)
        }

        var list: [ConfettiParticle] = []
        list.reserveCapacity(particleCount)

        for i in 0..<particleCount {
            let r1 = nextRandomDouble()
            let r2 = nextRandomDouble()
            let r3 = nextRandomDouble()
            let r4 = nextRandomDouble()
            let r5 = nextRandomDouble()
            let r6 = nextRandomDouble()
            let r7 = nextRandomDouble()

            // Origin: center-lower band of the container
            let fracX = 0.35 + (r1 * 0.30)
            let fracY = 0.55 + (r2 * 0.25)

            // Upward conical burst velocity
            let burstAngle = (r3 - 0.5) * (Double.pi * 0.85) - (Double.pi / 2.0)
            let speed = 220.0 + (r4 * 380.0)
            let vx = cos(burstAngle) * speed
            let vy = sin(burstAngle) * speed

            let gravity = 380.0 + (r5 * 240.0)
            let swayAmp = 12.0 + (r6 * 28.0)
            let swayFreq = 3.5 + (r7 * 6.5)
            let rotSpeed = (r1 - 0.5) * 14.0
            let initRot = r2 * Double.pi * 2.0
            let isCircle = (i % 3 == 0)
            let width = CGFloat(6.0 + (r3 * 6.0))
            let height = isCircle ? width : CGFloat(8.0 + (r4 * 10.0))
            let colorIdx = Int(r5 * Double(Self.colors.count)) % Self.colors.count

            list.append(ConfettiParticle(
                id: i,
                initialFractionX: fracX,
                initialFractionY: fracY,
                vx: vx,
                vy: vy,
                gravity: gravity,
                swayAmplitude: swayAmp,
                swayFrequency: swayFreq,
                rotationSpeed: rotSpeed,
                initialRotation: initRot,
                width: width,
                height: height,
                isCircle: isCircle,
                colorIndex: colorIdx
            ))
        }
        self.particles = list
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard !isCompleted else { return }
                let elapsed = timeline.date.timeIntervalSince(startTime)
                guard elapsed >= 0 else { return }
                let t = min(elapsed, duration)

                // Opacity decay in the final second of animation
                let opacity: Double
                if t >= duration {
                    opacity = 0.0
                } else if t > (duration - 1.0) {
                    opacity = max(0.0, (duration - t) / 1.0)
                } else {
                    opacity = 1.0
                }

                guard opacity > 0.001 else { return }

                for p in particles {
                    // Physics equations: x(t) with sinusoidal flutter, y(t) with gravity
                    let startX = size.width * p.initialFractionX
                    let startY = size.height * p.initialFractionY

                    let sway = sin(t * p.swayFrequency + Double(p.id)) * p.swayAmplitude
                    let currentX = startX + (p.vx * t * 0.75) + sway
                    let currentY = startY + (p.vy * t) + (0.5 * p.gravity * t * t)
                    let currentAngle = p.initialRotation + (p.rotationSpeed * t)

                    var pContext = context
                    pContext.translateBy(x: currentX, y: currentY)
                    pContext.rotate(by: Angle(radians: currentAngle))

                    let rect = CGRect(
                        x: -p.width / 2.0,
                        y: -p.height / 2.0,
                        width: p.width,
                        height: p.height
                    )

                    let color = Self.colors[p.colorIndex].opacity(opacity)

                    if p.isCircle {
                        pContext.fill(Path(ellipseIn: rect), with: .color(color))
                    } else {
                        pContext.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            startTime = Date()
        }
        .task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            isCompleted = true
            onFinished?()
        }
    }
}
