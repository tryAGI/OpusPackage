import AVFoundation
import OpusShims

public extension Opus {
    /// Production-ready Opus encoder with comprehensive configuration support
    final class Encoder {
        private let encoder: OpaquePointer
        public let config: Config
        public let format: AVAudioFormat?

        // MARK: - Initialization

        /// Initialize encoder with typed configuration
        public init(_ config: Config) throws {
            self.config = config
            format = nil

            var err: Int32 = 0
            guard
                let enc = opus_encoder_create(
                    config.sampleRate.rawValue,
                    config.channels.rawValue,
                    config.application.cValue,
                    &err
                ), err == OPUS_OK
            else {
                throw Opus.Error.initError(
                    err,
                    context: "creating encoder with sample rate: \(config.sampleRate.rawValue)Hz, channels: \(config.channels.rawValue)"
                )
            }

            encoder = enc
            try applyConfiguration(config)
        }

        /// Initialize encoder with AVAudioFormat and application type
        public init(format: AVAudioFormat, application: Application = .audio) throws {
            guard format.isValidOpusPCMFormat else {
                throw Opus.Error.badArgument
            }

            guard let sampleRate = SampleRate(hz: format.sampleRate),
                  let channels = Channels(avCount: format.channelCount)
            else {
                throw Opus.Error.badArgument
            }

            // Create default config from format
            config = Config(
                sampleRate: sampleRate,
                channels: channels,
                application: application
            )
            self.format = format

            var err: Int32 = 0
            guard
                let enc = opus_encoder_create(
                    Int32(format.sampleRate),
                    Int32(format.channelCount),
                    application.cValue,
                    &err
                ), err == OPUS_OK
            else {
                throw Opus.Error.initError(
                    err,
                    context: "creating encoder with sample rate: \(config.sampleRate.rawValue)Hz, channels: \(config.channels.rawValue)"
                )
            }

            encoder = enc
            try applyConfiguration(config)
        }

        deinit {
            opus_encoder_destroy(encoder)
        }

        // MARK: - Configuration

        private func applyConfiguration(_ config: Config) throws {
            // Apply all configuration settings with proper error checking
            guard opus_enc_set_complexity(encoder, config.complexity) == OPUS_OK,
                  opus_enc_set_vbr(encoder, config.vbr ? 1 : 0) == OPUS_OK,
                  opus_enc_set_vbr_constraint(encoder, config.constrainedVBR ? 1 : 0) == OPUS_OK,
                  opus_enc_set_inband_fec(encoder, config.fec ? 1 : 0) == OPUS_OK,
                  opus_enc_set_dtx(encoder, config.dtx ? 1 : 0) == OPUS_OK,
                  opus_enc_set_packet_loss_perc(encoder, config.expectedLossPerc) == OPUS_OK,
                  opus_enc_set_bitrate(encoder, config.bitrate) == OPUS_OK
            else {
                throw Opus.Error.configError(-1, context: "failed to apply encoder configuration")
            }
        }

        /// Reset encoder state
        public func reset() throws {
            let error = opus_encoder_init(
                encoder,
                config.sampleRate.rawValue,
                config.channels.rawValue,
                config.application.cValue
            )
            guard error == OPUS_OK else {
                throw Error(error)
            }
            try applyConfiguration(config)
        }

        // MARK: - Advanced Configuration Methods

        /// Set maximum bandwidth
        public func set(maxBandwidth: Bandwidth) throws {
            let result = opus_enc_set_max_bandwidth(encoder, maxBandwidth.cValue)
            guard result == OPUS_OK else {
                throw Opus.Error.configError(result, context: "setting max bandwidth to \(maxBandwidth)")
            }
        }

        /// Set bandwidth
        public func set(bandwidth: Bandwidth) throws {
            let result = opus_enc_set_bandwidth(encoder, bandwidth.cValue)
            guard result == OPUS_OK else {
                throw Opus.Error.configError(result, context: "setting bandwidth to \(bandwidth)")
            }
        }

        /// Set signal type
        public func set(signal: Signal) throws {
            let result = opus_enc_set_signal(encoder, signal.cValue)
            guard result == OPUS_OK else {
                throw Opus.Error.configError(result, context: "setting signal type to \(signal)")
            }
        }

        /// Set bitrate
        public func set(bitrate: Int32) throws {
            let result = opus_enc_set_bitrate(encoder, bitrate)
            guard result == OPUS_OK else {
                throw Opus.Error.configError(result, context: "setting bitrate to \(bitrate)")
            }
        }

        /// Set VBR mode
        public func set(vbr: Bool, constrained: Bool = false) throws {
            let vbrResult = opus_enc_set_vbr(encoder, vbr ? 1 : 0)
            let constrainedResult = opus_enc_set_vbr_constraint(encoder, constrained ? 1 : 0)

            guard vbrResult == OPUS_OK, constrainedResult == OPUS_OK else {
                throw Opus.Error.configError(-1, context: "setting VBR mode to \(vbr), constrained: \(constrained)")
            }
        }

