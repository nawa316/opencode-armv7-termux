#!/usr/bin/env bash
# One-line Termux installer for nawa316/opencode-armv7-termux
# Native OpenCode CLI + OpenTUI interactive TUI for 32-bit ARM Android (Android 7.0+ / API 24+)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/nawa316/opencode-armv7-termux/main/install.sh | bash
set -euo pipefail

REPO="nawa316/opencode-armv7-termux"
DEFAULT_TAG="v2.4.1-2"
DEFAULT_DEB="opencode_2.4.1-2_arm.deb"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"

if [ -t 1 ]; then
  C_GREEN='\033[1;32m'
  C_YELLOW='\033[1;33m'
  C_RED='\033[1;31m'
  C_CYAN='\033[1;36m'
  C_RESET='\033[0m'
else
  C_GREEN='' C_YELLOW='' C_RED='' C_CYAN='' C_RESET=''
fi

info() { printf "${C_CYAN}[opencode-install]${C_RESET} %s\n" "$*"; }
ok()   { printf "${C_GREEN}[opencode-install]${C_RESET} %s\n" "$*"; }
warn() { printf "${C_YELLOW}[opencode-install]${C_RESET} %s\n" "$*" >&2; }
die()  { printf "${C_RED}[opencode-install] Error:${C_RESET} %s\n" "$*" >&2; exit 1; }

if [ ! -d "$PREFIX" ] || ! command -v dpkg >/dev/null 2>&1; then
  die "This installer must be run inside Termux on Android."
fi

ARCH="$(dpkg --print-architecture 2>/dev/null || true)"
if [ -z "$ARCH" ]; then
  case "$(uname -m)" in
    armv7*|armv8l|arm) ARCH="arm" ;;
    *) ARCH="$(uname -m)" ;;
  esac
fi

if [ "$ARCH" != "arm" ]; then
  die "This package targets 32-bit ARM Termux (arm / armeabi-v7a), detected '$ARCH'."
fi

ANDROID_VER="$(getprop ro.build.version.release 2>/dev/null || echo unknown)"
ANDROID_SDK="$(getprop ro.build.version.sdk 2>/dev/null || echo unknown)"
info "Detected Termux arm (Android ${ANDROID_VER}, API ${ANDROID_SDK})"

# Resolve latest release tag & .deb asset from GitHub API (allow override via OPENCODE_TAG)
TAG="${OPENCODE_TAG:-}"
DEB_NAME=""
if [ -n "$TAG" ]; then
  API_URL="https://api.github.com/repos/${REPO}/releases/tags/${TAG}"
else
  info "Checking latest release of $REPO..."
  API_URL="https://api.github.com/repos/${REPO}/releases/latest"
fi

RELEASE_JSON="$(curl -fsSL "$API_URL" 2>/dev/null || true)"
if [ -n "$RELEASE_JSON" ]; then
  if [ -z "$TAG" ]; then
    TAG="$(printf '%s\n' "$RELEASE_JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
  fi
  DEB_NAME="$(printf '%s\n' "$RELEASE_JSON" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\(opencode_[^"]*_arm\.deb\)".*/\1/p' | head -n 1 || true)"
fi

if [ -z "$TAG" ] || [ -z "$DEB_NAME" ]; then
  warn "Could not query GitHub Releases API; falling back to ${DEFAULT_TAG} (${DEFAULT_DEB})."
  TAG="${TAG:-$DEFAULT_TAG}"
  DEB_NAME="${DEB_NAME:-$DEFAULT_DEB}"
fi
BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"

info "Target release: ${TAG} (${DEB_NAME})"

# Install required Termux dependencies (including ca-certificates for Android 7.1.1 TLS)
info "Installing required Termux dependencies..."
if command -v pkg >/dev/null 2>&1; then
  pkg update -y || true
  pkg install -y ca-certificates curl ripgrep
  pkg install -y git || warn "Optional package 'git' could not be installed."
  if ! command -v node >/dev/null 2>&1; then
    pkg install -y nodejs || pkg install -y nodejs-lts
  fi
else
  warn "'pkg' command not found; skipping automatic Termux dependency installation."
fi

# Download .deb and verify sha256
TMPDIR_WORK="$(mktemp -d "${TMPDIR:-$PREFIX/tmp}/opencode-install.XXXXXX")"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

info "Downloading ${DEB_NAME}..."
curl -fL --progress-bar "${BASE_URL}/${DEB_NAME}" -o "${TMPDIR_WORK}/${DEB_NAME}"

if curl -fsSL "${BASE_URL}/${DEB_NAME}.sha256" -o "${TMPDIR_WORK}/${DEB_NAME}.sha256" 2>/dev/null; then
  if command -v sha256sum >/dev/null 2>&1; then
    info "Verifying SHA-256 checksum..."
    EXPECTED_SHA="$(awk '{print $1; exit}' "${TMPDIR_WORK}/${DEB_NAME}.sha256")"
    ACTUAL_SHA="$(sha256sum "${TMPDIR_WORK}/${DEB_NAME}" | awk '{print $1; exit}')"
    if [ -n "$EXPECTED_SHA" ] && [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
      die "SHA-256 mismatch! expected=${EXPECTED_SHA} actual=${ACTUAL_SHA}"
    fi
    ok "SHA-256 verified (${ACTUAL_SHA})"
  fi
else
  warn "Checksum file not found for ${DEB_NAME}; skipping SHA-256 check."
fi

info "Installing ${DEB_NAME}..."
if ! dpkg -i "${TMPDIR_WORK}/${DEB_NAME}"; then
  info "Resolving any missing dependencies via apt..."
  apt-get install -f -y
fi

echo ""
ok "OpenCode (${TAG}, armv7a + OpenTUI) installed successfully!"

NODE_BIN="$PREFIX/bin/node"
if [ -x "$NODE_BIN" ]; then
  NODE_VER="$("$NODE_BIN" -v 2>/dev/null || echo unknown)"
  if "$NODE_BIN" --experimental-ffi -e "" >/dev/null 2>&1; then
    ok "Node.js ${NODE_VER} supports --experimental-ffi: full OpenTUI interactive TUI is ready!"
    echo "  Launch TUI:     opencode"
    echo "  Minimal mode:   opencode mini"
  else
    warn "Installed Node.js (${NODE_VER}) does not yet support --experimental-ffi (requires Node >= 26.4.0)."
    echo "  Upgrade Node:   pkg update && pkg upgrade nodejs"
    echo "  Headless mode:  opencode serve --port 4096"
  fi
fi
