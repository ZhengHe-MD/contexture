#!/usr/bin/env bash
# Resolves the executable for one Agent Adapter, covering both ways the
# install scripts get run:
#
#   - From a source checkout: there is a toolchain and there is source, so
#     build the product with SwiftPM, exactly as these scripts always did.
#   - From an unpacked release tarball: `bin/` sits next to `scripts/` and
#     there is neither source nor (necessarily) a Swift toolchain on the
#     machine, so use the prebuilt binary that shipped in the tarball.
#
# Callers source this file and call `resolve_adapter_binary <ProductName>`
# from the tree root; it echoes a path to a ready-to-copy executable and
# sends any build chatter to stderr so the path is the only thing on stdout.

resolve_adapter_binary() {
  local product="$1"
  local prebuilt_dir="${CONTEXTURE_PREBUILT_BIN_DIR:-bin}"

  if [ -x "$prebuilt_dir/$product" ]; then
    echo "$prebuilt_dir/$product"
    return 0
  fi

  if ! command -v swift >/dev/null 2>&1; then
    echo "error: no prebuilt $prebuilt_dir/$product to install, and no swift" \
         "toolchain to build one from source" >&2
    return 1
  fi

  swift build -c release --product "$product" >&2
  echo "$(swift build -c release --show-bin-path)/$product"
}
