import ConformanceHarness
import ContextureKit
import Foundation
import SelectionBridge
import Testing

/// The concrete, adapter-specific version of the risk issue #11's body
/// calls out by name: "the specific risk of shipping three adapters
/// together... expose a flaw in the Bridge's Consumption keying rather
/// than in the adapter itself." The shared 14-case harness already covers
/// "repeated hook call in the same turn" generically (case 5, exactly
/// two calls), which this Adapter also passes unmodified via
/// AntigravityAdapterConformanceTests. This test goes further: it drives
/// *three* real `PreInvocation`-shaped subprocess invocations, all keyed
/// to the same turn identity — matching Antigravity's documented
/// behavior of firing before *each* model call within a single user
/// task — against a real throwaway Bridge, and asserts the Selection
/// Context is injected on exactly the first call and `injectSteps` is
/// literally absent (not empty, not null) on every later one.
@Suite struct AntigravityAdapterMultiInvocationTests {
    @Test func onlyTheFirstOfSeveralPreInvocationCallsInOneTurnInjects() throws {
        guard let executableURL = AdapterBinaryLocator.find(named: "AntigravityAdapter") else {
            Issue.record("could not locate the compiled AntigravityAdapter binary next to the test bundle")
            return
        }
        let adapter = AntigravityAdapterUnderTest(executableURL: executableURL)

        let socketPath = "/tmp/ctx-antigravity-multi-\(UUID().uuidString.prefix(8)).sock"
        let server = SelectionBridgeServer(socketPath: socketPath)
        try server.start()
        defer { server.stop() }

        let workingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ctx-antigravity-multi-root-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: workingRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workingRoot) }

        let text = "selected once per turn, regardless of model call count"
        let data = Data(text.utf8)
        server.publish(SelectionSnapshot(
            documentID: DocumentID(),
            sourceBytes: data,
            format: .markdown,
            relativePath: "notes.md",
            absolutePath: workingRoot.appendingPathComponent("notes.md").path,
            revision: RevisionHash(contentBytes: data),
            byteRange: SourceByteRange(lowerBound: 0, upperBound: data.count),
            sharingMode: .nextPrompt,
            createdAt: Date(),
            sourceWindow: SourceWindowID(),
            version: 1
        ))

        // Every call below reuses the same conversationID/turnID — the
        // same armed Snapshot, several PreInvocation calls, one turn.
        let scenario = HarnessScenario(
            workingRoot: workingRoot.path,
            conversationID: "conv-multi-invocation",
            turnID: "turn-multi-invocation",
            prompt: "one of several model calls inside a single user task"
        )

        let first = try adapter.invoke(scenario: scenario, bridgeSocketPath: socketPath)
        let second = try adapter.invoke(scenario: scenario, bridgeSocketPath: socketPath)
        let third = try adapter.invoke(scenario: scenario, bridgeSocketPath: socketPath)

        #expect(first.injectedContext?.contains(text) == true, "expected injection on the first PreInvocation call of the turn")
        #expect(second.injectedContext == nil, "a second PreInvocation call in the same turn must not inject again")
        #expect(third.injectedContext == nil, "a third PreInvocation call in the same turn must not inject again")

        // "omits injectSteps entirely" is a stronger claim than
        // "injectedContext is nil" — assert the raw JSON has no
        // injectSteps key at all on both repeats, not an empty array or
        // a null field.
        for rawStdout in [second.rawStdout, third.rawStdout] {
            let json = try #require(try JSONSerialization.jsonObject(with: rawStdout) as? [String: Any])
            #expect(json.index(forKey: "injectSteps") == nil, "expected injectSteps entirely absent, got: \(json)")
        }
    }
}
