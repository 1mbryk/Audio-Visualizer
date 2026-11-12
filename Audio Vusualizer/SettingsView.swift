//
//  SettingsView.swift
//  Audio Vusualizer
//
//  App settings window (opened with ⌘,).
//

import SwiftUI

enum SettingsKey {
    /// Audio input gain multiplier, 0.25 ... 4 (1 = default).
    static let sensitivity = "sensitivity"
    /// Left half of the fire follows the left channel, right half the right one.
    static let stereo = "stereo"
    /// Selected visualization (`VisualizerMode` raw value).
    static let mode = "mode"
}

struct SettingsView: View {
    @AppStorage(SettingsKey.sensitivity) private var sensitivity = 1.0
    @AppStorage(SettingsKey.stereo) private var stereo = false

    /// The slider works on a log2 scale so ×0.5 and ×2 sit symmetrically around ×1.
    private var sliderValue: Binding<Double> {
        Binding(get: { log2(sensitivity) },
                set: { sensitivity = pow(2, $0) })
    }

    var body: some View {
        Form {
            LabeledContent("Чувствительность к звуку") {
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: sliderValue, in: -2...2) {
                        EmptyView()
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill")
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    HStack {
                        Text("×\(sensitivity, format: .number.precision(.fractionLength(2)))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Сбросить") { sensitivity = 1 }
                            .disabled(abs(sensitivity - 1) < 0.001)
                    }
                }
            }
            Text("Чем выше чувствительность, тем выше пламя при той же громкости.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle(isOn: $stereo) {
                Text("Стерео")
                Text("Левая половина костра реагирует на левый канал, правая — на правый.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    SettingsView()
}
