import { readFile, stat } from 'node:fs/promises';
import { resolve } from 'node:path';
import process from 'node:process';
import { spawnSync } from 'node:child_process';

const packageRoot = process.cwd();

function isObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function parseManifest(text) {
  const parsed = JSON.parse(text);
  if (!isObject(parsed) || typeof parsed.name !== 'string' || !isObject(parsed.exports)) {
    throw new Error('package.json must contain a string name and object exports map');
  }
  return parsed;
}

const manifest = parseManifest(
  await readFile(resolve(packageRoot, 'package.json'), 'utf8'),
);

function collectExportTargets(value, targets) {
  if (typeof value === 'string') {
    if (!value.includes('*')) targets.add(value);
    return;
  }
  if (!isObject(value)) return;
  for (const nested of Object.values(value)) collectExportTargets(nested, targets);
}

const required = new Set(['README.md', 'LICENSE', ...process.argv.slice(2)]);
for (const field of ['main', 'module', 'types']) {
  if (typeof manifest[field] === 'string') required.add(manifest[field]);
}
collectExportTargets(manifest.exports, required);

const errors = [];
if (manifest.license !== 'SEE LICENSE IN LICENSE') {
  errors.push('package.json license must be "SEE LICENSE IN LICENSE"');
}

const license = await readFile(resolve(packageRoot, 'LICENSE'), 'utf8').catch(() => '');
if (!license.includes('RunAnywhere License') || !license.includes('Copyright (c) 2025')) {
  errors.push('LICENSE must contain the RunAnywhere license notice and copyright');
}

for (const relativePath of required) {
  const absolutePath = resolve(packageRoot, relativePath);
  let info;
  try {
    info = await stat(absolutePath);
  } catch {
    errors.push(`missing required output: ${relativePath}`);
    continue;
  }
  if (!info.isFile() || info.size === 0) {
    errors.push(`required output is empty or not a file: ${relativePath}`);
    continue;
  }

  if (relativePath.endsWith('.js')) {
    const syntax = spawnSync(process.execPath, ['--check', absolutePath], {
      encoding: 'utf8',
    });
    if (syntax.status !== 0) {
      errors.push(`invalid JavaScript syntax in ${relativePath}: ${syntax.stderr.trim()}`);
    }
  }

  if (relativePath.endsWith('.wasm')) {
    const bytes = await readFile(absolutePath);
    if (
      bytes.length < 8
      || bytes[0] !== 0x00
      || bytes[1] !== 0x61
      || bytes[2] !== 0x73
      || bytes[3] !== 0x6d
    ) {
      errors.push(`invalid WebAssembly magic bytes in ${relativePath}`);
    } else if (!WebAssembly.validate(bytes)) {
      errors.push(`WebAssembly validation failed for ${relativePath}`);
    }
  }
}

if (errors.length > 0) {
  process.stderr.write(
    `ERROR: ${manifest.name} cannot be packed:\n${errors.map((error) => `  - ${error}`).join('\n')}\n`,
  );
  process.exitCode = 1;
} else {
  process.stdout.write(
    `Verified ${manifest.name}: ${required.size} browser-bundler outputs, declarations, `
      + 'WASM binaries, and license files are present and valid.\n',
  );
}
