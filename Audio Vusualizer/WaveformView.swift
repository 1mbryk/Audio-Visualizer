//
//  WaveformView.swift
//  Audio Vusualizer
//
//  Amplitude waveform: the peak envelope of the last few seconds of audio,
//  scrolling from right (now) to left (past), mirrored around the centre.
//

import SwiftUI

/// Slowly following reference loudness (dB) for the waveform's auto level.
final class AutoLevel {
    /// nil until the first frame, which takes the level straight from the audio, so a
    /// freshly opened view doesn't start with every bar pinned to the top.
    private(set) var reference: Float?

    /// Feeds the current column levels and returns the smoothed reference.
    func update(with dbs: [Float]) -> Float {
        // A high percentile rather than the maximum, so one spike doesn't squash everything.
        let sorted = dbs.sorted()
        let target = max(sorted.isEmpty ? -120 : sorted[Int(Double(sorted.count - 1) * 0.97)],
                         -50) // below this it is silence: don't blow up the noise
        // Follow gently (per frame): a bit faster when it gets louder than when quieter,
        // so the scale itself doesn't make all bars pump.
        guard let current = reference else {
            reference = target
            return target
        }
        let next = current + (target - current) * (target > current ? 0.05 : 0.01)
        reference = next
        return next
    }
}

/// Smoothly advancing position in the audio (in blocks) that the waveform scrolls by.
final class Playhead {
    /// How far the playhead stays behind the newest audio, seconds. Covers the gap
    /// between audio callbacks so the playhead never has to wait for data.
    static let latency = 0.045

    private var position: Double?
    private var lastDate: Date?

    func advance(to date: Date, newestBlock: Int, blocksPerSecond: Double) -> Double {
        let target = Double(newestBlock) - Self.latency * blocksPerSecond
        let dt = min(max(date.timeIntervalSince(lastDate ?? date), 0), 0.1)
        lastDate = date

        guard var p = position, abs(target - p) < blocksPerSecond * 0.5 else {
            // First frame, or far off (e.g. after a pause): jump straight there.
            position = target
            return target
        }
        // Constant speed, nudged gently towards the real stream to absorb clock drift.
        p += dt * blocksPerSecond
        p += (target - p) * min(1, dt * 1.5)
        p = min(p, Double(newestBlock))
        position = p
        return p
    }
}

struct WaveformView: View {
    let audio: SystemAudioMonitor

    @AppStorage(WaveformSettings.stereo) private var stereo = false
    /// dB of loudness between the bottom and the top of a bar.
    @AppStorage(WaveformSettings.rangeDB) private var rangeDB = WaveformSettings.defaultRangeDB
    @State private var level = AutoLevel()
    /// When the view first drew: bars grow in from zero after switching to this mode.
    @State private var appearance = Appearance()
    @State private var playhead = Playhead()
    /// Seconds of history shown across the width.
    @AppStorage(WaveformSettings.seconds) private var seconds = WaveformSettings.defaultSeconds
    /// Width of one bar, points; the gap after it is half as wide (at least 1 pt).
    @AppStorage(WaveformSettings.barWidth) private var barWidthSetting = WaveformSettings.defaultBarWidth
    @AppStorage(WaveformSettings.fade) private var fade = true

    private var barWidth: CGFloat { CGFloat(barWidthSetting) }
    private var barGap: CGFloat { max(1, barWidth / 2) }

