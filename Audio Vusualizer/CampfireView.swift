//
//  CampfireView.swift
//  Audio Vusualizer
//
//  The campfire visualization: shader-rendered fire plus sparks.
//

import SwiftUI

struct CampfireView: View {
    let audio: SystemAudioMonitor

    @State private var fire = FireModel()
    @AppStorage(CampfireSettings.submode) private var submode = CampfireSubmode.mono
    @State private var spectrum = CampfireSpectrum()
    @AppStorage(CampfireSettings.bellStrength) private var bellStrength = CampfireSettings.defaultBellStrength
    @AppStorage(CampfireSettings.bellWidth) private var bellWidth = CampfireSettings.defaultBellWidth
    @AppStorage(CampfireSettings.heightSpread) private var heightSpread = CampfireSettings.defaultHeightSpread
    @AppStorage(CampfireSettings.outlierRate) private var outlierRate = CampfireSettings.defaultOutlierRate
    @AppStorage(CampfireSettings.sparks) private var sparks = true
    @AppStorage(CampfireSettings.tongueWidth) private var tongueWidth = CampfireSettings.defaultTongueWidth

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geo in
                let _ = applySettings()
                let channels = audio.stereoLevels
                let _ = fire.step(date: timeline.date, size: geo.size,
                                  level: Double(audio.level),
                                  left: Double(channels.left), right: Double(channels.right),
                                  stereo: submode == .stereo)
                let _ = fire.bandLevels = submode == .spectrum
                    ? spectrum.update(audio: audio, bands: fire.tongueCount, date: timeline.date)
                    : nil
                ZStack {
                    Rectangle()
                        .fill(.black)
                        .colorEffect(ShaderLibrary.fire(
                            .float2(geo.size),
                            .float(Float(fire.time)),
                            .float(Float(fire.loudness)),
                            .float(Float(tongueWidth)),
                            .floatArray(fire.envelope())))
                    // The renderer must capture the frame date: otherwise SwiftUI sees an
                    // unchanged Canvas (same `fire` reference) and skips most redraws.
                    Canvas { [date = timeline.date] context, _ in
                        fire.drawSparks(in: &context, frame: date)
                    }
                    .blendMode(.plusLighter)
                }
            }
        }
    }

    private func applySettings() {
        if submode != .spectrum { spectrum.reset() }
        fire.bellStrength = bellStrength
        fire.bellWidth = bellWidth
        fire.heightSigma = heightSpread
        fire.outlierRate = outlierRate
        fire.sparksEnabled = sparks
        fire.tongueWidth = tongueWidth
    }
}

/// Per-tongue band loudness for the campfire's АЧХ submode.
final class CampfireSpectrum {
    private let analyzer = SpectrumAnalyzer()
    private let level = AutoLevel()
    private var values: [Double] = []
    private var lastBlockCount = -1
    private var lastAudio = Date.distantPast
    /// dB between a band that barely flickers and one at full height.
    private let rangeDB: Float = 36

    func reset() { values = [] }

    /// Smoothed 0...1 loudness of `bands` log-spaced bands, bass first.
    func update(audio: SystemAudioMonitor, bands: Int, date: Date) -> [Double] {
        if values.count != bands { values = Array(repeating: 0, count: bands) }
        guard bands > 0 else { return values }

        // No audio arrives during silence, so the samples go stale: let the fire settle.
        let blocks = audio.blockCount
        if blocks != lastBlockCount {
            lastBlockCount = blocks
            lastAudio = date
        }
        var targets = [Double](repeating: 0, count: bands)
        if date.timeIntervalSince(lastAudio) < 0.25 {
            let samples = audio.recentSamples(frames: analyzer.size)
            if samples.left.count == analyzer.size {
                let mono = zip(samples.left, samples.right).map { ($0 + $1) / 2 }
                let dbs = analyzer.bands(analyzer.power(of: mono), count: bands,
                                         sampleRate: audio.sampleRate, minHz: 40, maxHz: 12_000)
                let reference = level.update(with: dbs)
                targets = dbs.map { Double(min(max(1 + ($0 - reference) / rangeDB, 0), 1)) }
            }
        }
        // Flames rise quickly and sink slowly.
        for i in 0..<bands {
            let k = targets[i] > values[i] ? 0.35 : 0.08
            values[i] += (targets[i] - values[i]) * k
        }
        return values
    }
}
