import ConformanceHarness
import Testing

/// Registers the Antigravity Adapter against the shared black-box
/// conformance harness (issue #9) — the 14 cases from
/// docs/architecture/selection-bridge.md's "Test contract", run against a
/// throwaway Bridge and a real subprocess launch of the compiled
/// executable. Nothing about those cases is reimplemented here — mirrors
/// Tests/ClaudeCodeAdapterTests/ClaudeCodeAdapterConformanceTests.swift.
@Suite struct AntigravityAdapterConformanceTests {
    @Test func passesTheSharedBlackBoxConformanceSuite() throws {
        guard let executableURL = AdapterBinaryLocator.find(named: "AntigravityAdapter") else {
            Issue.record("could not locate the compiled AntigravityAdapter binary next to the test bundle")
            return
        }
        let adapter = AntigravityAdapterUnderTest(executableURL: executableURL)
        let results = try ConformanceHarness.run(adapter: adapter)
        for result in results {
            #expect(result.passed, "\(result.name): \(result.detail)")
        }
    }
}
