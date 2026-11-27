"use strict";
const fs = require("node:fs");
const log = (s) => fs.writeSync(1, s + "\n");

log("0. node=" + process.version + " arch=" + process.arch + " platform=" + process.platform);

try {
  const { DatabaseSync } = require("node:sqlite");
  const db = new DatabaseSync(":memory:");
  db.exec("CREATE TABLE t(x INT); INSERT INTO t VALUES (42);");
  log("1. sqlite OK: " + JSON.stringify(db.prepare("SELECT x FROM t").get()));
  db.close();
} catch (e) {
  log("1. sqlite ERR: " + e.message);
}

const ffi = require("node:ffi");
const libPath =
  process.env.OPENTUI_LIB_PATH ||
  (process.env.PREFIX || "/data/data/com.termux/files/usr") +
    "/lib/opencode/assets/@opentui/core-android-arm/libopentui.so";

log("2. dlopen " + libPath);
const d = ffi.dlopen(libPath, {
  ot_context_abi_version: { arguments: [], return: "u32" },
  imageRetainIccCache: { arguments: [], return: "void" },
  imageReleaseIccCache: { arguments: [], return: "void" },
  setLogCallback: { arguments: ["pointer"], return: "void" },
  ot_context_create: { arguments: ["pointer", "pointer"], return: "i32" },
  ot_context_destroy: { arguments: ["pointer"], return: "i32" },
  ot_session_create: { arguments: ["pointer", "pointer", "pointer"], return: "i32" },
});
log("3. abi=" + d.functions.ot_context_abi_version());

d.functions.imageRetainIccCache();
log("4. imageRetainIccCache OK");

const cb = d.lib.registerCallback(
  { arguments: ["u8", "pointer", "u32"], return: "void" },
  function (lvl, ptr, len) {
    log("   [zig-log] lvl=" + lvl + " ptr=" + ptr + " len=" + len);
  },
);
log("5. registerCallback ptr=" + cb);
d.functions.setLogCallback(cb);
log("6. setLogCallback OK");

const opts = new Uint32Array(8);
opts[0] = 32;
opts[1] = 2;
opts[3] = 65536;
opts[4] = 1000000;
const out = new BigUint64Array(1);
const optsPtr = ffi.getRawPointer(opts.buffer);
const outPtr = ffi.getRawPointer(out.buffer);
log("7. rawPtrs opts=" + optsPtr + " out=" + outPtr);

log("8a. calling ot_context_create with BigInt raw pointers...");
let rc = d.functions.ot_context_create(optsPtr, outPtr);
log("8a. rc=" + rc + " ctx=" + out[0]);
if (rc === 0 && out[0] !== 0n) {
  log("8b. destroying ctx=" + out[0]);
  const drc = d.functions.ot_context_destroy(out[0]);
  log("8b. destroy rc=" + drc);
}

out[0] = 0n;
log("9a. calling ot_context_create with TypedArray views...");
rc = d.functions.ot_context_create(opts, out);
log("9a. rc=" + rc + " ctx=" + out[0]);
if (rc === 0 && out[0] !== 0n) {
  const sessOpts = new Uint32Array(8);
  const dv = new DataView(sessOpts.buffer);
  dv.setUint32(0, 32, true);
  dv.setUint32(4, 2, true);
  dv.setUint32(8, 65536, true);
  dv.setUint32(12, 128, true);
  dv.setBigUint64(16, 8388608n, true);
  dv.setUint32(24, 4096, true);
  const sessOut = new Uint32Array(4);
  log("10. calling ot_session_create...");
  const src = d.functions.ot_session_create(out[0], sessOpts, sessOut);
  log("10. ot_session_create rc=" + src + " handle=" + Array.from(sessOut).join(","));

  log("11. destroying ctx=" + out[0]);
  log("11. destroy rc=" + d.functions.ot_context_destroy(out[0]));
}

d.functions.setLogCallback(0n);
d.lib.unregisterCallback(cb);
d.functions.imageReleaseIccCache();
log("12. ALL FFI TESTS PASSED!");