    var body: some View {
        TimelineView(.animation) { timeline in
            // Capturing the date makes the Canvas redraw every frame.
            Canvas { [date = timeline.date] context, size in
                draw(in: &context, size: size, date: date)
            }
        }
        .background(.black)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, date: Date) {
        let step = barWidth + barGap
        let columns = max(1, Int(size.width / step)) + 1          // +1 slides in from the right
        let blocksPerSecond = audio.sampleRate / Double(SystemAudioMonitor.peakBlock)
        // Whole blocks per bar, so every bar always covers the same audio while it scrolls.
        let k = max(1, Int((seconds * blocksPerSecond / Double(columns)).rounded()))
        // Each bar's energy is measured over at least ~23 ms, or bass makes it flicker.
        let window = max(k, 4)

        // Audio arrives in bursts (one callback = several blocks), so scrolling by the
        // newest block jerks. Scroll by a playhead on a smooth clock instead, which runs a
        // little behind the newest data so there's always audio to show.
        let latency = Int(Playhead.latency * blocksPerSecond) + 1
        let rms = audio.recentRMS(count: columns * k + window + latency + 2 * k)
        let n = rms.left.count
        guard n > 0 else { return }
        let head = playhead.advance(to: date, newestBlock: rms.end, blocksPerSecond: blocksPerSecond)
        let whole = Int(head.rounded(.down))
        // Absolute block index where the newest complete bar ends.
        let alignedEnd = whole - whole % k
        // How far the next (still filling) bar has grown: scroll by that fraction.
        let scroll = CGFloat((head - Double(alignedEnd)) / Double(k)) * step

        /// RMS in dB over the `window` blocks ending at absolute block `endBlock`.
        func barDB(_ values: [Float], endBlock: Int) -> Float {
            let hi = n - (rms.end - endBlock)          // position in the returned arrays
            let lo = max(hi - window, 0)
            guard hi > lo else { return -120 }
            var sum: Float = 0
            for i in lo..<hi { sum += values[i] * values[i] }
            return 20 * log10(max(sqrt(sum / Float(hi - lo)), 1e-6))
        }

        let mono = stereo ? [] : zip(rms.left, rms.right).map { sqrt(($0 * $0 + $1 * $1) / 2) }
        var up = [Float](repeating: -120, count: columns)
        var down = [Float](repeating: -120, count: columns)
        for c in 0..<columns {
            // Column `columns - 1` is the newest complete bar, at the right edge.
            let endBlock = alignedEnd - (columns - 1 - c) * k
            if stereo {
                // Left channel above the centre line, right channel below.
                up[c] = barDB(rms.left, endBlock: endBlock)
                down[c] = barDB(rms.right, endBlock: endBlock)
            } else {
                up[c] = barDB(mono, endBlock: endBlock)
                down[c] = up[c]
            }
        }

        // Auto level: the loudest parts of the recent history reach the top,
        // and `range` dB below that is the bottom.
        let reference = level.update(with: up + down)
        let grow = appearance.progress(at: date)
        let range = Float(rangeDB)
        let mid = size.height / 2
        // Bars may use the whole height; only a hairline is kept free at the edges.
        let maxHalf = mid - 1
        func height(_ db: Float) -> CGFloat {
            let v = min(max(1 + (db - reference) / range, 0), 1)
            // Curve that stretches the loud end, so beats stand out from sustained parts.
            return CGFloat(pow(v, 1.7)) * maxHalf * grow
        }

        // Right-align the bars, then slide them left as the next bar fills up.
        let origin = size.width - CGFloat(columns) * step - scroll
        MirroredBars.draw(in: &context, size: size,
                          up: up.map(height), down: down.map(height),
                          originX: origin, step: step, barWidth: barWidth, stereo: stereo)

        // The past fades out to the left.
        guard fade else { return }
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [.black.opacity(0.85), .black.opacity(0)]),
            startPoint: .zero, endPoint: CGPoint(x: size.width * 0.7, y: 0)))
    }
}

/// Grow-in animation for a freshly shown visualization: 0 → 1 with an ease-out.
final class Appearance {
    private var start: Date?
    let duration: TimeInterval = 0.6

    func progress(at date: Date) -> CGFloat {
        if start == nil { start = date }
        let t = min(max(date.timeIntervalSince(start!) / duration, 0), 1)
        return CGFloat(1 - pow(1 - t, 3))
    }
}
