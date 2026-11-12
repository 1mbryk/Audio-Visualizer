//
//  ContentView.swift
//  Audio Vusualizer
//
//  Created by Mацвей Пажытных on 12.11.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var fire = FireModel()
    @State private var audio = SystemAudioMonitor()
    @State private var errorText: String?
    @AppStorage(SettingsKey.sensitivity) private var sensitivity = 1.0
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
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if let errorText {
                Text(errorText)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.red.opacity(0.6), in: .rect(cornerRadius: 8))
                    .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 250)
        .background(.black)
        .onChange(of: sensitivity, initial: true) { _, value in
            audio.gain = Float(value)
        }
        .task {
            do {
                try audio.start()
            } catch {
                errorText = "Не удалось захватить системный звук: \(error.localizedDescription)"
            }
        }
        .onDisappear { audio.stop() }
    }
}

#Preview {
    ContentView()
}
