import AVFoundation
import OpusShims
import XCTest

@testable import OpusKit

@MainActor
final class UltraLowBandwidthTests: XCTestCase {
    func testUltraLowBandwidthConfiguration() throws {
        // Test the ultra-low bandwidth encoder configuration
        let encoder = try Opus.Encoder.ultraLowBandwidth(
            sampleRate: .hz16k,
            channels: .mono,
            bitrate: 6000,
            enableFEC: true
        )

        XCTAssertNotNil(encoder, "Ultra-low bandwidth encoder should be created")
    }

    func testDataUsageCalculation() throws {
        // Test various bitrates and calculate expected data usage
        let bitrates: [Int32] = [6000, 8000, 10000]

        for bitrate in bitrates {
            let encoder = try Opus.Encoder.ultraLowBandwidth(
                sampleRate: .hz16k,
                channels: .mono,
                bitrate: bitrate,
                enableFEC: false // Test without FEC for minimum usage
            )

            // Generate test audio (1 second of 440 Hz tone)
            let sampleRate = 16000
            let duration = 1.0 // 1 second
            let frameCount = Int(Double(sampleRate) * duration)
            var pcm = [opus_int16](repeating: 0, count: frameCount)

            // Generate sine wave
            for i in 0 ..< frameCount {
                let t = Double(i) / Double(sampleRate)
                pcm[i] = opus_int16(3000.0 * sin(2.0 * .pi * 440.0 * t))
            }

            // Encode in 60ms chunks (ultra-low BW uses longer frames)
            let frameSize = sampleRate * 60 / 1000 // 60ms at 16kHz = 960 samples
            var totalEncodedBytes = 0
            var chunks = 0

            for chunkStart in stride(from: 0, to: frameCount, by: frameSize) {
                let chunkEnd = min(chunkStart + frameSize, frameCount)
                let chunkSize = chunkEnd - chunkStart

                if chunkSize < frameSize { break } // Skip incomplete final chunk

                var chunkPCM = Array(pcm[chunkStart ..< chunkEnd])
                let encodedData = try encoder.encodePCM16Array(
                    &chunkPCM,
                    sampleRate: .hz16k,
                    duration: .ms60
                )

                totalEncodedBytes += encodedData.count
                chunks += 1
            }

            // Calculate actual vs theoretical data usage
            let actualBitsPerSecond = Double(totalEncodedBytes * 8) / (Double(chunks) * 0.06) // 60ms chunks
            let theoreticalBps = Double(bitrate)
            let compressionRatio = theoreticalBps / actualBitsPerSecond

            print("📊 Bitrate \(bitrate) bps test:")
            print("   - Encoded \(chunks) chunks (\(chunks * 60)ms total)")
            print("   - Total bytes: \(totalEncodedBytes)")
            print("   - Actual rate: \(String(format: "%.0f", actualBitsPerSecond)) bps")
            print("   - Theoretical: \(bitrate) bps")
            print("   - Efficiency: \(String(format: "%.1f", compressionRatio))x")

            // Verify the encoded data is reasonable
            XCTAssertGreaterThan(totalEncodedBytes, 0, "Should have encoded some data")
            XCTAssertLessThan(
                actualBitsPerSecond,
                Double(bitrate) * 2.0,
                "Actual rate should be reasonably close to target"
            )
        }
    }

    func testSilenceSuppressionWithDTX() throws {
        // Test that DTX (silence suppression) significantly reduces data for silent audio
        let encoder = try Opus.Encoder.ultraLowBandwidth(
            sampleRate: .hz16k,
            channels: .mono,
            bitrate: 6000,
            enableFEC: false
        )

        let sampleRate = 16000
        let frameSize = sampleRate * 60 / 1000 // 60ms

        // Test 1: Encode silence
        var silentPCM = [opus_int16](repeating: 0, count: frameSize)
        let silentData = try encoder.encodePCM16Array(&silentPCM, sampleRate: .hz16k, duration: .ms60)

        // Test 2: Encode tone
        var tonePCM = [opus_int16](repeating: 0, count: frameSize)
        for i in 0 ..< frameSize {
            let t = Double(i) / Double(sampleRate)
            tonePCM[i] = opus_int16(3000.0 * sin(2.0 * .pi * 440.0 * t))
        }
        let toneData = try encoder.encodePCM16Array(&tonePCM, sampleRate: .hz16k, duration: .ms60)

        print("🔇 DTX Silence Suppression Test:")
        print("   - Silent frame: \(silentData.count) bytes")
        print("   - Tone frame: \(toneData.count) bytes")
        print(
            "   - DTX savings: \(String(format: "%.1f", Double(toneData.count - silentData.count) / Double(toneData.count) * 100))%"
        )

        // DTX should make silent frames much smaller
        XCTAssertLessThan(silentData.count, toneData.count, "Silent frames should be smaller with DTX")
        XCTAssertGreaterThan(
            Double(toneData.count) / Double(silentData.count),
            1.5,
            "DTX should provide significant savings"
        )
    }
}
