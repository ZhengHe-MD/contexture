import BridgeClient
import Foundation
import Testing
@testable import ContextureApp

@Suite struct DiagnosticsReportBuilderTests {
    @Test func listsEveryAdapterWithItsCompatibility() {
        let report = DiagnosticsReportBuilder.build(
            adapters: [
                (name: "Claude Code", compatibility: .deterministic),
                (name: "Codex", compatibility: .notInstalled),
            ],
            recentActivity: []
        )
        #expect(report.contains("Claude Code"))
        #expect(report.contains("Deterministic"))
        #expect(report.contains("Codex"))
        #expect(report.contains("Not Installed"))
    }

    @Test func showsAPlaceholderWhenThereIsNoRecentActivity() {
        let report = DiagnosticsReportBuilder.build(adapters: [], recentActivity: [])
        #expect(report.contains("none yet"))
    }

    @Test func describesAnInjectedEntryWithItsCount() {
        let entry = AdapterDiagnosticEntry(timestamp: Date(), adapterID: "claude-code", outcome: .injected, injectedSnapshotCount: 2)
        let report = DiagnosticsReportBuilder.build(adapters: [], recentActivity: [entry])
        #expect(report.contains("claude-code"))
        #expect(report.contains("injected (2 selections)"))
    }

    @Test func usesSingularWordingForOneInjectedSnapshot() {
        let entry = AdapterDiagnosticEntry(timestamp: Date(), adapterID: "codex", outcome: .injected, injectedSnapshotCount: 1)
        let report = DiagnosticsReportBuilder.build(adapters: [], recentActivity: [entry])
        #expect(report.contains("injected (1 selection)"))
        #expect(!report.contains("1 selections"))
    }

    @Test func describesANoInjectionEntry() {
        let entry = AdapterDiagnosticEntry(timestamp: Date(), adapterID: "antigravity", outcome: .noInjection)
        let report = DiagnosticsReportBuilder.build(adapters: [], recentActivity: [entry])
        #expect(report.contains("no context"))
    }

    @Test func neverContainsAnythingResemblingSelectionOrPromptContent() {
        // The report is built entirely from AdapterDiagnosticEntry, which
        // structurally cannot carry free-form text (see
        // AdapterDiagnosticsLogTests.outcomeHasNoFieldCapableOfCarryingFreeFormContent) —
        // this just double-checks the *rendered* text stays that way too.
        let entries = [
            AdapterDiagnosticEntry(timestamp: Date(), adapterID: "claude-code", outcome: .injected, injectedSnapshotCount: 5),
            AdapterDiagnosticEntry(timestamp: Date(), adapterID: "codex", outcome: .noInjection),
        ]
        let report = DiagnosticsReportBuilder.build(
            adapters: [(name: "Claude Code", compatibility: .deterministic)],
            recentActivity: entries
        )
        // A very loose sanity check: the report should be short and
        // line-oriented, not contain anything resembling a Markdown
        // Document body or a rendered Selection Context envelope.
        #expect(!report.contains("Contexture Selection Context"))
    }
}
