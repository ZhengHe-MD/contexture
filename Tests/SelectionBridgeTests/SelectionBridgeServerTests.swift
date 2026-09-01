import Foundation
import Testing
@testable import SelectionBridge

@Suite struct SelectionBridgeServerTests {
    private func temporarySocketPath() -> String {
        // sockaddr_un.sun_path is a hard 104-byte kernel limit on macOS —
        // FileManager.default.temporaryDirectory (a long per-process
        // /var/folders/.../T/ path) plus a full UUID reliably exceeds it,
        // so this uses /tmp directly with a short random suffix instead.
        "/tmp/ctx-\(UUID().uuidString.prefix(8)).sock"
    }

    @Test func socketIsCreatedAtUserOnlyPermissions() throws {
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path)
        try server.start()
        defer { server.stop() }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test func stopRemovesTheSocketFile() throws {
        let path = temporarySocketPath()
        let server = SelectionBridgeServer(socketPath: path)
        try server.start()
        #expect(FileManager.default.fileExists(atPath: path))
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func startingTwiceAtTheSamePathDoesNotThrow() throws {
        // A stale socket file left over from a crashed previous run must
        // not block a fresh start.
        let path = temporarySocketPath()
        let first = SelectionBridgeServer(socketPath: path)
        try first.start()
        first.stop()

        let second = SelectionBridgeServer(socketPath: path)
        try second.start()
        defer { second.stop() }
        #expect(FileManager.default.fileExists(atPath: path))
    }
}
