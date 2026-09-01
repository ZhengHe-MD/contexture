/// The rendered-format identity of a Document's Source.
///
/// Ships from the first release even though `markdown` is its only possible
/// value today: adding the field later would break a contract already
/// installed on users' machines. See docs/product.md "Extensibility posture".
public enum FormatTag: String, Sendable, Codable, Equatable {
    case markdown
}
