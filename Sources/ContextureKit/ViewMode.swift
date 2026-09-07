import Foundation

/// The active presentation layout of a Document window.
public enum ViewMode: String, Sendable, Codable, CaseIterable, Equatable {
    case previewOnly = "previewOnly"
    case split = "split"
}

extension ViewMode {
    public static let userDefaultsKey = "ContextureDefaultViewMode"

    /// The user-preferred default View Mode for newly opened Document windows.
    public static var userDefault: ViewMode {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
                  let mode = ViewMode(rawValue: rawValue) else {
                return .previewOnly
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}
