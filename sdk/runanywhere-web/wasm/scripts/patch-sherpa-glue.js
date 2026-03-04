#!/usr/bin/env node
// =============================================================================
// RunAnywhere Web SDK — Post-compile browser patches for sherpa-onnx-glue.js
// =============================================================================
//
// The Emscripten "nodejs" WASM target produces glue code with Node.js
// assumptions that break in browsers. This script applies patches to make
// the glue JS browser-compatible.
//
// Patches applied:
//   1. ENVIRONMENT_IS_NODE = false           (force browser code paths)
//   2. require("node:path") → browser shim   (provides isAbsolute/normalize/join/basename/dirname)
//   3. NODERAWFS error throw → skip          (avoid "not supported" crash)
//   4. NODERAWFS FS patching → skip          (use MEMFS instead)
//   5. ESM default export appended           (for dynamic import() in browser)
//   6. instantiateWasm Promise → addRunDependency (fix async WASM init race)
//   7. HEAP views exported on Module (HEAP32/HEAPF32 needed for audio sample copy)
//
// Usage:
//   node patch-sherpa-glue.js <path-to-sherpa-onnx-glue.js>
//
// See packages/onnx/src/Foundation/SherpaONNXBridge.ts for the loader that
// consumes this patched file.
// =============================================================================

'use strict';

const fs = require('fs');

const glueFile = process.argv[2];
if (!glueFile) {
  console.error('Usage: node patch-sherpa-glue.js <path-to-sherpa-onnx-glue.js>');
  process.exit(1);
}

if (!fs.existsSync(glueFile)) {
  console.error(`ERROR: File not found: ${glueFile}`);
  process.exit(1);
}

let src = fs.readFileSync(glueFile, 'utf8');
const originalSize = src.length;
let patchCount = 0;

// ---------------------------------------------------------------------------
// Patch 1: Force ENVIRONMENT_IS_NODE = false
// ---------------------------------------------------------------------------
// Emscripten generates:
//   var ENVIRONMENT_IS_NODE=globalThis.process?.versions?.node&&...;
// Replace with:
//   var ENVIRONMENT_IS_NODE=false;

