# Installing Contexture

Contexture is distributed as a direct download from the project's
[GitHub releases](https://github.com/ZhengHe-MD/contexture/releases). Every
release carries three files:

| File | What it is |
| --- | --- |
| `Contexture-<version>-macos-universal.zip` | The editor. Apple Silicon and Intel, macOS 14 or later. |
| `contexture-adapters-<version>-macos-universal.tar.gz` | The three Agent Adapters and their install scripts. Optional. |
| `SHA256SUMS.txt` | Checksums for the two archives. |

## 1. Install the app

Unzip the app and move it to `/Applications`.

**The build is not signed with an Apple Developer ID, so macOS will refuse
to open it until you say otherwise.** This project has no Developer ID and
therefore cannot notarize the app; clearing that block is a one-time step
you have to take yourself. Pick either way:

The one-liner — removes the quarantine flag macOS attached when your
browser downloaded the file:

```bash
xattr -dr com.apple.quarantine /Applications/Contexture.app
```

Or through the UI:

- **macOS 15 (Sequoia) and later** — double-click Contexture and let the
  warning appear. Open **System Settings → Privacy & Security**, scroll to
  the message about Contexture being blocked, and click **Open Anyway**.
- **macOS 14 (Sonoma)** — Control-click Contexture in Finder, choose
  **Open**, then **Open** again in the dialog.

Either way it is a once-per-install step. After it, Contexture launches
normally.

If you would rather not trust a binary you cannot verify against a
Developer ID, build it yourself instead — the result is the same app:

```bash
git clone https://github.com/ZhengHe-MD/contexture.git
cd contexture && ./scripts/build-app.sh release
```

## 2. Install an Agent Adapter (optional)

Contexture is a complete editor with no adapter installed. Install one only
for the Agent Host you actually use. Unpack the adapters archive and run the
script for your host — the binaries ship prebuilt, so no Swift toolchain is
needed:

```bash
tar -xzf contexture-adapters-<version>-macos-universal.tar.gz
cd contexture-adapters-<version>
./scripts/install-claude-code-adapter.sh
```

The other two are `install-codex-adapter.sh` and
`install-antigravity-adapter.sh`. All three need `jq` (`brew install jq`).

Each install script copies its binary to
`~/Library/Application Support/Contexture/bin` and registers it as a hook
with that Agent Host. Each has a matching `uninstall-*-adapter.sh` that
removes exactly what it added.

> The Codex adapter's config path is a best-effort guess, not a confirmed
> format — read the header comment in `install-codex-adapter.sh` before
> relying on it.

## Verifying a download

```bash
shasum -a 256 -c SHA256SUMS.txt
```

## Uninstalling

```bash
./scripts/uninstall-claude-code-adapter.sh   # and/or the other two
rm -rf /Applications/Contexture.app
```
