//
//  SettingsView.swift
//  Audio Vusualizer
//
//  App settings window (opened with ⌘,): general audio options plus one
//  bubble per visualization mode.
//

import SwiftUI

enum SettingsKey {
    /// Audio input gain multiplier, 0.25 ... 4 (1 = default).
    static let sensitivity = "sensitivity"
    /// Selected visualization (`VisualizerMode` raw value).
    static let mode = "mode"
    /// Show the "controls are on the left" hint on entering full screen.
    static let fullScreenHint = "fullScreenHint"
    /// Old app-wide stereo switch, replaced by one switch per mode.
    static let legacyStereo = "stereo"

    /// Copies the old app-wide stereo choice into each mode's own switch, once.
    static func migrate(_ defaults: UserDefaults = .standard) {
        if let old = defaults.object(forKey: legacyStereo) as? Bool {
            for key in [CampfireSettings.legacyStereo, WaveformSettings.stereo] where defaults.object(forKey: key) == nil {
                defaults.set(old, forKey: key)
            }
            defaults.removeObject(forKey: legacyStereo)
        }
        // The campfire's stereo switch became one of its submodes.
        if let old = defaults.object(forKey: CampfireSettings.legacyStereo) as? Bool {
            if defaults.object(forKey: CampfireSettings.submode) == nil {
                defaults.set((old ? CampfireSubmode.stereo : .mono).rawValue, forKey: CampfireSettings.submode)
            }
            defaults.removeObject(forKey: CampfireSettings.legacyStereo)
        }
    }
}

/// How the campfire follows the audio.
enum CampfireSubmode: String, CaseIterable, Identifiable {
    /// The whole fire follows the overall loudness.
    case mono
    /// Left half follows the left channel, right half the right one.
    case stereo
    /// Bass drives the left of the fire, treble the right.
    case spectrum

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .mono: "Моно"
        case .stereo: "Стерео"
        case .spectrum: "АЧХ"
        }
    }
}

enum CampfireSettings {
    static let bellStrength = "campfire.bellStrength"
    static let bellWidth = "campfire.bellWidth"
    static let heightSpread = "campfire.heightSpread"
    static let outlierRate = "campfire.outlierRate"
    static let sparks = "campfire.sparks"
    static let tongueWidth = "campfire.tongueWidth"
    /// `CampfireSubmode` raw value.
    static let submode = "campfire.submode"
    /// Old stereo switch, replaced by `submode`.
    static let legacyStereo = "campfire.stereo"

    static let defaultBellStrength = 0.78
    static let defaultBellWidth = 0.45
    static let defaultHeightSpread = 0.16
    static let defaultOutlierRate = 0.12
    static let defaultTongueWidth = 1.0
}

enum WaveformSettings {
    static let seconds = "waveform.seconds"
    static let barWidth = "waveform.barWidth"
    static let fade = "waveform.fade"
    static let rangeDB = "waveform.rangeDB"
    /// Left channel above the centre line, right channel below.
    static let stereo = "waveform.stereo"

    static let defaultSeconds = 6.0
    static let defaultRangeDB = 15.0
    static let defaultBarWidth = 2.0
}

enum SpectrumSettings {
    static let barWidth = "spectrum.barWidth"
    static let rangeDB = "spectrum.rangeDB"
    static let smoothing = "spectrum.smoothing"
    /// Left channel above the centre line, right channel below.
    static let stereo = "spectrum.stereo"

    static let defaultBarWidth = 4.0
    static let defaultRangeDB = 36.0
    static let defaultSmoothing = 0.8
}

struct SettingsView: View {
    @AppStorage(SettingsKey.sensitivity) private var sensitivity = 1.0
    @AppStorage(SettingsKey.fullScreenHint) private var fullScreenHint = true

    @AppStorage(CampfireSettings.bellStrength) private var bellStrength = CampfireSettings.defaultBellStrength
    @AppStorage(CampfireSettings.bellWidth) private var bellWidth = CampfireSettings.defaultBellWidth
    @AppStorage(CampfireSettings.heightSpread) private var heightSpread = CampfireSettings.defaultHeightSpread
    @AppStorage(CampfireSettings.outlierRate) private var outlierRate = CampfireSettings.defaultOutlierRate
    @AppStorage(CampfireSettings.sparks) private var sparks = true
    @AppStorage(CampfireSettings.submode) private var campfireSubmode = CampfireSubmode.mono
    @AppStorage(CampfireSettings.tongueWidth) private var tongueWidth = CampfireSettings.defaultTongueWidth

