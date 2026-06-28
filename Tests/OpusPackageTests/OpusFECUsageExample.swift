import OpusShims
import XCTest
@testable import OpusKit

/// Example demonstrating proper FEC usage pattern for packet loss recovery
/// This shows the exact pattern you mentioned: "packet N-1 lost → decode N-1 from N with fec=true, then decode N
/// normally"
final class OpusFECUsageExample: XCTestCase {
    func testProperFECPattern() throws {
        // Setup encoder with FEC enabled
        let encoder = try Opus.Encoder.voice()
        try encoder.set(inbandFEC: true)
        try encoder.set(packetLossPercent: 10)

        let decoder = try Opus.Decoder.voice()

        // Generate 3 frames of test audio
        let frameSize = 320 // 20ms @ 16kHz
        let testAudio = generateSineWave(samples: frameSize * 3)

        // Encode 3 consecutive packets
        let packet1 = try encodeFrame(Array(testAudio[0 ..< frameSize]), encoder: encoder)
        let packet2 = try encodeFrame(Array(testAudio[frameSize ..< (frameSize * 2)]), encoder: encoder)
        let packet3 = try encodeFrame(Array(testAudio[(frameSize * 2) ..< (frameSize * 3)]), encoder: encoder)

        print("📡 Encoded 3 packets: \(packet1.count), \(packet2.count), \(packet3.count) bytes")

        // ✅ Normal case: All packets received
        try decoder.reset()
        let decoded1 = try decoder.decodePCM16(data: packet1, fec: false)
        let decoded2 = try decoder.decodePCM16(data: packet2, fec: false)
        let decoded3 = try decoder.decodePCM16(data: packet3, fec: false)
        print("✅ Normal decode: \(decoded1.count), \(decoded2.count), \(decoded3.count) samples")

        // 🔧 Packet loss scenario: packet2 is lost, packet3 arrives
        try decoder.reset()

        // Step 1: Decode packet1 normally
        let decodedFrame1 = try decoder.decodePCM16(data: packet1, fec: false)

        // Step 2: packet2 is LOST - simulate network loss
        print("📦 Packet 2 lost in network!")

        // Step 3: packet3 arrives - PROPER FEC USAGE PATTERN:
        print("📡 Packet 3 received - applying FEC recovery...")

        // 3a) First, decode the LOST packet2 using FEC from packet3
        let recoveredFrame2 = try decoder.decodePCM16(data: packet3, fec: true) // ✅ fec=true to recover N-1
        print("🔧 Recovered frame 2 using FEC: \(recoveredFrame2.count) samples")

        // 3b) Then, decode packet3 normally
        let decodedFrame3 = try decoder.decodePCM16(data: packet3, fec: false) // ✅ fec=false for current packet
        print("✅ Decoded frame 3 normally: \(decodedFrame3.count) samples")

        // Validate the FEC recovery worked
        XCTAssertEqual(decodedFrame1.count, frameSize, "Frame 1 should be full size")
        XCTAssertEqual(recoveredFrame2.count, frameSize, "Recovered frame 2 should be full size")
        XCTAssertEqual(decodedFrame3.count, frameSize, "Frame 3 should be full size")

        // Quality check: FEC should recover meaningful audio
        let originalRMS = calculateRMS(decoded2)
        let recoveredRMS = calculateRMS(recoveredFrame2)
        let recoveryRatio = recoveredRMS / originalRMS

        print("📊 FEC Quality Analysis:")
        print("   - Original frame 2 RMS: \(String(format: "%.3f", originalRMS))")
        print("   - FEC recovered RMS: \(String(format: "%.3f", recoveredRMS))")
        print("   - Recovery ratio: \(String(format: "%.1f%%", recoveryRatio * 100))")

        XCTAssertGreaterThan(recoveryRatio, 0.5, "FEC should recover at least 50% of original quality")
        XCTAssertLessThan(recoveryRatio, 1.5, "FEC should not create unrealistic amplification")

        print("✅ FEC pattern validation complete!")
    }

    func testSequentialPacketLoss() throws {
        // Test the pattern across multiple packet losses
        let encoder = try Opus.Encoder.voice()
        try encoder.set(inbandFEC: true)

        let decoder = try Opus.Decoder.voice()

        // Create 5 packets
        let frameSize = 320
        let packets = try (0 ..< 5).map { i in
            let audio = generateSineWave(samples: frameSize, frequency: 440 + Float(i * 50)) // Different frequencies
            return try encodeFrame(audio, encoder: encoder)
        }

        // Simulate loss pattern: packets 1 and 3 are lost
        let lossPattern = [false, true, false, true, false] // lose packets 1 and 3

        var recoveredAudio: [[opus_int16]] = []

        for (i, isLost) in lossPattern.enumerated() {
            print("\n--- Processing packet \(i) ---")

            if isLost {
                print("📦 Packet \(i) lost!")

                // Try FEC recovery from next packet (if available)
                if i + 1 < packets.count {
                    print("🔧 Attempting FEC recovery using packet \(i + 1)")
                    let recovered = try decoder.decodePCM16(data: packets[i + 1], fec: true)
                    recoveredAudio.append(recovered)
                    print("✅ FEC recovered \(recovered.count) samples for packet \(i)")
                } else {
                    // No next packet - use PLC
                    print("🔧 No next packet available, using PLC")
                    let concealed = try decoder.concealPCM16()
                    recoveredAudio.append(concealed)
                }
            } else {
                print("✅ Packet \(i) received normally")
                let decoded = try decoder.decodePCM16(data: packets[i], fec: false)
                recoveredAudio.append(decoded)
            }
        }

        // Validate all frames were recovered
        XCTAssertEqual(recoveredAudio.count, 5, "Should recover all 5 frames")
        for frame in recoveredAudio {
            XCTAssertEqual(frame.count, frameSize, "Each frame should be full size")
        }

        print("\n📊 Sequential Recovery Summary:")
        print("   - Total frames: 5")
        print("   - Lost frames: 2")
        print("   - All frames recovered: ✅")
    }

    // MARK: - Helper Methods

    private func generateSineWave(samples: Int, frequency: Float = 440.0) -> [opus_int16] {
        let sampleRate: Float = 16000.0
        return (0 ..< samples).map { i in
            let t = Float(i) / sampleRate
            let amplitude: Float = 16000.0
            let sample = amplitude * sin(2.0 * .pi * frequency * t)
            return opus_int16(sample)
        }
    }

    private func encodeFrame(_ frame: [opus_int16], encoder: Opus.Encoder) throws -> Data {
        try frame.withUnsafeBufferPointer { buffer in
            guard let ptr = buffer.baseAddress else { throw Opus.Error.badArgument }
            return try encoder.encode(pcm: ptr, frameSize: Int32(frame.count))
        }
    }

    private func calculateRMS(_ samples: [opus_int16]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(0.0) { sum, sample in
            let normalized = Float(sample) / Float(Int16.max)
            return sum + Double(normalized * normalized)
        }
        return Float(sqrt(sumSquares / Double(samples.count)))
    }
}
