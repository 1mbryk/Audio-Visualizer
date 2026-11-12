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

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geo in
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
}
