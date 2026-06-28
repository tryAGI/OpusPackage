@preconcurrency import AVFoundation // treat legacy non-Sendable as warnings
import OpusTypes
import XCTest

@testable import OpusKit

@MainActor
final class AVAudioFormatTests: XCTestCase {
    static let validFormats = [
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: true)!,
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: true)!,
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8000, channels: 2, interleaved: true)!,
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8000, channels: 2, interleaved: true)!,
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8000, channels: 2, interleaved: true)!,
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8000, channels: 2, interleaved: true)!,
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: true)!,
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true)!,
        AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMIsNonInterleaved: false,
        ])!,
        AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMIsNonInterleaved: false,
        ])!,
        AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMIsNonInterleaved: false,
        ])!,
        AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 16,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMIsNonInterleaved: false,
        ])!,
        AVAudioFormat(opusPCMFormat: .int16, sampleRate: .hz12k, channels: .mono)!,
        AVAudioFormat(opusPCMFormat: .int16, sampleRate: .hz12k, channels: .stereo)!,
        AVAudioFormat(opusPCMFormat: .int16, sampleRate: .hz16k, channels: .mono)!,
        AVAudioFormat(opusPCMFormat: .int16, sampleRate: .hz16k, channels: .stereo)!,
        AVAudioFormat(opusPCMFormat: .int16, sampleRate: .hz24k, channels: .mono)!,
        AVAudioFormat(opusPCMFormat: .int16, sampleRate: .hz24k, channels: .stereo)!,
        AVAudioFormat(opusPCMFormat: .int16, sampleRate: .hz48k, channels: .mono)!,
        AVAudioFormat(opusPCMFormat: .int16, sampleRate: .hz48k, channels: .stereo)!,
        AVAudioFormat(opusPCMFormat: .float32, sampleRate: .hz12k, channels: .mono)!,
        AVAudioFormat(opusPCMFormat: .float32, sampleRate: .hz12k, channels: .stereo)!,
        AVAudioFormat(opusPCMFormat: .float32, sampleRate: .hz16k, channels: .mono)!,
        AVAudioFormat(opusPCMFormat: .float32, sampleRate: .hz16k, channels: .stereo)!,
        AVAudioFormat(opusPCMFormat: .float32, sampleRate: .hz24k, channels: .mono)!,
        AVAudioFormat(opusPCMFormat: .float32, sampleRate: .hz24k, channels: .stereo)!,
        AVAudioFormat(opusPCMFormat: .float32, sampleRate: .hz48k, channels: .mono)!,
        AVAudioFormat(opusPCMFormat: .float32, sampleRate: .hz48k, channels: .stereo)!,
    ]

    static let invalidFormats = [
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: false)!,
        AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44100, channels: 2, interleaved: true)!,
        AVAudioFormat(commonFormat: .pcmFormatInt32, sampleRate: 48000, channels: 1, interleaved: true)!,
        AVAudioFormat(commonFormat: .pcmFormatInt32, sampleRate: 48000, channels: 2, interleaved: true)!,
        AVAudioFormat(commonFormat: .pcmFormatFloat64, sampleRate: 48000, channels: 1, interleaved: true)!,
        AVAudioFormat(commonFormat: .pcmFormatFloat64, sampleRate: 48000, channels: 2, interleaved: true)!,
        AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMIsNonInterleaved: true,
        ])!,
        AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 32,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMIsNonInterleaved: false,
        ])!,
        AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 32,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMIsNonInterleaved: false,
        ])!,
        AVAudioFormat(settings: [AVFormatIDKey: kAudioFormatOpus, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1])!,
        AVAudioFormat(settings: [AVFormatIDKey: kAudioFormatOpus, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2])!,
    ]

    func testIsValidFormat() throws {
        for validFormat in Self.validFormats {
            XCTAssert(validFormat.isValidOpusPCMFormat, validFormat.description)
        }

        for invalidFormat in Self.invalidFormats {
            XCTAssertFalse(invalidFormat.isValidOpusPCMFormat, invalidFormat.description)
        }
    }
}
