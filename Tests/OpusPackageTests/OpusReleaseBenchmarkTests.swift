#if os(macOS)
@preconcurrency import AVFoundation
import Darwin
import Foundation
import OpusKit
import XCTest

/// An opt-in optimized Release benchmark, without the Advantage application test host.
/// It measures native Opus and owned output; it is not a speech-quality or device-energy gate.
@MainActor
final class OpusReleaseBenchmarkTests: XCTestCase {
    private static let sampleRate = 48_000
    private static let iterations = 96
    private static let repetitions = 4
    private static let maximumPacketBytes = 1_500
    private static let seed: UInt64 = 14_695_981_039_346_656_037
    private static let prime = UInt64(1_099_511_628_211)

    private enum BenchmarkFailure: Error {
        case invalidPacket
        case invalidPCM
    }

    private struct Observation: Encodable {
        let operation: String
        let variant: String
        let frameMilliseconds: Int
        let repetition: Int
        let packetCount: Int
        let cpuP50Nanoseconds: UInt64
        let cpuP95Nanoseconds: UInt64
        let cpuP99Nanoseconds: UInt64
        let wallP50Nanoseconds: UInt64
        let wallP95Nanoseconds: UInt64
        let wallP99Nanoseconds: UInt64
        let totalInputBytes: Int
        let totalOutputBytes: Int
        let outputFNV1a64: String
    }

    private struct Report: Encodable {
        let schemaVersion = 1
        let buildConfiguration = "release"
        let cpuClock = "thread_cpu_time"
        let signal = "synthetic_voice_like_with_silence"
        let sampleRate = OpusReleaseBenchmarkTests.sampleRate
        let channels = 1
        let bitrate = 64_000
        let constrainedVBR = true
        let fecEnabled = false
        let dtxEnabled = true
        let packetCount = OpusReleaseBenchmarkTests.iterations
        let repetitions = OpusReleaseBenchmarkTests.repetitions
        let inputFingerprintFNV1a64: String
        let observations: [Observation]
    }

