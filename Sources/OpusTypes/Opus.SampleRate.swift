public extension Opus {
    @frozen enum SampleRate: Int32 {
        case hz8k = 8000
        case hz12k = 12000
        case hz16k = 16000
        case hz24k = 24000
        case hz48k = 48000

        @inlinable public var samplesPerMs: Int32 { rawValue / 1000 }
        @inlinable public func frameSize(_ dur: FrameDuration)
        -> Int32 { Int32((Double(rawValue) * dur.ms) / 1000.0 + 0.5) }
    }
}

public extension Opus.SampleRate {
    @inlinable var hz: Double { Double(rawValue) }

    /// Failable init that tolerates tiny floating errors from AVFoundation
    @inlinable init?(hz: Double, tolerance: Double = 0.5) {
        let legal: [Int32] = [8000, 12000, 16000, 24000, 48000]
        guard let m = legal.first(where: { abs(Double($0) - hz) <= tolerance }) else { return nil }
        self.init(rawValue: m)
    }
}
