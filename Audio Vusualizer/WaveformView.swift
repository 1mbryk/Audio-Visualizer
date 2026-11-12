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
    private(set) var reference: Float = -30

    /// Feeds the current column levels and returns the smoothed reference.
    func update(with dbs: [Float]) -> Float {
        // A high percentile rather than the maximum, so one spike doesn't squash everything.
        let sorted = dbs.sorted()
        let target = max(sorted.isEmpty ? -120 : sorted[Int(Double(sorted.count - 1) * 0.97)],
                         -50) // below this it is silence: don't blow up the noise
        // Follow gently (per frame): a bit faster when it gets louder than when quieter,
        // so the scale itself doesn't make all bars pump.
        reference += (target - reference) * (target > reference ? 0.05 : 0.01)
        return reference
    }
}

struct WaveformView: View {
    let audio: SystemAudioMonitor

    @AppStorage(SettingsKey.stereo) private var stereo = false
    /// dB of loudness between the bottom and the top of a bar.
    @AppStorage(WaveformSettings.rangeDB) private var rangeDB = WaveformSettings.defaultRangeDB
    @State private var level = AutoLevel()
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
                _ = date
                draw(in: &context, size: size)
            }
        }
        .background(.black)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let step = barWidth + barGap
        let columns = max(1, Int(size.width / step)) + 1          // +1 slides in from the right
        let blocksPerSecond = audio.sampleRate / Double(SystemAudioMonitor.peakBlock)
        // Whole blocks per bar, so every bar always covers the same audio while it scrolls.
        let k = max(1, Int((seconds * blocksPerSecond / Double(columns)).rounded()))
        // Each bar's energy is measured over at least ~23 ms, or bass makes it flicker.
        let window = max(k, 4)

        let rms = audio.recentRMS(count: columns * k + window)
        let n = rms.left.count
        guard n > 0 else { return }
        // Absolute block index where the newest complete bar ends.
        let alignedEnd = rms.end - rms.end % k
        // How far the next (still filling) bar has grown: scroll by that fraction.
        let scroll = CGFloat(rms.end % k) / CGFloat(k) * step

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
        let range = Float(rangeDB)
        let mid = size.height / 2
        let maxHalf = mid * 0.9
        func height(_ db: Float) -> CGFloat {
            let v = min(max(1 + (db - reference) / range, 0), 1)
            // Curve that stretches the loud end, so beats stand out from sustained parts.
            return CGFloat(pow(v, 1.7)) * maxHalf
        }

        var path = Path()
        // Right-align the bars, then slide them left as the next bar fills up.
        let origin = size.width - CGFloat(columns) * step + step - scroll
        for c in 0..<columns {
            let x = origin + CGFloat(c) * step - step
            let h1 = max(height(up[c]), 0.5)
            let h2 = max(height(down[c]), 0.5)
            let rect = CGRect(x: x, y: mid - h1, width: barWidth, height: h1 + h2)
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }

        // Bright at the centre, cooler towards the peaks.
        let colors: [Color] = stereo
            ? [Color(red: 0.3, green: 0.6, blue: 1), Color(red: 0.2, green: 0.95, blue: 1),
               Color(red: 1, green: 0.4, blue: 0.75), Color(red: 1, green: 0.55, blue: 0.4)]
            : [Color(red: 0.6, green: 0.4, blue: 1), Color(red: 0.2, green: 0.95, blue: 1),
               Color(red: 0.2, green: 0.95, blue: 1), Color(red: 0.6, green: 0.4, blue: 1)]
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: colors[0], location: 0.05),
                .init(color: colors[1], location: 0.5),
                .init(color: colors[2], location: 0.5),
                .init(color: colors[3], location: 0.95),
            ]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height))

        // Soft glow, then the bars themselves.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 8))
            layer.opacity = 0.6
            layer.fill(path, with: shading)
        }
        context.fill(path, with: shading)

        // The past fades out to the left.
        guard fade else { return }
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
            Gradient(colors: [.black.opacity(0.85), .black.opacity(0)]),
            startPoint: .zero, endPoint: CGPoint(x: size.width * 0.7, y: 0)))
    }
}
