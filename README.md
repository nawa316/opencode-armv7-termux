# opencode-armv7-termux

Native **Termux** `.deb` build of [**OpenCode**](https://github.com/anomalyco/opencode) **with full interactive TUI ([OpenTUI](https://github.com/anomalyco/opentui))** for **32-bit ARM Android (`armeabi-v7a` / `armv7l` / `armv8l`, Android API 24+)** — no `proot`, no QEMU, no Bun required.

> Inspired by [Lh29007/opencode-armv7a](https://github.com/Lh29007/opencode-armv7a) (headless server only), extended to cross-compile `libopentui.so` natively against Android Bionic (API 24) and ship the full interactive SolidJS + OpenTUI terminal interface in a single Termux `.deb`.

---

## Why this project exists

1. Official OpenCode releases target 64-bit platforms (`x64` / `arm64`) and primarily use **Bun**, which does not support 32-bit ARM CPUs.
2. OpenCode's Terminal UI is powered by **OpenTUI** (a Zig + Yoga C++20 native rendering core loaded over FFI), which ships prebuilt `.so` binaries only for 64-bit Linux/macOS/Windows.
3. On Android 7.0+ (API 24) 32-bit devices running Termux, **Node.js 26.4+** runs natively on `arm` and includes built-in `node:ffi` (`--experimental-ffi`) and `node:sqlite`.

This repository:
- Cross-compiles **`libopentui.so`** (`v0.9.9`) natively for **`arm-linux-androideabi.24`** (Android Bionic softfp EABI5, `DT_NEEDED` limited strictly to `libc.so`, `libm.so`, `libdl.so`, symbol versions `<= LIBC_N` / API 24).
- Patches OpenTUI's 64-bit atomics, 32-bit `commandSize` overflow safety, and `android-arm` asset target resolution.
- Mathematically verifies via C11 `_Static_assert` that **all 101 `opentui.h` C ABI structs** match byte-for-byte on `arm-linux-androideabi.24`.
- Bundles **OpenCode `v2.4.1`** (CLI + Server + SolidJS/OpenTUI TUI + tree-sitter syntax highlighting WASM parsers) into a Termux `arm` `.deb` tuned for older devices with **<= 2 GB RAM**.

---

## Requirements (on your Android 32-bit device)

- **Android 7.0+ (API 24+)** with 32-bit ARM Termux (`dpkg --print-architecture` prints `arm`).
- **Termux** (from F-Droid / GitHub, not Play Store).
- **Node.js >= 26.4.0** (`pkg install nodejs`) for native `node:ffi` (`--experimental-ffi`).
- **ripgrep** (`pkg install ripgrep`, declared as a `.deb` dependency).

---

## Install on Termux

```sh
pkg update && pkg upgrade -y
pkg install -y nodejs ripgrep git
apt install ./opencode_2.4.1-1_arm.deb
```

### Run the interactive TUI

```sh
# Launch OpenCode TUI in the current directory
opencode

# Or open a specific project directory
opencode ~/my-project

# Or use the lighter minimal interface
opencode mini
```

### Run headless API server (optional)

```sh
OPENCODE_SERVER_PASSWORD='your-password' opencode serve --port 4096
```

---

## Memory & Performance Tuning (<= 2 GB RAM devices)

The `$PREFIX/bin/opencode` launcher is tuned out-of-the-box for older 32-bit Android 7/8 devices:

| Environment Variable | Default | Description |
| --- | --- | --- |
| `OPENCODE_MAX_OLD_SPACE_SIZE` | `512` | V8 old-space heap cap in MB. Lower to `384` on 1 GB RAM devices, or raise to `768` on 3+ GB devices. |
| `OPENCODE_TERMUX_STANDALONE` | `1` | Runs the local server in-process (`--standalone`) when launching the TUI so only **one** Node.js process runs (saves ~150–250 MB RAM). Set to `0` to use background daemon mode. |
| `OPENCODE_DISABLE_FILEWATCHER` | `1` | Disables `@parcel/watcher` (no `android-arm` prebuild). |
| `OPENCODE_DISABLE_FFF` | `1` | Disables `fff-node` native search (no `android-arm` prebuild; uses native Termux `ripgrep` instead). |
| `OPENCODE_DISABLE_AUTOUPDATE` | `1` | Prevents self-updater from replacing the Termux `arm` package with an x64/arm64 binary. |
| `OPENTUI_LIB_PATH` | `$PREFIX/lib/opencode/assets/@opentui/core-android-arm/libopentui.so` | Override path to `libopentui.so` if testing a custom build. |

---

## Building from Source (Linux x86_64 host)

### Prerequisites

- **Linux x86_64** host with `git`, `dpkg-deb`, `readelf`, `tar`, `xz`
- **Bun** `1.4.2+`
- **Zig** `0.17.1` (exact version required by OpenTUI `0.9.9`)
- **Android NDK** r26/r27 (API 24 sysroot for `arm-linux-androideabi`)

### One-command build

```sh
ANDROID_NDK_HOME=~/Android/Sdk/ndk/27.0.12077973 \
ZIG=/path/to/zig-0.17.1/zig \
sh scripts/build-all.sh
```

Output package:

```
out/opencode_2.4.1-1_arm.deb
```

You can also pass `OPTIMIZE=ReleaseSmall` to further shrink `libopentui.so` at a small rendering speed trade-off, or reuse existing upstream checkouts via `OPENCODE_REPO=...` and `OPENTUI_SRC=...`.

---

## Repository Structure

```text
.
├── .github/workflows/build-deb.yml     # Automated CI & GitHub Release builder
├── versions.env                        # Pinned upstream OpenCode, OpenTUI, Zig, Android API versions
├── patches/opentui/
│   ├── 0001-native-arm32-atomics-and-abi.patch   # 32-bit ARM u64 spinlocks, u64 commandSize, 32-bit ABI guard
│   ├── 0002-native-android-bionic-build.patch    # Android NDK libc-file, sysroot includes, no -lpthread, strip
│   └── 0003-core-android-arm-asset-target.patch  # Map process.platform="android", arch="arm" -> libopentui.so
├── scripts/
│   ├── build-all.sh                    # End-to-end build pipeline
│   ├── build-opentui-android-arm.sh    # Cross-compile + ELF/Bionic audit + ARM32 ABI check
│   ├── install-patched-opentui.sh      # Build & install patched @opentui/core JS into OpenCode
│   ├── bundle-opencode.ts              # Vite bundle + platform-independent WASM/TUI asset staging
│   ├── native-guard-plugin.mjs         # Guards eager top-level desktop .node requires
│   ├── verify-arm32-abi.ts             # C11 _Static_assert check across all 101 opentui.h structs
│   └── build-termux-deb.sh             # Packages Termux arm .deb
└── termux/
    └── opencode                        # Termux launcher ($PREFIX/bin/opencode)
```

---

## Known Limitations

- **Node.js >= 26.4.0 required for TUI**: OpenTUI's Node backend relies on `node:ffi` (`--experimental-ffi`). Older Termux Node.js versions can still run headless commands (`opencode serve`), but will prompt you to upgrade Node.js for the TUI.
- **No native PTY / file watcher / FFF addons**: `@lydell/node-pty`, `@parcel/watcher`, and `fff-node` have no 32-bit Android prebuilds; they are safely guarded/disabled while core agent tools, shell execution, `ripgrep`, SQLite sessions, MCP, and OpenTUI rendering work natively.
- **No embedded web UI archive**: `app-archive.bin` is stubbed empty to keep the `.deb` compact and RAM usage low.

---

## Verification Matrix

| Check | Status |
| --- | --- |
| `libopentui.so` ELF32 ARM EABI5 softfp (`arm-linux-androideabi.24`) | Verified (`readelf -h/-A/-d/-V`) |
| `DT_NEEDED` strictly `libc.so`, `libm.so`, `libdl.so` (<= `LIBC_N` / API 24) | Verified |
| All 101 `opentui.h` C structs byte-identical on `arm-linux-androideabi.24` | Verified (`_Static_assert`) |
| OpenCode `2.4.1` Node.js bundle (`--version`, `--help`, SQLite, `/api/*`) | Verified on Node `26.4.0` |
| Live OpenTUI SolidJS TUI rendering inside PTY (`--standalone`) | Verified on Node `26.4.0` |
| Real 32-bit Android device (Termux `arm`) | Ready for on-device testing — please report feedback via Issues! |

---

## Credits & License

- [OpenCode](https://github.com/anomalyco/opencode) and [OpenTUI](https://github.com/anomalyco/opentui) by Anomaly (MIT License).
- [Lh29007/opencode-armv7a](https://github.com/Lh29007/opencode-armv7a) for pioneering 32-bit ARM Termux OpenCode packaging.
- Build scripts, patches, and launcher in this repository are released under the [MIT License](LICENSE).