    @AppStorage(WaveformSettings.seconds) private var waveSeconds = WaveformSettings.defaultSeconds
    @AppStorage(WaveformSettings.barWidth) private var waveBarWidth = WaveformSettings.defaultBarWidth
    @AppStorage(WaveformSettings.fade) private var waveFade = true
    @AppStorage(WaveformSettings.rangeDB) private var waveRange = WaveformSettings.defaultRangeDB
    @AppStorage(WaveformSettings.stereo) private var waveStereo = false

    @AppStorage(SpectrumSettings.barWidth) private var specBarWidth = SpectrumSettings.defaultBarWidth
    @AppStorage(SpectrumSettings.rangeDB) private var specRange = SpectrumSettings.defaultRangeDB
    @AppStorage(SpectrumSettings.smoothing) private var specSmoothing = SpectrumSettings.defaultSmoothing
    @AppStorage(SpectrumSettings.stereo) private var specStereo = false

    /// The slider works on a log2 scale so ×0.5 and ×2 sit symmetrically around ×1.
    private var sensitivitySlider: Binding<Double> {
        Binding(get: { log2(sensitivity) },
                set: { sensitivity = pow(2, $0) })
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Чувствительность к звуку") {
                    Slider(value: sensitivitySlider, in: -2...2) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill")
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                }
                valueRow("×\(sensitivity.formatted(.number.precision(.fractionLength(2))))",
                         note: "Чем выше, тем сильнее визуализация реагирует на тихий звук.")

