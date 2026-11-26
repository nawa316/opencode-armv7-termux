#!/bin/sh
# Cross-compiles libopentui.so for Android 32-bit ARM (armeabi-v7a / arm-linux-androideabi, API 24+)
# using Zig 0.17.1 and Android NDK.
#
# Environment variables:
#   ANDROID_NDK_HOME  Path to Android NDK (e.g. ~/Android/Sdk/ndk/27.0.12077973) [required]
#   OPENTUI_SRC       Path to anomalyco/opentui checkout (default: work/opentui)
#   ZIG               Path to zig 0.17.1 binary (default: zig on PATH)
#   ANDROID_API       Target Android API level (default: 24)
#   OPTIMIZE          Zig optimize mode: ReleaseFast or ReleaseSmall (default: ReleaseFast)
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../versions.env
. "$HERE/versions.env"

ANDROID_API="${ANDROID_API:-24}"
OPTIMIZE="${OPTIMIZE:-ReleaseFast}"
ZIG="${ZIG:-zig}"
WORK_DIR="${WORK_DIR:-$HERE/work}"
OUT_DIR="${OUT_DIR:-$HERE/out}"
OPENTUI_SRC="${OPENTUI_SRC:-$WORK_DIR/opentui}"
OUT_LIB="${OUT_LIB:-$OUT_DIR/opentui/android-arm-api${ANDROID_API}/libopentui.so}"

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  # Try common Android NDK locations automatically
  for candidate in \
    "${ANDROID_NDK_ROOT:-}" \
    "$HOME/Android/Sdk/ndk/"* \
    "/usr/local/lib/android/sdk/ndk/"* \
    "/opt/android-ndk"*; do
    if [ -d "$candidate/toolchains/llvm/prebuilt" ]; then
      ANDROID_NDK_HOME="$candidate"
      break
    fi
  done
fi

if [ -z "${ANDROID_NDK_HOME:-}" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
  echo "Error: ANDROID_NDK_HOME not found. Set ANDROID_NDK_HOME to your Android NDK r26/r27 directory." >&2
  exit 1
fi

SYSROOT=$(ls -d "$ANDROID_NDK_HOME"/toolchains/llvm/prebuilt/*/sysroot 2>/dev/null | head -1)
if [ -z "$SYSROOT" ] || [ ! -d "$SYSROOT/usr/lib/arm-linux-androideabi/$ANDROID_API" ]; then
  echo "Error: Android NDK sysroot for arm-linux-androideabi API $ANDROID_API not found under $ANDROID_NDK_HOME" >&2
  exit 1
fi

ZIG_ACTUAL=$("$ZIG" version)
if [ "$ZIG_ACTUAL" != "$ZIG_VERSION" ]; then
  echo "Error: OpenTUI $OPENTUI_VERSION requires Zig $ZIG_VERSION, found $ZIG_ACTUAL (ZIG=$ZIG)" >&2
  exit 1
fi

# Clone pinned OpenTUI if needed
if [ ! -d "$OPENTUI_SRC/.git" ]; then
  mkdir -p "$(dirname "$OPENTUI_SRC")"
  GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 https://github.com/anomalyco/opentui.git "$OPENTUI_SRC"
  git -C "$OPENTUI_SRC" fetch --depth 1 origin "$OPENTUI_COMMIT" || true
  git -C "$OPENTUI_SRC" checkout "$OPENTUI_COMMIT"
fi

# Reset and apply Android ARMv7a patches idempotently
git -C "$OPENTUI_SRC" checkout -- .
for patch in "$HERE"/patches/opentui/*.patch; do
  echo "[build-opentui] applying $(basename "$patch")"
  git -C "$OPENTUI_SRC" apply "$patch"
done

# Prepare vendored Zig dependencies (yoga, uucode, etc.)
sh "$OPENTUI_SRC/packages/native/scripts/prepare-zig-deps.sh"

# Generate Zig 0.17.1 --libc configuration file for Android NDK API level
mkdir -p "$WORK_DIR"
LIBC_FILE="$WORK_DIR/android-arm-api${ANDROID_API}.libc"
cat > "$LIBC_FILE" <<EOF
include_dir=$SYSROOT/usr/include
sys_include_dir=$SYSROOT/usr/include/arm-linux-androideabi
cc_dir=$SYSROOT/usr/lib/arm-linux-androideabi/$ANDROID_API
crt_dir=$SYSROOT/usr/lib/arm-linux-androideabi/$ANDROID_API
msvc_lib_dir=
kernel32_lib_dir=
darwin_sdk_dir=
EOF

TARGET="arm-linux-androideabi.${ANDROID_API}"
echo "[build-opentui] compiling libopentui.so for $TARGET ($OPTIMIZE)..."
(
  cd "$OPENTUI_SRC/packages/native"
  "$ZIG" build \
    -Doptimize="$OPTIMIZE" \
    -Dvideo=false \
    -Dlibrary-target="$TARGET" \
    -Dlibc-file="$LIBC_FILE" \
    -Dandroid-sysroot="$SYSROOT"
)

BUILT_LIB="$OPENTUI_SRC/packages/native/lib/$TARGET/libopentui.so"
mkdir -p "$(dirname "$OUT_LIB")"
cp "$BUILT_LIB" "$OUT_LIB"

# Verify ELF architecture, Bionic DT_NEEDED, and API level symbols
echo "[build-opentui] auditing ELF: $OUT_LIB"
if command -v readelf >/dev/null 2>&1; then
  readelf -h "$OUT_LIB" | grep -E "Class:|Machine:|Flags:"
  NEEDED=$(readelf -d "$OUT_LIB" | awk '/\(NEEDED\)/ {print $5}')
  echo "[build-opentui] DT_NEEDED: $NEEDED"
  if echo "$NEEDED" | grep -qvE '^\[(libc\.so|libm\.so|libdl\.so)\]$'; then
    echo "Error: unexpected DT_NEEDED library in $OUT_LIB: $NEEDED" >&2
    exit 1
  fi
  OT_COUNT=$(readelf --dyn-syms -W "$OUT_LIB" | grep -c " ot_")
  echo "[build-opentui] exported ot_* symbols: $OT_COUNT"
fi

# Verify all 101 C ABI struct layouts on arm-linux-androideabi.<API>
ZIG_DIR=$(dirname "$(command -v "$ZIG")")
PATH="$ZIG_DIR:$PATH" \
  OPENTUI_SRC="$OPENTUI_SRC" \
  ANDROID_SYSROOT="$SYSROOT" \
  ANDROID_API="$ANDROID_API" \
  ZIG="$ZIG" \
  bun "$HERE/scripts/verify-arm32-abi.ts"

echo "[build-opentui] OK: $OUT_LIB ($(du -h "$OUT_LIB" | cut -f1))"
