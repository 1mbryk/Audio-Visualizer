//
//  MatrixView.swift
//  Audio Vusualizer
//
//  "Матрица": digital rain of glyphs. Every column is a frequency band (bass on the
//  left, treble on the right); energy in a band sends streams of glyphs falling from
//  the top of its column — louder bands rain more often, longer, brighter and faster.
//

import AppKit
import SwiftUI

/// Simulation of the rain, kept across frames.
final class MatrixModel {
    struct Drop {
        var column: Int
        /// Row of the head, in cells (fractional while falling).
        var head: Double
        /// Cells per second.
        var speed: Double
        var length: Int
        /// 0...1, from the band's loudness when the drop started.
        var intensity: Double
        var glyphs: [Character]
    }

    static let glyphSet: [Character] = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789Z:.=*+-<>¦")
    static let glyphIndex: [Character: Int] = Dictionary(
        glyphSet.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

    private let analyzer = SpectrumAnalyzer()
    private let level = AutoLevel()
    private(set) var drops: [Drop] = []
    /// Smoothed 0...1 loudness per column, and its previous value (to catch onsets).
    private var bands: [Double] = []
    private var previous: [Double] = []
    private var lastTime: Double?
    private var lastBlockCount = -1
    private var lastAudio = Date.distantPast

    // Tunables set from the settings each frame.
    var speedScale = 1.0
    var trailScale = 1.0
    /// How often new drops start, relative to the default.
    var spawnScale = 1.0
    var rangeDB: Float = 30

    func step(date: Date, columns: Int, rows: Int, audio: SystemAudioMonitor) {
        let now = date.timeIntervalSinceReferenceDate
        let dt = min(max(now - (lastTime ?? now), 0), 1.0 / 20)
        lastTime = now

        if bands.count != columns {
            bands = Array(repeating: 0, count: columns)
            previous = bands
            drops.removeAll { $0.column >= columns }
        }

        // Band loudness. No audio arrives during silence, so the samples go stale then.
        let blocks = audio.blockCount
        if blocks != lastBlockCount {
            lastBlockCount = blocks
            lastAudio = date
        }
        var targets = [Double](repeating: 0, count: columns)
        if date.timeIntervalSince(lastAudio) < 0.25, columns > 0 {
            let samples = audio.recentSamples(frames: analyzer.size)
            if samples.left.count == analyzer.size {
                let mono = zip(samples.left, samples.right).map { ($0 + $1) / 2 }
                let dbs = analyzer.bands(analyzer.power(of: mono), count: columns,
                                         sampleRate: audio.sampleRate, minHz: 40, maxHz: 14_000)
                let reference = level.update(with: dbs)
                targets = dbs.map { Double(min(max(1 + ($0 - reference) / rangeDB, 0), 1)) }
            }
        }
        previous = bands
        for i in 0..<columns {
            bands[i] += (targets[i] - bands[i]) * (targets[i] > bands[i] ? 0.6 : 0.15)
        }

        // Start new drops at the top of columns with energy.
        for column in 0..<columns {
            let v = bands[column]
            guard v > 0.05 else { continue }
            let falling = drops.lazy.filter { $0.column == column }
            let busy = falling.contains { $0.head - Double($0.length) < 2 }   // tail still at the top
            if busy || falling.count >= 3 { continue }
            // A sudden hit starts a drop right away; at lower rates only some hits do,
            // so sound starting after silence doesn't drop a flat wall across every column.
            let onset = v - previous[column] > 0.12 && Double.random(in: 0..<1) < spawnScale
            let rate = 4.0 * v * v * spawnScale                                // drops per second
            if onset || Double.random(in: 0..<1) < rate * dt {
                drops.append(makeDrop(column: column, loudness: v, rows: rows))
            }
        }

        // Fall, flicker, and drop what has left the screen.
        for i in drops.indices {
            drops[i].head += drops[i].speed * dt
            if Double.random(in: 0..<1) < 6 * dt {
                let k = Int.random(in: 0..<drops[i].glyphs.count)
                drops[i].glyphs[k] = Self.glyphSet.randomElement()!
            }
        }
        drops.removeAll { $0.head - Double($0.length) > Double(rows) }
    }

    private func makeDrop(column: Int, loudness v: Double, rows: Int) -> Drop {
        let length = max(4, Int((6 + 22 * v) * trailScale * Double.random(in: 0.8...1.2)))
        return Drop(column: column,
                    head: 0,
                    speed: (10 + 26 * v) * speedScale * Double.random(in: 0.85...1.15),
                    length: length,
                    intensity: 0.45 + 0.55 * v,
                    glyphs: (0..<length).map { _ in Self.glyphSet.randomElement()! })
    }
}

/// White glyphs on a transparent texture, one cell per glyph, for the rain shader.
struct GlyphAtlas {
    let image: Image
    let columns: Int
    let rows: Int

