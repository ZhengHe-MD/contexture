import ConformanceHarness
import Testing

/// Registers the Claude Code Adapter against the shared black-box
/// conformance harness (issue #9) — the 14 cases from
/// docs/architecture/selection-bridge.md's "Test contract", run against a
/// throwaway Bridge and a real subprocess launch of the compiled
/// executable. Nothing about those cases is reimplemented here; a second
/// and third Adapter (issues #10, #11) register the same way, from their
/// own test targets.
@Suite struct ClaudeCodeAdapterConformanceTests {
    @Test func passesTheSharedBlackBoxConformanceSuite() throws {
        guard let executableURL = AdapterBinaryLocator.find(named: "ClaudeCodeAdapter") else {
            Issue.record("could not locate the compiled ClaudeCodeAdapter binary next to the test bundle")
            return
        }
        let adapter = ClaudeCodeAdapterUnderTest(executableURL: executableURL)
        let results = try ConformanceHarness.run(adapter: adapter)
        for result in results {
            #expect(result.passed, "\(result.name): \(result.detail)")
        }
    }
}
