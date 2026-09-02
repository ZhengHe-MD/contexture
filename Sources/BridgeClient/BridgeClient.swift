import ContextureKit
import Foundation

/// The Agent Adapter side of the Selection Bridge: reads Armed snapshots
/// and acknowledges Consumption. Every method fails silently (empty result,
/// no throw) on any transport problem — an absent Bridge or app is a
/// no-context condition, not an error an Adapter should ever surface.
public final class BridgeClient {
    private let socketPath: String
    private let timeout: TimeInterval

    public init(socketPath: String = BridgeLocation.defaultSocketPath(), timeout: TimeInterval = 1.5) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    /// Every Armed snapshot visible to this caller. Returns `[]` if the
    /// Bridge is unreachable, the app isn't running, or the response is
    /// malformed — an Adapter cannot distinguish these from "nothing is
    /// Armed" at the prompt boundary, by design.
    public func read(consumerID: String, conversationID: String, workingRoot: String?, turnID: String?) -> [SelectionSnapshot] {
        let request = BridgeReadRequest(
            consumerID: consumerID,
            conversationID: conversationID,
            workingRoot: workingRoot,
            turnID: turnID
        )
        guard let body = try? JSONEncoder().encode(request) else { return [] }
        guard let response = UnixSocketClient.send(
            socketPath: socketPath, method: "POST", path: "/read", jsonBody: body, timeout: timeout
        ) else { return [] }
        guard response.statusCode == 200 else { return [] }
        guard let decoded = try? JSONDecoder().decode(BridgeReadResponse.self, from: response.body) else { return [] }
        return decoded.snapshots
    }

    /// Marks the given snapshots Consumed so Next Prompt content cannot
    /// leak into a later prompt. Best-effort: a failure here just means
    /// the snapshot may be offered again, which is safe (at-most-once
    /// consumption is a Bridge-side invariant, not something the client
    /// can violate by failing to ack).
    public func ack(snapshotIDs: [SnapshotID], consumptionID: String) {
        let request = BridgeAckRequest(snapshotIDs: snapshotIDs, consumptionID: consumptionID)
        guard let body = try? JSONEncoder().encode(request) else { return }
        _ = UnixSocketClient.send(socketPath: socketPath, method: "POST", path: "/ack", jsonBody: body, timeout: timeout)
    }
}
