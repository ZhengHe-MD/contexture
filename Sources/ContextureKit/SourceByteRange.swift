/// A canonical UTF-8 byte range into a Document's Source. This, not any
/// UI-native UTF-16 range, is the write authority for what was selected.
public struct SourceByteRange: Sendable, Hashable, Codable {
    public let lowerBound: Int
    public let upperBound: Int

    public init(lowerBound: Int, upperBound: Int) {
        precondition(lowerBound >= 0 && upperBound >= lowerBound, "invalid byte range")
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public var count: Int { upperBound - lowerBound }
    public var isEmpty: Bool { count == 0 }
}
