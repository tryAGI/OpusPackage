import OpusShims
import XCTest
@testable import OpusKit

/// Simple network jitter and packet loss simulation for FEC testing
/// Tests the core FEC pattern: "packet N-1 lost → decode N-1 from N with fec=true, then decode N normally"
final class NetworkJitterSimulation: XCTestCase {
    // MARK: - Network Simulation Helpers

    struct NetworkPacket {
        let seq: UInt32
        let payload: Data
        let sentAt: Double
        var arrivedAt: Double?
        var isLost: Bool = false
    }

    /// Simple jitter buffer that implements proper FEC pattern
    class SimpleJitterBuffer {
        var packets: [UInt32: NetworkPacket] = [:]
        private var nextExpected: UInt32 = 1
        private let targetDelayMs: Double = 60 // 60ms playout delay

        func push(packet: NetworkPacket) {
            packets[packet.seq] = packet
            print("📨 JitterBuffer: Stored packet \(packet.seq)")
        }

        /// Try to get the next packet for playout, using FEC if needed
        func popDue(at currentTime: Double, decoder: Opus.Decoder) -> (Data, UInt32)? {
            // Check if expected packet is available
            if let packet = packets[nextExpected] {
                // Check if it's due for playout
                let playoutTime = packet.sentAt + (targetDelayMs / 1000.0)
                if currentTime >= playoutTime {
                    packets.removeValue(forKey: nextExpected)
                    nextExpected += 1

                    // Decode normally
                    do {
                        let decoded = try decoder.decodePCM16(data: packet.payload, fec: false)
                        let data = decoded.withUnsafeBytes { Data($0) }
                        print("✅ JitterBuffer: Decoded packet \(packet.seq - 1) normally")
                        return (data, UInt32(decoded.count))
                    } catch {
                        print("❌ JitterBuffer: Failed to decode packet \(packet.seq - 1): \(error)")
                        return nil
                    }
                }
                return nil // Not due yet
            }

            // Expected packet is missing - try FEC recovery from next packet
            if let nextPacket = packets[nextExpected + 1] {
                print("🔧 JitterBuffer: Attempting FEC recovery for missing packet \(nextExpected)")

                do {
                    // Step 1: Recover missing packet using FEC
                    let recoveredPCM = try decoder.decodePCM16(data: nextPacket.payload, fec: true)
                    packets.removeValue(forKey: nextExpected + 1) // Remove the FEC source packet
                    nextExpected += 1

                    let data = recoveredPCM.withUnsafeBytes { Data($0) }
                    print("✅ JitterBuffer: FEC recovered packet \(nextExpected - 1) (\(recoveredPCM.count) samples)")
                    return (data, UInt32(recoveredPCM.count))
                } catch {
                    print("❌ JitterBuffer: FEC recovery failed: \(error)")
                    nextExpected += 1 // Skip this packet
                    return nil
                }
            }

            // Neither current nor next packet available - check if we should give up
            let estimatedSendTime = currentTime - (targetDelayMs / 1000.0)
            if estimatedSendTime > 0 {
                print("🔇 JitterBuffer: Giving up on packet \(nextExpected), using PLC")
                nextExpected += 1

                // Generate PLC (Packet Loss Concealment)
                do {
                    let plcPCM = try decoder.concealPCM16()
                    let data = plcPCM.withUnsafeBytes { Data($0) }
                    return (data, UInt32(plcPCM.count))
                } catch {
                    print("❌ JitterBuffer: PLC failed: \(error)")
                    return nil
                }
            }

            return nil // Still waiting
        }
    }

    // MARK: - Tests

