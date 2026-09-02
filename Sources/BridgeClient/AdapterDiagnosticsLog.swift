import Foundation

/// One hook invocation's outcome, content-free by construction: there is no
/// field anywhere in this type an Adapter could accidentally populate with
/// Selection text or prompt content. `injectedSnapshotCount` is a count,
/// never the snapshots themselves.
///
/// docs/product.md "Distribution direction" / issue #12: "Diagnostics are
/// available on explicit request only and must never contain Selection
/// contents." This is the "never contain" half — the app only reads this
/// log when a writer explicitly opens Diagnostics (the "on explicit
/// request" half lives in `Sources/ContextureApp/DiagnosticsWindowController.swift`),
/// but the log itself is safe to write unconditionally on every invocation
/// because nothing in it could leak regardless of who reads it or when.
public struct AdapterDiagnosticEntry: Codable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case injected
        case noInjection
    }

    public let timestamp: Date
    public let adapterID: String
    public let outcome: Outcome
    public let injectedSnapshotCount: Int?

    public init(timestamp: Date, adapterID: String, outcome: Outcome, injectedSnapshotCount: Int? = nil) {
        self.timestamp = timestamp
        self.adapterID = adapterID
        self.outcome = outcome
        self.injectedSnapshotCount = injectedSnapshotCount
    }
}

/// Append-only, best-effort, content-free activity log every Adapter
/// writes one line to per invocation. "Best-effort" is deliberate: a
/// failure to write a diagnostic line must never be the reason a real
/// prompt submission is delayed or fails — every operation here silently
/// gives up rather than throwing.
public enum AdapterDiagnosticsLog {
    public static func defaultPath() -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Contexture").appendingPathComponent("diagnostics.log").path
    }

    /// Appends one JSON-lines entry. Never throws; failures (missing
    /// directory, no write permission, disk full) are silently swallowed —
    /// see the type's doc comment for why.
    public static func record(_ entry: AdapterDiagnosticEntry, path: String = defaultPath()) {
        guard let payload = try? JSONEncoder().encode(entry),
              var line = String(data: payload, encoding: .utf8) else { return }
        line += "\n"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let lineData = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(lineData)
            try? handle.close()
        } else {
            try? lineData.write(to: url)
        }
    }

    /// The most recent `limit` entries, oldest first within that window.
    /// Malformed lines (a partially-written entry from a crash mid-write,
    /// for instance) are skipped rather than failing the whole read.
    public static func recentEntries(limit: Int = 50, path: String = defaultPath()) -> [AdapterDiagnosticEntry] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        let entries = contents
            .split(separator: "\n")
            .compactMap { line -> AdapterDiagnosticEntry? in
                try? decoder.decode(AdapterDiagnosticEntry.self, from: Data(line.utf8))
            }
        return Array(entries.suffix(limit))
    }
}
