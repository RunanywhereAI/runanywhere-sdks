/**
 * OPFS download-persistence browser test (issue #1174).
 *
 * Real-browser companion to the unit suite in
 * `packages/core/tests/unit/Public/ModelRegistryHydration.test.ts`, which can
 * only install fake `FileSystemDirectoryHandle` objects. This spec instead:
 *
 *   1. writes a tiny model payload into the ORIGIN'S REAL OPFS via
 *      `navigator.storage.getDirectory()`,
 *   2. hydrates the registry through the public facade and asserts the row
 *      reads DOWNLOADED with the canonical `/opfs/...` localPath,
 *   3. calls the native registry refresh with an explicit `pruneOrphans: true`
 *      opt-in — which must be IGNORED on Web because native probes see only
 *      MEMFS — and asserts the healthy OPFS-only row survives (the #1169
 *      regression guard),
 *   4. hard-reloads the page, re-registers the row (any host app re-registers
 *      its catalog on every boot), runs the native rescan AND the OPFS
 *      hydration again, and asserts the row is STILL downloaded,
 *   5. purges the OPFS bytes and asserts hydration reports the row as NOT
 *      downloaded (negative reconciliation against real OPFS).
 *
 * No network, no model downloads: hydration only consults file existence and
 * the 80% size-completeness threshold in `resolveHydratedModelPath`, so a
 * 64-byte payload registered with `sizeBytes: 64` behaves like a real
 * download for every registry/reconciliation path this journey exercises.
 */
import { test, expect } from '@playwright/test';
import { resolve } from 'node:path';

// Repo root, resolved from this file's location, so the Vite `/@fs/...`
// imports work from any checkout location and on any OS. Override with
// `RA_REPO_ROOT` when running against a different layout (mirrors
// multi-wasm-init.spec.ts).
//
// Vite's /@fs handler wants the absolute path INCLUDING its leading
// separator after the prefix: `/@fs/<abs>` matches both this Windows dev box
// (`/@fs/D:/...`) and POSIX checkouts (`/@fs/home/...`), where a missing
// slash on Windows silently falls through to the SPA HTML fallback.
const REPO_ROOT = (process.env.RA_REPO_ROOT ?? resolve(__dirname, '..', '..', '..', '..'))
  .replace(/\\/g, '/');

/** Vite-serve an absolute repo path from the example dev server. */
function viteModuleUrl(absRepoPath: string): string {
  const normalized = absRepoPath.replaceAll('\\', '/');
  const withSeparator = normalized.startsWith('/') ? normalized : `/${normalized}`;
  return `/@fs${withSeparator}`;
}

const FRAMEWORK_OPFS_PATHS_URL = viteModuleUrl(
  `${REPO_ROOT}/bindings/web/packages/core/src/Infrastructure/FrameworkOPFSPaths.ts`,
);
const PROTO_MODEL_TYPES_URL = viteModuleUrl(
  `${REPO_ROOT}/bindings/proto-ts/src/model_types.ts`,
);

const TEST_MODEL_ID = 'opfs-reload-persistence-test';
const TEST_MODEL_URL = `https://example.test/${TEST_MODEL_ID}/model.gguf`;
/** 64-byte payload vs registered `sizeBytes: 64` → passes the completeness check. */
const PAYLOAD_BYTES = 64;

/** Generated proto `ModelInfo` subset the registry reads/writes expose. */
interface CatalogRow {
  registryStatus: number;
  localPath: string;
}

/** The app publishes the full public `RunAnywhere` facade on this global. */
interface HarnessSdk {
  models: {
    register(model: {
      id: string;
      name: string;
      framework: number;
      category: number;
      format: number;
      description?: string;
    } & { url: string; sizeBytes: number; memoryRequiredBytes?: number }): CatalogRow;
    get(id: string): CatalogRow | null;
    refresh(options?: { rescanLocal?: boolean; pruneOrphans?: boolean }): Promise<void>;
  };
  storage: {
    refresh(): Promise<number>;
  };
}

interface BootSnapshot {
  ready: boolean;
  state: string;
}

/**
 * The example app publishes its boot progress and the SDK singleton on
 * `window`. The globals are narrowed here instead of `declare global` so this
 * spec participates in the repo's `tsconfig.browser.json` program without
 * colliding with the (not-included) specs that type the same names
 * differently.
 */
