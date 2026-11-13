//
//  MirroredBars.swift
//  Audio Vusualizer
//
//  Shared look of the bar visualizations (waveform, spectrum): rounded bars
//  mirrored around the horizontal centre line, with a gradient and soft glow.
//

import SwiftUI

enum MirroredBars {
    /// Draws one bar per entry of `up`/`down` (heights in points above and below the
    /// centre line), starting at `originX` and `step` points apart.
    /// Colours come from `palette`; in stereo the bottom half (right channel) can have
    /// its own gradient.
    static func draw(in context: inout GraphicsContext, size: CGSize,
                     up: [CGFloat], down: [CGFloat],
                     originX: CGFloat, step: CGFloat, barWidth: CGFloat, stereo: Bool,
                     palette: BarPalette) {
        let mid = size.height / 2
        var path = Path()
        for c in 0..<min(up.count, down.count) {
            let x = originX + CGFloat(c) * step
            guard x + barWidth >= 0, x <= size.width else { continue }
            let h1 = max(up[c], 0.5)
            let h2 = max(down[c], 0.5)
            let rect = CGRect(x: x, y: mid - h1, width: barWidth, height: h1 + h2)
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: barWidth / 2, height: barWidth / 2))
        }

        let shading: GraphicsContext.Shading
        switch palette.style {
        case .gradient:
            // From the centre colour at the centre line to the edge colour at the bar ends;
            // in stereo the lower half (right channel) has its own pair.
            let lowerCenter = stereo ? palette.rightCenter : palette.center
            let lowerEdge = stereo ? palette.rightEdge : palette.edge
            shading = .linearGradient(
                Gradient(stops: [
                    .init(color: palette.edge, location: 0.05),
                    .init(color: palette.center, location: 0.5),
                    .init(color: lowerCenter, location: 0.5),
                    .init(color: lowerEdge, location: 0.95),
                ]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height))
        case .spectrum:
            // Rainbow across the width.
            let hues = stride(from: 0.0, through: 0.8, by: 0.1).map {
                Color(hue: $0, saturation: 0.85, brightness: 1)
            }
            shading = .linearGradient(Gradient(colors: hues),
                                      startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
        }

        // Soft glow, then the bars themselves.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 8))
            layer.opacity = 0.6
            layer.fill(path, with: shading)
        }
        context.fill(path, with: shading)

        if palette.style == .spectrum {
            // Lighter towards the centre line, full colour at the bar ends.
            var light = context
            light.blendMode = .plusLighter
            light.fill(path, with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0.1),
                    .init(color: .white.opacity(0.35), location: 0.5),
                    .init(color: .clear, location: 0.9),
                ]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
    }
}
