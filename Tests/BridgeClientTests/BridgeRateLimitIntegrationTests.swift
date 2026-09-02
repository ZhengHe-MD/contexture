import ContextureKit
import Foundation
import SelectionBridge
import Testing
@testable import BridgeClient

/// Rate limiting (docs/architecture/selection-bridge.md "Local security
/// boundary": "Rate-limit reads") verified over the real transport, the
/// same way BridgeClientIntegrationTests verifies everything else — a
/// live SelectionBridgeServer on a real Unix domain socket, hit with real
/// HTTP requests. Uses `@testable import BridgeClient` to reach
/// `UnixSocketClient` directly: the public `BridgeClient` API deliberately
/// collapses every non-200 response (including 429) to an empty result
/// (fail-open), so observing the status code itself needs the lower-level
/// client.
@Suite struct BridgeRateLimitIntegrationTests {
    private func temporarySocketPath() -> String {
        "/tmp/ctx-\(UUID().uuidString.prefix(8)).sock"
    }

    @Test func requestsBeyondTheLimitReceive429() throws {
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path, rateLimiter: RateLimiter(maxRequestsPerWindow: 2, window: 60))
        try server.start()
        defer { server.stop() }

        let readRequest = try JSONEncoder().encode(
            BridgeReadRequest(consumerID: "test", conversationID: "conv-1", workingRoot: "/tmp", turnID: nil)
        )

        let first = UnixSocketClient.send(socketPath: path, method: "POST", path: "/read", jsonBody: readRequest, timeout: 2)
        let second = UnixSocketClient.send(socketPath: path, method: "POST", path: "/read", jsonBody: readRequest, timeout: 2)
        let third = UnixSocketClient.send(socketPath: path, method: "POST", path: "/read", jsonBody: readRequest, timeout: 2)

        #expect(first?.statusCode == 200)
        #expect(second?.statusCode == 200)
        #expect(third?.statusCode == 429)
    }

    @Test func aClientFacingReadSilentlyReturnsEmptyWhenRateLimited() throws {
        // The fail-open contract every Adapter depends on: rate-limited
        // looks identical to "nothing Armed" from BridgeClient's public API
        // — never a thrown error or a distinguishable failure a caller
        // could branch on.
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path, rateLimiter: RateLimiter(maxRequestsPerWindow: 1, window: 60))
        try server.start()
        defer { server.stop() }

        let client = BridgeClient(socketPath: path, timeout: 2)
        _ = client.read(consumerID: "test", conversationID: "conv-1", workingRoot: "/tmp", turnID: nil)
        let rateLimited = client.read(consumerID: "test", conversationID: "conv-1", workingRoot: "/tmp", turnID: nil)
        #expect(rateLimited.isEmpty)
    }
}
