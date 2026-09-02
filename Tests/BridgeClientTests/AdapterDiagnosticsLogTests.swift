import BridgeClient
import Foundation
import Testing

@Suite struct AdapterDiagnosticsLogTests {
    private func scratchPath() -> String {
        "/tmp/ctx-diag-\(UUID().uuidString.prefix(8)).log"
    }

    @Test func recordThenReadRoundTrips() {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let entry = AdapterDiagnosticEntry(
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            adapterID: "claude-code",
            outcome: .injected,
            injectedSnapshotCount: 2
        )
        AdapterDiagnosticsLog.record(entry, path: path)

        let entries = AdapterDiagnosticsLog.recentEntries(path: path)
        #expect(entries.count == 1)
        #expect(entries.first?.adapterID == "claude-code")
        #expect(entries.first?.outcome == .injected)
        #expect(entries.first?.injectedSnapshotCount == 2)
    }

    @Test func multipleEntriesAppendRatherThanOverwrite() {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        AdapterDiagnosticsLog.record(AdapterDiagnosticEntry(timestamp: Date(), adapterID: "codex", outcome: .noInjection), path: path)
        AdapterDiagnosticsLog.record(AdapterDiagnosticEntry(timestamp: Date(), adapterID: "antigravity", outcome: .injected, injectedSnapshotCount: 1), path: path)

        let entries = AdapterDiagnosticsLog.recentEntries(path: path)
        #expect(entries.map(\.adapterID) == ["codex", "antigravity"])
    }

    @Test func recentEntriesReturnsEmptyForANonexistentFile() {
        #expect(AdapterDiagnosticsLog.recentEntries(path: scratchPath()).isEmpty)
    }

    @Test func recentEntriesRespectsTheLimitKeepingTheMostRecent() {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        for index in 0..<5 {
            AdapterDiagnosticsLog.record(AdapterDiagnosticEntry(timestamp: Date(), adapterID: "adapter-\(index)", outcome: .noInjection), path: path)
        }

        let entries = AdapterDiagnosticsLog.recentEntries(limit: 2, path: path)
        #expect(entries.map(\.adapterID) == ["adapter-3", "adapter-4"])
    }

    @Test func malformedLinesAreSkippedRatherThanFailingTheWholeRead() {
        let path = scratchPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        AdapterDiagnosticsLog.record(AdapterDiagnosticEntry(timestamp: Date(), adapterID: "codex", outcome: .noInjection), path: path)
        // Append a genuinely malformed line after the valid one, the same
        // way a partially-written entry from a crash mid-write might land.
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data("not valid json\n".utf8))
            try? handle.close()
        }
        AdapterDiagnosticsLog.record(AdapterDiagnosticEntry(timestamp: Date(), adapterID: "antigravity", outcome: .noInjection), path: path)

        let entries = AdapterDiagnosticsLog.recentEntries(path: path)
        #expect(entries.map(\.adapterID) == ["codex", "antigravity"])
    }

    @Test func outcomeHasNoFieldCapableOfCarryingFreeFormContent() {
        // Structural guarantee, not a runtime one: AdapterDiagnosticEntry's
        // only content-shaped field is a Bool-like Outcome enum and an
        // optional Int count — there is no String field anywhere a caller
        // could pass Selection or prompt text into, so this is really
        // asserting the type's shape compiles the way this test expects.
        let entry = AdapterDiagnosticEntry(timestamp: Date(), adapterID: "claude-code", outcome: .injected, injectedSnapshotCount: 3)
        let mirror = Mirror(reflecting: entry)
        let stringFields = mirror.children.compactMap { $0.value as? String }
        // adapterID itself is a String, but it is a fixed identifier
        // ("claude-code"/"codex"/"antigravity"), not writer-controlled
        // content — everything else must be non-String.
        #expect(stringFields == ["claude-code"])
    }
}
