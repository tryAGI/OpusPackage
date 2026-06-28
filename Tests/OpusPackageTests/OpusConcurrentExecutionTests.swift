@preconcurrency import AVFoundation
import Dispatch
import XCTest

@testable import OpusKit

final class OpusConcurrentExecutionTests: XCTestCase {
    func testConcurrentEncodeDecodeTasksWorkOffMainThread() async throws {
        let completedTasks = try await withThrowingTaskGroup(of: Int.self) { group in
            for taskIndex in 0..<4 {
                group.addTask(priority: .userInitiated) {
                    dispatchPrecondition(condition: .notOnQueue(.main))

                    let format = AVAudioFormat(opusPCMFormat: .float32, sampleRate: .hz48k, channels: .mono)!
                    let frameCapacity = AVAudioFrameCount(Opus.SampleRate.hz48k.frameSize(.ms20))
                    let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)!
                    input.frameLength = input.frameCapacity

                    if let channelData = input.floatChannelData {
                        for sampleIndex in 0..<Int(input.frameLength) {
                            let sign: Float = sampleIndex.isMultiple(of: 2) ? 1 : -1
                            channelData[0][sampleIndex] = sign * Float(taskIndex + 1) * 0.03
                        }
                    }

                    let encoder = try Opus.Encoder(format: input.format)
                    let decoder = try Opus.Decoder(format: input.format)

                    var encoded = Data(count: 1500)
                    let encodedByteCount = try encoder.encode(input, to: &encoded)
                    encoded.count = encodedByteCount

                    let decoded = try decoder.decode(encoded)
                    XCTAssertEqual(decoded.frameLength, input.frameLength)
                    XCTAssertTrue(decoded.format.isEqual(input.format))

                    return 1
                }
            }

            var completedTasks = 0
            for try await completed in group {
                completedTasks += completed
            }
            return completedTasks
        }

        XCTAssertEqual(completedTasks, 4)
    }
}
