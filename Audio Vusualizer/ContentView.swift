//
//  ContentView.swift
//  Audio Vusualizer
//
//  Created by Mацвей Пажытных on 12.11.2026.
//

import SwiftUI

struct ContentView: View {
    @State private var audio = SystemAudioMonitor()
    @State private var errorText: String?
    @AppStorage(SettingsKey.sensitivity) private var sensitivity = 1.0
    @AppStorage(SettingsKey.mode) private var mode = VisualizerMode.campfire

    var body: some View {
        visualizer
            // The visualization runs under the transparent header, edge to edge.
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
            .toolbar { header }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            // In full screen the header hides and only slides in when the pointer reaches the top edge.
            .windowToolbarFullScreenVisibility(.onHover)
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

    @ViewBuilder
    private var visualizer: some View {
        switch mode {
        case .campfire: CampfireView(audio: audio)
        }
    }

    @ToolbarContentBuilder
    private var header: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            // A Menu (not a bare Picker) so the toolbar shows the mode's name, not just its icon.
            Menu {
                Picker("Режим", selection: $mode) {
                    ForEach(VisualizerMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(mode.title, systemImage: mode.systemImage)
                    .labelStyle(.titleAndIcon)
            }
            .help("Режим визуализации")
        }
        ToolbarItem(placement: .primaryAction) {
            SettingsLink {
                Label("Настройки", systemImage: "gearshape")
            }
            .help("Настройки (⌘,)")
        }
    }
}

#Preview {
    ContentView()
}
