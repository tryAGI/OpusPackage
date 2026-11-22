import AVFoundation
import OpusShims

public extension Opus {
    /// Production-ready Opus decoder with comprehensive functionality
    final class Decoder {
        private let decoder: OpaquePointer
        public let sampleRate: SampleRate
        public let channels: Channels
        public let format: AVAudioFormat?

        // MARK: - Initialization

        /// Initialize decoder with typed sample rate and channels
        public init(sampleRate: SampleRate, channels: Channels) throws {
            self.sampleRate = sampleRate
            self.channels = channels
            format = nil

            var err: Int32 = 0
            guard let dec = opus_decoder_create(sampleRate.rawValue, channels.rawValue, &err),
                  err == OPUS_OK
            else {
                throw Error.initError(
                    err,
                    context: "sample rate: \(sampleRate.rawValue)Hz, channels: \(channels.rawValue)"
                )
            }

            decoder = dec
        }

        /// Initialize decoder with AVAudioFormat
        public init(format: AVAudioFormat, application _: Application = .audio) throws {
            guard format.isValidOpusPCMFormat else {
                throw Error.badArgument
            }

            guard let sampleRate = SampleRate(hz: format.sampleRate),
                  let channels = Channels(avCount: format.channelCount)
            else {
                throw Error.badArgument
            }

            self.sampleRate = sampleRate
            self.channels = channels
            self.format = format

            var err: Int32 = 0
            guard let dec = opus_decoder_create(Int32(format.sampleRate), Int32(format.channelCount), &err),
                  err == OPUS_OK
            else {
                throw Error.initError(
                    err,
                    context: "sample rate: \(format.sampleRate)Hz, channels: \(format.channelCount)"
                )
            }

            decoder = dec
        }

        deinit {
            opus_decoder_destroy(decoder)
        }

        /// Reset decoder state
        public func reset() throws {
            let error = opus_decoder_init(decoder, sampleRate.rawValue, channels.rawValue)
            guard error == OPUS_OK else {
                throw Error.initError(error, context: "decoder reset failed")
            }
        }

        // MARK: - High-level AVAudioPCMBuffer API

