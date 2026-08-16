// Unit tests for the app.asar → app.asar.unpacked rewrite that every path
// handed to the OS loader has to go through.
//
// These run under plain Node, without Electron's fs shim. That is the useful
// half of the packaged-app shape: the archive path has nothing behind it, which
// is exactly what dlopen and AddDllDirectory see inside a real packaged app.
// Electron's shim is what makes the bug invisible in JS, not what makes it work.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, test } from 'node:test';

import { asarUnpacked } from '../../dist/backend/plugin-registry';
import { resolveCommonsLibrary } from '../../dist/bridge';

const roots: string[] = [];

// Every commons filename the three shipping platforms use. The resolver picks
// by process.platform, so staging all three keeps the fixture host-agnostic
// without restating the mapping the resolver owns.
const COMMONS_FILE_NAMES = ['librac_commons.dylib', 'librac_commons.so', 'rac_commons.dll'];

/**
 * Stage a packaged-app layout and hand back the two sibling directories.
 * `archive` is inside app.asar and never gets files written under it; whatever
 * the caller stages goes in `unpacked`.
 */
function stagePackagedApp(): { archive: string; unpacked: string } {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rac-asar-'));
  roots.push(root);
  const archive = path.join(root, 'app.asar', 'node_modules', 'runanywhere', 'dist');
  const unpacked = path.join(root, 'app.asar.unpacked', 'node_modules', 'runanywhere', 'dist');
  fs.mkdirSync(unpacked, { recursive: true });
  return { archive, unpacked };
}

after(() => {
  for (const root of roots) fs.rmSync(root, { recursive: true, force: true });
});

test('asarUnpacked leaves a path outside app.asar alone', () => {
  const plain = path.join(os.tmpdir(), 'not-packaged', 'librac_commons.dylib');
  assert.equal(asarUnpacked(plain), plain);
});

test('asarUnpacked rewrites to the unpacked sibling when the real file is there', () => {
  const { archive, unpacked } = stagePackagedApp();
  fs.writeFileSync(path.join(unpacked, 'runanywhere_llamacpp.dll'), '');

  assert.equal(
    asarUnpacked(path.join(archive, 'runanywhere_llamacpp.dll')),
    path.join(unpacked, 'runanywhere_llamacpp.dll')
  );
});

test('asarUnpacked returns the input when nothing was unpacked', () => {
  // An app that sets no asarUnpack rule has no sibling tree at all. Rewriting
  // blindly would hand the loader a path that is wrong in a second way.
  const { archive } = stagePackagedApp();
  const inArchive = path.join(archive, 'runanywhere_llamacpp.dll');
  assert.equal(asarUnpacked(inArchive), inArchive);
});

test('asarUnpacked rewrites a directory path, not just a file path', () => {
  // prepareNativeLoad rewrites the addon path and then takes its dirname, so
  // the directory that reaches addSidecarDirToDllSearch has to land in the
  // unpacked tree too — that directory is the whole point of the call.
  const { archive, unpacked } = stagePackagedApp();
  fs.writeFileSync(path.join(unpacked, 'runanywhere_native.node'), '');

  const addonDir = path.dirname(asarUnpacked(path.join(archive, 'runanywhere_native.node')));
  assert.equal(addonDir, unpacked);
});

test('resolveCommonsLibrary finds commons staged in the unpacked tree', () => {
  // The regression: the addon loads from the archive because Electron patches
  // process.dlopen, so addonDir is an archive path. Joining the commons name
  // onto it and existence-checking that used to be the whole resolver, which
  // meant the one consumer that needs a real disk path never got one.
  const { archive, unpacked } = stagePackagedApp();
  for (const name of COMMONS_FILE_NAMES) fs.writeFileSync(path.join(unpacked, name), '');

  const resolved = resolveCommonsLibrary(archive);
  assert.ok(resolved, 'commons should resolve out of app.asar.unpacked');
  assert.equal(path.dirname(resolved), unpacked);
});

test('resolveCommonsLibrary reports nothing when commons was not staged', () => {
  const { archive } = stagePackagedApp();
  assert.equal(resolveCommonsLibrary(archive), undefined);
});

test('resolveCommonsLibrary still works in an unpackaged tree', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'rac-plain-'));
  roots.push(root);
  for (const name of COMMONS_FILE_NAMES) fs.writeFileSync(path.join(root, name), '');

  const resolved = resolveCommonsLibrary(root);
  assert.ok(resolved, 'commons should resolve from a plain directory');
  assert.equal(path.dirname(resolved), root);
});
