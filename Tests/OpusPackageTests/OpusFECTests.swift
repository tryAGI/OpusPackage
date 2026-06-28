import OpusShims
import XCTest
@testable import OpusKit

/// Test Forward Error Correction (FEC) functionality
/// Simulates real network packet loss and validates FEC reconstruction
final class OpusFECTests: XCTestCase {
    // MARK: - Test Data Generation

    /// Generate test audio signal (sine wave)
    private func generateTestAudio(
        sampleRate: Opus.SampleRate,
        channels: Opus.Channels,
        durationMs: Int,
        frequency: Float = 440.0 // A4 note
    ) -> [opus_int16] {
        let samplesPerMs = Int(sampleRate.rawValue) / 1000
        let totalSamples = samplesPerMs * durationMs * Int(channels.rawValue)

        var samples: [opus_int16] = []
        samples.reserveCapacity(totalSamples)

        for i in 0 ..< totalSamples {
            let t = Float(i) / Float(sampleRate.rawValue * Int32(channels.rawValue))
            let amplitude: Float = 16000.0 // ~50% of Int16 range
            let sample = amplitude * sin(2.0 * .pi * frequency * t)
            samples.append(opus_int16(sample))
        }

        return samples
    }

    // MARK: - FEC Tests

    func testFECBasicFunctionality() throws {
        // Create encoder with FEC enabled
        let config = Opus.Config(
            sampleRate: .hz16k,
            channels: .mono,
            application: .voip,
            complexity: 5,
            vbr: true,
            constrainedVBR: true,
            fec: true, // ✅ Enable FEC
            dtx: false,
            expectedLossPerc: 15,
            bitrate: 24000
        )

        let encoder = try Opus.Encoder(config)
        let decoder = try Opus.Decoder(sampleRate: .hz16k, channels: .mono)

        // Generate test audio (40ms = 2 frames of 20ms each)
        let testAudio = generateTestAudio(sampleRate: .hz16k, channels: .mono, durationMs: 40)

        // Split into two 20ms frames
        let frameSize = 320 // 16kHz * 0.02s = 320 samples
        let frame1 = Array(testAudio[0 ..< frameSize])
        let frame2 = Array(testAudio[frameSize ..< (frameSize * 2)])

        // Encode both frames
        let packet1 = try frame1.withUnsafeBufferPointer { buffer in
            guard let ptr = buffer.baseAddress else { throw Opus.Error.badArgument }
            return try encoder.encode(pcm: ptr, frameSize: Int32(frameSize))
        }

        let packet2 = try frame2.withUnsafeBufferPointer { buffer in
            guard let ptr = buffer.baseAddress else { throw Opus.Error.badArgument }
            return try encoder.encode(pcm: ptr, frameSize: Int32(frameSize))
        }

        print("✅ Encoded 2 frames: \(packet1.count) + \(packet2.count) bytes")

        // Test 1: Normal decode (no packet loss)
        let decoded1Normal = try decoder.decodePCM16(data: packet1)
        let decoded2Normal = try decoder.decodePCM16(data: packet2)

        XCTAssertEqual(decoded1Normal.count, frameSize, "Frame 1 should decode to \(frameSize) samples")
        XCTAssertEqual(decoded2Normal.count, frameSize, "Frame 2 should decode to \(frameSize) samples")

        // Reset decoder for FEC test
        try decoder.reset()

        // Test 2: Simulate packet loss + FEC recovery
        // Scenario: packet1 is lost, packet2 arrives
        print("🔧 Simulating packet loss: frame 1 lost, frame 2 received")

        // Step 1: Try to recover lost frame1 using FEC from frame2
        let recoveredFrame1 = try decoder.decodePCM16(data: packet2, fec: true)

        // Step 2: Decode frame2 normally
        let decodedFrame2 = try decoder.decodePCM16(data: packet2, fec: false)

        print("✅ FEC recovery: frame1=\(recoveredFrame1.count) samples, frame2=\(decodedFrame2.count) samples")

        // Validate FEC reconstruction
        XCTAssertEqual(recoveredFrame1.count, frameSize, "FEC should recover \(frameSize) samples for lost frame")
        XCTAssertEqual(decodedFrame2.count, frameSize, "Normal decode should produce \(frameSize) samples")

        // Quality check: FEC should produce reasonable audio (not silence)
        let recoveredRMS = calculateRMS(recoveredFrame1)
        let originalRMS = calculateRMS(decoded1Normal)

        // FEC recovered audio should have some energy (not complete silence)
        XCTAssertGreaterThan(recoveredRMS, originalRMS * 0.1, "FEC audio should have reasonable energy")

        print("📊 Quality comparison:")
        print("   - Original RMS: \(String(format: "%.2f", originalRMS))")
        print("   - FEC recovered RMS: \(String(format: "%.2f", recoveredRMS))")
        print("   - Recovery ratio: \(String(format: "%.1f", recoveredRMS / originalRMS * 100))%")
    }

