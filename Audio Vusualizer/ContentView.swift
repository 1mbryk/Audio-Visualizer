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
    @AppStorage(CampfireSettings.submode) private var campfireSubmode = CampfireSubmode.mono
    @AppStorage(WaveformSettings.stereo) private var waveformStereo = false
    @AppStorage(SpectrumSettings.stereo) private var spectrumStereo = false
    @State private var isFullScreen = false
    /// The pointer is at the left edge in full screen, so the sidebar is shown.
    @State private var sidebarRevealed = false
    /// "Controls are on the left" hint, shown for a few seconds on entering full screen.
    @State private var hintVisible = false
    @State private var hintTask: Task<Void, Never>?
    /// Lets the glass highlight glide between rows when the selection changes.
    @Namespace private var glassNamespace

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

    /// Every visualization runs edge to edge, under the header.
    private var visualizer: some View {
        Group {
            switch mode {
            case .campfire: CampfireView(audio: audio)
            case .waveform: WaveformView(audio: audio)
            case .spectrum: SpectrumView(audio: audio)
            case .matrix: MatrixView(audio: audio)
            }
        }
        .ignoresSafeArea()
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
            HStack(spacing: 12) {
                modeMenu
                // Submodes of the current mode, as in the full-screen sidebar.
                submodePicker(for: mode)
                    .fixedSize()
            }
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

    /// Full-screen controls: window buttons, the list of modes, the current mode's
    /// submodes and settings, on an ultra-thin panel at the left edge.
    /// Selected rows and buttons are glass, like the toolbar.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            WindowControls()
                .fixedSize()
                .padding(.leading, 8)
                .padding(.bottom, 4)

            GlassEffectContainer {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle("Режим")
                    ForEach(VisualizerMode.allCases) { item in
                        sidebarRow(item.title, systemImage: item.systemImage, selected: item == mode,
                                   glassID: "mode") {
                            mode = item
                        }
                    }
                }
            }

            // Modes with a single submode (the matrix: АЧХ only) have nothing to choose here.
            let items = submodes(for: mode)
            if !items.isEmpty {
                Divider()
                    .padding(.horizontal, 6)

                GlassEffectContainer {
                    VStack(alignment: .leading, spacing: 2) {
                        sectionTitle("Подрежим")
                        ForEach(items) { item in
                            sidebarRow(item.title, systemImage: item.systemImage, selected: item.selected,
                                       glassID: "submode", action: item.select)
                        }
                    }
                }
            }

            Spacer()

            SettingsLink {
                Label("Настройки", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .help("Настройки (⌘,)")
        }
        // From the top edge; the window buttons sit where they are in a normal window.
        .padding(.top, 19)
        .padding(.bottom, 20)
        .padding(.horizontal, 12)
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
        }
        .animation(.snappy(duration: 0.25), value: mode)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 10)
            .padding(.bottom, 4)
    }

    private struct SubmodeItem: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let systemImage: String
        let selected: Bool
        let select: () -> Void
    }

    /// Rows for the current mode's submodes: Моно / Стерео / АЧХ for the fire,
    /// Моно / Стерео for the bar modes.
    private func submodes(for item: VisualizerMode) -> [SubmodeItem] {
        func channels(_ stereo: Binding<Bool>) -> [SubmodeItem] {
            [SubmodeItem(id: "mono", title: "Моно", systemImage: "speaker.wave.2",
                         selected: !stereo.wrappedValue) { stereo.wrappedValue = false },
             SubmodeItem(id: "stereo", title: "Стерео", systemImage: "hifispeaker.2",
                         selected: stereo.wrappedValue) { stereo.wrappedValue = true }]
        }
        switch item {
        case .campfire:
            let icons: [CampfireSubmode: String] = [.mono: "speaker.wave.2", .stereo: "hifispeaker.2",
                                                    .spectrum: "chart.bar.xaxis"]
            return CampfireSubmode.allCases.map { sub in
                SubmodeItem(id: sub.rawValue, title: sub.title, systemImage: icons[sub]!,
                            selected: campfireSubmode == sub) { campfireSubmode = sub }
            }
        case .waveform: return channels($waveformStereo)
        case .spectrum: return channels($spectrumStereo)
        case .matrix: return []   // one submode only: АЧХ
        }
    }

    /// Submodes of the selected mode: Моно / Стерео / АЧХ for the fire, Моно / Стерео otherwise.
    @ViewBuilder
    private func submodePicker(for item: VisualizerMode) -> some View {
        switch item {
        case .campfire:
            Picker("Подрежим", selection: $campfireSubmode) {
                ForEach(CampfireSubmode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        case .waveform:
            channelsPicker($waveformStereo)
        case .spectrum:
            channelsPicker($spectrumStereo)
        case .matrix:
            EmptyView()   // one submode only: АЧХ
        }
    }

    private func channelsPicker(_ stereo: Binding<Bool>) -> some View {
        Picker("Подрежим", selection: stereo) {
            Text("Моно").tag(false)
            Text("Стерео").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func sidebarRow(_ title: LocalizedStringKey, systemImage: String, selected: Bool,
                            glassID: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
            .contentShape(.rect(cornerRadius: 10))
            .modifier(SelectionGlass(selected: selected, id: glassID, namespace: glassNamespace))
        }
        .buttonStyle(.plain)
    }

}

#Preview {
    ContentView()
}

/// Glass highlight behind the selected sidebar row; it morphs between rows that share `id`.
private struct SelectionGlass: ViewModifier {
    let selected: Bool
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if selected {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                .glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}
