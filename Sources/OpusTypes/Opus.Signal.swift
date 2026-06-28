public extension Opus {
    @frozen enum Signal: Int32, Sendable, CaseIterable {
        case auto = -1000 // OPUS_AUTO
        case voice = 3001 // OPUS_SIGNAL_VOICE
        case music = 3002 // OPUS_SIGNAL_MUSIC
    }
}

public extension Opus.Signal {
    /// Pass this into C APIs (identical to rawValue).
    @inlinable var cValue: Int32 { rawValue }

    /// Create from a C value (e.g. OPUS_GET_SIGNAL).
    @inlinable init?(cValue: Int32) { self.init(rawValue: cValue) }

    /// Human-readable description
    var description: String {
        switch self {
        case .auto: "Auto"
        case .voice: "Voice"
        case .music: "Music"
        }
    }
}
