#!/usr/bin/env bun
// Bundles anomalyco/opencode (CLI + Server + SolidJS/OpenTUI TUI) into a Node.js ESM bundle
// and stages all platform-independent runtime assets (tree-sitter WASM/queries, parser worker,
// photon WASM, UI audio) for Termux arm (armeabi-v7a).
import { copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { createRequire } from "node:module"
import path from "node:path"
import { nativeGuardPlugin } from "./native-guard-plugin.mjs"

const OPENCODE_CLI = path.resolve(process.env.OPENCODE_CLI ?? "")
const OUT_DIR = path.resolve(process.env.BUNDLE_OUT ?? path.join(OPENCODE_CLI, "dist-arm32"))

if (!process.env.OPENCODE_CLI) {
  console.error("Usage: OPENCODE_CLI=/path/to/opencode/packages/cli [BUNDLE_OUT=...] bun scripts/bundle-opencode.ts")
  process.exit(1)
}

process.chdir(OPENCODE_CLI)

const req = createRequire(path.join(OPENCODE_CLI, "package.json"))
const { build } = await import(req.resolve("vite"))
const { mainConfig } = await import(path.join(OPENCODE_CLI, "vite.node.config.ts"))
const { nodeTarget } = await import(path.join(OPENCODE_CLI, "src/node/target.ts"))
const { collectNodeAssets } = await import(path.join(OPENCODE_CLI, "script/node-assets.ts"))
const { bundledModelsSnapshot } = await import(path.join(OPENCODE_CLI, "../core/script/models-snapshot.ts"))

const pkg = JSON.parse(await readFile(path.join(OPENCODE_CLI, "package.json"), "utf8"))
const version = process.env.OPENCODE_VERSION ?? pkg.version
const channel = process.env.OPENCODE_CHANNEL ?? "latest"
const modelsSnapshot = await bundledModelsSnapshot()

await rm(OUT_DIR, { recursive: true, force: true })
await mkdir(OUT_DIR, { recursive: true })

const cfg = mainConfig({
  version,
  channel,
  highlights: undefined,
  modelsSnapshot,
  assetHash: `termux-arm-${version}`,
  // Use linux-x64 as the template target during Vite bundling; desktop native addons are
  // excluded when staging assets, and nativeGuardPlugin guards eager native requires.
  target: nodeTarget("linux", "x64"),
}) as any

cfg.plugins.push(nativeGuardPlugin())
cfg.build.outDir = OUT_DIR
cfg.build.minify = process.env.OPENCODE_NO_MINIFY === "1" ? false : true

await build(cfg)

// Verify bundled bundle contains patched android-arm OpenTUI descriptor and inlined models snapshot
const bundlePath = path.join(OUT_DIR, "opencode.mjs")
const bundleText = await readFile(bundlePath, "utf8")
if (!/android:\s*"libopentui\.so"/.test(bundleText)) {
  throw new Error(
    "Bundled opencode.mjs is missing the patched android-arm OpenTUI target. Did install-patched-opentui.sh run first?",
  )
}
if (!bundleText.includes('"zhipuai"')) {
  throw new Error("Bundled opencode.mjs is missing inlined models.dev snapshot")
}

// Stage platform-independent assets (WASM, tree-sitter .scm queries, parser.worker.js, audio)
const allAssets = await collectNodeAssets(nodeTarget("linux", "x64"))
const assetsOut = path.join(OUT_DIR, "assets")
await mkdir(assetsOut, { recursive: true })

let stagedCount = 0
for (const asset of allAssets) {
  // Skip desktop x64/arm64 native binaries; libopentui.so for android-arm is staged separately
  if (
    asset.key.endsWith(".node") ||
    asset.key.includes("node-pty") ||
    asset.key.includes("fff-bin") ||
    asset.key.includes("ffi-rs") ||
    asset.key.includes("opencode-pty") ||
    asset.key.startsWith("@opentui/core-")
  ) {
    continue
  }
  const dest = path.join(assetsOut, asset.key)
  await mkdir(path.dirname(dest), { recursive: true })
  await copyFile(asset.source, dest)
  stagedCount++
}

// Empty web archive placeholder (TUI + v2 API package)
await writeFile(path.join(assetsOut, "app-archive.bin"), new Uint8Array())

console.log(`[bundle-opencode] OK: ${bundlePath} (+ ${stagedCount} assets staged in ${assetsOut})`)
