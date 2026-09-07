import Foundation

/// The active presentation layout of a Document window.
public enum ViewMode: String, Sendable, Codable, CaseIterable, Equatable {
    case previewOnly = "previewOnly"
    case split = "split"
}

extension ViewMode {
    public static let userDefaultsKey = "ContextureDefaultViewMode"

    /// Reads the preferred View Mode from the specified defaults domain, defaulting to `.previewOnly`.
    public static func preferred(in defaults: UserDefaults = .standard) -> ViewMode {
        guard let rawValue = defaults.string(forKey: userDefaultsKey),
              let mode = ViewMode(rawValue: rawValue) else {
            return .previewOnly
        }
        return mode
    }

    /// Stores the preferred View Mode in the specified defaults domain.
    public static func setPreferred(_ mode: ViewMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: userDefaultsKey)
    }

    /// The user-preferred default View Mode for newly opened Document windows in standard defaults.
    public static var userDefault: ViewMode {
        get { preferred(in: .standard) }
        set { setPreferred(newValue, in: .standard) }
    }
}
