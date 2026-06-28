public extension Opus {
    @frozen enum PCMFormat: Sendable {
        case int16 // uses opus_encode
        case float32 // uses opus_encode_float
    }
}

public extension Opus.PCMFormat {
    @inlinable var usesFloatAPI: Bool { self == .float32 }
    @inlinable var bytesPerSample: Int { self == .int16 ? 2 : 4 }
}
