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

    /// Smoothed loudness, 0 (silence) ... 1 (very loud).
    var level: Float { state.withLock { $0.level } }

    private struct State { var level: Float = 0 }
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
        var sumSquares: Float = 0
        var count = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList)) {
            guard let data = buffer.mData else { continue }
            let n = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            let samples = data.assumingMemoryBound(to: Float32.self)
            for i in 0..<n {
                let s = samples[i]
                sumSquares += s * s
            }
            count += n
        }
        guard count > 0 else { return }

        let rms = sqrt(sumSquares / Float(count))
        let db = 20 * log10(max(rms, 1e-7))
        // Map -55 dB ... -6 dB onto 0 ... 1.
        let target = min(max((db + 55) / 49, 0), 1)

        state.withLock { s in
            // Fast attack, slower release, like a VU meter.
            let k: Float = target > s.level ? 0.5 : 0.08
            s.level += (target - s.level) * k
        }
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
