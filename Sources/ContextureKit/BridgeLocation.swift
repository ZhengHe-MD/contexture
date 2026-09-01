import Foundation

/// Where the Bridge's Unix domain socket lives. A single, well-known,
/// per-user path — Agent Adapters have no other way to discover it.
public enum BridgeLocation {
    public static func defaultSocketPath() -> String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Contexture", isDirectory: true)
        return dir.appendingPathComponent("bridge.sock").path
    }
}
