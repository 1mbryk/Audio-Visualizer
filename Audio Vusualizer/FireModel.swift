//
//  FireModel.swift
//  Audio Vusualizer
//
//  Simulation of the campfire's height envelope (rendered by Fire.metal)
//  and of the sparks flying above it.
//

import SwiftUI

/// Standard normal sample (Box–Muller).
func gaussian() -> Double {
    let u1 = Double.random(in: Double.ulpOfOne..<1)
    let u2 = Double.random(in: 0..<1)
    return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
}

final class FireModel {

    // MARK: Tunables

    /// Mean and spread of the (relative) tongue height, before loudness is applied.
    let heightMean = 0.55
    let heightSigma = 0.16
    /// Expected outliers per tongue per second, and their size range.
    let outlierRate = 0.12
    let outlierBoost = 1.5...2.4
    /// Horizontal distance between envelope nodes, points.
    let spacing: CGFloat = 40
    /// Bell-shaped envelope across the width: σ in units of half-width,
    /// and the minimum height factor kept at the edges so the fire spans the whole window.
    let bellSigma = 0.45
    let bellFloor = 0.22
    /// In stereo mode the bell is much flatter so each side can follow its own channel.
    let stereoBellSigma = 0.7
    let stereoBellFloor = 0.7

    /// Height factor for a horizontal position `x` normalized to -1...1.
    func bell(_ x: Double) -> Double {
        let sigma = stereo ? stereoBellSigma : bellSigma
        let floor = stereo ? stereoBellFloor : bellFloor
        return floor + (1 - floor) * exp(-x * x / (2 * sigma * sigma))
    }

    // MARK: State

    struct Tongue {
        var height: Double = 0        // current relative height (smoothed)
        var target: Double = 0        // relative height it is moving toward
        var retargetIn: Double = 0    // seconds until a new target is sampled
        var boost: Double = 0         // current extra height from an outlier
        var boostTarget: Double = 0   // outlier size, decays to 0
    }

    struct Spark {
        var p: CGPoint
        var v: CGVector
        var life: Double
        let maxLife: Double
        let size: CGFloat
    }

    private(set) var tongues: [Tongue] = []
    private var sparks: [Spark] = []
    private var lastTime: Double?
    /// Seconds since the fire started; drives the shader's noise.
    private(set) var time: Double = 0
    /// Smoothed loudness of both channels (0...1).
    private(set) var loudness: Double = 0
    /// Smoothed loudness of the left and right channels (0...1), used in stereo mode.
    private var loudnessLeft: Double = 0
    private var loudnessRight: Double = 0
    /// Stereo mode: the left half of the fire follows the left channel, the right half the right one.
    private(set) var stereo = false

    // MARK: Update

    func step(date: Date, size: CGSize, level: Double,
              left: Double, right: Double, stereo: Bool) {
        self.stereo = stereo
        let now = date.timeIntervalSinceReferenceDate
        let dt = min(max(now - (lastTime ?? now), 0), 1.0 / 20)
        lastTime = now
        time += dt

        let k = min(1, dt * 8)
        loudness += (level - loudness) * k
        loudnessLeft += (left - loudnessLeft) * k
        loudnessRight += (right - loudnessRight) * k

        let needed = max(8, Int(size.width / spacing) + 1)
        if tongues.count != needed {
            tongues = (0..<needed).map { _ in
                var t = Tongue()
                t.target = sampleHeight()
                t.height = t.target
                t.retargetIn = .random(in: 0...0.6)
                return t
            }
        }

        for i in tongues.indices {
            var t = tongues[i]

            // Normally distributed heights, re-sampled at random intervals.
            t.retargetIn -= dt
            if t.retargetIn <= 0 {
                t.target = sampleHeight()
                t.retargetIn = .random(in: 0.25...0.7)
            }

            // Random outliers: a tongue swells up, then slowly settles.
            if Double.random(in: 0..<1) < outlierRate * dt {
                t.boostTarget = max(t.boostTarget, .random(in: outlierBoost) - 1)
            }
            t.boostTarget *= exp(-dt * 1.6)
            t.boost += (t.boostTarget - t.boost) * min(1, dt * 5)

            t.height += (t.target - t.height) * min(1, dt * 3.5)
            tongues[i] = t
        }

        updateSparks(dt: dt, size: size)
    }

    private func sampleHeight() -> Double {
        max(0.12, heightMean + heightSigma * gaussian())
    }

    /// Envelope heights for the shader, as fractions of the view height,
    /// evenly spaced from the left edge (first) to the right edge (last).
    func envelope() -> [Float] {
        let last = Double(max(tongues.count - 1, 1))
        return tongues.enumerated().map { i, t in
            let u = Double(i) / last                 // 0 left edge ... 1 right edge
            // In stereo the loudness crossfades smoothly from the left to the right channel.
            let loud = stereo ? loudnessLeft + (loudnessRight - loudnessLeft) * u : loudness
            // A small flame always burns; loudness scales everything else.
            let amp = 0.08 + 0.95 * pow(loud, 1.15)
            return Float(min((t.height + t.boost) * amp * bell(u * 2 - 1), 1.4))
        }
    }

    private func updateSparks(dt: Double, size: CGSize) {
        let rate = 3 + 70 * loudness * loudness
        var toSpawn = rate * dt
        while toSpawn > 0 {
            if toSpawn < 1, Double.random(in: 0..<1) > toSpawn { break }
            toSpawn -= 1
            let life = Double.random(in: 0.8...2.2)
            sparks.append(Spark(
                // Sparks follow the same bell: mostly from the middle of the fire.
                p: CGPoint(x: size.width * CGFloat(0.5 + 0.5 * min(max(gaussian() * (stereo ? stereoBellSigma : bellSigma) * 1.2, -1), 1)),
                           y: size.height - .random(in: size.height * 0.05...size.height * 0.3) * (0.3 + loudness)),
                v: CGVector(dx: .random(in: -25...25), dy: -CGFloat.random(in: 60...200) * (0.5 + loudness)),
                life: life, maxLife: life, size: .random(in: 0.8...2.2)))
        }
        for i in sparks.indices {
            sparks[i].life -= dt
            sparks[i].v.dx += CGFloat(sin(time * 3 + Double(i)) * 40 * dt)
            sparks[i].p.x += sparks[i].v.dx * dt
            sparks[i].p.y += sparks[i].v.dy * dt
        }
        sparks.removeAll { $0.life <= 0 || $0.p.y < -10 }
    }

    // MARK: Drawing

    func drawSparks(in context: inout GraphicsContext) {
        for s in sparks {
            let k = s.life / s.maxLife
            let r = s.size * CGFloat(0.5 + 0.5 * k)
            let rect = CGRect(x: s.p.x - r, y: s.p.y - r, width: 2 * r, height: 2 * r)
            // Faint glow plus a bright core.
            let glow = rect.insetBy(dx: -2.5 * r, dy: -2.5 * r)
            context.fill(Path(ellipseIn: glow), with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.35, blue: 0.05).opacity(0.3 * k), .clear]),
                center: s.p, startRadius: 0, endRadius: glow.width / 2))
            context.fill(Path(ellipseIn: rect),
                         with: .color(Color(red: 1, green: 0.6 + 0.35 * k, blue: 0.25 * k).opacity(k)))
        }
    }
}
