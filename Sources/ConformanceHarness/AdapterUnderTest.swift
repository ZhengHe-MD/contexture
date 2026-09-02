import Foundation

/// The neutral parameters one hook invocation needs, independent of which
/// Agent Host's stdin shape they end up mapped into.
public struct HarnessScenario: Sendable {
    /// An absolute directory path. Every in-scope Snapshot in a given case
    /// is published with an `absolutePath` under this.
    public let workingRoot: String
    public let conversationID: String
    public let turnID: String
    public let prompt: String

    public init(workingRoot: String, conversationID: String, turnID: String, prompt: String) {
        self.workingRoot = workingRoot
        self.conversationID = conversationID
        self.turnID = turnID
        self.prompt = prompt
    }
}

/// One hook invocation's outcome, reduced to what the 14 black-box cases
/// need: the model-visible injected context, if any, and the adapter's raw
/// stdout so the "no Contexture content at all" cases can check nothing
/// leaked anywhere in it, not just in the field a well-behaved adapter
/// would use.
public struct HookResult: Sendable {
    public let injectedContext: String?
    public let rawStdout: Data

    public init(injectedContext: String?, rawStdout: Data) {
        self.injectedContext = injectedContext
        self.rawStdout = rawStdout
    }
}

/// A black-box Agent Adapter: the harness only ever talks to it through its
/// real stdin/stdout contract, exactly as the real Agent Host would
/// (docs/architecture/selection-bridge.md "Test contract") — never through
/// `@testable import` or any Swift-level shortcut. A second and third
/// Adapter (issues #10, #11) implement this protocol once each; none of
/// the 14 cases themselves need to change.
public protocol AdapterUnderTest: Sendable {
    /// Used only in failure messages.
    var name: String { get }

    /// Runs one real hook invocation — a genuine subprocess launch of the
    /// compiled Adapter executable — against `bridgeSocketPath`. Every
    /// Adapter must honor `CONTEXTURE_BRIDGE_SOCKET` (or an equivalent
    /// override) so the harness can point an unmodified copy of it at a
    /// throwaway Bridge instead of the real per-user one.
    func invoke(scenario: HarnessScenario, bridgeSocketPath: String) throws -> HookResult
}
