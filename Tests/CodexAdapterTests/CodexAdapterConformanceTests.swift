import ConformanceHarness
import Testing

/// Registers the Codex Adapter against the shared black-box conformance
/// harness (issue #9) — the 14 cases from docs/architecture/selection-
/// bridge.md's "Test contract", run against a throwaway Bridge and a real
/// subprocess launch of the compiled executable. Nothing about those cases
/// is reimplemented here; see Tests/ClaudeCodeAdapterTests for the first
/// Adapter registered the same way.
@Suite struct CodexAdapterConformanceTests {
    @Test func passesTheSharedBlackBoxConformanceSuite() throws {
        guard let executableURL = AdapterBinaryLocator.find(named: "CodexAdapter") else {
            Issue.record("could not locate the compiled CodexAdapter binary next to the test bundle")
            return
        }
        let adapter = CodexAdapterUnderTest(executableURL: executableURL)
        let results = try ConformanceHarness.run(adapter: adapter)
        for result in results {
            #expect(result.passed, "\(result.name): \(result.detail)")
        }
    }
}
