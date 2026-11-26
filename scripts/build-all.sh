#!/bin/sh
# End-to-end build pipeline for OpenCode (with native OpenTUI TUI) on Termux arm (armeabi-v7a, API 24+).
#
# Usage:
#   ANDROID_NDK_HOME=/path/to/ndk ZIG=/path/to/zig sh scripts/build-all.sh
#
# Optional overrides:
#   OPENCODE_REPO   Reuse an existing anomalyco/opencode checkout (default: work/opencode)
#   OPENTUI_SRC     Reuse an existing anomalyco/opentui checkout (default: work/opentui)
#   ANDROID_API     Target Android API level (default: 24)
#   OPTIMIZE        Zig optimize mode: ReleaseFast or ReleaseSmall (default: ReleaseFast)
#   SKIP_INSTALL    Set to 1 if bun install was already run in OPENCODE_REPO
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../versions.env
. "$HERE/versions.env"

export ANDROID_API="${ANDROID_API:-24}"
export WORK_DIR="${WORK_DIR:-$HERE/work}"
export OUT_DIR="${OUT_DIR:-$HERE/out}"
export OPENCODE_REPO="${OPENCODE_REPO:-$WORK_DIR/opencode}"
export OPENTUI_SRC="${OPENTUI_SRC:-$WORK_DIR/opentui}"
export ZIG="${ZIG:-zig}"
export BUNDLE_OUT="${BUNDLE_OUT:-$OUT_DIR/bundle}"
export OUT_LIB="${OUT_LIB:-$OUT_DIR/opentui/android-arm-api${ANDROID_API}/libopentui.so}"

echo "=== [1/4] Cross-compiling OpenTUI $OPENTUI_VERSION (arm-linux-androideabi.$ANDROID_API) ==="
sh "$HERE/scripts/build-opentui-android-arm.sh"

echo "=== [2/4] Preparing OpenCode $OPENCODE_VERSION workspace ==="
if [ ! -d "$OPENCODE_REPO/.git" ]; then
  mkdir -p "$(dirname "$OPENCODE_REPO")"
  git clone --depth 1 https://github.com/anomalyco/opencode.git "$OPENCODE_REPO"
  git -C "$OPENCODE_REPO" fetch --depth 1 origin "$OPENCODE_COMMIT" || true
  git -C "$OPENCODE_REPO" checkout "$OPENCODE_COMMIT"
fi

if [ "${SKIP_INSTALL:-0}" != "1" ] && [ ! -d "$OPENCODE_REPO/node_modules" ]; then
  bun install --cwd "$OPENCODE_REPO" --os='*' --cpu='*'
fi

echo "=== [3/4] Installing patched @opentui/core & bundling OpenCode for Node.js ==="
sh "$HERE/scripts/install-patched-opentui.sh"
OPENCODE_CLI="$OPENCODE_REPO/packages/cli" \
  OPENCODE_VERSION="$OPENCODE_VERSION" \
  BUNDLE_OUT="$BUNDLE_OUT" \
  bun "$HERE/scripts/bundle-opencode.ts"

echo "=== [4/4] Building Termux arm .deb package ==="
BUNDLE_DIR="$BUNDLE_OUT" \
  OPENTUI_LIB="$OUT_LIB" \
  sh "$HERE/scripts/build-termux-deb.sh"

echo "=== Build complete ==="
ls -lh "$OUT_DIR"/opencode_*_arm.deb
