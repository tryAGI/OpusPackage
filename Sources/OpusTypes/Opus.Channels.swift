import AVFoundation

public extension Opus {
    @frozen enum Channels: Int32 {
        case mono = 1
        case stereo = 2
    }
}

public extension Opus.Channels {
    @inlinable var cValue: Int32 { rawValue }
    @inlinable var avCount: AVAudioChannelCount { AVAudioChannelCount(rawValue) }
    @inlinable init?(avCount: AVAudioChannelCount) {
        switch avCount {
        case 1: self = .mono
        case 2: self = .stereo
        default: return nil
        }
    }

    /// Opus wants interleaved stereo; mono interleave does not matter
    @inlinable var defaultInterleaved: Bool { self == .stereo }
}