interface TestWindow extends Window {
  __RUNANYWHERE_AI_READY__?: BootSnapshot;
  __RUNANYWHERE_SDK__?: HarnessSdk;
}

/** Proto enums + framework OPFS dir, resolved once per browser page. */
interface PageConstants {
  frameworkDir: string;
  downloaded: number;
  loaded: number;
  registered: number;
}

interface PageModelTypes {
  InferenceFramework: { INFERENCE_FRAMEWORK_LLAMA_CPP: number };
  ModelCategory: { MODEL_CATEGORY_LANGUAGE: number };
  ModelFormat: { MODEL_FORMAT_GGUF: number };
  ModelRegistryStatus: {
    MODEL_REGISTRY_STATUS_DOWNLOADED: number;
    MODEL_REGISTRY_STATUS_LOADED: number;
    MODEL_REGISTRY_STATUS_REGISTERED: number;
  };
}

test.describe('OPFS download persistence across reload (#1174)', () => {
  test(
    'OPFS-only download survives reload + native refresh, and purge is reconciled',
    async ({ page }, testInfo) => {
      test.setTimeout(120_000);

      const fatalErrors: string[] = [];
      page.on('console', (msg) => {
        if (msg.type() === 'error') fatalErrors.push(msg.text());
      });
      page.on('pageerror', (err) => fatalErrors.push(`pageerror: ${err.message}`));

      const stages: Array<{ stage: string; row: CatalogRow | null }> = [];
      const record = (stage: string, row: CatalogRow | null | undefined): void => {
        stages.push({
          stage,
          row: row
            ? { registryStatus: row.registryStatus, localPath: row.localPath }
            : null,
        });
      };

      /** Read + record a row, failing when it must exist. */
      const readRow = async (stage: string, id: string): Promise<CatalogRow> => {
        const row = await page.evaluate(
          (modelId) => (window as TestWindow).__RUNANYWHERE_SDK__?.models.get(modelId) ?? undefined,
          id,
        );
        record(stage, row);
        expect(row, `${stage}: registry row missing for '${id}'`).toBeTruthy();
        return row as CatalogRow;
      };

      /** Read + record a row that may legitimately be absent. */
      const readOptionalRow = async (stage: string, id: string): Promise<CatalogRow | null> => {
        const row = await page.evaluate(
          (modelId) => (window as TestWindow).__RUNANYWHERE_SDK__?.models.get(modelId) ?? undefined,
          id,
        );
        record(stage, row);
        return row ?? null;
      };

      /** Wait for the example app's boot contract (initial load or reload). */
      const waitForBoot = async (): Promise<void> => {
        await page.waitForFunction(
          () => {
            const snapshot = (window as TestWindow).__RUNANYWHERE_AI_READY__;
            return Boolean(snapshot && snapshot.ready);
          },
          null,
          { timeout: 90_000 },
        );
        await page.waitForFunction(
          () => Boolean((window as TestWindow).__RUNANYWHERE_SDK__),
          null,
          { timeout: 10_000 },
        );
      };

      // ---- Boot ------------------------------------------------------------
      await page.goto('/');
      await waitForBoot();

      // Resolve constants + register the fixture row in one page pass so the
      // catalog entry, framework dir, and enum values all come from the SDK's
      // own modules (no hard-coded path tree or enum numbers in this spec).
      const constants: PageConstants = await page.evaluate(
        async ({ id, url, pathsUrl, typesUrl }) => {
          const frameworkPaths = await import(pathsUrl);
          const protoTypes: PageModelTypes = await import(typesUrl);
          const frameworkDir = frameworkPaths.frameworkOPFSDir(
            protoTypes.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
          );
          if (!frameworkDir) throw new Error('frameworkOPFSDir returned null for LlamaCpp');

          const sdkInstance = (window as TestWindow).__RUNANYWHERE_SDK__;
          if (!sdkInstance) throw new Error('window.__RUNANYWHERE_SDK__ was not published');
          sdkInstance.models.register({
            id,
            name: 'OPFS reload persistence probe',
            framework: protoTypes.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
            category: protoTypes.ModelCategory.MODEL_CATEGORY_LANGUAGE,
            format: protoTypes.ModelFormat.MODEL_FORMAT_GGUF,
            url,
            sizeBytes: 64,
            memoryRequiredBytes: 1_048_576,
            description: 'browser fixture for issue #1174',
          });
          return {
            frameworkDir,
            downloaded: protoTypes.ModelRegistryStatus.MODEL_REGISTRY_STATUS_DOWNLOADED,
            loaded: protoTypes.ModelRegistryStatus.MODEL_REGISTRY_STATUS_LOADED,
            registered: protoTypes.ModelRegistryStatus.MODEL_REGISTRY_STATUS_REGISTERED,
          };
        },
        { id: TEST_MODEL_ID, url: TEST_MODEL_URL, pathsUrl: FRAMEWORK_OPFS_PATHS_URL, typesUrl: PROTO_MODEL_TYPES_URL },
      );

      const registeredRow = await readRow('registered (fresh row carries no artifacts)', TEST_MODEL_ID);
      expect(registeredRow.registryStatus, 'registered row must start REGISTERED')
        .toBe(constants.registered);
      expect(registeredRow.localPath, 'registered row must start without a localPath').toBe('');

      // ---- Write real OPFS bytes at the canonical hydration path -----------
      const modelDirSegments = ['RunAnywhere', 'Models', constants.frameworkDir, TEST_MODEL_ID];
      const modelLocalPath = `/opfs/${modelDirSegments.join('/')}/model.gguf`;

      const written = await page.evaluate(
        ({ dirSegments, fileName, byteCount }) => {
          return (async () => {
            let dir = await navigator.storage.getDirectory();
            for (const segment of dirSegments) {
              dir = await dir.getDirectoryHandle(segment, { create: true });
            }
            const fileHandle = await dir.getFileHandle(fileName, { create: true });
            const writable = await fileHandle.createWritable();
            await writable.write(new Uint8Array(byteCount).fill(0x41));
            await writable.close();
            return (await fileHandle.getFile()).size;
          })();
        },
        { dirSegments: modelDirSegments, fileName: 'model.gguf', byteCount: PAYLOAD_BYTES },
      );
      expect(written, 'OPFS write did not persist the payload bytes').toBe(PAYLOAD_BYTES);

      // ---- Hydrate: OPFS-aware positive linking ----------------------------
      await page.evaluate(() => {
        const sdkInstance = (window as TestWindow).__RUNANYWHERE_SDK__;
        if (!sdkInstance) throw new Error('window.__RUNANYWHERE_SDK__ was not published');
        return sdkInstance.storage.refresh();
      });
      const linked = await readRow('hydrated (session 1)', TEST_MODEL_ID);
      const isDownloadedStatus = (row: CatalogRow): boolean =>
        row.registryStatus === constants.downloaded || row.registryStatus === constants.loaded;
      expect(isDownloadedStatus(linked),
        `hydration should mark the OPFS-only download DOWNLOADED, got ${JSON.stringify(linked)}`).toBe(true);
      expect(linked.localPath).toBe(modelLocalPath);

      // ---- Native refresh must not clobber the OPFS-only row (#1169) -------
      // The explicit `pruneOrphans: true` opt-in is REQUIRED to be ignored on
      // Web: native probes read only MEMFS, which holds no copy of these
      // bytes. With orphan pruning enabled (pre-#1169) this refresh clears
      // the row and every later assertion fails.
      const nativeRefreshed = await page.evaluate(
        async ({ id }: { id: string }) => {
          const sdkInstance = (window as TestWindow).__RUNANYWHERE_SDK__;
          if (!sdkInstance) throw new Error('window.__RUNANYWHERE_SDK__ was not published');
          await sdkInstance.models.refresh({ rescanLocal: true, pruneOrphans: true });
          return { row: sdkInstance.models.get(id) };
        },
        { id: TEST_MODEL_ID },
      );
      record('after native refresh (pruneOrphans ignored)', nativeRefreshed.row);
      expect(nativeRefreshed.row && isDownloadedStatus(nativeRefreshed.row),
        `native refresh cleared an OPFS-only download: ${JSON.stringify(nativeRefreshed.row)}`).toBe(true);

      // Once more through hydration: complete OPFS bytes must stay linked.
      await page.evaluate(() => {
        const sdkInstance = (window as TestWindow).__RUNANYWHERE_SDK__;
        if (!sdkInstance) throw new Error('window.__RUNANYWHERE_SDK__ was not published');
        return sdkInstance.storage.refresh();
      });
      const stillLinked = await readRow('idempotent hydration (session 1)', TEST_MODEL_ID);
      expect(isDownloadedStatus(stillLinked),
        `idempotent hydration unlinked a healthy download: ${JSON.stringify(stillLinked)}`).toBe(true);

      // ---- Session 2: real page reload -------------------------------------
      // The reload destroys the WASM heap (empty MEMFS + fresh registry).
      // After boot the fixture row does not exist until the "catalog"
      // registers it again — exactly the cold-start contract of every host
      // app. The OPFS bytes are the only surviving state.
      await page.reload();
      await waitForBoot();
      expect(await readOptionalRow('after reload (no re-registration yet)', TEST_MODEL_ID),
        'fresh WASM heap must not hallucinate the fixture row').toBeNull();

      // Re-register the row as a fresh catalog would, run the native rescan
      // (which reads only MEMFS and must find nothing to prune or clear),
      // then hydrate — the OPFS-only download must come back as downloaded.
      await page.evaluate(
        async ({ id, url, typesUrl }) => {
          const protoTypes: PageModelTypes = await import(typesUrl);
          const sdkInstance = (window as TestWindow).__RUNANYWHERE_SDK__;
          if (!sdkInstance) throw new Error('window.__RUNANYWHERE_SDK__ was not published');
          sdkInstance.models.register({
            id,
            name: 'OPFS reload persistence probe',
            framework: protoTypes.InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
            category: protoTypes.ModelCategory.MODEL_CATEGORY_LANGUAGE,
            format: protoTypes.ModelFormat.MODEL_FORMAT_GGUF,
            url,
            sizeBytes: 64,
            memoryRequiredBytes: 1_048_576,
            description: 'browser fixture for issue #1174',
          });
        },
        { id: TEST_MODEL_ID, url: TEST_MODEL_URL, typesUrl: PROTO_MODEL_TYPES_URL },
      );
      await page.evaluate(() => {
        const sdkInstance = (window as TestWindow).__RUNANYWHERE_SDK__;
        if (!sdkInstance) throw new Error('window.__RUNANYWHERE_SDK__ was not published');
        sdkInstance.models.refresh({ rescanLocal: true });
        return sdkInstance.storage.refresh();
      });
      const rehydrated = await readRow(
        'after reload + re-register + native refresh + hydration',
        TEST_MODEL_ID,
      );
      expect(isDownloadedStatus(rehydrated),
        `OPFS-only download did not survive reload + refresh: ${JSON.stringify(rehydrated)}`).toBe(true);
      expect(rehydrated.localPath).toBe(modelLocalPath);

      // ---- Purge: deleted OPFS bytes must clear the row --------------------
      const purged = await page.evaluate(
        async ({ id, frameworkDirSegments }) => {
          const sdkInstance = (window as TestWindow).__RUNANYWHERE_SDK__;
          if (!sdkInstance) throw new Error('window.__RUNANYWHERE_SDK__ was not published');
          const steps: string[] = [];
          try {
            let dir = await navigator.storage.getDirectory();
            for (const segment of frameworkDirSegments) {
              dir = await dir.getDirectoryHandle(segment, { create: false });
              steps.push(segment);
            }
            await dir.removeEntry(id, { recursive: true });
            steps.push(`removeEntry(${id})`);
            const patched = await sdkInstance.storage.refresh();
            steps.push(`storage.refresh -> ${patched}`);
            return { patched, steps, row: sdkInstance.models.get(id) };
          } catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            throw new Error(`purge failed at ${steps.join('>')} (${message})`);
          }
        },
        { id: TEST_MODEL_ID, frameworkDirSegments: modelDirSegments.slice(0, -1) },
      );
      record('after purge + hydration (session 2)', purged.row);
      expect(purged.patched, 'hydration must reconcile exactly the purged row').toBe(1);
      expect(purged.row?.registryStatus, `purged row still downloaded: ${JSON.stringify(purged.row)}`)
        .toBe(constants.registered);
      expect(purged.row?.localPath ?? '', 'purged row must lose its localPath').toBe('');

      // ---- Hygiene: no fatal console/page errors ---------------------------
      const fatal = fatalErrors.filter(
        (err) => !(
          err.includes('Device registration')
          || err.includes('model assignment base URL is not configured')
          || err.includes('Failed to load resource')
        ),
      );
      expect(fatal, `unexpected console/page errors:\n${fatal.join('\n')}`).toHaveLength(0);

      await testInfo.attach('stage-history', {
        body: JSON.stringify(stages, null, 2),
        contentType: 'application/json',
      });
    },
  );
});