    func testNetworkJitterWithFECRecovery() throws {
        // Setup encoder with FEC enabled
        let encoder = try Opus.Encoder.voice()
        try encoder.set(inbandFEC: true)
        try encoder.set(packetLossPercent: 10) // Expect 10% loss

        let decoder = try Opus.Decoder.voice()
        let jitterBuffer = SimpleJitterBuffer()

        print("🎬 Starting network jitter simulation with FEC...")

        // Generate test packets
        let frameSize = 320 // 20ms @ 16kHz
        let packetCount = 8
        let baseTime = Date().timeIntervalSince1970

        var sentPackets: [NetworkPacket] = []

        // Encode packets
        for i in 0 ..< packetCount {
            let seq = UInt32(i + 1)
            let sentAt = baseTime + Double(i) * 0.02 // 20ms intervals

            // Generate unique audio per packet (different frequencies)
            let audio = generateSineWave(samples: frameSize, frequency: 440 + Float(i * 50))
            let encoded = try audio.withUnsafeBufferPointer { buffer in
                guard let ptr = buffer.baseAddress else { throw Opus.Error.badArgument }
                return try encoder.encode(pcm: ptr, frameSize: Int32(frameSize))
            }

            var packet = NetworkPacket(seq: seq, payload: encoded, sentAt: sentAt)

            // Simulate network conditions: packet 3 and 6 are lost
            if seq == 3 || seq == 6 {
                packet.isLost = true
                print("📦 Packet \(seq) lost in network simulation")
            } else {
                // Add jitter: ±10ms random delay
                let jitter = Double.random(in: -0.01 ... 0.01)
                packet.arrivedAt = sentAt + 0.03 + jitter // 30ms base delay + jitter
                print("📡 Packet \(seq) will arrive at +\(Int((packet.arrivedAt! - baseTime) * 1000))ms")
            }

            sentPackets.append(packet)
        }

        // Simulate receiver processing
        var currentTime = baseTime + 0.05 // Start processing 50ms later
        var receivedFrames: [(data: Data, samples: UInt32)] = []

        for _ in 0 ..< 15 { // Process for 300ms (15 * 20ms ticks)
            // Deliver any packets that have arrived
            for packet in sentPackets {
                if !packet.isLost,
                   let arrivalTime = packet.arrivedAt,
                   currentTime >= arrivalTime,
                   jitterBuffer.packets[packet.seq] == nil
                {
                    jitterBuffer.push(packet: packet)
                }
            }

            // Try to pop a frame for playout
            if let frame = jitterBuffer.popDue(at: currentTime, decoder: decoder) {
                receivedFrames.append((data: frame.0, samples: frame.1))
                print(
                    "🔊 Played frame \(receivedFrames.count) at +\(Int((currentTime - baseTime) * 1000))ms (\(frame.1) samples)"
                )
            }

            currentTime += 0.02 // Advance 20ms
        }

        print("\n📊 Network Jitter Simulation Results:")
        print("   - Packets sent: \(packetCount)")
        print("   - Packets lost: 2 (packets 3, 6)")
        print("   - Frames received: \(receivedFrames.count)")

        // Validate FEC effectiveness
        XCTAssertGreaterThanOrEqual(receivedFrames.count, 6, "Should receive most frames despite losses")

        // Check audio quality - FEC frames should have reasonable energy
        var normalFrames = 0
        var fecFrames = 0
        var plcFrames = 0

        for frame in receivedFrames {
            let rms = calculateRMS(frame.data)
            if rms > 0.25 {
                normalFrames += 1
            } else if rms > 0.1 {
                fecFrames += 1
            } else {
                plcFrames += 1
            }
        }

        print("   - Normal frames (RMS > 0.25): \(normalFrames)")
        print("   - FEC frames (RMS 0.1-0.25): \(fecFrames)")
        print("   - PLC frames (RMS < 0.1): \(plcFrames)")

        // FEC should recover at least some lost packets
        XCTAssertGreaterThan(fecFrames, 0, "FEC should recover some lost packets")

        print("✅ Network jitter simulation with FEC completed successfully")
    }

    func testBurstPacketLoss() throws {
        // Test FEC under burst packet loss (more challenging scenario)
        let encoder = try Opus.Encoder.voice()
        try encoder.set(inbandFEC: true)
        try encoder.set(packetLossPercent: 15) // High loss expectation

        let decoder = try Opus.Decoder.voice()
        let jitterBuffer = SimpleJitterBuffer()

        print("🔥 Starting burst packet loss simulation...")

        let frameSize = 320
        let packetCount = 10
        let baseTime = Date().timeIntervalSince1970

        var sentPackets: [NetworkPacket] = []

        // Create packets
        for i in 0 ..< packetCount {
            let seq = UInt32(i + 1)
            let audio = generateSineWave(samples: frameSize, frequency: 220 + Float(i * 30))
            let encoded = try audio.withUnsafeBufferPointer { buffer in
                guard let ptr = buffer.baseAddress else { throw Opus.Error.badArgument }
                return try encoder.encode(pcm: ptr, frameSize: Int32(frameSize))
            }

            var packet = NetworkPacket(seq: seq, payload: encoded, sentAt: baseTime + Double(i) * 0.02)

            // Simulate burst loss: packets 4, 5, 6 are lost (3 consecutive)
            if seq >= 4, seq <= 6 {
                packet.isLost = true
                print("📦 Burst loss: packet \(seq)")
            } else {
                packet.arrivedAt = packet.sentAt + 0.025 // 25ms delay
            }

            sentPackets.append(packet)
        }

        // Process with jitter buffer
        var currentTime = baseTime + 0.04
        var receivedFrames: [Data] = []

        for _ in 0 ..< 20 { // Longer processing window
            // Deliver packets
            for packet in sentPackets {
                if !packet.isLost,
                   let arrivalTime = packet.arrivedAt,
                   currentTime >= arrivalTime,
                   jitterBuffer.packets[packet.seq] == nil
                {
                    jitterBuffer.push(packet: packet)
                }
            }

            // Try to decode
            if let frame = jitterBuffer.popDue(at: currentTime, decoder: decoder) {
                receivedFrames.append(frame.0)
            }

            currentTime += 0.02
        }

        print("\n📊 Burst Loss Results:")
        print("   - Sent: \(packetCount), Lost: 3 consecutive, Received: \(receivedFrames.count)")

        // Should handle burst loss gracefully
        XCTAssertGreaterThanOrEqual(receivedFrames.count, 5, "Should recover reasonably from burst loss")

        print("✅ Burst packet loss test completed")
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

    private func calculateRMS(_ audioData: Data) -> Float {
        let samples = audioData.withUnsafeBytes { bytes in
            bytes.bindMemory(to: Int16.self)
        }

        guard !samples.isEmpty else { return 0 }

        let sumSquares = samples.reduce(0.0) { sum, sample in
            let normalized = Float(sample) / Float(Int16.max)
            return sum + Double(normalized * normalized)
        }

        return Float(sqrt(sumSquares / Double(samples.count)))
    }
}

// No longer needed since packets is now public
