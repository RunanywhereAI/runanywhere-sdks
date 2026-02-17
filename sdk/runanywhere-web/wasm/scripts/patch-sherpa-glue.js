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
//   2. require("node:path") → browser shim   (provides isAbsolute/normalize/join)
//   3. NODERAWFS error throw → skip          (avoid "not supported" crash)
//   4. NODERAWFS FS patching → skip          (use MEMFS instead)
//   5. ESM default export appended           (for dynamic import() in browser)
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
    'join2:function(a,b){return PATH.normalize(a+"/"+b)}',
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
// Write patched file
// ---------------------------------------------------------------------------

fs.writeFileSync(glueFile, src, 'utf8');
const newSize = src.length;
const delta = newSize - originalSize;

console.log('');
console.log(`  ${patchCount}/5 patches applied`);
console.log(`  File size: ${originalSize} → ${newSize} bytes (${delta >= 0 ? '+' : ''}${delta})`);

if (patchCount < 3) {
  console.error('');
  console.error('WARNING: Fewer than 3 patches applied. The glue file format may have changed.');
  console.error('Check the Emscripten output and update patch patterns if needed.');
  process.exit(1);
}
