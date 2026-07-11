#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

const outputRoot = path.resolve(process.cwd(), process.argv[2] ?? 'dist');
const requiredFiles = [
  'index.html',
  'coi-serviceworker.js',
  'assets/racommons.js',
  'assets/racommons.wasm',
  'assets/racommons-llamacpp.js',
  'assets/racommons-llamacpp.wasm',
  'assets/racommons-llamacpp-webgpu.js',
  'assets/racommons-llamacpp-webgpu.wasm',
  'assets/racommons-onnx-sherpa.js',
  'assets/racommons-onnx-sherpa.wasm',
];

const invalidFiles = requiredFiles.filter((relativePath) => {
  const file = path.join(outputRoot, relativePath);
  return !fs.existsSync(file) || !fs.statSync(file).isFile() || fs.statSync(file).size === 0;
});

if (invalidFiles.length > 0) {
  const details = invalidFiles.map((file) => `  - ${file}`).join('\n');
  throw new Error(`Release output is missing required non-empty files:\n${details}`);
}

process.stdout.write(`Verified ${requiredFiles.length} release files in ${outputRoot}\n`);
