public extension Opus {
    struct Config: Sendable {
        public var sampleRate: SampleRate
        public var channels: Channels
        public var application: Application
        public var complexity: Int32 // 0...10
        public var vbr: Bool
        public var constrainedVBR: Bool
        public var fec: Bool
        public var dtx: Bool
        public var expectedLossPerc: Int32 // 0...100
        public var bitrate: Int32 // bps

        public init(
            sampleRate: SampleRate = .hz16k,
            channels: Channels = .mono,
            application: Application = .voip,
            complexity: Int32 = 10,
            vbr: Bool = true,
            constrainedVBR: Bool = true,
            fec: Bool = true,
            dtx: Bool = true,
            expectedLossPerc: Int32 = 10,
            bitrate: Int32 = 24000
        ) {
            self.sampleRate = sampleRate
            self.channels = channels
            self.application = application
            self.complexity = complexity
            self.vbr = vbr
            self.constrainedVBR = constrainedVBR
            self.fec = fec
            self.dtx = dtx
            self.expectedLossPerc = expectedLossPerc
            self.bitrate = bitrate
        }

        public static let voiceLowBW = Config() // good default for speech @16k
        public static let music48k = Config(
            sampleRate: .hz48k, channels: .stereo,
            application: .audio, complexity: 9,
            vbr: true, constrainedVBR: false,
            fec: false, dtx: false,
            expectedLossPerc: 0, bitrate: 96000
        )
    }
}
