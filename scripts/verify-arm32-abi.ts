#!/usr/bin/env bun
// Verifies via C11 _Static_assert that all OpenTUI C ABI structs in opentui.h
// have identical sizes, alignments, and field offsets on arm-linux-androideabi.<API>
// as the generated JavaScript ABI metadata in @opentui/core.
import { spawnSync } from "node:child_process"
import { mkdtempSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import path from "node:path"

const OPENTUI_SRC = path.resolve(process.env.OPENTUI_SRC ?? "")
const ANDROID_SYSROOT = path.resolve(process.env.ANDROID_SYSROOT ?? "")
const ANDROID_API = process.env.ANDROID_API ?? "24"
const ZIG = process.env.ZIG ?? "zig"

if (!process.env.OPENTUI_SRC || !process.env.ANDROID_SYSROOT) {
  console.error("Usage: OPENTUI_SRC=<path> ANDROID_SYSROOT=<path> [ANDROID_API=24] [ZIG=zig] bun scripts/verify-arm32-abi.ts")
  process.exit(1)
}

const { compileHeader } = await import(path.join(OPENTUI_SRC, "packages/core/scripts/native-abi.ts"))
const abi = compileHeader()

const decls = ['#include "opentui.h"', "#include <stddef.h>"]
for (const [name, record] of Object.entries(abi.layouts) as [string, any][]) {
  decls.push(`_Static_assert(sizeof(${name}) == ${record.size}, "size mismatch: ${name}");`)
  decls.push(`_Static_assert(_Alignof(${name}) == ${record.alignment}, "align mismatch: ${name}");`)
  for (const [field, info] of Object.entries(record.fields) as [string, any][]) {
    const member = `((${name} *)0)->${field}`
    decls.push(`_Static_assert(offsetof(${name}, ${field}) == ${info.offset}, "offset mismatch: ${name}.${field}");`)
    decls.push(`_Static_assert(sizeof(${member}) == ${info.size}, "field size mismatch: ${name}.${field}");`)
  }
}

const tempDir = mkdtempSync(path.join(tmpdir(), "opentui-arm32-abi-"))
try {
  const srcPath = path.join(tempDir, "check-arm32-abi.c")
  const objPath = path.join(tempDir, "check-arm32-abi.o")
  writeFileSync(srcPath, decls.join("\n") + "\n")

  const target = `arm-linux-androideabi.${ANDROID_API}`
  const result = spawnSync(
    ZIG,
    [
      "cc",
      "-c",
      "-std=c11",
      "-Wall",
      "-Wextra",
      "-Werror",
      "-target",
      target,
      "-nostdlibinc",
      "-isystem",
      path.join(ANDROID_SYSROOT, "usr/include/arm-linux-androideabi"),
      "-isystem",
      path.join(ANDROID_SYSROOT, "usr/include"),
      "-I",
      path.join(OPENTUI_SRC, "packages/native/include"),
      srcPath,
      "-o",
      objPath,
    ],
    { encoding: "utf8" },
  )

  if (result.error) throw result.error
  if (result.status !== 0) {
    console.error(`ARM32 C ABI check failed for ${target}:\n${result.stderr}`)
    process.exit(1)
  }

  console.log(
    `[verify-arm32-abi] OK: all ${Object.keys(abi.layouts).length} C ABI structs verified byte-identical on ${target}`,
  )
} finally {
  rmSync(tempDir, { recursive: true, force: true })
}
