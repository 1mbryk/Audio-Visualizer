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
    @AppStorage(SettingsKey.fullScreenHint) private var showHintSetting = true
    @State private var isFullScreen = false
    /// The pointer is at the left edge in full screen, so the sidebar is shown.
    @State private var sidebarRevealed = false
    /// "Controls are on the left" hint, shown for a few seconds on entering full screen.
    @State private var hintVisible = false
    @State private var hintTask: Task<Void, Never>?

    /// Width of the full-screen sidebar.
    private let sidebarWidth: CGFloat = 220
    /// How close to the left edge the pointer has to come to slide the sidebar in.
    private let revealZone: CGFloat = 30

    var body: some View {
        visualizer
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
            .overlay(alignment: .leading) {
                if isFullScreen && hintVisible && !sidebarRevealed {
                    hint
                        .padding(.leading, 24)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .overlay(alignment: .leading) {
                if isFullScreen && sidebarRevealed {
                    sidebar
                        .ignoresSafeArea()
                        .transition(.move(edge: .leading))
                }
            }
            .animation(.snappy(duration: 0.3), value: sidebarRevealed)
            .animation(.easeInOut(duration: 0.4), value: hintVisible)
            .frame(minWidth: 400, minHeight: 250)
            .background(.black)
            .preferredColorScheme(.dark)
            .toolbar { header }
            .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            // In full screen the toolbar is replaced by a sidebar that slides in from the left
            // edge. Driven by our own full-screen observer, because SwiftUI's
            // `windowToolbarFullScreenVisibility` misses windows restored into full screen.
            .toolbar(isFullScreen ? .hidden : .visible, for: .windowToolbar)
            .background(FullScreenObserver(isFullScreen: $isFullScreen) { pointer in
                if pointer.menuOpen { return }
                // Reveal near the left edge; keep it while the pointer stays over the sidebar.
                let reveal = isFullScreen && pointer.insideVertically
                    && pointer.fromLeft < (sidebarRevealed ? sidebarWidth + 12 : revealZone)
                if reveal != sidebarRevealed { sidebarRevealed = reveal }
            })
            .onChange(of: isFullScreen, initial: true) { _, full in
                sidebarRevealed = false
                if full && showHintSetting { showHint() } else { hideHint() }
            }
            .onChange(of: sidebarRevealed) { _, revealed in
                if revealed { hideHint() }
            }
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
        // The fire and the waveform run under the header, edge to edge.
        case .campfire: CampfireView(audio: audio).ignoresSafeArea()
        case .waveform: WaveformView(audio: audio).ignoresSafeArea()
        case .spectrum: SpectrumView(audio: audio)
        }
    }

    // MARK: Hint

    private func showHint() {
        hintTask?.cancel()
        hintTask = Task {
            // Let the full-screen transition finish first.
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            hintVisible = true
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            hintVisible = false
        }
    }

    private func hideHint() {
        hintTask?.cancel()
        hintTask = nil
        hintVisible = false
    }

    private var hint: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.left.2")
                .font(.system(size: 15, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("Управление — у левого края")
                    .font(.headline)
                Text("Подведите курсор к левому краю экрана")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    // MARK: Window header

    /// Window header: the system toolbar.
    @ToolbarContentBuilder
    private var header: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            modeMenu
        }
        ToolbarItem(placement: .primaryAction) {
            settingsButton
        }
    }

    /// A Menu (not a bare Picker) so the header shows the mode's name, not just its icon.
    private var modeMenu: some View {
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

    private var settingsButton: some View {
        SettingsLink {
            Label("Настройки", systemImage: "gearshape")
                .labelStyle(.iconOnly)
        }
        .buttonBorderShape(.circle)
        .help("Настройки (⌘,)")
    }

    // MARK: Full-screen sidebar

    /// Full-screen controls: window buttons, the list of modes and settings, on an
    /// ultra-thin panel at the left edge (clear of the system menu bar at the top).
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            WindowControls()
                .fixedSize()
                .padding(.leading, 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("Режим")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
                    .padding(.bottom, 4)
                ForEach(VisualizerMode.allCases) { item in
                    sidebarRow(item.title, systemImage: item.systemImage, selected: item == mode) {
                        mode = item
                    }
                }
            }

            Spacer()

            SettingsLink {
                rowLabel("Настройки", systemImage: "gearshape", selected: false)
            }
            .buttonStyle(.plain)
            .help("Настройки (⌘,)")
        }
        // Below the area the system menu bar slides over.
        .padding(.top, 44)
        .padding(.bottom, 20)
        .padding(.horizontal, 12)
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
        }
    }

    private func sidebarRow(_ title: LocalizedStringKey, systemImage: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(title, systemImage: systemImage, selected: selected)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(_ title: LocalizedStringKey, systemImage: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            // Fixed-width icons so the titles line up.
            Image(systemName: systemImage)
                .frame(width: 22)
            Text(title)
        }
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? Color.white.opacity(0.14) : .clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
    }
}

#Preview {
    ContentView()
}
