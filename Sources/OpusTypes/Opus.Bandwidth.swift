public extension Opus {
    @frozen enum Bandwidth: Int32, Sendable, CaseIterable {
        case narrowband = 1101 // OPUS_BANDWIDTH_NARROWBAND (4 kHz)
        case mediumband = 1102 // OPUS_BANDWIDTH_MEDIUMBAND (6 kHz)
        case wideband = 1103 // OPUS_BANDWIDTH_WIDEBAND (8 kHz)
        case superWideband = 1104 // OPUS_BANDWIDTH_SUPERWIDEBAND (12 kHz)
        case fullband = 1105 // OPUS_BANDWIDTH_FULLBAND (20 kHz)
    }
}

public extension Opus.Bandwidth {
    /// Pass this into C APIs (identical to rawValue).
    @inlinable var cValue: Int32 { rawValue }

    /// Create from a C value (e.g. OPUS_GET_BANDWIDTH).
    @inlinable init?(cValue: Int32) { self.init(rawValue: cValue) }

    /// Human-readable description
    var description: String {
        switch self {
        case .narrowband: "Narrowband (4 kHz)"
        case .mediumband: "Mediumband (6 kHz)"
        case .wideband: "Wideband (8 kHz)"
        case .superWideband: "Super-wideband (12 kHz)"
        case .fullband: "Fullband (20 kHz)"
        }
    }
}
