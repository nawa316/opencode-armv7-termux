// Wraps eager top-level native addon createRequire() calls (e.g., @lydell/node-pty)
// in try/catch so OpenCode starts cleanly on 32-bit ARM Android where desktop x64/arm64
// .node prebuilds are absent. Features requiring the missing addon fail only if invoked.
export function nativeGuardPlugin() {
  return {
    name: "arm32:native-guard",
    renderChunk(code) {
      const re = /const (\w+)\s*=\s*createRequire\(import\.meta\.url\)\((process\.env\.\w+\s*\?\?\s*"[^"]+")\)/g
      let count = 0
      const out = code.replace(re, (_match, name, arg) => {
        count++
        return `let ${name}; try { ${name} = createRequire(import.meta.url)(${arg}) } catch { ${name} = undefined }`
      })
      console.log("[arm32:native-guard] guarded eager requires:", count)
      return { code: out, map: null }
    },
  }
}
