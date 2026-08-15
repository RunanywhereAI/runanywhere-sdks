// Unit tests for backend plugin artifact resolution.
//
// The asar cases are the ones with teeth: a packaged Electron app resolves a
// backend package root from `__dirname`, which points INSIDE app.asar, and the
// OS loader cannot open a path in an archive. These assert the rewrite to the
// unpacked copy happens, and — just as important — that it does not happen when
// there is nothing unpacked to rewrite to.
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { test } from 'node:test';

import {
  BackendPluginId,
  pluginLibraryFileName,
  resolvePluginArtifactPath,
} from '../../dist/backend/plugin-registry';

/** A throwaway `<root>/app.asar[.unpacked]/...` layout for one backend. */
function stageAsarLayout(options: { unpack: boolean }): {
  root: string;
  packageRoot: string;
  unpackedFile: string;
} {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ra-asar-'));
  const rel = path.join(
    'node_modules',
    '@runanywhere',
    'electron-sherpa'
  );
  const packageRoot = path.join(root, 'app.asar', rel);
  const leaf = path.join(
    'prebuilds',
    `${process.platform}-${process.arch}`,
    pluginLibraryFileName(BackendPluginId.Sherpa)
  );
  const unpackedFile = path.join(root, 'app.asar.unpacked', rel, leaf);
  if (options.unpack) {
    fs.mkdirSync(path.dirname(unpackedFile), { recursive: true });
    fs.writeFileSync(unpackedFile, 'not a real dylib');
  }
  return { root, packageRoot, unpackedFile };
}

test('a plain package root resolves to prebuilds/<platform>-<arch>/<lib>', () => {
  const packageRoot = path.join(path.sep, 'tmp', 'pkg');
  assert.equal(
    resolvePluginArtifactPath({ id: BackendPluginId.Sherpa, packageRoot }),
    path.join(
      packageRoot,
      'prebuilds',
      `${process.platform}-${process.arch}`,
      pluginLibraryFileName(BackendPluginId.Sherpa)
    )
  );
});

test('a path inside app.asar resolves to the unpacked file that really exists', () => {
  const { root, packageRoot, unpackedFile } = stageAsarLayout({ unpack: true });
  try {
    assert.equal(
      resolvePluginArtifactPath({ id: BackendPluginId.Sherpa, packageRoot }),
      unpackedFile
    );
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('app.asar is left alone when nothing was unpacked beside it', () => {
  // Rewriting unconditionally would replace a path that at least resolves
  // through Electron's fs shim with one that exists nowhere at all.
  const { root, packageRoot } = stageAsarLayout({ unpack: false });
  try {
    const resolved = resolvePluginArtifactPath({ id: BackendPluginId.Sherpa, packageRoot });
    assert.ok(
      resolved.includes(`app.asar${path.sep}`),
      'unpacked copy is absent, so the original path must survive'
    );
    assert.ok(!resolved.includes('app.asar.unpacked'), 'must not invent an unpacked path');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('a package root merely containing the text "asar" is not rewritten', () => {
  const packageRoot = path.join(path.sep, 'tmp', 'asarcompany', 'pkg');
  const resolved = resolvePluginArtifactPath({ id: BackendPluginId.ONNX, packageRoot });
  assert.ok(resolved.startsWith(packageRoot), 'only a real app.asar segment is a container');
});
