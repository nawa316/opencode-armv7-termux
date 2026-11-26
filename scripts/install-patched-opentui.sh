#!/bin/sh
# Builds patched @opentui/core JavaScript library (with android-arm asset target support)
# and installs it into the anomalyco/opencode checkout's node_modules before Vite bundling.
#
# Environment variables:
#   OPENCODE_REPO  Path to anomalyco/opencode checkout (default: work/opencode)
#   OPENTUI_SRC    Path to anomalyco/opentui checkout (default: work/opentui)
#   ZIG            Path to zig 0.17.1 binary (default: zig on PATH)
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
OPENCODE_REPO="${OPENCODE_REPO:-$HERE/work/opencode}"
OPENTUI_SRC="${OPENTUI_SRC:-$HERE/work/opentui}"
ZIG="${ZIG:-zig}"

if [ ! -d "$OPENTUI_SRC/packages/core" ]; then
  echo "Error: OPENTUI_SRC not found at $OPENTUI_SRC" >&2
  exit 1
fi
if [ ! -d "$OPENCODE_REPO/node_modules" ]; then
  echo "Error: OPENCODE_REPO/node_modules not found at $OPENCODE_REPO (run bun install first)" >&2
  exit 1
fi

# Ensure patch 0003 is applied
if ! git -C "$OPENTUI_SRC" apply --check -R "$HERE/patches/opentui/0003-core-android-arm-asset-target.patch" 2>/dev/null; then
  git -C "$OPENTUI_SRC" apply "$HERE/patches/opentui/0003-core-android-arm-asset-target.patch"
fi

if [ ! -d "$OPENTUI_SRC/node_modules" ]; then
  bun install --cwd "$OPENTUI_SRC"
fi

ZIG_DIR=$(dirname "$(command -v "$ZIG")")
echo "[install-patched-opentui] building @opentui/core JS dist..."
(
  cd "$OPENTUI_SRC/packages/core"
  PATH="$ZIG_DIR:$PATH" bun scripts/build.ts --lib
)

DEST=$(ls -d "$OPENCODE_REPO"/node_modules/.bun/@opentui+core@*/node_modules/@opentui/core 2>/dev/null | head -1)
if [ -z "$DEST" ] || [ ! -d "$DEST" ]; then
  DEST="$OPENCODE_REPO/node_modules/@opentui/core"
fi
if [ ! -d "$DEST" ]; then
  echo "Error: could not locate @opentui/core inside $OPENCODE_REPO/node_modules" >&2
  exit 1
fi

cp -r "$OPENTUI_SRC/packages/core/dist/." "$DEST/"
echo "[install-patched-opentui] installed patched @opentui/core into: $DEST"