    func testNativeReleaseEncodeAndOwnedDecodeComparison() throws {
        guard ProcessInfo.processInfo.environment["OPUS_RELEASE_BENCHMARK"] == "1" else {
            throw XCTSkip("Set OPUS_RELEASE_BENCHMARK=1 for the optimized Release benchmark.")
        }

        var inputFingerprint = Self.seed
        var observations: [Observation] = []

        for frameMilliseconds in [20, 60, 120] {
            let duration = Opus.FrameDuration(Double(frameMilliseconds))
            let sampleCount = Self.sampleRate * frameMilliseconds / 1_000
            let frames = try makeFrames(milliseconds: frameMilliseconds, fingerprint: &inputFingerprint)

            for repetition in 0 ..< Self.repetitions {
                let complexities: [Int32] = repetition.isMultiple(of: 2) ? [7, 6, 5] : [5, 6, 7]
                for complexity in complexities {
                    let encoder = try makeEncoder(complexity: complexity)
                    var scratch = Data(count: Self.maximumPacketBytes)

                    // Warm a stateful encoder before measuring its packet materialization.
                    for index in 0 ..< 16 {
                        _ = try encoder.encode(frames[index % frames.count], to: &scratch)
                    }

                    let row = try measure(
                        operation: "encodeWithOwnedPacket",
                        variant: "complexity\(complexity)",
                        frameMilliseconds: frameMilliseconds,
                        repetition: repetition
                    ) { index in
                        let length = try encoder.encode(frames[index % frames.count], to: &scratch)
                        guard length > 0, length <= scratch.count else { throw BenchmarkFailure.invalidPacket }
                        return (scratch.subdata(in: 0 ..< length), 0)
                    }
                    observations.append(row)
                }
            }

            // Encode inputs only once per duration. The same packets, decoder state
            // and warm-up sequence are used for both old and new decode methods.
            let fixtureEncoder = try makeEncoder(complexity: 7)
            var scratch = Data(count: Self.maximumPacketBytes)
            var packets: [Data] = []
            for frame in frames {
                let length = try fixtureEncoder.encode(frame, to: &scratch)
                guard length > 0, length <= scratch.count else { throw BenchmarkFailure.invalidPacket }
                packets.append(scratch.subdata(in: 0 ..< length))
            }
            let sanityDecoder = try Opus.Decoder(sampleRate: .hz48k, channels: .mono)
            XCTAssertEqual(try sanityDecoder.decodePCM16(data: packets[0], expected: duration).count, sampleCount)

            for mode in ["decode", "plc"] {
                for repetition in 0 ..< Self.repetitions {
                    let choices = repetition.isMultiple(of: 2) ? [false, true] : [true, false]
                    var referenceChecksum: String?

                    for ownedOutput in choices {
                        let decoder = try Opus.Decoder(sampleRate: .hz48k, channels: .mono)
                        for index in 0 ..< 16 {
                            _ = try decoder.decodePCM16(data: packets[index % packets.count], expected: duration)
                        }
                        let row = try measure(
                            operation: mode,
                            variant: ownedOutput ? "ownedData" : "legacyArrayPlusBulkCopy",
                            frameMilliseconds: frameMilliseconds,
                            repetition: repetition
                        ) { index in
                            let packet = packets[index % packets.count]
                            let result: Data
                            if ownedOutput {
                                var output = Data()
                                if mode == "plc" {
                                    _ = try decoder.concealPCM16(expected: duration, into: &output)
                                } else {
                                    _ = try decoder.decodePCM16(data: packet, expected: duration, into: &output)
                                }
                                result = output
                            } else {
                                let samples = if mode == "plc" {
                                    try decoder.concealPCM16(expected: duration)
                                } else {
                                    try decoder.decodePCM16(data: packet, expected: duration)
                                }
                                result = samples.withUnsafeBytes { Data($0) }
                            }
                            guard result.count == sampleCount * MemoryLayout<Int16>.size else {
                                throw BenchmarkFailure.invalidPCM
                            }
                            return (result, mode == "plc" ? 0 : packet.count)
                        }
                        if let referenceChecksum {
                            XCTAssertEqual(row.outputFNV1a64, referenceChecksum)
                        } else {
                            referenceChecksum = row.outputFNV1a64
                        }
                        observations.append(row)
                    }
                }
            }
        }

        let report = Report(
            inputFingerprintFNV1a64: String(inputFingerprint, radix: 16),
            observations: observations
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let message = try XCTUnwrap(String(data: encoder.encode(report), encoding: .utf8))
        print("OPUS_OPTIMIZED_RELEASE_BENCHMARK " + message)
    }

    private func makeEncoder(complexity: Int32) throws -> Opus.Encoder {
        try Opus.Encoder(.init(
            sampleRate: .hz48k,
            channels: .mono,
            application: .voip,
            complexity: complexity,
            vbr: true,
            constrainedVBR: true,
            fec: false,
            dtx: true,
            expectedLossPerc: 0,
            bitrate: 64_000
        ))
    }

    private func makeFrames(milliseconds: Int, fingerprint: inout UInt64) throws -> [AVAudioPCMBuffer] {
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: Double(Self.sampleRate), channels: 1
        ))
        let sampleCount = Self.sampleRate * milliseconds / 1_000
        var frames: [AVAudioPCMBuffer] = []
        for packet in 0 ..< 32 {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)
            ))
            buffer.frameLength = AVAudioFrameCount(sampleCount)
            let channel = try XCTUnwrap(buffer.floatChannelData)[0]
            let envelope = packet % 7 == 6 ? 0.0 : 1.0
            for index in 0 ..< sampleCount {
                let second = Double(packet * sampleCount + index) / Double(Self.sampleRate)
                let value = Float(envelope * (
                    0.15 * sin(2 * .pi * 225 * second) + 0.06 * sin(2 * .pi * 610 * second)
                ))
                channel[index] = value
                fingerprint ^= UInt64(value.bitPattern)
                fingerprint &*= Self.prime
            }
            frames.append(buffer)
        }
        return frames
    }

    private func measure(
        operation: String,
        variant: String,
        frameMilliseconds: Int,
        repetition: Int,
        body: (Int) throws -> (Data, Int)
    ) throws -> Observation {
        var cpu: [UInt64] = []
        var wall: [UInt64] = []
        cpu.reserveCapacity(Self.iterations)
        wall.reserveCapacity(Self.iterations)
        var checksum = Self.seed
        var inputBytes = 0
        var outputBytes = 0

        for index in 0 ..< Self.iterations {
            let cpuStart = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            let wallStart = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let (packet, sourceBytes) = try body(index)
            let wallEnd = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let cpuEnd = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            cpu.append(cpuEnd - cpuStart)
            wall.append(wallEnd - wallStart)
            inputBytes += sourceBytes
            outputBytes += packet.count
            for byte in packet {
                checksum ^= UInt64(byte)
                checksum &*= Self.prime
            }
        }

        cpu.sort()
        wall.sort()
        return Observation(
            operation: operation, variant: variant,
            frameMilliseconds: frameMilliseconds, repetition: repetition,
            packetCount: Self.iterations,
            cpuP50Nanoseconds: percentile(cpu, 50),
            cpuP95Nanoseconds: percentile(cpu, 95),
            cpuP99Nanoseconds: percentile(cpu, 99),
            wallP50Nanoseconds: percentile(wall, 50),
            wallP95Nanoseconds: percentile(wall, 95),
            wallP99Nanoseconds: percentile(wall, 99),
            totalInputBytes: inputBytes,
            totalOutputBytes: outputBytes,
            outputFNV1a64: String(checksum, radix: 16)
        )
    }

    private func percentile(_ sorted: [UInt64], _ percent: Int) -> UInt64 {
        sorted[(sorted.count - 1) * percent / 100]
    }
}
#endif
