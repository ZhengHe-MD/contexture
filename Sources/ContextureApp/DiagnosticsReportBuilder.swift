import BridgeClient
import Foundation

/// Builds the plain-text report `DiagnosticsWindowController` displays.
/// Pure formatting over already-gathered data — no file I/O of its own —
/// so it's directly unit-testable with synthetic fixtures instead of real
/// installs/logs.
enum DiagnosticsReportBuilder {
    static func build(
        adapters: [(name: String, compatibility: AdapterCompatibility)],
        recentActivity: [AdapterDiagnosticEntry]
    ) -> String {
        var lines: [String] = []
        lines.append("Adapter Diagnostics")
        lines.append("")
        lines.append("Per-host status:")
        let nameWidth = (adapters.map(\.name.count).max() ?? 0)
        for adapter in adapters {
            let padded = adapter.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0)
            lines.append("  \(padded)  \(adapter.compatibility.rawValue)")
        }
        lines.append("")
        lines.append("Recent activity (content-free — never Selection or prompt text):")
        if recentActivity.isEmpty {
            lines.append("  (none yet)")
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            for entry in recentActivity.reversed() {
                let timestamp = formatter.string(from: entry.timestamp)
                let detail: String
                switch entry.outcome {
                case .injected:
                    let count = entry.injectedSnapshotCount ?? 0
                    detail = "injected (\(count) selection\(count == 1 ? "" : "s"))"
                case .noInjection:
                    detail = "no context"
                }
                lines.append("  \(timestamp)  \(entry.adapterID)  \(detail)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
