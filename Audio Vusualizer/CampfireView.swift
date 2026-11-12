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
    @AppStorage(SettingsKey.stereo) private var stereo = false
    @AppStorage(CampfireSettings.bellStrength) private var bellStrength = CampfireSettings.defaultBellStrength
    @AppStorage(CampfireSettings.bellWidth) private var bellWidth = CampfireSettings.defaultBellWidth
    @AppStorage(CampfireSettings.heightSpread) private var heightSpread = CampfireSettings.defaultHeightSpread
    @AppStorage(CampfireSettings.outlierRate) private var outlierRate = CampfireSettings.defaultOutlierRate
    @AppStorage(CampfireSettings.sparks) private var sparks = true

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geo in
                let _ = applySettings()
                let channels = audio.stereoLevels
                let _ = fire.step(date: timeline.date, size: geo.size,
                                  level: Double(audio.level),
                                  left: Double(channels.left), right: Double(channels.right),
                                  stereo: stereo)
                ZStack {
                    Rectangle()
                        .fill(.black)
                        .colorEffect(ShaderLibrary.fire(
                            .float2(geo.size),
                            .float(Float(fire.time)),
                            .float(Float(fire.loudness)),
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
        fire.bellStrength = bellStrength
        fire.bellWidth = bellWidth
        fire.heightSigma = heightSpread
        fire.outlierRate = outlierRate
        fire.sparksEnabled = sparks
    }
}
