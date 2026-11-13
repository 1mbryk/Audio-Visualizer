//
//  SpectrumView.swift
//  Audio Vusualizer
//
//  АЧХ (frequency spectrum): one bar per log-spaced frequency band, bass on the
//  left, treble on the right, drawn like the waveform's mirrored bars.
//

import SwiftUI

/// Per-view state that outlives a single frame.
final class SpectrumState {
    let analyzer = SpectrumAnalyzer()
    let level = AutoLevel()
    var up: [CGFloat] = []
    var down: [CGFloat] = []
    /// Detects silence: the system delivers no audio then, so the samples go stale.
    var lastBlockCount = -1
    var lastAudio = Date.distantPast
}

struct SpectrumView: View {
    let audio: SystemAudioMonitor

    @AppStorage(SpectrumSettings.stereo) private var stereo = false
    @AppStorage(SpectrumSettings.barWidth) private var barWidthSetting = SpectrumSettings.defaultBarWidth
    @AppStorage(SpectrumSettings.rangeDB) private var rangeDB = SpectrumSettings.defaultRangeDB
    @AppStorage(SpectrumSettings.smoothing) private var smoothing = SpectrumSettings.defaultSmoothing
    @State private var state = SpectrumState()

    private var barWidth: CGFloat { CGFloat(barWidthSetting) }
    private var barGap: CGFloat { max(1, barWidth / 2) }

    @AppStorage(BarPalette.Keys("spectrum").style) private var colorStyle = BarColorStyle.gradient
    @AppStorage(BarPalette.Keys("spectrum").center) private var colorCenter = BarPalette.defaultCenter
    @AppStorage(BarPalette.Keys("spectrum").edge) private var colorEdge = BarPalette.defaultEdge
    @AppStorage(BarPalette.Keys("spectrum").rightCenter) private var colorRightCenter = BarPalette.defaultRightCenter
    @AppStorage(BarPalette.Keys("spectrum").rightEdge) private var colorRightEdge = BarPalette.defaultRightEdge

    private var palette: BarPalette {
        BarPalette(style: colorStyle, center: colorCenter, edge: colorEdge,
                   rightCenter: colorRightCenter, rightEdge: colorRightEdge)
    }

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
        // As many bars as fit at the chosen thickness (capped for large screens), then
        // stretched so the row spans exactly the full width.
        let count = min(max(8, Int((size.width + barGap) / (barWidth + barGap))), 512)
        let step = (size.width + barGap) / CGFloat(count)
        let width = step * barWidth / (barWidth + barGap)
        let mid = size.height / 2
        let maxHalf = mid - 1

        if state.up.count != count {
            state.up = Array(repeating: 0, count: count)
            state.down = Array(repeating: 0, count: count)
        }

        let blocks = audio.blockCount
        if blocks != state.lastBlockCount {
            state.lastBlockCount = blocks
            state.lastAudio = date
        }
        let silent = date.timeIntervalSince(state.lastAudio) > 0.25

        var targetUp = [CGFloat](repeating: 0, count: count)
        var targetDown = targetUp
        if !silent {
            let samples = audio.recentSamples(frames: state.analyzer.size)
            if samples.left.count == state.analyzer.size {
                let rate = audio.sampleRate
                let up: [Float]
                let down: [Float]
                if stereo {
                    // Left channel above the centre line, right channel below.
                    up = state.analyzer.bands(state.analyzer.power(of: samples.left), count: count, sampleRate: rate)
                    down = state.analyzer.bands(state.analyzer.power(of: samples.right), count: count, sampleRate: rate)
                } else {
                    let mono = zip(samples.left, samples.right).map { ($0 + $1) / 2 }
                    up = state.analyzer.bands(state.analyzer.power(of: mono), count: count, sampleRate: rate)
                    down = up
                }
                // Auto level: the strongest bands reach the top, `range` dB below is the bottom.
                let reference = state.level.update(with: up + down)
                let range = Float(rangeDB)
                func height(_ db: Float) -> CGFloat {
                    let v = min(max(1 + (db - reference) / range, 0), 1)
                    return CGFloat(pow(v, 1.4)) * maxHalf
                }
                targetUp = up.map(height)
                targetDown = down.map(height)
            }
        }

        // Bars jump up quickly and fall back smoothly.
        let attack: CGFloat = 0.6
        let release = CGFloat(1 - smoothing)
        for i in 0..<count {
            let tu = targetUp[i], td = targetDown[i]
            state.up[i] += (tu - state.up[i]) * (tu > state.up[i] ? attack : release)
            state.down[i] += (td - state.down[i]) * (td > state.down[i] ? attack : release)
        }

        MirroredBars.draw(in: &context, size: size, up: state.up, down: state.down,
                          originX: 0, step: step, barWidth: width, stereo: stereo,
                          palette: palette)
    }
}
