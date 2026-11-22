import Foundation
import OpusKit
import OpusShims
import XCTest

@MainActor
final class OpusOwnedPCMOutputTests: XCTestCase {
    private func makePacket(
        sampleRate: Opus.SampleRate,
        channels: Opus.Channels,
        duration: Opus.FrameDuration
    ) throws -> Data {
        let encoder = try Opus.Encoder(.init(
            sampleRate: sampleRate,
            channels: channels,
            application: .voip,
            complexity: 7,
            vbr: true,
            constrainedVBR: true,
            fec: true,
            dtx: false,
            expectedLossPerc: 15,
            bitrate: 64_000
        ))
        let frames = Int(sampleRate.frameSize(duration))
        let channelCount = Int(channels.rawValue)
        let pcm: [opus_int16] = (0 ..< frames * channelCount).map { index in
            let value = 12_000 * sin(2 * Double.pi * Double(index / channelCount) / 53)
            return opus_int16(value)
        }
        return try pcm.withUnsafeBufferPointer { samples in
            try encoder.encode(pcm: samples.baseAddress!, frameSize: Int32(frames))
        }
    }

    func testOwnedOutputMatchesLegacyDecodeForMonoStereoAndLongFrames() throws {
        for (rate, channels, duration) in [
            (Opus.SampleRate.hz16k, Opus.Channels.mono, Opus.FrameDuration.ms20),
            (Opus.SampleRate.hz48k, Opus.Channels.mono, Opus.FrameDuration(120)),
            (Opus.SampleRate.hz48k, Opus.Channels.stereo, Opus.FrameDuration.ms20),
        ] {
            let packet = try makePacket(sampleRate: rate, channels: channels, duration: duration)
            let legacy = try Opus.Decoder(sampleRate: rate, channels: channels)
            let owned = try Opus.Decoder(sampleRate: rate, channels: channels)
            let reference = try legacy.decodePCM16(data: packet, expected: duration)
            let expectedBytes = reference.withUnsafeBytes { Data($0) }

            var output = Data(repeating: 0xAB, count: 16)
            let frames = try owned.decodePCM16(data: packet, expected: duration, into: &output)
            XCTAssertEqual(frames, reference.count / Int(channels.rawValue))
            XCTAssertEqual(output, expectedBytes)

            // A later decode must not mutate bytes retained by an asynchronous consumer.
            let previous = output
            let nextFrames = try owned.decodePCM16(data: packet, expected: duration, into: &output)
            XCTAssertEqual(nextFrames, frames)
            XCTAssertEqual(previous, expectedBytes)
        }
    }

    func testOwnedFECAndPLCMatchLegacyState() throws {
        let packet = try makePacket(sampleRate: .hz16k, channels: .mono, duration: .ms20)
        let legacy = try Opus.Decoder(sampleRate: .hz16k, channels: .mono)
        let owned = try Opus.Decoder(sampleRate: .hz16k, channels: .mono)

        let recovered = try legacy.decodePCM16(data: packet, fec: true, expected: .ms20)
        var output = Data()
        let frames = try owned.decodePCM16(data: packet, fec: true, expected: .ms20, into: &output)
        XCTAssertEqual(frames, recovered.count)
        XCTAssertEqual(output, recovered.withUnsafeBytes { Data($0) })

        let legacyPLC = try legacy.concealPCM16(expected: .ms20)
        let plcFrames = try owned.concealPCM16(expected: .ms20, into: &output)
        XCTAssertEqual(plcFrames, legacyPLC.count)
        XCTAssertEqual(output, legacyPLC.withUnsafeBytes { Data($0) })
    }

    func testInvalidInputAndUndersizedBufferAreRejected() throws {
        let decoder = try Opus.Decoder(sampleRate: .hz48k, channels: .stereo)
        var output = Data([1, 2, 3])
        XCTAssertThrowsError(try decoder.decodePCM16(data: Data(), into: &output))
        XCTAssertEqual(output, Data([1, 2, 3]))

        let packet = try makePacket(sampleRate: .hz48k, channels: .stereo, duration: .ms20)
        var undersized = [opus_int16](repeating: 0, count: 100)
        XCTAssertThrowsError(try packet.withUnsafeBytes { raw in
            try undersized.withUnsafeMutableBufferPointer { samples in
                try decoder.decodePCM16(
                    packet: raw.bindMemory(to: UInt8.self).baseAddress,
                    packetLen: Int32(packet.count),
                    expected: .ms20,
                    into: samples
                )
            }
        })
    }
}
