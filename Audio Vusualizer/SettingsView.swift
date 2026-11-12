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
    /// Each half of the visualization follows its own channel.
    static let stereo = "stereo"
    /// Selected visualization (`VisualizerMode` raw value).
    static let mode = "mode"
}

enum CampfireSettings {
    static let bellStrength = "campfire.bellStrength"
    static let bellWidth = "campfire.bellWidth"
    static let heightSpread = "campfire.heightSpread"
    static let outlierRate = "campfire.outlierRate"
    static let sparks = "campfire.sparks"

    static let defaultBellStrength = 0.78
    static let defaultBellWidth = 0.45
    static let defaultHeightSpread = 0.16
    static let defaultOutlierRate = 0.12
}

enum WaveformSettings {
    static let seconds = "waveform.seconds"
    static let barWidth = "waveform.barWidth"
    static let fade = "waveform.fade"
    static let rangeDB = "waveform.rangeDB"

    static let defaultSeconds = 6.0
    static let defaultRangeDB = 15.0
    static let defaultBarWidth = 2.0
}

struct SettingsView: View {
    @AppStorage(SettingsKey.sensitivity) private var sensitivity = 1.0
    @AppStorage(SettingsKey.stereo) private var stereo = false

    @AppStorage(CampfireSettings.bellStrength) private var bellStrength = CampfireSettings.defaultBellStrength
    @AppStorage(CampfireSettings.bellWidth) private var bellWidth = CampfireSettings.defaultBellWidth
    @AppStorage(CampfireSettings.heightSpread) private var heightSpread = CampfireSettings.defaultHeightSpread
    @AppStorage(CampfireSettings.outlierRate) private var outlierRate = CampfireSettings.defaultOutlierRate
    @AppStorage(CampfireSettings.sparks) private var sparks = true

    @AppStorage(WaveformSettings.seconds) private var waveSeconds = WaveformSettings.defaultSeconds
    @AppStorage(WaveformSettings.barWidth) private var waveBarWidth = WaveformSettings.defaultBarWidth
    @AppStorage(WaveformSettings.fade) private var waveFade = true
    @AppStorage(WaveformSettings.rangeDB) private var waveRange = WaveformSettings.defaultRangeDB

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

                Toggle(isOn: $stereo) {
                    Text("Стерео")
                    Text("Левый и правый каналы показываются отдельно.")
                }
            } header: {
                bubbleHeader("Общие", systemImage: "slider.horizontal.3",
                             isDefault: abs(sensitivity - 1) < 0.001 && !stereo) {
                    sensitivity = 1
                    stereo = false
                }
            }

            campfireBubble
            waveformBubble
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Mode bubbles

    private var campfireBubble: some View {
        Section {
            slider("Выраженность колокола", value: $bellStrength, in: 0...1,
                   text: (bellStrength * 100).formatted(.number.precision(.fractionLength(0))) + " %")
            slider("Ширина колокола", value: $bellWidth, in: 0.2...1,
                   text: bellWidth.formatted(.number.precision(.fractionLength(2))))
            slider("Разброс высот", value: $heightSpread, in: 0...0.35,
                   text: heightSpread.formatted(.number.precision(.fractionLength(2))))
            slider("Выбросы", value: $outlierRate, in: 0...0.5,
                   text: outlierRate.formatted(.number.precision(.fractionLength(2))) + " / с")
            Toggle("Искры", isOn: $sparks)
        } header: {
            bubbleHeader(VisualizerMode.campfire,
                         isDefault: bellStrength == CampfireSettings.defaultBellStrength
                            && bellWidth == CampfireSettings.defaultBellWidth
                            && heightSpread == CampfireSettings.defaultHeightSpread
                            && outlierRate == CampfireSettings.defaultOutlierRate
                            && sparks) {
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
        } header: {
            bubbleHeader(VisualizerMode.waveform,
                         isDefault: waveSeconds == WaveformSettings.defaultSeconds
                            && waveBarWidth == WaveformSettings.defaultBarWidth
                            && waveFade
                            && waveRange == WaveformSettings.defaultRangeDB) {
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

    // MARK: Building blocks

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