        /// Set DTX (discontinuous transmission)
        public func set(dtx: Bool) throws {
            let result = opus_enc_set_dtx(encoder, dtx ? 1 : 0)
            guard result == OPUS_OK else {
                throw Opus.Error.configError(result, context: "setting DTX to \(dtx)")
            }
        }

        /// Set complexity (0-10)
        public func set(complexity: Int32) throws {
            let result = opus_enc_set_complexity(encoder, complexity)
            guard result == OPUS_OK else {
                throw Opus.Error.configError(result, context: "setting complexity to \(complexity)")
            }
        }

        /// Set inband FEC
        public func set(inbandFEC: Bool) throws {
            let result = opus_enc_set_inband_fec(encoder, inbandFEC ? 1 : 0)
            guard result == OPUS_OK else {
                throw Opus.Error.configError(result, context: "setting inband FEC to \(inbandFEC)")
            }
        }

        /// Set expected packet loss percentage
        public func set(packetLossPercent: Int32) throws {
            let result = opus_enc_set_packet_loss_perc(encoder, packetLossPercent)
            guard result == OPUS_OK else {
                throw Opus.Error.configError(result, context: "setting packet loss percentage to \(packetLossPercent)")
            }
        }

        // MARK: - AVAudioPCMBuffer Encoding (High-level API)

        /// Encode AVAudioPCMBuffer to Data
        public func encode(_ input: AVAudioPCMBuffer) throws -> Data {
            var data = Data(count: 1500) // Reasonable default size
            let bytesEncoded = try encode(input, to: &data)
            data.count = bytesEncoded
            return data
        }

        /// Encode AVAudioPCMBuffer to existing Data buffer
        public func encode(_ input: AVAudioPCMBuffer, to output: inout Data) throws -> Int {
            try output.withUnsafeMutableBytes { bytes in
                try encode(input, to: bytes)
            }
        }

        /// Encode AVAudioPCMBuffer to UnsafeMutableRawBufferPointer
        public func encode(_ input: AVAudioPCMBuffer, to output: UnsafeMutableRawBufferPointer) throws -> Int {
            let outputBuffer = UnsafeMutableBufferPointer(
                start: output.baseAddress?.bindMemory(to: UInt8.self, capacity: output.count),
                count: output.count
            )
            return try encode(input, to: outputBuffer)
        }

        /// Encode AVAudioPCMBuffer to UInt8 buffer
        public func encode(_ input: AVAudioPCMBuffer, to output: UnsafeMutableBufferPointer<UInt8>) throws -> Int {
            // Validate format compatibility if we have a stored format
            if let expectedFormat = format {
                guard input.format.sampleRate == expectedFormat.sampleRate,
                      input.format.channelCount == expectedFormat.channelCount
                else {
                    throw Opus.Error.badArgument
                }
            }

            switch input.format.commonFormat {
            case .pcmFormatInt16:
                let inputData = UnsafeBufferPointer(
                    start: input.int16ChannelData![0],
                    count: Int(input.frameLength * input.format.channelCount)
                )
                return try encode(inputData, to: output)
            case .pcmFormatFloat32:
                let inputData = UnsafeBufferPointer(
                    start: input.floatChannelData![0],
                    count: Int(input.frameLength * input.format.channelCount)
                )
                return try encode(inputData, to: output)
            default:
                throw Opus.Error.badArgument
            }
        }

        // MARK: - Raw PCM Encoding (Low-level API)

        /// Encode Int16 PCM with frame duration
        public func encodePCM16(
            _ pcm: UnsafePointer<opus_int16>,
            sampleRate: SampleRate,
            duration: FrameDuration = .ms20,
            maxPacketBytes: Int32 = 400
        ) throws -> Data {
            let frameSize = sampleRate.frameSize(duration)
            var packet = [UInt8](repeating: 0, count: Int(maxPacketBytes))

            let bytesEncoded = try packet.withUnsafeMutableBufferPointer { buffer in
                guard let dst = buffer.baseAddress else { throw Opus.Error.badArgument }
                let result = opus_encode(encoder, pcm, frameSize, dst, maxPacketBytes)
                guard result > 0 else { throw Opus.Error.encodingError(result, context: "PCM16 encoding failed") }
                return Int(result)
            }

            return Data(packet.prefix(bytesEncoded))
        }

        /// Encode Int16 PCM array
        public func encodePCM16Array(
            _ samples: inout [opus_int16],
            sampleRate: SampleRate,
            duration: FrameDuration = .ms20,
            maxPacketBytes: Int32 = 400
        ) throws -> Data {
            try samples.withUnsafeMutableBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { throw Opus.Error.badArgument }
                return try encodePCM16(
                    baseAddress,
                    sampleRate: sampleRate,
                    duration: duration,
                    maxPacketBytes: maxPacketBytes
                )
            }
        }

