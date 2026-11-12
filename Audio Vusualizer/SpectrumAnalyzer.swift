//
//  SpectrumAnalyzer.swift
//  Audio Vusualizer
//
//  Power spectrum of a block of samples (Hann window + real FFT, Accelerate),
//  grouped into logarithmically spaced frequency bands.
//

import Accelerate
import Foundation

final class SpectrumAnalyzer {
    /// FFT length: 4096 samples ≈ 93 ms at 44.1 kHz, ~11 Hz per bin.
    let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private var real: [Float]
    private var imag: [Float]

    init(size: Int = 4096) {
        self.size = size
        log2n = vDSP_Length(log2(Double(size)).rounded())
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                             count: size, isHalfWindow: false)
        real = [Float](repeating: 0, count: size / 2)
        imag = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Power per FFT bin (size/2 bins), normalised so a full-scale sine peaks near 1.
    func power(of samples: [Float]) -> [Float] {
        precondition(samples.count == size)
        let windowed = vDSP.multiply(samples, window)
        let half = size / 2
        var power = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBytes { bytes in
                    vDSP_ctoz(bytes.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                              &split, 1, vDSP_Length(half))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(half))
            }
        }
        // zrip returns 2·DFT; a Hann-windowed sine of amplitude A peaks at A·N/4.
        var scale = Float(4) / Float(size * size)
        vDSP_vsmul(power, 1, &scale, &power, 1, vDSP_Length(half))
        power[0] = 0  // DC (and the packed Nyquist value)
        return power
    }

    /// Level in dB of `count` log-spaced bands from `minHz` to `maxHz`.
    /// Narrow low bands, narrower than one bin, interpolate between bins.
    /// `tilt` dB per octave (relative to 1 kHz) offsets music's natural bass-heavy slope.
    func bands(_ power: [Float], count: Int, sampleRate: Double,
               minHz: Double = 30, maxHz: Double = 16_000, tilt: Double = 3) -> [Float] {
        let top = min(maxHz, sampleRate / 2 * 0.98)
        let binHz = sampleRate / Double(size)
        let ratio = top / minHz
        return (0..<count).map { i in
            let f0 = minHz * pow(ratio, Double(i) / Double(count))
            let f1 = minHz * pow(ratio, Double(i + 1) / Double(count))
            let k0 = f0 / binHz, k1 = f1 / binHz
            var p: Float
            if k1 - k0 < 1 {
                // Interpolate the power at the band's centre.
                let kc = (k0 + k1) / 2
                let i0 = min(Int(kc), power.count - 2)
                let t = Float(kc - Double(i0))
                p = power[i0] * (1 - t) + power[i0 + 1] * t
            } else {
                let lo = max(Int(k0.rounded(.down)), 1)
                let hi = min(max(Int(k1.rounded(.up)), lo + 1), power.count)
                var sum: Float = 0
                for k in lo..<hi { sum += power[k] }
                p = sum / Float(hi - lo)
            }
            let centre = sqrt(f0 * f1)
            return 10 * log10(max(p, 1e-14)) + Float(tilt * log2(centre / 1000))
        }
    }
}
