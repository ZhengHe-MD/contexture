import Foundation

/// Defines standard zoom factors, discrete stepping increments, and persistence
/// for Document presentation scaling.
public enum DocumentZoom {
    public static let levels: [Double] = [0.50, 0.75, 0.85, 1.00, 1.15, 1.25, 1.50, 1.75, 2.00, 2.50, 3.00]
    public static let defaultFactor: Double = 1.00
    public static let minimumFactor: Double = 0.50
    public static let maximumFactor: Double = 3.00
    public static let tolerance: Double = 0.001

    public static let userDefaultsKey = "ContexturePreferredZoomFactor"
    public static let didChangeNotification = Notification.Name("ContextureDocumentZoomDidChangeNotification")
    public static let factorUserInfoKey = "factor"

    /// Calculates the next discrete zoom factor strictly greater than `current`.
    public static func zoomedIn(from current: Double) -> Double {
        for level in levels where level > current + tolerance {
            return level
        }
        return maximumFactor
    }

    /// Calculates the next discrete zoom factor strictly smaller than `current`.
    public static func zoomedOut(from current: Double) -> Double {
        for level in levels.reversed() where level < current - tolerance {
            return level
        }
        return minimumFactor
    }

    /// Clamps the factor within minimum and maximum limits.
    public static func clamp(_ factor: Double) -> Double {
        min(max(factor, minimumFactor), maximumFactor)
    }

    /// Returns a localized percentage representation, e.g. "100%", "125%".
    public static func percentageString(for factor: Double) -> String {
        let percent = Int((factor * 100.0).rounded())
        return "\(percent)%"
    }

    /// Reads the preferred zoom factor from the specified defaults domain, defaulting to 1.0.
    public static func preferred(in defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: userDefaultsKey) != nil else {
            return defaultFactor
        }
        let stored = defaults.double(forKey: userDefaultsKey)
        guard stored >= minimumFactor && stored <= maximumFactor else {
            return defaultFactor
        }
        return stored
    }

    /// Stores the preferred zoom factor in the specified defaults domain.
    public static func setPreferred(_ factor: Double, in defaults: UserDefaults = .standard) {
        defaults.set(clamp(factor), forKey: userDefaultsKey)
    }
}