                Toggle(isOn: $fullScreenHint) {
                    Text("Подсказка в полноэкранном режиме")
                    Text("При входе в полноэкранный режим напоминать, что управление у левого края.")
                }
            } header: {
                bubbleHeader("Общие", systemImage: "slider.horizontal.3",
                             isDefault: abs(sensitivity - 1) < 0.001 && fullScreenHint) {
                    sensitivity = 1
                    fullScreenHint = true
                }
            }

            campfireBubble
            waveformBubble
            spectrumBubble
        }
        .formStyle(.grouped)
        // A fixed, comfortable height; the bubbles scroll inside it. The window can be
        // made taller (or shorter, down to the minimum) by dragging its edge.
        .frame(width: 480)
        .frame(minHeight: 360, idealHeight: 620, maxHeight: .infinity)
    }

    // MARK: Mode bubbles

    private var campfireBubble: some View {
        Section {
            slider("Выраженность колокола", value: $bellStrength, in: 0...1,
                   text: (bellStrength * 100).formatted(.number.precision(.fractionLength(0))) + " %")
            slider("Ширина колокола", value: $bellWidth, in: 0.2...1,
                   text: bellWidth.formatted(.number.precision(.fractionLength(2))))
            slider("Ширина языков", value: $tongueWidth, in: 0.5...2,
                   text: "×" + tongueWidth.formatted(.number.precision(.fractionLength(2))))
            slider("Разброс высот", value: $heightSpread, in: 0...0.35,
                   text: heightSpread.formatted(.number.precision(.fractionLength(2))))
            slider("Выбросы", value: $outlierRate, in: 0...0.5,
                   text: outlierRate.formatted(.number.precision(.fractionLength(2))) + " / с")
            Toggle("Искры", isOn: $sparks)
            Picker(selection: $campfireSubmode) {
                ForEach(CampfireSubmode.allCases) { Text($0.title).tag($0) }
            } label: {
                Text("Подрежим")
                Text("Стерео: левая половина — левый канал, правая — правый. АЧХ: басы слева, высокие справа.")
            }
            .pickerStyle(.segmented)
        } header: {
            bubbleHeader(VisualizerMode.campfire,
                         isDefault: bellStrength == CampfireSettings.defaultBellStrength
                            && bellWidth == CampfireSettings.defaultBellWidth
                            && heightSpread == CampfireSettings.defaultHeightSpread
                            && outlierRate == CampfireSettings.defaultOutlierRate
                            && sparks
                            && campfireSubmode == .mono
                            && tongueWidth == CampfireSettings.defaultTongueWidth) {
                campfireSubmode = .mono
                tongueWidth = CampfireSettings.defaultTongueWidth
                bellStrength = CampfireSettings.defaultBellStrength
                bellWidth = CampfireSettings.defaultBellWidth
                heightSpread = CampfireSettings.defaultHeightSpread
                outlierRate = CampfireSettings.defaultOutlierRate
                sparks = true
            }
        } footer: {
            Text("Высоты языков случайны по нормальному распределению; выбросы — сколько раз в секунду в среднем один язык резко взлетает.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var waveformBubble: some View {
        Section {
            slider("Длина истории", value: $waveSeconds, in: 2...10, step: 0.5,
                   text: waveSeconds.formatted(.number.precision(.fractionLength(1))) + " с")
            slider("Толщина столбиков", value: $waveBarWidth, in: 1...6, step: 0.5,
                   text: waveBarWidth.formatted(.number.precision(.fractionLength(1))) + " pt")
            slider("Диапазон громкости", value: $waveRange, in: 9...48, step: 3,
                   text: waveRange.formatted(.number.precision(.fractionLength(0))) + " дБ")
            Toggle("Затухание прошлого", isOn: $waveFade)
            channelsPicker($waveStereo)
        } header: {
            bubbleHeader(VisualizerMode.waveform,
                         isDefault: waveSeconds == WaveformSettings.defaultSeconds
                            && waveBarWidth == WaveformSettings.defaultBarWidth
                            && waveFade
                            && waveRange == WaveformSettings.defaultRangeDB
                            && !waveStereo) {
                waveStereo = false
                waveRange = WaveformSettings.defaultRangeDB
                waveSeconds = WaveformSettings.defaultSeconds
                waveBarWidth = WaveformSettings.defaultBarWidth
                waveFade = true
            }
        } footer: {
            Text("Уровень подстраивается под громкость трека. Чем меньше диапазон, тем сильнее видна разница между тихим и громким.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var spectrumBubble: some View {
        Section {
            slider("Толщина столбиков", value: $specBarWidth, in: 1...12, step: 0.5,
                   text: specBarWidth.formatted(.number.precision(.fractionLength(1))) + " pt")
            slider("Диапазон громкости", value: $specRange, in: 18...60, step: 3,
                   text: specRange.formatted(.number.precision(.fractionLength(0))) + " дБ")
            slider("Плавность спада", value: $specSmoothing, in: 0...0.95,
                   text: (specSmoothing * 100).formatted(.number.precision(.fractionLength(0))) + " %")
            channelsPicker($specStereo)
        } header: {
            bubbleHeader(VisualizerMode.spectrum,
                         isDefault: specBarWidth == SpectrumSettings.defaultBarWidth
                            && specRange == SpectrumSettings.defaultRangeDB
                            && specSmoothing == SpectrumSettings.defaultSmoothing
                            && !specStereo) {
                specBarWidth = SpectrumSettings.defaultBarWidth
                specRange = SpectrumSettings.defaultRangeDB
                specSmoothing = SpectrumSettings.defaultSmoothing
                specStereo = false
            }
        } footer: {
            Text("Басы слева, высокие справа (30 Гц – 16 кГц, логарифмическая шкала). Уровень подстраивается под трек.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Building blocks

    /// Моно / Стерео submode of the bar modes (stereo: left channel above, right below).
    private func channelsPicker(_ stereo: Binding<Bool>) -> some View {
        Picker(selection: stereo) {
            Text("Моно").tag(false)
            Text("Стерео").tag(true)
        } label: {
            Text("Подрежим")
            Text("Стерео: левый канал над центральной линией, правый — под ней.")
        }
        .pickerStyle(.segmented)
    }

    private func bubbleHeader(_ mode: VisualizerMode, isDefault: Bool,
                              reset: @escaping () -> Void) -> some View {
        bubbleHeaderContent(Label(mode.title, systemImage: mode.systemImage), isDefault: isDefault, reset: reset)
    }

    private func bubbleHeader(_ title: LocalizedStringKey, systemImage: String, isDefault: Bool,
                              reset: @escaping () -> Void) -> some View {
        bubbleHeaderContent(Label(title, systemImage: systemImage), isDefault: isDefault, reset: reset)
    }

    private func bubbleHeaderContent(_ label: Label<Text, Image>, isDefault: Bool,
                                     reset: @escaping () -> Void) -> some View {
        HStack {
            label.font(.headline)
            Spacer()
            Button("Сбросить", action: reset)
                .buttonStyle(.link)
                .font(.callout)
                .disabled(isDefault)
        }
    }

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>,
                        in range: ClosedRange<Double>, step: Double? = nil, text: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                if let step {
                    Slider(value: value, in: range, step: step)
                } else {
                    Slider(value: value, in: range)
                }
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }

    private func valueRow(_ value: String, note: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
}
