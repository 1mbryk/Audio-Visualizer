//
//  VisualizerMode.swift
//  Audio Vusualizer
//
//  The list of visualizations the header lets you pick from.
//

import SwiftUI

enum VisualizerMode: String, CaseIterable, Identifiable {
    case campfire
    case waveform

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .campfire: "Костёр"
        case .waveform: "Вейвформа"
        }
    }

    var systemImage: String {
        switch self {
        case .campfire: "flame.fill"
        case .waveform: "waveform.path"
        }
    }
}
