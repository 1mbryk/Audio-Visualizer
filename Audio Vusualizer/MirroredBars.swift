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
    /// In stereo the top half (left channel) and the bottom half (right channel) get
    /// different colours.
    static func draw(in context: inout GraphicsContext, size: CGSize,
                     up: [CGFloat], down: [CGFloat],
                     originX: CGFloat, step: CGFloat, barWidth: CGFloat, stereo: Bool) {
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

        // Bright at the centre, cooler towards the peaks.
        let colors: [Color] = stereo
            ? [Color(red: 0.3, green: 0.6, blue: 1), Color(red: 0.2, green: 0.95, blue: 1),
               Color(red: 1, green: 0.4, blue: 0.75), Color(red: 1, green: 0.55, blue: 0.4)]
            : [Color(red: 0.6, green: 0.4, blue: 1), Color(red: 0.2, green: 0.95, blue: 1),
               Color(red: 0.2, green: 0.95, blue: 1), Color(red: 0.6, green: 0.4, blue: 1)]
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: colors[0], location: 0.05),
                .init(color: colors[1], location: 0.5),
                .init(color: colors[2], location: 0.5),
                .init(color: colors[3], location: 0.95),
            ]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height))

        // Soft glow, then the bars themselves.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 8))
            layer.opacity = 0.6
            layer.fill(path, with: shading)
        }
        context.fill(path, with: shading)
    }
}
