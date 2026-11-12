//
//  SystemAudioMonitor.swift
//  Audio Vusualizer
//
//  Captures everything the Mac is playing through a Core Audio process tap
//  and exposes the current loudness as a 0...1 value.
//

import AudioToolbox
import CoreAudio
import Foundation
import Synchronization

nonisolated final class SystemAudioMonitor: @unchecked Sendable {

    enum MonitorError: LocalizedError {
        case coreAudio(String, OSStatus)
        var errorDescription: String? {
            switch self {
            case let .coreAudio(what, status): "\(what) failed (OSStatus \(status))"
            }
        }
    }

    /// Smoothed loudness of both channels together, 0 (silence) ... 1 (very loud).
    var level: Float { state.withLock { $0.level } }

    /// Smoothed loudness of the left and right channels separately, 0 ... 1.
    var stereoLevels: (left: Float, right: Float) {
        state.withLock { ($0.left, $0.right) }
    }

    /// Input gain (sensitivity) applied before measuring loudness; 1 = unchanged.
    var gain: Float {
        get { state.withLock { $0.gain } }
        set { state.withLock { $0.gain = max(newValue, 0) } }
    }

    /// The most recent `frames` samples of each channel, oldest first (gain not applied).
    func recentSamples(frames: Int) -> (left: [Float], right: [Float]) {
        state.withLock { s in
            let n = min(frames, State.ringSize)
            var left = [Float](repeating: 0, count: n)
            var right = [Float](repeating: 0, count: n)
            var j = (s.writeIndex - n + State.ringSize) % State.ringSize
            for i in 0..<n {
                left[i] = s.ringLeft[j]
                right[i] = s.ringRight[j]
                j = (j + 1) % State.ringSize
            }
            return (left, right)
        }
    }

    /// The most recent `count` peak values per channel, oldest first (gain not applied).
    /// Each value is the largest |sample| over `State.peakBlock` frames (~5 ms).
    func recentPeaks(count: Int) -> (left: [Float], right: [Float]) {
        state.withLock { s in
            let n = min(count, State.peakRingSize)
            var left = [Float](repeating: 0, count: n)
            var right = [Float](repeating: 0, count: n)
            var j = (s.peakIndex - n + State.peakRingSize) % State.peakRingSize
            for i in 0..<n {
                left[i] = s.peakLeft[j]
                right[i] = s.peakRight[j]
                j = (j + 1) % State.peakRingSize
            }
            return (left, right)
        }
    }

    /// Sample rate of the captured stream, Hz.
    var sampleRate: Double { state.withLock { $0.sampleRate } }

    /// Frames per peak value in `recentPeaks`.
    static var peakBlock: Int { State.peakBlock }

    /// RMS of each peak block, per channel, oldest first (gain not applied).
    /// `end` is the absolute number of blocks recorded so far, i.e. the index just
    /// after the newest returned block; it lets views keep bars anchored to the audio.
    func recentRMS(count: Int) -> (left: [Float], right: [Float], end: Int) {
        state.withLock { s in
            let n = min(count, State.peakRingSize)
            var left = [Float](repeating: 0, count: n)
            var right = [Float](repeating: 0, count: n)
            var j = (s.peakIndex - n + State.peakRingSize) % State.peakRingSize
            for i in 0..<n {
                left[i] = s.rmsLeft[j]
                right[i] = s.rmsRight[j]
                j = (j + 1) % State.peakRingSize
            }
            return (left, right, s.totalBlocks)
        }
    }

    private struct State {
        static let ringSize = 8192
        /// Frames per peak value, and how many peak values are kept (~10 s at 48 kHz).
        static let peakBlock = 256
        static let peakRingSize = 2048

        var level: Float = 0
        var left: Float = 0
        var right: Float = 0
        var gain: Float = 1
        var sampleRate: Double = 48_000
        // Ring buffers with the latest raw samples, for waveform drawing.
        var ringLeft = [Float](repeating: 0, count: ringSize)
        var ringRight = [Float](repeating: 0, count: ringSize)
        var writeIndex = 0
        // Peak history for the amplitude waveform.
        var peakLeft = [Float](repeating: 0, count: peakRingSize)
        var peakRight = [Float](repeating: 0, count: peakRingSize)
        var rmsLeft = [Float](repeating: 0, count: peakRingSize)
        var rmsRight = [Float](repeating: 0, count: peakRingSize)
        var peakIndex = 0
        var totalBlocks = 0
        var blockFrames = 0
        var blockMax: (left: Float, right: Float) = (0, 0)
        var blockSumSq: (left: Float, right: Float) = (0, 0)

        mutating func push(_ l: Float, _ r: Float) {
            ringLeft[writeIndex] = l
            ringRight[writeIndex] = r
            writeIndex = (writeIndex + 1) % Self.ringSize

            blockMax.left = max(blockMax.left, abs(l))
            blockMax.right = max(blockMax.right, abs(r))
            blockSumSq.left += l * l
            blockSumSq.right += r * r
            blockFrames += 1
            if blockFrames == Self.peakBlock {
                peakLeft[peakIndex] = blockMax.left
                peakRight[peakIndex] = blockMax.right
                rmsLeft[peakIndex] = sqrt(blockSumSq.left / Float(Self.peakBlock))
                rmsRight[peakIndex] = sqrt(blockSumSq.right / Float(Self.peakBlock))
                peakIndex = (peakIndex + 1) % Self.peakRingSize
                totalBlocks += 1
                blockFrames = 0
                blockMax = (0, 0)
                blockSumSq = (0, 0)
            }
        }
    }
    private let state = Mutex(State())

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "fire.audio.tap", qos: .userInteractive)

    func start() throws {
        stop()

        // 1. Global stereo tap of every process' output; audio keeps playing normally.
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true
        tapDescription.name = "Fire Visualizer Tap"

        var newTap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(tapDescription, &newTap), "AudioHardwareCreateProcessTap")
        tapID = newTap

        // 2. Aggregate device that contains the tap (clocked by the default output device).
        let outputUID = try defaultOutputDeviceUID()
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Fire Visualizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapDescription.uuid.uuidString,
            ]],
        ]
        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregate),
                  "AudioHardwareCreateAggregateDevice")
        aggregateID = newAggregate

        // 3. IO proc: compute RMS of each buffer and feed an envelope follower.
        var procID: AudioDeviceIOProcID?
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, inData, _, _, _ in
            self?.process(inData)
        }, "AudioDeviceCreateIOProcIDWithBlock")
        ioProcID = procID

        var rate = Float64(0)
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        var rateAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(aggregateID, &rateAddress, 0, nil, &rateSize, &rate) == noErr, rate > 0 {
            state.withLock { $0.sampleRate = rate }
        }

        try check(AudioDeviceStart(aggregateID, ioProcID), "AudioDeviceStart")
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            if let ioProcID { AudioDeviceDestroyIOProcID(aggregateID, ioProcID) }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit { stop() }

    // MARK: - Processing

    private func process(_ bufferList: UnsafePointer<AudioBufferList>) {
        // The tap is stereo. Depending on the stream layout the samples arrive either
        // interleaved in one buffer (L R L R …) or as one buffer per channel.
        var sum: (left: Float, right: Float) = (0, 0)
        var frames: (left: Int, right: Int) = (0, 0)

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        for (index, buffer) in buffers.enumerated() {
            guard let data = buffer.mData else { continue }
            let n = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            let samples = data.assumingMemoryBound(to: Float32.self)
            let channels = max(Int(buffer.mNumberChannels), 1)

            if channels >= 2 {
                // Interleaved: channel 0 is left, channel 1 is right.
                var i = 0
                while i + 1 < n {
                    sum.left += samples[i] * samples[i]
                    sum.right += samples[i + 1] * samples[i + 1]
                    i += channels
                }
                frames.left += n / channels
                frames.right += n / channels
            } else {
                // One channel per buffer: even buffers are left, odd ones right.
                var acc: Float = 0
                for i in 0..<n { acc += samples[i] * samples[i] }
                if index % 2 == 0 { sum.left += acc; frames.left += n }
                else { sum.right += acc; frames.right += n }
            }
        }
        guard frames.left + frames.right > 0 else { return }
        // A mono stream feeds both sides.
        if frames.right == 0 { sum.right = sum.left; frames.right = frames.left }

        let rmsLeft = sqrt(sum.left / Float(max(frames.left, 1)))
        let rmsRight = sqrt(sum.right / Float(max(frames.right, 1)))
        let rmsBoth = sqrt((sum.left + sum.right) / Float(frames.left + frames.right))

        state.withLock { s in
            s.level = follow(s.level, rms: rmsBoth, gain: s.gain)
            s.left = follow(s.left, rms: rmsLeft, gain: s.gain)
            s.right = follow(s.right, rms: rmsRight, gain: s.gain)
            store(buffers, into: &s)
        }
    }

    /// Appends the callback's samples to the ring buffers (in place, no allocations).
    private func store(_ buffers: UnsafeMutableAudioBufferListPointer, into s: inout State) {
        guard let first = buffers.first, let firstData = first.mData else { return }
        let channels = max(Int(first.mNumberChannels), 1)
        let a = firstData.assumingMemoryBound(to: Float32.self)
        let n = Int(first.mDataByteSize) / MemoryLayout<Float32>.size

        if channels >= 2 {
            var i = 0
            while i + 1 < n {
                s.push(a[i], a[i + 1])
                i += channels
            }
        } else {
            // One buffer per channel; a lone buffer is mono and feeds both sides.
            let b = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float32.self) : nil
            let nb = buffers.count > 1 ? Int(buffers[1].mDataByteSize) / MemoryLayout<Float32>.size : n
            for i in 0..<min(n, nb) {
                s.push(a[i], b?[i] ?? a[i])
            }
        }
    }

    /// Envelope follower: maps RMS to 0...1 and smooths it with a fast attack and slower release.
    private func follow(_ current: Float, rms: Float, gain: Float) -> Float {
        let db = 20 * log10(max(rms * gain, 1e-7))
        // Map -55 dB ... -6 dB onto 0 ... 1.
        let target = min(max((db + 55) / 49, 0), 1)
        let k: Float = target > current ? 0.5 : 0.08
        return current + (target - current) * k
    }

    // MARK: - Helpers

    private func defaultOutputDeviceUID() throws -> String {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID),
                  "Get default output device")

        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        try check(AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid), "Get output device UID")
        guard let uid else { throw MonitorError.coreAudio("Output device UID is nil", -1) }
        return uid.takeRetainedValue() as String
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw MonitorError.coreAudio(what, status) }
    }
}
