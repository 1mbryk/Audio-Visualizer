//
//  BarPalette.swift
//  Audio Vusualizer
//
//  Colours of the bar modes (waveform, АЧХ): a two-colour gradient from the centre
//  line to the bar ends (a second pair for the right channel in stereo), or a
//  rainbow across the width.
//

import AppKit
import SwiftUI

enum BarColorStyle: String, CaseIterable, Identifiable {
    /// From "centre" colour at the centre line to "edge" colour at the bar ends.
    case gradient
    /// Rainbow across the width: red on the left … violet on the right.
    case spectrum

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .gradient: "Градиент"
        case .spectrum: "Спектр"
        }
    }
}

struct BarPalette {
    var style: BarColorStyle
    /// Upper half (left channel in stereo, both halves in mono).
    var center: Color
    var edge: Color
    /// Lower half in stereo (right channel).
    var rightCenter: Color
    var rightEdge: Color

    static let defaultCenter = Color(red: 0.2, green: 0.95, blue: 1)
    static let defaultEdge = Color(red: 0.6, green: 0.4, blue: 1)
    static let defaultRightCenter = Color(red: 1, green: 0.4, blue: 0.75)
    static let defaultRightEdge = Color(red: 1, green: 0.55, blue: 0.4)

    /// UserDefaults keys for a mode, e.g. `BarPalette.Keys("waveform")`.
    struct Keys {
        let style, center, edge, rightCenter, rightEdge: String
        init(_ prefix: String) {
            style = "\(prefix).colorStyle"
            center = "\(prefix).colorCenter"
            edge = "\(prefix).colorEdge"
            rightCenter = "\(prefix).colorRightCenter"
            rightEdge = "\(prefix).colorRightEdge"
        }
    }
}

/// Lets colours live in `@AppStorage` (stored as "r,g,b,a" in sRGB).
extension Color: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        self = Color(.sRGB, red: parts[0], green: parts[1], blue: parts[2], opacity: parts[3])
    }

    public var rawValue: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "0,0,0,1" }
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
            .map { String(format: "%.4f", $0) }.joined(separator: ",")
    }
}
