import Foundation

/// Finds a sibling executable product in the same SwiftPM build output
/// directory `swift test` produced. `Bundle.main` is not a reliable anchor
/// here: swift-testing can run the test bundle by loading it into a
/// separate `swiftpm-testing-helper` process (confirmed empirically — the
/// helper's own `Bundle.main` has nothing to do with `.build/`), so this
/// instead searches `.build/` under the current working directory, which
/// `swift build`/`swift test` are always run from at the package root.
///
/// Copied from Tests/ClaudeCodeAdapterTests/AdapterBinaryLocator.swift
/// rather than shared, since test targets don't share sources — see that
/// file for the original.
enum AdapterBinaryLocator {
    static func find(named binaryName: String) -> URL? {
        let buildRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build")
        guard let enumerator = FileManager.default.enumerator(
            at: buildRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        // Prefer a debug build over a release one if somehow both are
        // present, and the shortest matching path — a same-named DWARF
        // debug symbol file (`AntigravityAdapter.dSYM/.../DWARF/AntigravityAdapter`)
        // otherwise matches just as well and sorts arbitrarily against the
        // real executable.
        var candidates: [URL] = []
        for case let url as URL in enumerator {
            guard url.lastPathComponent == binaryName,
                  !url.path.contains(".dSYM"),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            candidates.append(url)
        }
        return candidates.sorted { lhs, rhs in
            let lhsIsDebug = lhs.path.contains("/debug/")
            let rhsIsDebug = rhs.path.contains("/debug/")
            if lhsIsDebug != rhsIsDebug { return lhsIsDebug }
            return lhs.pathComponents.count < rhs.pathComponents.count
        }.first
    }
}
