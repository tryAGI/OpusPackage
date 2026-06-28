@preconcurrency import AVFoundation
import XCTest

@testable import OpusKit

final class OpusBackgroundExecutionTests: XCTestCase {
    func testEncodeDecodeWorksOffMainThread() async throws {
        let decodedSuccessfully = try await Task.detached(priority: .userInitiated) { () throws -> Bool in
            dispatchPrecondition(condition: .notOnQueue(.main))

            let format = AVAudioFormat(opusPCMFormat: .float32, sampleRate: .hz48k, channels: .mono)!
            let frameCapacity = AVAudioFrameCount(Opus.SampleRate.hz48k.frameSize(.ms20))
            let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)!
            input.frameLength = input.frameCapacity

            if let channelData = input.floatChannelData {
                for index in 0..<Int(input.frameLength) {
                    channelData[0][index] = index.isMultiple(of: 2) ? 0.25 : -0.25
                }
            }

            let encoder = try Opus.Encoder(format: input.format)
            let decoder = try Opus.Decoder(format: input.format)

            var encoded = Data(count: 1500)
            let encodedByteCount = try encoder.encode(input, to: &encoded)
            encoded.count = encodedByteCount

            let decoded = try decoder.decode(encoded)

            return decoded.frameLength == input.frameLength
                && decoded.format.isEqual(input.format)
        }.value

        XCTAssertTrue(decodedSuccessfully)
    }
}