    func testPacketLossSequence() throws {
        // Test realistic packet loss patterns
        let encoder = try Opus.Encoder.voice(sampleRate: .hz16k, channels: .mono)
        let decoder = try Opus.Decoder.voice(sampleRate: .hz16k, channels: .mono)

        // Configure encoder for high packet loss environment
        try encoder.set(inbandFEC: true)
        try encoder.set(packetLossPercent: 20) // 20% expected loss

        // Generate longer test sequence (200ms = 10 frames)
        let testAudio = generateTestAudio(sampleRate: .hz16k, channels: .mono, durationMs: 200)
        let frameSize = 320 // 20ms at 16kHz
        let frameCount = testAudio.count / frameSize

        // Encode all frames
        var packets: [Data] = []
        for i in 0 ..< frameCount {
            let start = i * frameSize
            let end = min(start + frameSize, testAudio.count)
            let frame = Array(testAudio[start ..< end])

            let packet = try frame.withUnsafeBufferPointer { buffer in
                guard let ptr = buffer.baseAddress else { throw Opus.Error.badArgument }
                return try encoder.encode(pcm: ptr, frameSize: Int32(frame.count))
            }
            packets.append(packet)
        }

        // Simulate packet loss pattern: lose every 3rd packet
        let lossPattern = [false, false, true, false, false, true, false, false, true, false] // 30% loss

        var decodedAudio: [opus_int16] = []
        var lossCount = 0
        var recoveryCount = 0

        for (i, isLost) in lossPattern.enumerated() {
            if i >= packets.count { break }

            if isLost {
                lossCount += 1
                print("📦 Packet \(i) lost")

                // Try FEC recovery from next packet (if available)
                if i + 1 < packets.count {
                    let recoveredFrame = try decoder.decodePCM16(data: packets[i + 1], fec: true)
                    decodedAudio.append(contentsOf: recoveredFrame)
                    recoveryCount += 1
                    print("🔧 Recovered packet \(i) using FEC from packet \(i + 1)")
                } else {
                    // No next packet - use PLC (Packet Loss Concealment)
                    let concealedFrame = try decoder.concealPCM16()
                    decodedAudio.append(contentsOf: concealedFrame)
                    print("🔧 Used PLC for packet \(i)")
                }
            } else {
                // Normal decode
                let decodedFrame = try decoder.decodePCM16(data: packets[i])
                decodedAudio.append(contentsOf: decodedFrame)
                print("✅ Packet \(i) decoded normally")
            }
        }

        print("\n📊 Packet Loss Simulation Results:")
        print("   - Total packets: \(min(lossPattern.count, packets.count))")
        print("   - Lost packets: \(lossCount)")
        print("   - FEC recoveries: \(recoveryCount)")
        print("   - Total decoded samples: \(decodedAudio.count)")

        // Validate results
        XCTAssertGreaterThan(recoveryCount, 0, "Should successfully recover some packets using FEC")
        XCTAssertGreaterThan(decodedAudio.count, frameSize * 5, "Should decode substantial amount of audio")

        // Check audio quality
        let finalRMS = calculateRMS(decodedAudio)
        XCTAssertGreaterThan(finalRMS, 0.1, "Decoded audio should have reasonable energy despite packet loss")
    }

    func testBurstPacketLoss() throws {
        // Test FEC performance with burst losses (more realistic for mobile networks)
        let encoder = try Opus.Encoder.voice()
        let decoder = try Opus.Decoder.voice()

        try encoder.set(inbandFEC: true)
        try encoder.set(packetLossPercent: 10)

        // Generate test audio
        let testAudio = generateTestAudio(sampleRate: .hz16k, channels: .mono, durationMs: 160) // 8 frames
        let frameSize = 320
        let frameCount = 8

        // Encode frames
        var packets: [Data] = []
        for i in 0 ..< frameCount {
            let start = i * frameSize
            let frame = Array(testAudio[start ..< (start + frameSize)])

            let packet = try frame.withUnsafeBufferPointer { buffer in
                guard let ptr = buffer.baseAddress else { throw Opus.Error.badArgument }
                return try encoder.encode(pcm: ptr, frameSize: Int32(frameSize))
            }
            packets.append(packet)
        }

        // Simulate burst loss: packets 2,3,4 are lost (3 consecutive packets)
        let burstLossPattern = [false, false, true, true, true, false, false, false]

        var decodedFrames: [[opus_int16]] = []

        for (i, isLost) in burstLossPattern.enumerated() {
            if isLost {
                print("📦 Burst loss: packet \(i)")

                // For burst losses, try FEC from first available packet after burst
                if i == 4 { // Last packet in burst - try recovery from packet 5
                    let recoveredFrame = try decoder.decodePCM16(data: packets[5], fec: true)
                    decodedFrames.append(recoveredFrame)
                    print("🔧 Recovered burst-lost packet \(i) using FEC")
                } else {
                    // Use PLC for other packets in burst
                    let concealedFrame = try decoder.concealPCM16()
                    decodedFrames.append(concealedFrame)
                    print("🔧 Used PLC for burst-lost packet \(i)")
                }
            } else {
                // Normal decode
                let decodedFrame = try decoder.decodePCM16(data: packets[i])
                decodedFrames.append(decodedFrame)
            }
        }

        // Validate burst loss handling
        XCTAssertEqual(decodedFrames.count, frameCount, "Should handle all frames despite burst loss")

        let totalSamples = decodedFrames.reduce(0) { $0 + $1.count }
        XCTAssertEqual(totalSamples, frameCount * frameSize, "Should maintain consistent frame sizes")

        print("✅ Burst loss test completed: \(frameCount) frames, \(totalSamples) total samples")
    }

    // MARK: - Helper Methods

    private func calculateRMS(_ samples: [opus_int16]) -> Float {
        guard !samples.isEmpty else { return 0 }

        let sumSquares = samples.reduce(0.0) { sum, sample in
            let normalized = Float(sample) / Float(Int16.max)
            return sum + Double(normalized * normalized)
        }

        return Float(sqrt(sumSquares / Double(samples.count)))
    }
}
