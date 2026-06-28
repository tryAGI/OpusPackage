import Opus
import OpusShims
import XCTest

@testable import OpusKit

final class OpusPackageTests: XCTestCase {
    // MARK: - Namespace and Memory Tests

    /// Validate that Opus namespace contains expected types
    func testNamespaceTypes() {
        // Test that the Opus namespace types are accessible
        let _: Opus.SampleRate.Type = Opus.SampleRate.self
        let _: Opus.Channels.Type = Opus.Channels.self
        let _: Opus.Application.Type = Opus.Application.self
        let _: Opus.FrameDuration.Type = Opus.FrameDuration.self
    }

    func testMemorySizes() {
        let encMono = opus_encoder_get_size(1)
        let encStereo = opus_encoder_get_size(2)
        let decMono = opus_decoder_get_size(1)
        let decStereo = opus_decoder_get_size(2)

        // Basic sanity
        XCTAssertGreaterThan(encMono, 0)
        XCTAssertGreaterThan(encStereo, encMono) // stereo > mono
        XCTAssertGreaterThan(decMono, 0)
        XCTAssertGreaterThan(decStereo, decMono)

        // Reasonable upper bound (room for config/versions)
        let maxBytes: Int32 = 1 << 18 // 256 KiB
        XCTAssertLessThan(encMono, maxBytes)
        XCTAssertLessThan(encStereo, maxBytes)
        XCTAssertLessThan(decMono, maxBytes)
        XCTAssertLessThan(decStereo, maxBytes)

        // Optional: alignment checks (Opus structs are word-aligned)
        XCTAssertEqual(encMono % 4, 0)
        XCTAssertEqual(encStereo % 4, 0)
        XCTAssertEqual(decMono % 4, 0)
        XCTAssertEqual(decStereo % 4, 0)

        // Optional: delta sanity with wide guard (keeps noisy regressions out)
        XCTAssertLessThan(encStereo - encMono, 32 << 10) // < 32 KiB
        XCTAssertLessThan(decStereo - decMono, 32 << 10)
    }

    // MARK: - Low-Level C API Tests

    func testLowLevelRoundtrip16kMono20ms() throws {
        // Prepare encoder/decoder
        var err: Int32 = 0
        let sr: Int32 = 16000
        let ch: Int32 = 1
        let frameSize: Int32 = sr / 50 // 20ms = 320 samples at 16k

        guard let enc = opus_encoder_create(sr, ch, OPUS_APPLICATION_VOIP, &err), err == OPUS_OK else {
            XCTFail("opus_encoder_create failed \(err)")
            return
        }
        defer { opus_encoder_destroy(enc) }

        guard let dec = opus_decoder_create(sr, ch, &err), err == OPUS_OK else {
            XCTFail("opus_decoder_create failed \(err)")
            return
        }
        defer { opus_decoder_destroy(dec) }

        // Apply CTLs
        _ = opus_enc_set_complexity(enc, 10)
        _ = opus_enc_set_signal(enc, OPUS_SIGNAL_VOICE)
        _ = opus_enc_set_vbr(enc, 1)
        _ = opus_enc_set_vbr_constraint(enc, 1)
        _ = opus_enc_set_inband_fec(enc, 1)
        _ = opus_enc_set_dtx(enc, 1)
        _ = opus_enc_set_packet_loss_perc(enc, 10)
        _ = opus_enc_set_bitrate(enc, 24000)

        // Verify a couple of CTLs via GET
        var br: opus_int32 = 0
        XCTAssertEqual(opus_enc_get_bitrate(enc, &br), OPUS_OK)
        XCTAssertEqual(br, 24000)

        var vbr: Int32 = -1
        XCTAssertEqual(opus_enc_get_vbr(enc, &vbr), OPUS_OK)
        XCTAssertEqual(vbr, 1)

        // Generate 20ms 440 Hz sine wave (Int16 mono)
        var pcm = [opus_int16](repeating: 0, count: Int(frameSize))
        let amp: Double = 3000
        for i in 0 ..< Int(frameSize) {
            let t = Double(i) / Double(sr)
            pcm[i] = opus_int16(amp * sin(2.0 * .pi * 440.0 * t))
        }

        // Encode
        var packet = [UInt8](repeating: 0, count: 400) // plenty for 20ms voice
        let encBytes = packet.withUnsafeMutableBufferPointer { buf -> Int32 in
            guard let dst = buf.baseAddress else { return -1 }
            return pcm.withUnsafeBufferPointer { pcmBuf -> Int32 in
                guard let src = pcmBuf.baseAddress else { return -1 }
                return opus_encode(enc, src, frameSize, dst, Int32(buf.count))
            }
        }

        XCTAssertGreaterThan(encBytes, 0, "encode failed \(encBytes)")
        XCTAssertLessThan(encBytes, 400, "suspiciously large packet")

        // Decode
        var decoded = [opus_int16](repeating: 0, count: Int(frameSize * ch))
        let decSamples = decoded.withUnsafeMutableBufferPointer { outBuf -> Int32 in
            guard let outPtr = outBuf.baseAddress else { return -1 }
            return packet.withUnsafeBufferPointer { pktBuf -> Int32 in
                // pktBuf.baseAddress may be nil only if count == 0; here encBytes > 0, so it’s non-nil
                let pktPtr = pktBuf.baseAddress
                return opus_decode(dec, pktPtr, encBytes, outPtr, frameSize, 0)
            }
        }
        XCTAssertEqual(decSamples, frameSize, "unexpected decoded samples")
    }

    func testOpusKitConvenience() throws {
        // Simple smoke test for unified Opus.Encoder
        let encoder = try Opus.Encoder.voice(sampleRate: .hz16k, channels: .mono)
        var pcm = [opus_int16](repeating: 0, count: 320)
        let data = try encoder.encodePCM16Array(&pcm, sampleRate: .hz16k, duration: .ms20)
        XCTAssertGreaterThan(data.count, 0)
    }
}