        /// Encode raw Int16 PCM to output buffer
        public func encode(
            pcm: UnsafePointer<opus_int16>,
            frameSize: Int32,
            maxPacketBytes: Int32 = 1500
        ) throws -> Data {
            precondition(maxPacketBytes > 0, "maxPacketBytes must be > 0")

            var packet = [UInt8](repeating: 0, count: Int(maxPacketBytes))
            let bytesEncoded = try packet.withUnsafeMutableBufferPointer { buffer in
                guard let dst = buffer.baseAddress else { throw Opus.Error.badArgument }
                let result = opus_encode(encoder, pcm, frameSize, dst, maxPacketBytes)
                guard result > 0 else { throw Opus.Error.encodingError(result, context: "PCM16 encoding failed") }
                return Int(result)
            }

            return Data(packet.prefix(bytesEncoded))
        }

        // MARK: - Private encoding methods

        private func encode(
            _ input: UnsafeBufferPointer<Int16>,
            to output: UnsafeMutableBufferPointer<UInt8>
        ) throws -> Int {
            guard let inputPtr = input.baseAddress, let outputPtr = output.baseAddress else {
                throw Opus.Error.badArgument
            }

            let frameCount = Int32(input.count) / config.channels.rawValue
            let encodedSize = opus_encode(encoder, inputPtr, frameCount, outputPtr, Int32(output.count))

            guard encodedSize > 0 else {
                throw Opus.Error.encodingError(encodedSize, context: "raw PCM encoding failed")
            }

            return Int(encodedSize)
        }

        private func encode(
            _ input: UnsafeBufferPointer<Float32>,
            to output: UnsafeMutableBufferPointer<UInt8>
        ) throws -> Int {
            guard let inputPtr = input.baseAddress, let outputPtr = output.baseAddress else {
                throw Opus.Error.badArgument
            }

            let frameCount = Int32(input.count) / config.channels.rawValue
            let encodedSize = opus_encode_float(encoder, inputPtr, frameCount, outputPtr, Int32(output.count))

            guard encodedSize > 0 else {
                throw Opus.Error.encodingError(encodedSize, context: "raw PCM encoding failed")
            }

            return Int(encodedSize)
        }
    }
}

// MARK: - Convenience Extensions

public extension Opus.Encoder {
    /// Create encoder with preset configuration
    static func voice(sampleRate: Opus.SampleRate = .hz16k, channels: Opus.Channels = .mono) throws -> Opus.Encoder {
        let config = Opus.Config(
            sampleRate: sampleRate,
            channels: channels,
            application: .voip,
            complexity: 10,
            vbr: true,
            constrainedVBR: true,
            fec: true,
            dtx: true,
            expectedLossPerc: 10,
            bitrate: 24000
        )
        return try Opus.Encoder(config)
    }

    /// Create encoder with music preset configuration
    static func music(sampleRate: Opus.SampleRate = .hz48k, channels: Opus.Channels = .stereo) throws -> Opus.Encoder {
        let config = Opus.Config(
            sampleRate: sampleRate,
            channels: channels,
            application: .audio,
            complexity: 9,
            vbr: true,
            constrainedVBR: false,
            fec: false,
            dtx: false,
            expectedLossPerc: 0,
            bitrate: 96000
        )
        return try Opus.Encoder(config)
    }

    /// Create encoder optimized for ultra-low bandwidth 24/7 speech transmission
    /// Perfect for: speech recognition, limited data plans, continuous transmission
    /// Data usage: ~6 kbps = 750 B/s = 2.7 MB/hr = 64.8 MB/day = ~1.94 GB/30d
    /// With DTX silence suppression, actual usage will be much lower
    static func ultraLowBandwidth(
        sampleRate: Opus.SampleRate = .hz16k,
        channels: Opus.Channels = .mono,
        bitrate: Int32 = 6000,
        enableFEC: Bool = true
    ) throws -> Opus.Encoder {
        // Start with basic VOIP config
        let config = Opus.Config(
            sampleRate: sampleRate,
            channels: channels,
            application: .voip,
            complexity: 2, // Low CPU/battery usage
            vbr: true,
            constrainedVBR: false, // Unconstrained VBR for maximum savings
            fec: enableFEC, // FEC for mobile reliability (costs ~5-15% more bits)
            dtx: true, // Silence suppression (huge savings)
            expectedLossPerc: enableFEC ? 5 : 0,
            bitrate: bitrate
        )

        let encoder = try Opus.Encoder(config)

        // Apply ultra-low bandwidth optimizations
        try encoder.set(bandwidth: .narrowband) // 4 kHz bandpass (8 kHz total)
        try encoder.set(signal: .voice) // Voice optimization

        print("🔧 Ultra-low bandwidth Opus encoder configured:")
        print("   - Sample rate: \(sampleRate) (capture) → Narrowband encoding")
        print("   - Channels: \(channels)")
        print("   - Target bitrate: \(bitrate) bps")
        print("   - VBR: unconstrained (adapts to content)")
        print("   - DTX: enabled (silence suppression)")
        print("   - FEC: \(enableFEC ? "enabled" : "disabled")")
        print("   - Complexity: 2 (battery optimized)")
        let expectedMBPerHour = Float(bitrate) / 8000.0 * 3.6
        print("   - Expected data: ~\(String(format: "%.1f", expectedMBPerHour)) MB/hr")

        return encoder
    }
}
