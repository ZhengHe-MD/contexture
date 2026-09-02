import Foundation

/// Per-host compatibility, reported honestly rather than flattened into one
/// supported badge (docs/product.md "Distribution direction" / issue #12).
/// Every Adapter this app ships today is Deterministic once installed
/// (docs/research/agent-compatibility.md's compatibility matrix) — Best
/// Effort exists here for a future host whose only integration seam is
/// non-deterministic (Cursor, Windsurf, per that same matrix), not for any
/// of the three current Adapters.
enum AdapterCompatibility: String {
    case deterministic = "Deterministic"
    case bestEffort = "Best Effort"
    case notInstalled = "Not Installed"
}

enum AdapterInstallStatus {
    /// True if `configJSON` registers `binaryPath` as a hook command under
    /// `eventName`. Claude Code/Codex use a nested settings-style shape;
    /// Antigravity uses named hook definitions at the root of hooks.json.
    /// Keeping both checks here lets Diagnostics report the installed state
    /// without flattening the hosts' actual configuration contracts.
    static func hooksConfigRegisters(_ configJSON: Data, eventName: String, binaryPath: String) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: configJSON) as? [String: Any],
              !json.isEmpty else { return false }

        // Claude Code/Codex settings-style registration.
        if let hooks = json["hooks"] as? [String: Any],
           let eventEntries = hooks[eventName] as? [[String: Any]],
           eventEntries.contains(where: { entry in
               guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
               return innerHooks.contains { command($0["command"] as? String, invokes: binaryPath) }
           }) {
            return true
        }

        // Antigravity plugin hooks.json: named hook definitions at the root,
        // with PreInvocation handlers directly under the event key.
        return json.values.contains { value in
            guard let definition = value as? [String: Any],
                  let handlers = definition[eventName] as? [[String: Any]] else { return false }
            return handlers.contains { command($0["command"] as? String, invokes: binaryPath) }
        }
    }

    private static func command(_ command: String?, invokes binaryPath: String) -> Bool {
        guard let command else { return false }
        return command == binaryPath || command == "\"\(binaryPath)\"" || command == "'\(binaryPath)'"
    }
}

/// One row of the Diagnostics report: a known Adapter, where its installed
/// binary and host config are expected to live, and how to recognize
/// registration in that config's JSON shape.
struct AdapterDescriptor {
    let name: String
    let binaryPath: String
    let configPath: String
    let hookEventName: String
}

enum KnownAdapters {
    static func descriptors() -> [AdapterDescriptor] {
        let installDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Contexture")
            .appendingPathComponent("bin")
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            AdapterDescriptor(
                name: "Claude Code",
                binaryPath: installDir.appendingPathComponent("claude-code-adapter").path,
                configPath: home.appendingPathComponent(".claude/settings.json").path,
                hookEventName: "UserPromptSubmit"
            ),
            AdapterDescriptor(
                name: "Codex",
                binaryPath: installDir.appendingPathComponent("codex-adapter").path,
                configPath: home.appendingPathComponent(".codex/config.json").path,
                hookEventName: "UserPromptSubmit"
            ),
            AdapterDescriptor(
                name: "Antigravity",
                binaryPath: installDir.appendingPathComponent("antigravity-adapter").path,
                configPath: home.appendingPathComponent(".gemini/config/plugins/contexture-adapter/hooks.json").path,
                hookEventName: "PreInvocation"
            ),
        ]
    }

    /// The binary must exist *and* the relevant host config must actually
    /// register it — a leftover binary from a stale/partial install with
    /// no active hook registration is "Not Installed," not "Deterministic."
    static func compatibility(for descriptor: AdapterDescriptor) -> AdapterCompatibility {
        guard FileManager.default.isExecutableFile(atPath: descriptor.binaryPath),
              let configData = FileManager.default.contents(atPath: descriptor.configPath),
              AdapterInstallStatus.hooksConfigRegisters(configData, eventName: descriptor.hookEventName, binaryPath: descriptor.binaryPath)
        else {
            return .notInstalled
        }
        return .deterministic
    }
}