    static func make(glyphs: [Character], size: CGFloat, cell: CGSize) -> GlyphAtlas {
        let scale: CGFloat = 2
        let columns = 16
        let rows = (glyphs.count + columns - 1) / columns
        let cw = Int((cell.width * scale).rounded(.up)), ch = Int((cell.height * scale).rounded(.up))
        let ctx = CGContext(data: nil, width: cw * columns, height: ch * rows, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        // Flip so rows go top-down like the texture coordinates.
        ctx.translateBy(x: 0, y: CGFloat(ch * rows))
        ctx.scaleBy(x: 1, y: -1)
        let font = NSFont.monospacedSystemFont(ofSize: size * scale, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        for (i, glyph) in glyphs.enumerated() {
            let text = NSAttributedString(string: String(glyph), attributes: attributes)
            let bounds = text.size()
            let x = CGFloat((i % columns) * cw) + (CGFloat(cw) - bounds.width) / 2
            let y = CGFloat((i / columns) * ch) + (CGFloat(ch) - bounds.height) / 2
            text.draw(at: NSPoint(x: x, y: y))
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = Image(decorative: ctx.makeImage()!, scale: scale)
        return GlyphAtlas(image: image, columns: columns, rows: rows)
    }
}

struct MatrixView: View {
    let audio: SystemAudioMonitor

    @AppStorage(MatrixSettings.glyphSize) private var glyphSize = MatrixSettings.defaultGlyphSize
    @AppStorage(MatrixSettings.speed) private var speed = MatrixSettings.defaultSpeed
    @AppStorage(MatrixSettings.trail) private var trail = MatrixSettings.defaultTrail
    @AppStorage(MatrixSettings.rangeDB) private var rangeDB = MatrixSettings.defaultRangeDB
    @AppStorage(MatrixSettings.spawnRate) private var spawnRate = MatrixSettings.defaultSpawnRate
    @State private var model = MatrixModel()
    @State private var atlas: (size: Double, atlas: GlyphAtlas)?

    private var cell: CGSize { CGSize(width: glyphSize * 0.9, height: glyphSize * 1.15) }

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geo in
                let frame = step(date: timeline.date, size: geo.size)
                let glyphs = currentAtlas()
                ZStack {
                    rain(frame, glyphs)
                    // Soft green glow around the bright glyphs.
                    rain(frame, glyphs)
                        .blur(radius: glyphSize * 0.4)
                        .blendMode(.plusLighter)
                        .opacity(0.7)
                }
            }
        }
        .background(.black)
    }

    private struct Frame {
        var cells: [Float]
        var grid: CGSize
        /// Cell size stretched so the columns span exactly the full width.
        var cell: CGSize
    }

    private func rain(_ frame: Frame, _ glyphs: GlyphAtlas) -> some View {
        Rectangle()
            .fill(.black)
            .colorEffect(ShaderLibrary.matrixRain(
                .float2(frame.cell),
                .float2(frame.grid),
                .floatArray(frame.cells),
                .image(glyphs.image),
                .float2(CGSize(width: glyphs.columns, height: glyphs.rows))))
    }

    private func currentAtlas() -> GlyphAtlas {
        if let atlas, atlas.size == glyphSize { return atlas.atlas }
        let made = GlyphAtlas.make(glyphs: MatrixModel.glyphSet, size: glyphSize, cell: cell)
        DispatchQueue.main.async { atlas = (glyphSize, made) }
        return made
    }

    /// Advances the rain and lays it out as one value per grid cell for the shader.
    private func step(date: Date, size: CGSize) -> Frame {
        let columns = max(1, Int(size.width / cell.width))
        let rows = Int(size.height / cell.height) + 1

        model.speedScale = speed
        model.trailScale = trail
        model.spawnScale = spawnRate
        model.rangeDB = Float(rangeDB)
        model.step(date: date, columns: columns, rows: rows, audio: audio)

        var cells = [Float](repeating: 0, count: columns * rows)
        for drop in model.drops {
            let headRow = Int(drop.head)
            for k in 0..<drop.length {
                let row = headRow - k
                guard row >= 0, row < rows else { continue }
                let glyph = MatrixModel.glyphIndex[drop.glyphs[k % drop.glyphs.count]] ?? 0
                // The head is marked with brightness 1; the tail fades out towards its end.
                let brightness = k == 0
                    ? 1.0
                    : min(0.99, drop.intensity * pow(1 - Double(k) / Double(drop.length), 1.3))
                let index = drop.column * rows + row
                let value = Float(glyph * 2) + Float(brightness)
                // Where drops overlap keep the brighter one.
                if value - Float(Int(value / 2) * 2) > cells[index] - Float(Int(cells[index] / 2) * 2) {
                    cells[index] = value
                }
            }
        }
        return Frame(cells: cells, grid: CGSize(width: columns, height: rows),
                     cell: CGSize(width: size.width / CGFloat(columns), height: cell.height))
    }
}

