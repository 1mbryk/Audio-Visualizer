//
//  VisualizerMode.swift
//  Audio Vusualizer
//
//  The list of visualizations the header lets you pick from.
//

import SwiftUI

enum VisualizerMode: String, CaseIterable, Identifiable {
    case campfire

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .campfire: "Костёр"
        }
    }

    var systemImage: String {
        switch self {
        case .campfire: "flame.fill"
        }
    }
}
