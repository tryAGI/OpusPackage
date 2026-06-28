import OpusShims

public extension Opus {
    struct Error: Swift.Error, Equatable, RawRepresentable, ExpressibleByIntegerLiteral, CustomStringConvertible {
        public typealias IntegerLiteralType = Int32
        public var rawValue: IntegerLiteralType

        // Context information for better debugging
        public let context: String?
        public let operation: String?

        public static let ok = Self(OPUS_OK)
        public static let badArgument = Self(OPUS_BAD_ARG)
        public static let bufferTooSmall = Self(OPUS_BUFFER_TOO_SMALL)
        public static let internalError = Self(OPUS_INTERNAL_ERROR)
        public static let invalidPacket = Self(OPUS_INVALID_PACKET)
        public static let unimplemented = Self(OPUS_UNIMPLEMENTED)
        public static let invalidState = Self(OPUS_INVALID_STATE)
        public static let allocationFailure = Self(OPUS_ALLOC_FAIL)

        public init(rawValue: IntegerLiteralType) {
            self.rawValue = rawValue
            context = nil
            operation = nil
        }

        public init(integerLiteral value: IntegerLiteralType) {
            self.init(rawValue: value)
        }

        public init(_ value: some BinaryInteger) {
            self.init(rawValue: IntegerLiteralType(value))
        }

        // Enhanced initializer with context
        public init(_ value: some BinaryInteger, context: String? = nil, operation: String? = nil) {
            rawValue = IntegerLiteralType(value)
            self.context = context
            self.operation = operation
        }

        public var description: String {
            let baseMessage = switch rawValue {
            case OPUS_OK:
                "Success"
            case OPUS_BAD_ARG:
                "Bad argument - One or more invalid/out-of-range arguments"
            case OPUS_BUFFER_TOO_SMALL:
                "Buffer too small - Output buffer is too small"
            case OPUS_INTERNAL_ERROR:
                "Internal error - An internal error was detected"
            case OPUS_INVALID_PACKET:
                "Invalid packet - The compressed data passed is corrupted"
            case OPUS_UNIMPLEMENTED:
                "Unimplemented - Invalid/unsupported request number"
            case OPUS_INVALID_STATE:
                "Invalid state - An encoder or decoder structure is invalid or already freed"
            case OPUS_ALLOC_FAIL:
                "Allocation failure - Memory allocation has failed"
            default:
                "Unknown Opus error"
            }

            var fullMessage = "Opus Error (\(rawValue)): \(baseMessage)"

            if let operation {
                fullMessage += " during \(operation)"
            }

            if let context {
                fullMessage += " - \(context)"
            }

            return fullMessage
        }

        // Helper methods for common operations
        public static func encodingError(_ code: Int32, context: String? = nil) -> Self {
            Self(code, context: context, operation: "encoding")
        }

        public static func decodingError(_ code: Int32, context: String? = nil) -> Self {
            Self(code, context: context, operation: "decoding")
        }

        public static func initError(_ code: Int32, context: String? = nil) -> Self {
            Self(code, context: context, operation: "initialization")
        }

        public static func configError(_ code: Int32, context: String? = nil) -> Self {
            Self(code, context: context, operation: "configuration")
        }
    }
}
