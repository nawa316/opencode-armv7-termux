"use strict";
const fs = require("node:fs");
const Module = require("node:module");

const logPath = (process.env.HOME || ".") + "/opencode-ffi-trace.log";
try { fs.unlinkSync(logPath); } catch {}
const log = (msg) => {
  try { fs.writeFileSync(logPath, msg + "\n", { flag: "a" }); } catch {}
};

const origLoad = Module._load;
Module._load = function (request, parent, isMain) {
  const mod = origLoad.apply(this, arguments);
  if (request !== "node:ffi" || !mod || mod.__traced) return mod;

  const target = mod.default || mod;
  const wrapped = Object.create(target);
  wrapped.__traced = true;

  if (typeof target.getRawPointer === "function") {
    wrapped.getRawPointer = function (buf) {
      log("FFI getRawPointer byteLength=" + (buf && buf.byteLength));
      const r = target.getRawPointer.apply(target, arguments);
      log("  -> " + String(r));
      return r;
    };
  }
  if (typeof target.toArrayBuffer === "function") {
    wrapped.toArrayBuffer = function (ptr, len, copy) {
      log("FFI toArrayBuffer ptr=" + String(ptr) + " len=" + len + " copy=" + copy);
      const r = target.toArrayBuffer.apply(target, arguments);
      log("  -> ArrayBuffer(" + r.byteLength + ")");
      return r;
    };
  }
  if (typeof target.dlopen === "function") {
    wrapped.dlopen = function (path, symbols) {
      log("FFI dlopen path=" + path + " syms=" + Object.keys(symbols || {}).length);
      const res = target.dlopen.apply(target, arguments);
      const wrappedFns = {};
      for (const [name, fn] of Object.entries(res.functions)) {
        wrappedFns[name] = function () {
          const argsDesc = Array.from(arguments).map((a) => {
            if (ArrayBuffer.isView(a)) return a.constructor.name + "(" + a.byteLength + ")";
            if (a instanceof ArrayBuffer) return "AB(" + a.byteLength + ")";
            return String(a);
          }).join(", ");
          log("CALL " + name + "(" + argsDesc + ")");
          const out = fn.apply(this, arguments);
          log("RET  " + name + " -> " + String(out));
          return out;
        };
      }
      const origLib = res.lib;
      const wrappedLib = {
        close() {
          log("LIB close()");
          return origLib.close();
        },
        registerCallback(sig, cb) {
          log("LIB registerCallback args=" + JSON.stringify(sig.arguments) + " ret=" + sig.return);
          const wrappedCb = function () {
            log("CB_ENTER args=" + Array.from(arguments).map(String).join(", "));
            const r = cb.apply(this, arguments);
            log("CB_EXIT -> " + String(r));
            return r;
          };
          const p = origLib.registerCallback(sig, wrappedCb);
          log("LIB registerCallback -> " + String(p));
          return p;
        },
        unregisterCallback(p) {
          log("LIB unregisterCallback " + String(p));
          return origLib.unregisterCallback(p);
        },
      };
      return { lib: wrappedLib, functions: wrappedFns };
    };
  }
  wrapped.default = wrapped;
  return wrapped;
};

log("TRACE LOADED node=" + process.version + " arch=" + process.arch + " pid=" + process.pid);
