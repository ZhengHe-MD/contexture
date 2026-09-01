/// The writer-controlled lifetime of Selection Context.
///
/// Pinned is deliberately absent: docs/product.md defers it until daily use
/// shows writers re-selecting the same passage repeatedly. Do not add a case
/// for it ahead of that evidence.
public enum SharingMode: String, Sendable, Codable, Equatable {
    case off
    case nextPrompt
}
