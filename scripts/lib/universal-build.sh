#!/usr/bin/env bash
# Builds SwiftPM products for one or more architectures and fuses them into
# universal binaries.
#
# Why per-arch builds instead of `swift build --arch arm64 --arch x86_64`:
# that single-invocation form routes through xcbuild, which only exists in a
# full Xcode install. Building each architecture in its own invocation stays
# on SwiftPM's native build system, which works with the Command Line Tools
# alone — so the same script runs on a contributor's machine and on CI.
# `lipo` then does the fusing that xcbuild would have done.
#
# Callers source this file from the tree root and use:
#   contexture_build <config> [arch...]   -> fills CONTEXTURE_BIN_DIRS
#   contexture_fuse <product> <output> "${CONTEXTURE_BIN_DIRS[@]}"

# Bin directories produced by the most recent contexture_build, in the order
# the architectures were given. With no architectures it holds the single
# native bin directory.
CONTEXTURE_BIN_DIRS=()

contexture_build() {
  local config="$1"
  shift
  CONTEXTURE_BIN_DIRS=()

  if [ "$#" -eq 0 ]; then
    swift build --configuration "$config" >&2
    CONTEXTURE_BIN_DIRS=("$(swift build --configuration "$config" --show-bin-path)")
    return 0
  fi

  local arch
  for arch in "$@"; do
    echo "== building $arch ($config) ==" >&2
    swift build --configuration "$config" --arch "$arch" >&2
    CONTEXTURE_BIN_DIRS+=("$(swift build --configuration "$config" --arch "$arch" --show-bin-path)")
  done
}

contexture_fuse() {
  local product="$1" output="$2"
  shift 2

  local inputs=() dir
  for dir in "$@"; do
    inputs+=("$dir/$product")
  done

  if [ "${#inputs[@]}" -eq 1 ]; then
    cp "${inputs[0]}" "$output"
  else
    lipo -create -output "$output" "${inputs[@]}"
  fi
  chmod +x "$output"
}