const envPattern = /var ENVIRONMENT_IS_NODE=[^;]+;/;
if (envPattern.test(src)) {
  src = src.replace(envPattern, 'var ENVIRONMENT_IS_NODE=false;');
  console.log('  ✓ Patch 1: ENVIRONMENT_IS_NODE = false');
  patchCount++;
} else {
  console.error('  ✗ Patch 1: ENVIRONMENT_IS_NODE declaration not found');
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Patch 2: Replace require("node:path") with browser-compatible PATH shim
// ---------------------------------------------------------------------------
// Emscripten generates (unguarded, top-level):
//   var nodePath=require("node:path");
//   var PATH={isAbs:nodePath.isAbsolute,normalize:nodePath.normalize,
//             join:nodePath.join,join2:nodePath.join};
//
// Replace the require + PATH definition with a self-contained browser shim.

const nodePathPattern =
  /var nodePath=require\(["']node:path["']\);var PATH=\{[^}]+\}/;

if (nodePathPattern.test(src)) {
  const pathShim = [
    'var nodePath=null;',
    'var PATH={',
    'isAbs:function(p){return p.charAt(0)==="/"},',
    'normalize:function(p){',
    'var parts=p.split("/").filter(function(x){return x&&x!=="."});',
    'var abs=p.charAt(0)==="/";',
    'var result=[];',
    'for(var i=0;i<parts.length;i++){',
    'if(parts[i]===".."){if(result.length>0&&result[result.length-1]!=="..")result.pop();else if(!abs)result.push("..")}',
    'else result.push(parts[i])}',
    'var out=(abs?"/":"")+result.join("/");',
    'return out||"."},',
    'join:function(){return PATH.normalize(Array.prototype.slice.call(arguments).join("/"))},',
    'join2:function(a,b){return PATH.normalize(a+"/"+b)},',
    'basename:function(p,ext){',
    'var base=p.replace(/\\/$/,"").split("/").pop()||"";',
    'if(ext&&base.slice(-ext.length)===ext)base=base.slice(0,-ext.length);',
    'return base},',
    'dirname:function(p){var d=p.replace(/\\/+$/,"").split("/").slice(0,-1).join("/");return d||"/"}',
    '}',
  ].join('');

  src = src.replace(nodePathPattern, pathShim);
  console.log('  ✓ Patch 2: require("node:path") → browser PATH shim');
  patchCount++;
} else {
  // Try simpler pattern (just guard the require)
  const simplePattern = /var nodePath=require\(["']node:path["']\)/;
  if (simplePattern.test(src)) {
    src = src.replace(
      simplePattern,
      'var nodePath=ENVIRONMENT_IS_NODE?require("node:path"):null',
    );
    console.log('  ⚠ Patch 2: Guarded require("node:path") (PATH shim not applied)');
    patchCount++;
  } else {
    console.log('  ⚠ Patch 2: require("node:path") not found (may not exist in this version)');
  }
}

// ---------------------------------------------------------------------------
// Patch 3: Skip NODERAWFS error throw
// ---------------------------------------------------------------------------
// Emscripten generates:
//   if(!ENVIRONMENT_IS_NODE){throw new Error("NODERAWFS is currently only
//     supported on Node.js environment.")}
//
// Since ENVIRONMENT_IS_NODE is now false, this would throw. Replace with no-op.

const noderawfsThrow =
  /if\(!ENVIRONMENT_IS_NODE\)\{throw new Error\("NODERAWFS[^"]*"\)\}/;

if (noderawfsThrow.test(src)) {
  src = src.replace(noderawfsThrow, '/* PATCHED: NODERAWFS check removed for browser */');
  console.log('  ✓ Patch 3: NODERAWFS environment check → skipped');
  patchCount++;
} else {
  console.log('  ⚠ Patch 3: NODERAWFS throw not found (may not exist in this version)');
}

// ---------------------------------------------------------------------------
// Patch 4: Skip NODERAWFS FS patching
// ---------------------------------------------------------------------------
// Emscripten generates:
//   var VFS={...FS};for(var _key in NODERAWFS){FS[_key]=_wrapNodeError(NODERAWFS[_key])}
//
// This overwrites FS methods with NODERAWFS (Node.js filesystem) wrappers.
// In the browser we want to keep the standard MEMFS-based FS methods.

const noderawfsFS =
  /var VFS=\{\.\.\.FS\};for\(var _key in NODERAWFS\)\{FS\[_key\]=_wrapNodeError\(NODERAWFS\[_key\]\)\}/;

if (noderawfsFS.test(src)) {
  src = src.replace(
    noderawfsFS,
    '/* PATCHED: NODERAWFS FS patching skipped for browser (using MEMFS) */',
  );
  console.log('  ✓ Patch 4: NODERAWFS FS patching → skipped (MEMFS preserved)');
  patchCount++;
} else {
  console.log('  ⚠ Patch 4: NODERAWFS FS patching not found (may not exist in this version)');
}

// ---------------------------------------------------------------------------
// Patch 5: Append ESM default export
// ---------------------------------------------------------------------------
// Emscripten generates CJS exports:
//   module.exports=Module;module.exports.default=Module
//
// Browser dynamic import() needs ESM. Append an ESM default export so both
// CJS (Node.js) and ESM (browser import()) work.

if (!src.includes('export default Module')) {
  src += '\nexport default Module;\n';
  console.log('  ✓ Patch 5: ESM default export appended');
  patchCount++;
} else {
  console.log('  ✓ Patch 5: ESM default export already present');
  patchCount++;
}

// ---------------------------------------------------------------------------
// Patch 6: Fix instantiateWasm async path — use addRunDependency pattern
// ---------------------------------------------------------------------------
// Emscripten generates a Promise-based instantiateWasm path:
//   if(Module["instantiateWasm"]){return new Promise((resolve,reject)=>{
//     Module["instantiateWasm"](info,(inst,mod)=>{resolve(receiveInstance(inst,mod))})})}
//
// This is broken for async WASM compilation: createWasm() returns a Promise,
// which gets assigned to wasmExports. Then run() calls initRuntime() which
// calls wasmExports["J"]() — but wasmExports is still a Promise at that point!
//
// Fix: use addRunDependency/removeRunDependency so run() defers until WASM
// is fully instantiated and wasmExports is set to the actual WASM exports.

const instantiateWasmPromisePattern =
  'if(Module["instantiateWasm"]){return new Promise((resolve,reject)=>{' +
  'Module["instantiateWasm"](info,(inst,mod)=>{resolve(receiveInstance(inst,mod))})})}'

const instantiateWasmFixedPattern =
  'if(Module["instantiateWasm"]){addRunDependency("instantiateWasm");' +
  'Module["instantiateWasm"](info,(inst,mod)=>{receiveInstance(inst,mod);' +
  'removeRunDependency("instantiateWasm")});return {}}';

if (src.includes(instantiateWasmPromisePattern)) {
  src = src.replace(instantiateWasmPromisePattern, instantiateWasmFixedPattern);
  console.log('  ✓ Patch 6: instantiateWasm Promise → addRunDependency (deferred run)');
  patchCount++;
} else if (src.includes(instantiateWasmFixedPattern)) {
  console.log('  ✓ Patch 6: instantiateWasm already uses addRunDependency pattern');
  patchCount++;
} else {
  console.log('  ⚠ Patch 6: instantiateWasm Promise pattern not found (format may differ)');
}

// ---------------------------------------------------------------------------
// Patch 7: Export HEAP views on Module object
// ---------------------------------------------------------------------------
// Emscripten keeps HEAP8/HEAP32/HEAPF32 etc. as closure-private variables.
// The SherpaONNXBridge reads them via module.HEAP32, module.HEAPF32 etc.
// after synthesis to copy audio samples from WASM memory.
//
// Patch: insert Module["HEAPxx"] = HEAPxx assignments INSIDE updateMemoryViews
// (before the closing }) so they run on every memory growth event.
// IMPORTANT: must be inside the function body, not after the closing }.

const heapViewsExports =
  'Module["HEAP8"]=HEAP8;Module["HEAP16"]=HEAP16;Module["HEAPU8"]=HEAPU8;' +
  'Module["HEAPU16"]=HEAPU16;Module["HEAP32"]=HEAP32;Module["HEAPU32"]=HEAPU32;' +
  'Module["HEAPF32"]=HEAPF32;Module["HEAPF64"]=HEAPF64;';

const heapSuffix64  = ';HEAPU64=new BigUint64Array(b);' + heapViewsExports + '}';
const heapSuffix    = ';HEAPU64=new BigUint64Array(b)}';
const heapSuffixAlt = ';HEAPF64=new Float64Array(b)}';  // builds without HEAP64

if (src.includes('Module["HEAP32"]=HEAP32')) {
  console.log('  ✓ Patch 7: HEAP views already exported on Module');
  patchCount++;
} else if (src.includes(heapSuffix)) {
  // Insert exports INSIDE the function: replace closing } with exports + }
  src = src.replace(heapSuffix, ';HEAPU64=new BigUint64Array(b);' + heapViewsExports + '}');
  console.log('  ✓ Patch 7: HEAP views exported on Module object (inside updateMemoryViews)');
  patchCount++;
} else if (src.includes(heapSuffixAlt) && !src.includes('Module["HEAP32"]=HEAP32')) {
  src = src.replace(heapSuffixAlt,
    ';HEAPF64=new Float64Array(b);' +
    'Module["HEAP32"]=HEAP32;Module["HEAPU8"]=HEAPU8;Module["HEAPF32"]=HEAPF32;Module["HEAPF64"]=HEAPF64;' +
    '}');
  console.log('  ✓ Patch 7: HEAP views exported on Module object (alt pattern, inside function)');
  patchCount++;
} else {
  console.log('  ⚠ Patch 7: updateMemoryViews end pattern not found');
}

// ---------------------------------------------------------------------------
// Write patched file
// ---------------------------------------------------------------------------

fs.writeFileSync(glueFile, src, 'utf8');
const newSize = src.length;
const delta = newSize - originalSize;

console.log('');
console.log(`  ${patchCount}/7 patches applied`);
console.log(`  File size: ${originalSize} → ${newSize} bytes (${delta >= 0 ? '+' : ''}${delta})`);

if (patchCount < 3) {
  console.error('');
  console.error('WARNING: Fewer than 3 patches applied. The glue file format may have changed.');
  console.error('Check the Emscripten output and update patch patterns if needed.');
  process.exit(1);
}
