import Foundation
import Testing
@testable import ContextureApp

@Suite struct AdapterInstallStatusTests {
    @Test func registersTrueWhenTheCommandIsPresentUnderTheEvent() {
        let json = Data("""
        {"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/bin/adapter"}]}]}}
        """.utf8)
        #expect(AdapterInstallStatus.hooksConfigRegisters(json, eventName: "UserPromptSubmit", binaryPath: "/bin/adapter"))
    }

    @Test func registersFalseWhenTheCommandDiffers() {
        let json = Data("""
        {"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"/bin/other"}]}]}}
        """.utf8)
        #expect(!AdapterInstallStatus.hooksConfigRegisters(json, eventName: "UserPromptSubmit", binaryPath: "/bin/adapter"))
    }

    @Test func registersFalseWhenTheEventIsAbsent() {
        let json = Data("""
        {"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"/bin/adapter"}]}]}}
        """.utf8)
        #expect(!AdapterInstallStatus.hooksConfigRegisters(json, eventName: "UserPromptSubmit", binaryPath: "/bin/adapter"))
    }

    @Test func registersFalseWhenHooksKeyIsMissingEntirely() {
        let json = Data("""
        {"model":"opus"}
        """.utf8)
        #expect(!AdapterInstallStatus.hooksConfigRegisters(json, eventName: "UserPromptSubmit", binaryPath: "/bin/adapter"))
    }

    @Test func registersFalseForMalformedJSON() {
        #expect(!AdapterInstallStatus.hooksConfigRegisters(Data("not json".utf8), eventName: "UserPromptSubmit", binaryPath: "/bin/adapter"))
    }

    @Test func registersTrueAmongMultipleUnrelatedHookEntries() {
        // Mirrors what a real settings file looks like once other tools
        // have registered their own hooks alongside this one.
        let json = Data("""
        {"hooks":{"UserPromptSubmit":[
            {"hooks":[{"type":"command","command":"/bin/unrelated-tool"}]},
            {"hooks":[{"type":"command","command":"/bin/adapter"}]}
        ]}}
        """.utf8)
        #expect(AdapterInstallStatus.hooksConfigRegisters(json, eventName: "UserPromptSubmit", binaryPath: "/bin/adapter"))
    }

    @Test func registersAntigravityRootLevelNamedHook() {
        let json = Data("""
        {"contexture-selection":{"PreInvocation":[
            {"type":"command","command":"'/path with spaces/adapter'","timeout":5}
        ]}}
        """.utf8)
        #expect(AdapterInstallStatus.hooksConfigRegisters(json, eventName: "PreInvocation", binaryPath: "/path with spaces/adapter"))
    }

    // MARK: KnownAdapters.compatibility(for:) — real file I/O against scratch paths

    private func scratchDescriptor(registered: Bool, binaryExists: Bool = true) -> AdapterDescriptor {
        let id = UUID().uuidString.prefix(8)
        let binaryPath = "/tmp/ctx-diag-bin-\(id)"
        let configPath = "/tmp/ctx-diag-config-\(id).json"
        if binaryExists {
            FileManager.default.createFile(atPath: binaryPath, contents: Data(), attributes: [.posixPermissions: 0o755])
        }
        let hooksArray = registered
            ? #"[{"hooks":[{"type":"command","command":"\#(binaryPath)"}]}]"#
            : "[]"
        let json = #"{"hooks":{"UserPromptSubmit":\#(hooksArray)}}"#
        try? json.write(toFile: configPath, atomically: true, encoding: .utf8)
        return AdapterDescriptor(name: "Test", binaryPath: binaryPath, configPath: configPath, hookEventName: "UserPromptSubmit")
    }

    @Test func compatibilityIsDeterministicWhenBinaryExistsAndConfigRegistersIt() {
        let descriptor = scratchDescriptor(registered: true)
        defer {
            try? FileManager.default.removeItem(atPath: descriptor.binaryPath)
            try? FileManager.default.removeItem(atPath: descriptor.configPath)
        }
        #expect(KnownAdapters.compatibility(for: descriptor) == .deterministic)
    }

    @Test func compatibilityIsNotInstalledWhenConfigDoesNotRegisterTheBinary() {
        let descriptor = scratchDescriptor(registered: false)
        defer {
            try? FileManager.default.removeItem(atPath: descriptor.binaryPath)
            try? FileManager.default.removeItem(atPath: descriptor.configPath)
        }
        #expect(KnownAdapters.compatibility(for: descriptor) == .notInstalled)
    }

    @Test func compatibilityIsNotInstalledWhenTheBinaryIsMissingEvenIfConfigRegistersIt() {
        // A stale hook entry pointing at a binary that was removed some
        // other way (a manual `rm`, not through the uninstall script) must
        // not be reported as Deterministic.
        let descriptor = scratchDescriptor(registered: true, binaryExists: false)
        defer { try? FileManager.default.removeItem(atPath: descriptor.configPath) }
        #expect(KnownAdapters.compatibility(for: descriptor) == .notInstalled)
    }

    @Test func compatibilityIsNotInstalledWhenNeitherBinaryNorConfigExist() {
        let descriptor = AdapterDescriptor(
            name: "Test",
            binaryPath: "/tmp/ctx-diag-does-not-exist-\(UUID().uuidString)",
            configPath: "/tmp/ctx-diag-does-not-exist-\(UUID().uuidString).json",
            hookEventName: "UserPromptSubmit"
        )
        #expect(KnownAdapters.compatibility(for: descriptor) == .notInstalled)
    }

    @Test func threeKnownAdaptersAreDescribed() {
        let names = Set(KnownAdapters.descriptors().map(\.name))
        #expect(names == ["Claude Code", "Codex", "Antigravity"])
    }
}
