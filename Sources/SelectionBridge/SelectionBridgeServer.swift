import ContextureKit
import Foundation

/// Wires the wire protocol (publish/read/ack/clear) to a SelectionStore
/// over a Unix domain socket. This is the Bridge's process boundary — see
/// `publish(snapshot) -> version`, `clear`, `read`, `ack` in
/// docs/architecture/selection-bridge.md "Shape".
public final class SelectionBridgeServer {
    private let store: SelectionStore
    private let transport: UnixSocketServer

    public init(socketPath: String = BridgeLocation.defaultSocketPath(), store: SelectionStore = SelectionStore()) {
        self.store = store
        self.transport = UnixSocketServer(socketPath: socketPath)
    }

    public func start() throws {
        try transport.start { [store] request in
            Self.route(request, store: store)
        }
    }

    public func stop() {
        transport.stop()
    }

    /// The editor app hosts this server in-process, so it publishes
    /// directly rather than round-tripping through its own socket —
    /// Adapters, which run as separate processes, go through BridgeClient
    /// instead.
    @discardableResult
    public func publish(_ snapshot: SelectionSnapshot) -> Int {
        store.publish(snapshot)
    }

    public func clear(documentID: DocumentID, version: Int? = nil) {
        store.clear(documentID: documentID, version: version)
    }

    private static func route(_ request: HTTPRequest, store: SelectionStore) -> HTTPResponse {
        switch (request.method, request.path) {
        case ("POST", "/publish"):
            guard let decoded = try? JSONDecoder().decode(BridgePublishRequest.self, from: request.body) else {
                return .empty(400)
            }
            let version = store.publish(decoded.snapshot)
            return .json(200, BridgePublishResponse(version: version))

        case ("POST", "/read"):
            // Working Root scoping arrives with issue #8; every caller
            // sees every Armed snapshot until then.
            guard (try? JSONDecoder().decode(BridgeReadRequest.self, from: request.body)) != nil else {
                return .empty(400)
            }
            return .json(200, BridgeReadResponse(snapshots: store.read()))

        case ("POST", "/ack"):
            guard let decoded = try? JSONDecoder().decode(BridgeAckRequest.self, from: request.body) else {
                return .empty(400)
            }
            store.ack(snapshotIDs: decoded.snapshotIDs)
            return .empty(200)

        case ("POST", "/clear"):
            guard let decoded = try? JSONDecoder().decode(BridgeClearRequest.self, from: request.body) else {
                return .empty(400)
            }
            store.clear(documentID: decoded.documentID, version: decoded.version)
            return .empty(200)

        default:
            return .empty(404)
        }
    }
}
