import Foundation

/// Request/response bodies for the Bridge's HTTP-over-Unix-socket wire
/// protocol (docs/architecture/selection-bridge.md). Shared by
/// SelectionBridge (the server) and BridgeClient (the adapter-side client)
/// so the two sides can't drift apart on shape.
public struct BridgePublishRequest: Codable, Sendable {
    public let snapshot: SelectionSnapshot

    public init(snapshot: SelectionSnapshot) {
        self.snapshot = snapshot
    }
}

public struct BridgePublishResponse: Codable, Sendable {
    public let version: Int

    public init(version: Int) {
        self.version = version
    }
}

public struct BridgeReadRequest: Codable, Sendable {
    public let consumerID: String
    public let conversationID: String
    public let workingRoot: String?
    public let turnID: String?

    public init(consumerID: String, conversationID: String, workingRoot: String?, turnID: String?) {
        self.consumerID = consumerID
        self.conversationID = conversationID
        self.workingRoot = workingRoot
        self.turnID = turnID
    }
}

public struct BridgeReadResponse: Codable, Sendable {
    public let snapshots: [SelectionSnapshot]

    public init(snapshots: [SelectionSnapshot]) {
        self.snapshots = snapshots
    }
}

public struct BridgeAckRequest: Codable, Sendable {
    public let snapshotIDs: [SnapshotID]
    public let consumptionID: String

    public init(snapshotIDs: [SnapshotID], consumptionID: String) {
        self.snapshotIDs = snapshotIDs
        self.consumptionID = consumptionID
    }
}

public struct BridgeClearRequest: Codable, Sendable {
    public let documentID: DocumentID
    public let version: Int?

    public init(documentID: DocumentID, version: Int?) {
        self.documentID = documentID
        self.version = version
    }
}