        /// Decode Data to AVAudioPCMBuffer (requires format to be set)
        public func decode(_ input: Data) throws -> AVAudioPCMBuffer {
            guard let format else {
                throw Error.badArgument
            }

            return try input.withUnsafeBytes { bytes in
                let input = bytes.bindMemory(to: UInt8.self)
                let sampleCount = opus_decoder_get_nb_samples(decoder, input.baseAddress!, Int32(bytes.count))
                if sampleCount < 0 {
                    throw Error.decodingError(
                        sampleCount,
                        context: "failed to get sample count from packet (\(bytes.count) bytes)"
                    )
                }
                let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount))!
                try decode(input, to: output)
                return output
            }
        }

        /// Decode to existing AVAudioPCMBuffer
        public func decode(_ input: UnsafeBufferPointer<UInt8>, to output: AVAudioPCMBuffer) throws {
            let decodedCount: Int
            switch output.format.commonFormat {
            case .pcmFormatInt16:
                let outputBuffer = UnsafeMutableBufferPointer(
                    start: output.int16ChannelData![0],
                    count: Int(output.frameCapacity)
                )
                decodedCount = try decode(input, to: outputBuffer)
            case .pcmFormatFloat32:
                let outputBuffer = UnsafeMutableBufferPointer(
                    start: output.floatChannelData![0],
                    count: Int(output.frameCapacity)
                )
                decodedCount = try decode(input, to: outputBuffer)
            default:
                throw Error.badArgument
            }

            if decodedCount < 0 {
                throw Error.decodingError(Int32(decodedCount), context: "failed to decode to AVAudioPCMBuffer")
            }
            output.frameLength = AVAudioFrameCount(decodedCount)
        }

        // MARK: - Low-level Raw PCM API

        /// Decode Opus packet into Int16 PCM array (with FEC and PLC support)
        /// - Parameters:
        ///   - packet: Encoded payload. Pass `nil` (and `packetLen = 0`) to invoke PLC.
        ///   - packetLen: Number of bytes in `packet`.
        ///   - fec: Set true to decode FEC when available (for previous lost packet).
        ///   - expected: Frame duration you expect (buffers sized from this).
        /// - Returns: PCM samples (Int16). Count = `returnedSamples * channels`.
        public func decodePCM16(
            packet: UnsafePointer<UInt8>?,
            packetLen: Int32,
            fec: Bool = false,
            expected: FrameDuration = .ms20
        ) throws -> [opus_int16] {
            // Allocate for the expected frame size
            let frameSize = sampleRate.frameSize(expected)
            var pcm = [opus_int16](repeating: 0, count: Int(frameSize * channels.rawValue))

            let outSamples: Int32 = try pcm.withUnsafeMutableBufferPointer { buffer in
                guard let dst = buffer.baseAddress else {
                    throw Error.badArgument
                }
                let result = opus_decode(decoder, packet, packetLen, dst, frameSize, fec ? 1 : 0)
                guard result >= 0 else {
                    let context = "packet: \(packetLen) bytes, expected: \(expected.ms)ms, fec: \(fec)"
                    throw Error.decodingError(result, context: "Int16 decode failed - \(context)")
                }
                return result
            }

            // Trim array to actual returned samples
            let actualSamples = Int(outSamples * channels.rawValue)
            if actualSamples < pcm.count {
                pcm.removeSubrange(actualSamples ..< pcm.count)
            }
            return pcm
        }

        /// Convenience: decode from Data packet to Int16 array
        public func decodePCM16(
            data: Data,
            fec: Bool = false,
            expected: FrameDuration = .ms20
        ) throws -> [opus_int16] {
            try data.withUnsafeBytes { raw in
                let ptr = raw.bindMemory(to: UInt8.self).baseAddress
                return try decodePCM16(packet: ptr, packetLen: Int32(data.count), fec: fec, expected: expected)
            }
        }

        /// Decode PCM16 directly into independently owned Data without an intermediate Int16 array.
        /// The Data can be reused across calls; shared storage is copied on write before decoding.
        /// - Returns: Decoded frames per channel. The output is trimmed to the exact PCM byte count.
        public func decodePCM16(
            data: Data,
            fec: Bool = false,
            expected: FrameDuration = .ms20,
            into output: inout Data
        ) throws -> Int {
            guard !data.isEmpty, data.count <= Int(Int32.max) else {
                throw Error.badArgument
            }

            return try data.withUnsafeBytes { raw in
                let packet = raw.bindMemory(to: UInt8.self)
                return try decodePCM16(
                    packet: packet.baseAddress,
                    packetLen: Int32(packet.count),
                    fec: fec,
                    expected: expected,
                    into: &output
                )
            }
        }

        /// Decode PCM16 into already allocated, aligned sample storage.
        /// The caller owns the memory and must keep it alive for the duration of this call.
        /// - Returns: Decoded frames per channel; output capacity is expressed in interleaved samples.
        public func decodePCM16(
            packet: UnsafePointer<UInt8>?,
            packetLen: Int32,
            fec: Bool = false,
            expected: FrameDuration = .ms20,
            into output: UnsafeMutableBufferPointer<opus_int16>
        ) throws -> Int {
            let frames = Int(sampleRate.frameSize(expected))
            let channelsCount = Int(channels.rawValue)
            guard frames > 0,
                  packetLen >= 0,
                  (packetLen == 0 || packet != nil),
                  output.count >= frames * channelsCount,
                  let destination = output.baseAddress
            else {
                throw Error.badArgument
            }

            let decodedFrames = opus_decode(
                decoder, packet, packetLen, destination, Int32(frames), fec ? 1 : 0
            )
            guard decodedFrames >= 0 else {
                throw Error.decodingError(
                    decodedFrames,
                    context: "Int16 decode failed - packet: \(packetLen) bytes, expected: \(expected.ms)ms, fec: \(fec)"
                )
            }
            return Int(decodedFrames)
        }

        /// Packet Loss Concealment directly into owned PCM bytes.
        /// - Returns: Generated frames per channel.
        public func concealPCM16(
            expected: FrameDuration = .ms20,
            into output: inout Data
        ) throws -> Int {
            try decodePCM16(
                packet: nil,
                packetLen: 0,
                fec: false,
                expected: expected,
                into: &output
            )
        }

        private func decodePCM16(
            packet: UnsafePointer<UInt8>?,
            packetLen: Int32,
            fec: Bool,
            expected: FrameDuration,
            into output: inout Data
        ) throws -> Int {
            let frameCapacity = Int(sampleRate.frameSize(expected))
            let byteCapacity = frameCapacity * Int(channels.rawValue) * MemoryLayout<opus_int16>.stride
            guard frameCapacity > 0 else { throw Error.badArgument }

            // All mutable access stays within Data's exclusive borrow. No native pointer escapes.
            output.count = byteCapacity
            do {
                let decodedFrames = try output.withUnsafeMutableBytes { raw -> Int in
                    guard let base = raw.baseAddress,
                          Int(bitPattern: base) % MemoryLayout<opus_int16>.alignment == 0
                    else {
                        throw Error.badArgument
                    }
                    let samples = raw.bindMemory(to: opus_int16.self)
                    return try decodePCM16(
                        packet: packet,
                        packetLen: packetLen,
                        fec: fec,
                        expected: expected,
                        into: samples
                    )
                }
                output.count = decodedFrames * Int(channels.rawValue) * MemoryLayout<opus_int16>.stride
                return decodedFrames
            } catch {
                output.removeAll(keepingCapacity: true)
                throw error
            }
        }

        /// Packet Loss Concealment - generate replacement audio for lost packet
        public func concealPCM16(expected: FrameDuration = .ms20) throws -> [opus_int16] {
            try decodePCM16(packet: nil, packetLen: 0, fec: false, expected: expected)
        }

        // MARK: - Private decode methods for different formats

        private func decode(
            _ input: UnsafeBufferPointer<UInt8>,
            to output: UnsafeMutableBufferPointer<Int16>
        ) throws -> Int {
            guard let inputPtr = input.baseAddress, let outputPtr = output.baseAddress else {
                throw Error.badArgument
            }

            let frameCount = Int32(output.count) / channels.rawValue
            let decodedCount = opus_decode(decoder, inputPtr, Int32(input.count), outputPtr, frameCount, 0)

            guard decodedCount >= 0 else {
                throw Error.decodingError(
                    decodedCount,
                    context: "Int16 decode failed, input: \(input.count) bytes, output capacity: \(output.count) samples"
                )
            }

            return Int(decodedCount)
        }

        private func decode(
            _ input: UnsafeBufferPointer<UInt8>,
            to output: UnsafeMutableBufferPointer<Float32>
        ) throws -> Int {
            guard let inputPtr = input.baseAddress, let outputPtr = output.baseAddress else {
                throw Error.badArgument
            }

            let frameCount = Int32(output.count) / channels.rawValue
            let decodedCount = opus_decode_float(decoder, inputPtr, Int32(input.count), outputPtr, frameCount, 0)

            guard decodedCount >= 0 else {
                throw Error.decodingError(
                    decodedCount,
                    context: "Float32 decode failed, input: \(input.count) bytes, output capacity: \(output.count) samples"
                )
            }

            return Int(decodedCount)
        }
    }
}

// MARK: - Convenience Extensions

public extension Opus.Decoder {
    /// Create decoder with common voice settings
    static func voice(sampleRate: Opus.SampleRate = .hz16k, channels: Opus.Channels = .mono) throws -> Opus.Decoder {
        try Opus.Decoder(sampleRate: sampleRate, channels: channels)
    }

    /// Create decoder with common music settings
    static func music(sampleRate: Opus.SampleRate = .hz48k, channels: Opus.Channels = .stereo) throws -> Opus.Decoder {
        try Opus.Decoder(sampleRate: sampleRate, channels: channels)
    }
}
