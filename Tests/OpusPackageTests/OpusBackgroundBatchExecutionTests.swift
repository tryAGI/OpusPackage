@preconcurrency import AVFoundation
import Dispatch
import XCTest

@testable import OpusKit

final class OpusBackgroundBatchExecutionTests: XCTestCase {
    func testRepeatedEncodeDecodeBatchWorksOffMainThread() async throws {
        let iterationCount = 8

        let completedIterations = try await Task.detached(priority: .userInitiated) { () throws -> Int in
            dispatchPrecondition(condition: .notOnQueue(.main))

            let format = AVAudioFormat(opusPCMFormat: .float32, sampleRate: .hz48k, channels: .mono)!
            let frameCapacity = AVAudioFrameCount(Opus.SampleRate.hz48k.frameSize(.ms20))
            let encoder = try Opus.Encoder(format: format)
            let decoder = try Opus.Decoder(format: format)

            for iteration in 0..<iterationCount {
                let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)!
                input.frameLength = input.frameCapacity

                if let channelData = input.floatChannelData {
                    for index in 0..<Int(input.frameLength) {
                        let polarity: Float = index.isMultiple(of: 2) ? 1 : -1
                        channelData[0][index] = polarity * Float(iteration + 1) * 0.02
                    }
                }

                var encoded = Data(count: 1500)
                let encodedByteCount = try encoder.encode(input, to: &encoded)
                encoded.count = encodedByteCount

                let decoded = try decoder.decode(encoded)
                XCTAssertEqual(decoded.frameLength, input.frameLength)
                XCTAssertTrue(decoded.format.isEqual(input.format))
            }

            return iterationCount
        }.value

        XCTAssertEqual(completedIterations, iterationCount)
    }
}
