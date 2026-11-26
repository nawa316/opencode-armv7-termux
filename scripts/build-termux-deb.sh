#!/bin/sh
# Packages the bundled OpenCode JS + assets + Android armv7a libopentui.so + Termux launcher
# into a Termux .deb package (Architecture: arm, Android API 24+).
#
# Environment variables:
#   BUNDLE_DIR    Directory containing opencode.mjs and assets/ (default: out/bundle)
#   OPENTUI_LIB   Path to arm-linux-androideabi.24 libopentui.so (default: out/opentui/android-arm-api24/libopentui.so)
#   OUT_DEB       Output .deb path (default: out/opencode_<version>-<rev>_arm.deb)
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=../versions.env
. "$HERE/versions.env"

ANDROID_API="${ANDROID_API:-24}"
OUT_DIR="${OUT_DIR:-$HERE/out}"
BUNDLE_DIR="${BUNDLE_DIR:-$OUT_DIR/bundle}"
OPENTUI_LIB="${OPENTUI_LIB:-$OUT_DIR/opentui/android-arm-api${ANDROID_API}/libopentui.so}"
OUT_DEB="${OUT_DEB:-$OUT_DIR/opencode_${OPENCODE_VERSION}-${PACKAGE_REVISION}_arm.deb}"

if [ ! -f "$BUNDLE_DIR/opencode.mjs" ]; then
  echo "Error: missing bundle $BUNDLE_DIR/opencode.mjs" >&2
  exit 1
fi
if [ ! -f "$OPENTUI_LIB" ]; then
  echo "Error: missing Android armv7a native library $OPENTUI_LIB" >&2
  exit 1
fi

STAGE="$OUT_DIR/deb-root"
PREFIX_DIR="$STAGE/data/data/com.termux/files/usr"
APP_DIR="$PREFIX_DIR/lib/opencode"

rm -rf "$STAGE"
mkdir -p "$PREFIX_DIR/bin" "$APP_DIR/assets/@opentui/core-android-arm" "$STAGE/DEBIAN"

cp "$BUNDLE_DIR/opencode.mjs" "$APP_DIR/opencode.mjs"
cp -r "$BUNDLE_DIR/assets/." "$APP_DIR/assets/"
cp "$OPENTUI_LIB" "$APP_DIR/assets/@opentui/core-android-arm/libopentui.so"
chmod 755 "$APP_DIR/assets/@opentui/core-android-arm/libopentui.so"

cp "$HERE/termux/opencode" "$PREFIX_DIR/bin/opencode"
chmod 755 "$PREFIX_DIR/bin/opencode"

INSTALLED_SIZE=$(du -sk "$STAGE/data" | cut -f1)

cat > "$STAGE/DEBIAN/control" <<EOF
Package: opencode
Version: ${OPENCODE_VERSION}-${PACKAGE_REVISION}
Architecture: arm
Maintainer: opencode-armv7-termux contributors <https://github.com/anomalyco/opencode>
Installed-Size: ${INSTALLED_SIZE}
Depends: nodejs (>= ${NODE_MIN_VERSION}), ripgrep
Recommends: git
Section: devel
Priority: optional
Homepage: https://github.com/anomalyco/opencode
Description: OpenCode CLI, TUI (OpenTUI), and v2 server for Termux armv7a
 Native Termux build of anomalyco/opencode ${OPENCODE_VERSION} with cross-compiled
 OpenTUI (${OPENTUI_VERSION}) for 32-bit ARM Android (armeabi-v7a, API ${ANDROID_API}+).
 Includes interactive Terminal UI, syntax highlighting WASM parsers, and v2 API server,
 tuned for older 32-bit Android devices with limited RAM (<= 2 GB).
EOF

cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
set -e
NODE="/data/data/com.termux/files/usr/bin/node"
if [ -x "$NODE" ] && ! "$NODE" --experimental-ffi -e "" >/dev/null 2>&1; then
  echo "Note: Your Termux Node.js does not support --experimental-ffi yet."
  echo "Run 'pkg update && pkg upgrade nodejs' (Node.js >= 26.4.0) to use the OpenCode TUI."
fi
exit 0
EOF
chmod 755 "$STAGE/DEBIAN/postinst"

mkdir -p "$(dirname "$OUT_DEB")"
dpkg-deb --root-owner-group -Zxz --build "$STAGE" "$OUT_DEB"
echo "[build-termux-deb] OK: $OUT_DEB ($(du -h "$OUT_DEB" | cut -f1))"
