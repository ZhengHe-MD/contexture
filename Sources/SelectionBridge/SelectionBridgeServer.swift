import ContextureKit
import Foundation

/// Opaque handle for a registration made with
/// `SelectionBridgeServer.addArmedChangeObserver(_:)`. Keep it and pass it
/// to `removeArmedChangeObserver(_:)` when the observer goes away (e.g. a
/// window closing) to avoid leaking its closure.
public struct ArmedChangeObserverToken: Sendable, Hashable {
    fileprivate let id = UUID()

    public init() {}
}

/// Wires the wire protocol (publish/read/ack/clear) to a SelectionStore
/// over a Unix domain socket. This is the Bridge's process boundary — see
/// `publish(snapshot) -> version`, `clear`, `read`, `ack` in
/// docs/architecture/selection-bridge.md "Shape".
public final class SelectionBridgeServer {
    private let store: SelectionStore
    private let transport: UnixSocketServer

    // SelectionStore has no observation API of its own (issue #6's design
    // note deliberately keeps that core API untouched so it doesn't overlap
    // with issue #7's work there) — this is a thin, additive notification
    // layer above it so a UI observer (e.g. a window's persistent Armed
    // indicator, docs/product.md "Arming") can refresh without polling.
    // Several windows/Documents can be open at once, so this supports many
    // observers rather than a single closure.
    private let observersLock = NSLock()
    private var armedChangeObservers: [UUID: () -> Void] = [:]

    public init(socketPath: String = BridgeLocation.defaultSocketPath(), store: SelectionStore = SelectionStore()) {
        self.store = store
        self.transport = UnixSocketServer(socketPath: socketPath)
    }

    public func start() throws {
        try transport.start { [weak self, store] request in
            let response = Self.route(request, store: store)
            if Self.mutatesArming(request.path) {
                self?.notifyArmedChangeObservers()
            }
            return response
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
        let version = store.publish(snapshot)
        notifyArmedChangeObservers()
        return version
    }

    public func clear(documentID: DocumentID, version: Int? = nil) {
        store.clear(documentID: documentID, version: version)
        notifyArmedChangeObservers()
    }

    /// Whether `documentID` currently has an Armed, non-empty Snapshot —
    /// the same predicate `read()` applies (docs/architecture/
    /// selection-bridge.md "Injection decision"), scoped to one Document.
    /// Built on the existing `read()` rather than a new SelectionStore
    /// query, so the store's core API stays untouched.
    public func isArmed(documentID: DocumentID) -> Bool {
        store.read().contains { $0.documentID == documentID }
    }

    /// Registers a callback invoked after `publish`, `clear`, or `ack`
    /// (in-process or over the socket) changes what's Armed. Called on
    /// whatever thread the mutation happened on — an AppKit observer must
    /// hop to the main queue itself before touching UI.
    @discardableResult
    public func addArmedChangeObserver(_ observer: @escaping () -> Void) -> ArmedChangeObserverToken {
        let token = ArmedChangeObserverToken()
        observersLock.lock()
        armedChangeObservers[token.id] = observer
        observersLock.unlock()
        return token
    }

    /// Removes a callback registered with `addArmedChangeObserver(_:)`.
    public func removeArmedChangeObserver(_ token: ArmedChangeObserverToken) {
        observersLock.lock()
        armedChangeObservers.removeValue(forKey: token.id)
        observersLock.unlock()
    }

    private func notifyArmedChangeObservers() {
        observersLock.lock()
        let observers = Array(armedChangeObservers.values)
        observersLock.unlock()
        for observer in observers {
            observer()
        }
    }

    private static func mutatesArming(_ path: String) -> Bool {
        path == "/publish" || path == "/clear" || path == "/ack"
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
