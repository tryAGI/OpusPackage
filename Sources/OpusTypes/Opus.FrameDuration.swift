public extension Opus {
    @frozen struct FrameDuration: Equatable {
        public let ms: Double
        @inlinable public init(_ ms: Double) { self.ms = ms }
        public static let ms2_5 = FrameDuration(2.5)
        public static let ms5 = FrameDuration(5)
        public static let ms10 = FrameDuration(10)
        public static let ms20 = FrameDuration(20)
        public static let ms40 = FrameDuration(40)
        public static let ms60 = FrameDuration(60)
    }
}
