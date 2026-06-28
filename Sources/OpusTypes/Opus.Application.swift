public extension Opus {
    @frozen enum Application: Int32, Sendable {
        // Raw values are the libopus constants (RFC 6716); stable since 2012.
        case voip = 2048 // OPUS_APPLICATION_VOIP
        case audio = 2049 // OPUS_APPLICATION_AUDIO
        case restrictedLowDelay = 2051 // OPUS_APPLICATION_RESTRICTED_LOWDELAY
    }
}

public extension Opus.Application {
    /// Pass this into C APIs (identical to rawValue).
    @inlinable var cValue: Int32 { rawValue }

    /// Create from a C value (e.g. OPUS_GET_APPLICATION).
    @inlinable init?(cValue: Int32) { self.init(rawValue: cValue) }
}
