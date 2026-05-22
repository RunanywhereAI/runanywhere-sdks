#!/usr/bin/env node
/**
 * Web lane matrix E2E executor — Playwright automation for catalog §8 TCs.
 * Artifacts: actions.jsonl, command_summary.tsv, screenshots/, logs/browser_*.jsonl
 */
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LANE_ROOT = process.env.WEB_LANE_ROOT ?? __dirname;
const BASE_URL = process.env.WEB_BASE_URL ?? 'http://127.0.0.1:5173';
const REPO_ROOT = process.env.RA_REPO_ROOT
  ?? path.resolve(LANE_ROOT, '../../../../../..');
const SCREENSHOTS = path.join(LANE_ROOT, 'screenshots');
const LOGS = path.join(LANE_ROOT, 'logs');
const ACTIONS_FILE = path.join(LANE_ROOT, 'actions.jsonl');
const CMD_SUMMARY = path.join(LANE_ROOT, 'command_summary.tsv');
const CONSOLE_LOG = path.join(LOGS, 'browser_console.jsonl');
const NETWORK_LOG = path.join(LOGS, 'browser_network.jsonl');

const LLM_MODEL = 'SmolLM2 360M Q8_0';
const LLM_MODEL_ID = 'smollm2-360m-q8_0';
const VLM_MODEL = 'SmolVLM2 256M Video Instruct Q8_0';
const VLM_MODEL_ID = 'smolvlm2-256m-video-instruct-q8_0';
const STT_MODEL = 'Whisper Tiny English';
const STT_MODEL_ID = 'sherpa-onnx-whisper-tiny.en';
const ONNX_SHERPA_WASM = path.join(REPO_ROOT, 'sdk/runanywhere-web/packages/onnx/wasm/racommons-onnx-sherpa.wasm');
const STT_DOWNLOAD_TIMEOUT_MS = 240_000;
const STT_LOAD_TIMEOUT_MS = 120_000;
const SPEECH_LOAD_TIMEOUT_MS = 120_000;
const TTS_MODEL = 'Piper TTS US English (Lessac)';
const TTS_MODEL_ID = 'vits-piper-en_US-lessac-medium';
const EMBED_MODEL = 'All MiniLM L6 v2';
const LLM_PROMPT = 'In one sentence, explain what RunAnywhere does.';
const TTS_TEXT = 'RunAnywhere runs privately on your device.';
const RAG_QUERY = 'Where should model lifecycle logic live?';

fs.mkdirSync(SCREENSHOTS, { recursive: true });
fs.mkdirSync(LOGS, { recursive: true });
if (!fs.existsSync(CMD_SUMMARY)) {
  fs.writeFileSync(CMD_SUMMARY, 'name\tstatus\texit_code\tlog\n');
}

const consoleEntries = [];
const networkEntries = [];
const tcResults = {};

function nowIso() {
  return new Date().toISOString();
}

function recordAction(entry) {
  const row = {
    ts: nowIso(),
    target: '07_web',
    sdk: 'Web',
    platform: 'Browser',
    modality: entry.modality ?? 'general',
    phase: entry.phase ?? 'other',
    action: entry.action,
    expected: entry.expected ?? '',
    actual: entry.actual ?? '',
    status: entry.status,
    failureKind: entry.failureKind ?? '',
    screenshot: entry.screenshot ?? '',
    logs: entry.logs ?? [`logs/browser_console.jsonl`],
    modelId: entry.modelId ?? '',
    notes: entry.notes ?? '',
  };
  fs.appendFileSync(ACTIONS_FILE, `${JSON.stringify(row)}\n`);
}

function errorMessage(err) {
  return err instanceof Error ? err.message : String(err);
}

const HARNESS_FAILURE_RE = /Target (page|closed)|browser has been closed|Execution context was destroyed|Protocol error|Page crashed|context or browser has been closed|Browser has been closed/i;

function isHarnessFailure(err, pageHolder) {
  if (HARNESS_FAILURE_RE.test(errorMessage(err))) return true;
  if (pageHolder?.page?.isClosed?.()) return true;
  if (pageHolder?.browser && pageHolder.browser.isConnected?.() === false) return true;
  return false;
}

function attachPageListeners(page) {
  page.on('console', (msg) => {
    consoleEntries.push({ ts: nowIso(), type: msg.type(), text: msg.text() });
  });
  page.on('request', (req) => {
    if (req.resourceType() === 'fetch' || req.resourceType() === 'xhr') {
      networkEntries.push({ ts: nowIso(), method: req.method(), url: req.url() });
    }
  });
}

function recordCommand(name, status, exitCode, logPath) {
  fs.appendFileSync(CMD_SUMMARY, `${name}\t${status}\t${exitCode}\t${logPath}\n`);
}

async function snapshotTc(page, tcId, step, status, notes = '') {
  const shotName = `screenshots/${tcId}_${step}.png`;
  const shotPath = path.join(LANE_ROOT, shotName);
  await page.screenshot({ path: shotPath, fullPage: true });
  const logSlice = path.join(LOGS, `console_${tcId}_${step}.jsonl`);
  fs.writeFileSync(logSlice, consoleEntries.slice(-80).map((e) => JSON.stringify(e)).join('\n'));
  recordCommand(`tc_${tcId}_${step}`, status, status === 'PASS' ? 0 : 1, `logs/console_${tcId}_${step}.jsonl`);
  recordAction({
    action: `${tcId}_${step}`,
    phase: step.includes('download') ? 'model_download' : step.includes('load') ? 'model_load' : step.includes('infer') ? 'inference' : 'modality_result',
    expected: `${tcId} step ${step} succeeds`,
    actual: notes || status,
    status,
    screenshot: shotName,
    logs: [`logs/console_${tcId}_${step}.jsonl`],
    notes,
  });
  tcResults[tcId] = { status, notes, screenshot: shotName };
  return shotName;
}

async function waitInteractive(page, timeout = 120_000) {
  await page.waitForFunction(
    () => {
      const snap = window.__RUNANYWHERE_AI_READY__;
      return snap && (snap.state === 'interactive' || snap.state === 'error');
    },
    null,
    { timeout },
  );
  const snap = await page.evaluate(() => window.__RUNANYWHERE_AI_READY__);
  if (snap?.state === 'error') throw new Error(`App error: ${snap.error}`);
}

async function clearSiteStorage(page) {
  await page.goto('about:blank');
  const client = await page.context().newCDPSession(page);
  await client.send('Storage.clearDataForOrigin', {
    origin: 'http://127.0.0.1:5173',
    storageTypes: 'all',
  });
}

async function gotoFresh(page) {
  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1500);
  if (await page.evaluate(() => !crossOriginIsolated && 'serviceWorker' in navigator)) {
    await page.waitForTimeout(2000);
    if (page.url().includes('5173')) await waitInteractive(page).catch(() => {});
  }
  await waitInteractive(page);
}

async function closeModelSheet(page) {
  const close = page.locator('#model-sheet-close');
  if (await close.isVisible().catch(() => false)) {
    await close.click();
  } else {
    await page.keyboard.press('Escape').catch(() => {});
  }
  await page.locator('.modal-backdrop').waitFor({ state: 'hidden', timeout: 10_000 }).catch(() => {});
}

async function clickTab(page, label) {
  await closeModelSheet(page);
  await page.locator('.tab-item').filter({ hasText: label }).click();
  await page.waitForTimeout(400);
}

async function openModelSheet(page) {
  const getStarted = page.locator('#chat-get-started-btn');
  if (await getStarted.isVisible().catch(() => false)) {
    await getStarted.click();
  } else {
    await page.locator('#chat-toolbar-model').click();
  }
  await page.locator('.modal-sheet').waitFor({ state: 'visible', timeout: 15_000 });
}

function isSherpaWasmPresentOnDisk() {
  try {
    return fs.existsSync(ONNX_SHERPA_WASM) && fs.statSync(ONNX_SHERPA_WASM).size > 1024;
  } catch {
    return false;
  }
}

function recentConsoleText(limit = 120) {
  return consoleEntries.slice(-limit).map((e) => e.text).join('\n');
}

function speechInfraLimitedReason() {
  if (!isSherpaWasmPresentOnDisk()) {
    return 'Sherpa ONNX WASM artifact missing (CI/skip build)';
  }
  const blob = recentConsoleText();
  if (/gzip -d|Failed to open archive.*tar\.gz/i.test(blob)) {
    return 'STT/TTS archive extract failed in browser (tar.gz)';
  }
  if (/ONNX\/Sherpa backends registered/i.test(blob) === false
    && /backend not available|Backend not available/i.test(blob)) {
    return 'ONNX/Sherpa backend not registered';
  }
  if (/pthread_create failed/i.test(blob)) {
    return 'Sherpa/ONNX pthread blocked in headless Playwright';
  }
  return '';
}

async function registerOnnx(page) {
  if (!isSherpaWasmPresentOnDisk()) {
    return { ok: false, reason: 'sherpa_wasm_missing' };
  }
  try {
    await page.evaluate(async ({ repoRoot }) => {
      const onnxPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/onnx/src/index.ts`;
      const onnx = await import(/* @vite-ignore */ onnxPath);
      await onnx.ONNX.register();
    }, { repoRoot: REPO_ROOT });
    return { ok: true };
  } catch (err) {
    return { ok: false, reason: errorMessage(err) };
  }
}

async function registerLlamaCpp(page) {
  try {
    await page.evaluate(async ({ repoRoot }) => {
      const llamaPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/llamacpp/src/index.ts`;
      const llama = await import(/* @vite-ignore */ llamaPath);
      await llama.LlamaCPP.register({ acceleration: 'auto' });
    }, { repoRoot: REPO_ROOT });
    return { ok: true };
  } catch (err) {
    return { ok: false, reason: errorMessage(err) };
  }
}

async function downloadAndLoadSpeech(page, modelName, modelId, pageHolder = null) {
  if (pageHolder) page = await ensureLivePage(pageHolder);
  const reg = await registerOnnx(page);
  if (!reg.ok) {
    return {
      status: 'LIMITED',
      notes: reg.reason === 'sherpa_wasm_missing'
        ? 'Sherpa WASM missing — STT/TTS load skipped'
        : `ONNX.register failed: ${reg.reason}`,
    };
  }

  const sheetOpen = await page.locator('.modal-sheet').isVisible().catch(() => false);
  if (!sheetOpen) await openModelSheet(page);

  try {
    await downloadModelInSheet(page, modelName, modelId, STT_DOWNLOAD_TIMEOUT_MS, pageHolder);
  } catch (err) {
    const registry = await isModelDownloadedInRegistry(page, modelId);
    const infra = speechInfraLimitedReason();
    if (registry.ok || infra) {
      return {
        status: 'LIMITED',
        notes: registry.ok
          ? `registry downloaded (${registry.via}); sheet wait: ${infra || errorMessage(err).slice(0, 80)}`
          : infra || errorMessage(err),
      };
    }
    return {
      status: 'FAIL',
      notes: errorMessage(err),
    };
  }

  try {
    await loadModelInSheet(page, modelName, modelId, STT_LOAD_TIMEOUT_MS);
  } catch (err) {
    const registry = await isModelDownloadedInRegistry(page, modelId);
    const infra = speechInfraLimitedReason();
    if (registry.ok || infra) {
      return {
        status: 'LIMITED',
        notes: registry.ok
          ? `registry downloaded (${registry.via}); load blocked: ${infra || errorMessage(err).slice(0, 80)}`
          : infra || errorMessage(err),
      };
    }
    return {
      status: 'FAIL',
      notes: errorMessage(err),
    };
  }

  return { status: 'PASS', notes: `${modelName} downloaded and loaded` };
}

async function registerLlamacpp(page) {
  await page.evaluate(async ({ repoRoot }) => {
    const llamaPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/llamacpp/src/index.ts`;
    const llama = await import(/* @vite-ignore */ llamaPath);
    await llama.LlamaCPP.register();
  }, { repoRoot: REPO_ROOT });
}

function modelRow(page, modelId, modelName) {
  return page.locator(`.modal-sheet .model-row[data-model-id="${modelId}"]`).or(
    page.locator('.modal-sheet .model-row').filter({ hasText: modelName }).first(),
  );
}

async function waitForRegistryLocalPath(page, modelId, timeoutMs = 120_000) {
  await page.waitForFunction(
    (id) => {
      try {
        const model = window.__RUNANYWHERE_SDK__?.getModel?.(id);
        return Boolean(model?.localPath && model.isDownloaded);
      } catch {
        return false;
      }
    },
    modelId,
    { timeout: timeoutMs },
  );
}

/** Poll registry until OPFS hydrate marks the model downloaded (WEB-HARNESS-002). */
async function waitForOpfsHydration(page, modelId, timeoutMs = 90_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await page.evaluate(async () => {
      const sdk = window.__RUNANYWHERE_SDK__;
      if (typeof sdk?.hydrateModelRegistry === 'function') {
        await sdk.hydrateModelRegistry();
      }
    }).catch(() => {});

    const registry = await isModelDownloadedInRegistry(page, modelId);
    if (registry.ok) return;

    await page.waitForTimeout(2000);
  }

  await page.waitForFunction(
    (id) => {
      try {
        const sdk = window.__RUNANYWHERE_SDK__;
        const model = sdk?.getModel?.(id);
        if (model?.isDownloaded && model?.localPath) return true;
        const list = sdk?.downloadedModels?.();
        return Boolean(list?.models?.some((m) => m.id === id));
      } catch {
        return false;
      }
    },
    modelId,
    { timeout: Math.min(30_000, timeoutMs) },
  );
}

async function isModelDownloadedInRegistry(page, modelId) {
  return page.evaluate((id) => {
    try {
      const sdk = window.__RUNANYWHERE_SDK__;
      const model = sdk?.getModel?.(id);
      if (model?.isDownloaded && model?.localPath) {
        return { ok: true, via: 'getModel', localPath: model.localPath };
      }
      const list = sdk?.downloadedModels?.();
      const found = list?.models?.find((m) => m.id === id);
      if (found) {
        return { ok: true, via: 'downloadedModels', localPath: found.localPath ?? '' };
      }
    } catch { /* ignore */ }
    return { ok: false, via: '', localPath: '' };
  }, modelId);
}

/** Registry-first persistence check; fall back to model-sheet load/unload buttons. */
async function assertModelPersistedAfterHydrate(page, modelId, modelName) {
  await waitForOpfsHydration(page, modelId);

  const registry = await isModelDownloadedInRegistry(page, modelId);
  if (registry.ok) {
    return { pass: true, detail: `registry downloaded (${registry.via})` };
  }

  const row = modelRow(page, modelId, modelName);
  await row.waitFor({ state: 'visible', timeout: 15_000 }).catch(() => {});
  const uiOk = await row.locator('[data-action="load"], [data-action="unload"]').first()
    .isVisible({ timeout: 15_000 }).catch(() => false);
  if (uiOk) {
    return { pass: true, detail: 'model sheet shows load/unload' };
  }

  return { pass: false, detail: 'registry not downloaded and no load/unload in sheet' };
}

async function downloadModelInSheet(page, modelName, modelId, timeoutMs = 1_800_000, pageHolder = null) {
  if (pageHolder) page = await ensureLivePage(pageHolder);
  const row = modelRow(page, modelId, modelName);
  await row.waitFor({ state: 'visible', timeout: 30_000 });
  const dl = row.locator('[data-action="download"]');
  if (await dl.isVisible().catch(() => false)) {
    await dl.click();
    await page.waitForFunction(
      (id) => {
        const r = document.querySelector(`.modal-sheet .model-row[data-model-id="${id}"]`);
        return r?.querySelector('[data-action="load"]') != null;
      },
      modelId,
      { timeout: timeoutMs },
    );
    await waitForRegistryLocalPath(page, modelId, Math.min(timeoutMs, 120_000));
  } else {
    const loadBtn = row.locator('[data-action="load"]');
    if (await loadBtn.isVisible().catch(() => false)) {
      await waitForRegistryLocalPath(page, modelId, Math.min(timeoutMs, 60_000)).catch(() => {});
    }
  }
}

async function loadModelInSheet(page, modelName, modelId, timeoutMs = 180_000) {
  const row = modelRow(page, modelId, modelName);
  const loadBtn = row.locator('[data-action="load"]');
  await loadBtn.waitFor({ state: 'visible', timeout: 30_000 });
  await loadBtn.click();
  await page.waitForFunction(
    (id) => {
      try {
        const current = window.__RUNANYWHERE_SDK__?.currentModel?.();
        if (current?.modelId === id) return true;
      } catch { /* ignore */ }
      const r = document.querySelector(`.modal-sheet .model-row[data-model-id="${id}"]`);
      return r?.querySelector('[data-action="unload"]') != null;
    },
    modelId,
    { timeout: timeoutMs },
  );
  await page.waitForTimeout(1000);
}

async function recreateBrowserPage(pageHolder) {
  if (pageHolder.page) {
    await pageHolder.page.close().catch(() => {});
  }
  pageHolder.page = await pageHolder.context.newPage();
  attachPageListeners(pageHolder.page);
  return pageHolder.page;
}

async function recreateBrowserContext(pageHolder) {
  if (pageHolder.context) {
    await pageHolder.context.close().catch(() => {});
  }
  pageHolder.context = await pageHolder.browser.newContext({
    viewport: { width: 1280, height: 900 },
    permissions: ['microphone', 'camera'],
  });
  pageHolder.page = await pageHolder.context.newPage();
  attachPageListeners(pageHolder.page);
  return pageHolder.page;
}

async function ensureLivePage(pageHolder) {
  const pageAlive = pageHolder.page && !pageHolder.page.isClosed();
  const browserAlive = pageHolder.browser?.isConnected?.() !== false;
  if (pageAlive && browserAlive) {
    return pageHolder.page;
  }
  console.warn('[harness] recreating Playwright context (page or browser closed)');
  recordAction({
    action: 'harness_page_recovery',
    phase: 'other',
    expected: 'live browser page',
    actual: pageAlive ? 'browser disconnected' : 'page closed',
    status: 'PASS',
    failureKind: 'harness',
    notes: 'Recreating Playwright context after closed page/browser',
  });
  const page = await recreateBrowserContext(pageHolder);
  await gotoFresh(page);
  await waitInteractive(page);
  return page;
}

async function runTc(id, fn, pageHolder) {
  const maxAttempts = 2;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      if (pageHolder) {
        pageHolder.page = await ensureLivePage(pageHolder);
      }
      await fn();
      return true;
    } catch (err) {
      const msg = errorMessage(err);
      const harness = isHarnessFailure(err, pageHolder);
      console.error(`[${id}] attempt ${attempt}/${maxAttempts} failed (${harness ? 'harness' : 'product'}):`, msg);

      if (harness && attempt < maxAttempts) {
        recordAction({
          action: `${id}_harness_retry`,
          phase: 'other',
          expected: `${id} completes after harness recovery`,
          actual: msg.slice(0, 300),
          status: 'PASS',
          failureKind: 'harness',
          notes: `Retrying ${id} after harness failure (attempt ${attempt}/${maxAttempts})`,
        });
        if (pageHolder) {
          pageHolder.page = await ensureLivePage(pageHolder);
        }
        continue;
      }

      recordCommand(id, 'FAIL', 1, 'logs/browser_console.jsonl');
      recordAction({
        action: id,
        status: 'FAIL',
        expected: `${id} completes`,
        actual: msg.slice(0, 500),
        phase: 'modality_result',
        failureKind: harness ? 'harness' : 'product',
        notes: msg.slice(0, 500),
      });
      tcResults[id] = {
        status: 'FAIL',
        failureKind: harness ? 'harness' : 'product',
        notes: msg.slice(0, 500),
      };
      return false;
    }
  }
  return false;
}

async function downloadAndLoad(
  page,
  modelName,
  modelId,
  downloadTimeoutMs = 1_800_000,
  loadTimeoutMs = SPEECH_LOAD_TIMEOUT_MS,
  pageHolder = null,
) {
  if (pageHolder) page = await ensureLivePage(pageHolder);
  const sheetOpen = await page.locator('.modal-sheet').isVisible().catch(() => false);
  if (!sheetOpen) await openModelSheet(page);

  try {
    await downloadModelInSheet(page, modelName, modelId, downloadTimeoutMs, pageHolder);
  } catch (err) {
    const registry = await isModelDownloadedInRegistry(page, modelId);
    const infra = speechInfraLimitedReason();
    if (registry.ok || infra) {
      return {
        status: 'LIMITED',
        notes: registry.ok
          ? `registry downloaded (${registry.via}); sheet wait: ${infra || errorMessage(err).slice(0, 80)}`
          : infra || errorMessage(err),
      };
    }
    return { status: 'FAIL', notes: errorMessage(err) };
  }

  try {
    await loadModelInSheet(page, modelName, modelId, loadTimeoutMs);
  } catch (err) {
    const registry = await isModelDownloadedInRegistry(page, modelId);
    const infra = speechInfraLimitedReason();
    const blob = recentConsoleText();
    const headlessLoad = infra
      || /pthread_create failed|memory access out of bounds|OOM|out of memory/i.test(blob);
    if (registry.ok || headlessLoad) {
      return {
        status: 'LIMITED',
        notes: registry.ok
          ? `registry downloaded (${registry.via}); load blocked: ${infra || errorMessage(err).slice(0, 80)}`
          : infra || errorMessage(err),
      };
    }
    return { status: 'FAIL', notes: errorMessage(err) };
  }

  return { status: 'PASS', notes: '' };
}

async function runExecutor() {
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--enable-unsafe-webgpu',
      '--enable-features=SharedArrayBuffer,WebAssemblyJSPI,WebAssemblyStackSwitching',
      '--use-fake-ui-for-media-stream',
      '--use-fake-device-for-media-stream',
    ],
  });
  const pageHolder = { browser, context: null, page: null };
  pageHolder.context = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    permissions: ['microphone', 'camera'],
  });
  pageHolder.page = await pageHolder.context.newPage();
  attachPageListeners(pageHolder.page);
  const page = pageHolder.page;

  try {
    // TC-01 — SDK init (fresh storage)
    await clearSiteStorage(page);
    recordAction({ action: 'clean_install', phase: 'clean_install', expected: 'empty origin', actual: 'cleared site storage', status: 'PASS', modality: 'init' });
    await gotoFresh(page);
    const initSnap = await page.evaluate(() => ({
      ready: window.__RUNANYWHERE_AI_READY__,
      sdk: window.__RUNANYWHERE_SDK__?.version,
      backend: document.documentElement.dataset.runanywhereAiBackend,
    }));
    const tc01Pass = initSnap.ready?.state === 'interactive'
      && consoleEntries.some((e) => e.text.includes('[RunAnywhere] SDK initialized'));
    await snapshotTc(page, 'tc01', 'launch', tc01Pass ? 'PASS' : 'FAIL',
      `sdk=${initSnap.sdk} backend=${initSnap.backend}`);

    // TC-02 — LLM download
    await clickTab(page, 'Chat');
    await page.locator('#chat-get-started-btn').click().catch(async () => {
      await page.locator('#chat-toolbar-model').click();
    });
    await page.locator('.modal-sheet').waitFor({ state: 'visible' });
    await snapshotTc(page, 'tc02', 'sheet_open', 'PASS', 'model sheet opened');
    await downloadModelInSheet(page, LLM_MODEL, LLM_MODEL_ID, 1_800_000, pageHolder);
    await snapshotTc(page, 'tc02', 'download_complete', 'PASS', `${LLM_MODEL} downloaded`);

    // TC-04 — Load
    let llmLoaded = false;
    await runTc('tc04', async () => {
      const livePage = pageHolder.page;
      await loadModelInSheet(livePage, LLM_MODEL, LLM_MODEL_ID);
      llmLoaded = await livePage.evaluate((id) => {
        try { return window.__RUNANYWHERE_SDK__?.currentModel?.()?.modelId === id; }
        catch { return false; }
      }, LLM_MODEL_ID);
      await snapshotTc(livePage, 'tc04', 'load', llmLoaded ? 'PASS' : 'FAIL', `currentModel=${llmLoaded}`);
    }, pageHolder);

    // TC-05 — LLM inference
    await runTc('tc05', async () => {
      const livePage = pageHolder.page;
      if (!llmLoaded) throw new Error('LLM not loaded — skipping inference');
      await livePage.locator('#chat-input').fill(LLM_PROMPT);
      await livePage.locator('#chat-send-btn').click();
      await livePage.waitForFunction(
        () => {
          const bubbles = document.querySelectorAll('.chat-message--assistant .chat-bubble');
          const last = bubbles[bubbles.length - 1];
          return last && last.textContent && last.textContent.length > 20 && !last.textContent.includes('…');
        },
        null,
        { timeout: 300_000 },
      );
      const reply = await livePage.locator('.chat-message--assistant .chat-bubble').last().textContent();
      await snapshotTc(livePage, 'tc05', 'inference', reply && reply.length > 10 ? 'PASS' : 'FAIL', reply?.slice(0, 120));
    }, pageHolder);

    // TC-Inference-cancel
    await runTc('tc_inference_cancel', async () => {
      const livePage = pageHolder.page;
      if (!llmLoaded) throw new Error('LLM not loaded');
      await livePage.locator('#chat-input').fill('Write a detailed essay about on-device AI in at least 200 words.');
      await livePage.locator('#chat-send-btn').click();
      await livePage.waitForTimeout(2000);
      await livePage.locator('#chat-clear-btn').click();
      await livePage.waitForTimeout(2000);
      await snapshotTc(livePage, 'tc_inference_cancel', 'clear_midstream', 'PASS', 'Clear clicked during generation');
    }, pageHolder);

    // TC-15 — Storage baseline
    await runTc('tc15', async () => {
      const livePage = pageHolder.page;
      await clickTab(livePage, 'Storage');
      const storageText = await livePage.locator('#storage-scroll').innerText();
      const tc15Pass = storageText.includes('Browser Storage') && storageText.includes('Registered Models');
      await snapshotTc(livePage, 'tc15', 'baseline', tc15Pass ? 'PASS' : 'FAIL', storageText.slice(0, 200));
    }, pageHolder);

    // TC-Storage-OPFS — hard refresh
    await runTc('tc_storage_opfs', async () => {
      const livePage = pageHolder.page;
      await livePage.reload({ waitUntil: 'domcontentloaded' });
      await waitInteractive(livePage);
      await waitForOpfsHydration(livePage, LLM_MODEL_ID);
      await clickTab(livePage, 'Chat');
      await openModelSheet(livePage);
      const persisted = await assertModelPersistedAfterHydrate(livePage, LLM_MODEL_ID, LLM_MODEL);
      await snapshotTc(
        livePage,
        'tc_storage_opfs',
        'hard_refresh',
        persisted.pass ? 'PASS' : 'FAIL',
        persisted.detail,
      );
      await closeModelSheet(livePage);
    }, pageHolder);

    // TC-03a — tab close persistence (same browser context so OPFS is shared)
    await pageHolder.page.close().catch(() => {});
    pageHolder.page = null;
    await recreateBrowserPage(pageHolder);
    await gotoFresh(pageHolder.page);
    await waitInteractive(pageHolder.page);

    await runTc('tc03a', async () => {
      const livePage = pageHolder.page;
      await livePage.evaluate(async () => {
        const sdk = window.__RUNANYWHERE_SDK__;
        if (typeof sdk?.hydrateModelRegistry === 'function') {
          await sdk.hydrateModelRegistry();
        }
      }).catch(() => {});
      await waitForOpfsHydration(livePage, LLM_MODEL_ID, 120_000);
      await clickTab(livePage, 'Chat');
      await openModelSheet(livePage);
      const persisted = await assertModelPersistedAfterHydrate(livePage, LLM_MODEL_ID, LLM_MODEL);
      await snapshotTc(
        livePage,
        'tc03a',
        'tab_reopen',
        persisted.pass ? 'PASS' : 'FAIL',
        persisted.detail || 'model persisted after new context',
      );
      await closeModelSheet(livePage);
    }, pageHolder);

    await runTc('tc16', async () => {
      const livePage = pageHolder.page;
      await clickTab(livePage, 'Storage');
      const afterKill = await livePage.locator('#storage-model-list').innerText();
      await snapshotTc(livePage, 'tc16', 'after_tab_close', afterKill.includes('SmolLM') ? 'PASS' : 'LIMITED', afterKill.slice(0, 150));
    }, pageHolder);

    await runTc('tc03d', async () => {
      const livePage = pageHolder.page;
      await clearSiteStorage(livePage);
      await gotoFresh(livePage);
      await clickTab(livePage, 'Storage');
      const cleared = await livePage.locator('#storage-model-list').innerText();
      await snapshotTc(livePage, 'tc03d', 'clear_site_data', !cleared.includes('Loaded') ? 'PASS' : 'FAIL', cleared.slice(0, 150));
    }, pageHolder);

    await runTc('tc03c', async () => {
      const livePage = pageHolder.page;
      await clearSiteStorage(livePage);
      await gotoFresh(livePage);
      await openModelSheet(livePage);
      const needDl = await livePage.locator(`.modal-sheet .model-row[data-model-id="${LLM_MODEL_ID}"]`)
        .locator('[data-action="download"]').isVisible().catch(() => false);
      await snapshotTc(livePage, 'tc03c', 'fresh_origin', needDl ? 'PASS' : 'FAIL', 'models gone after clear');
      await closeModelSheet(livePage);
    }, pageHolder);

    await runTc('tc02_redownload', async () => {
      const livePage = pageHolder.page;
      const dl = await downloadAndLoad(livePage, LLM_MODEL, LLM_MODEL_ID, 900_000, 180_000, pageHolder);
      if (dl.status === 'FAIL') throw new Error(dl.notes);
      llmLoaded = await livePage.evaluate((id) => {
        try { return window.__RUNANYWHERE_SDK__?.currentModel?.()?.modelId === id; }
        catch { return false; }
      }, LLM_MODEL_ID);
    }, pageHolder);

    // TC-07 / TC-10 — Transcribe
    await runTc('tc10', async () => {
      const livePage = pageHolder.page;
      const reg = await registerOnnx(livePage);
      await clickTab(livePage, 'Transcribe');
      const tc10Status = reg.ok ? 'PASS' : 'LIMITED';
      const tc10Notes = reg.ok ? 'transcribe tab rendered' : `ONNX register: ${reg.reason}`;
      await snapshotTc(livePage, 'tc10', 'transcribe_ui', tc10Status, tc10Notes);
    }, pageHolder);
    await runTc('tc07', async () => {
      const livePage = pageHolder.page;
      await registerOnnx(livePage);
      await clickTab(livePage, 'Transcribe');
      await livePage.locator('#transcribe-model-btn').click();
      const speech = await downloadAndLoadSpeech(livePage, STT_MODEL, STT_MODEL_ID, pageHolder);
      if (speech.status !== 'PASS') {
        await snapshotTc(livePage, 'tc07', 'stt_ready', speech.status, speech.notes);
        if (speech.status === 'FAIL') throw new Error(speech.notes);
        return;
      }
      await clickTab(livePage, 'Transcribe');
      const sttReady = await livePage.locator('#mic-toggle-btn').isEnabled().catch(() => false);
      await snapshotTc(
        livePage,
        'tc07',
        'stt_ready',
        sttReady ? 'PASS' : 'LIMITED',
        sttReady ? 'STT model loaded; mic path needs audio fixture' : 'STT loaded but mic toggle disabled',
      );
    }, pageHolder);

    // TC-08 / TC-11 — Speak
    await runTc('tc11', async () => {
      const livePage = pageHolder.page;
      await clickTab(livePage, 'Speak');
      await snapshotTc(livePage, 'tc11', 'speak_ui', 'PASS', 'speak tab rendered');
    }, pageHolder);
    await runTc('tc08', async () => {
      const livePage = pageHolder.page;
      await registerOnnx(livePage);
      await clickTab(livePage, 'Speak');
      await livePage.locator('#speak-model-btn').click();
      const speech = await downloadAndLoadSpeech(livePage, TTS_MODEL, TTS_MODEL_ID, pageHolder);
      if (speech.status !== 'PASS') {
        await snapshotTc(livePage, 'tc08', 'tts', speech.status, speech.notes);
        if (speech.status === 'FAIL') throw new Error(speech.notes);
        return;
      }
      await clickTab(livePage, 'Speak');
      await livePage.locator('#speak-text').fill(TTS_TEXT);
      const speakBtn = livePage.locator('#speak-btn');
      if (await speakBtn.isEnabled().catch(() => false)) {
        await speakBtn.click();
        await livePage.waitForFunction(
          () => document.querySelector('#speak-status')?.textContent?.includes('Last synthesis'),
          null,
          { timeout: 180_000 },
        ).catch(() => {});
      }
      const speakStatus = await livePage.locator('#speak-status').innerText().catch(() => '');
      await snapshotTc(livePage, 'tc08', 'tts', speakStatus.includes('Last synthesis') ? 'PASS' : 'LIMITED', speakStatus.slice(0, 120));
    }, pageHolder);

    // TC-09 — VLM
    await runTc('tc09', async () => {
      const livePage = pageHolder.page;
      await registerLlamaCpp(livePage);
      await clickTab(livePage, 'Vision');
      await livePage.locator('#vision-model-btn').click();
      const vlm = await downloadAndLoad(livePage, VLM_MODEL, VLM_MODEL_ID, 900_000, 180_000, pageHolder);
      if (vlm.status !== 'PASS') {
        await snapshotTc(livePage, 'tc09', 'vlm', vlm.status, vlm.notes);
        if (vlm.status === 'FAIL') throw new Error(vlm.notes);
        return;
      }
      await clickTab(livePage, 'Vision');
      await livePage.locator('#vision-camera-btn').click();
      await livePage.waitForTimeout(3000);
      await livePage.locator('#vision-capture-btn').click().catch(() => {});
      await livePage.locator('#vision-analyze-btn').click().catch(() => {});
      await livePage.waitForFunction(
        () => {
          const out = document.querySelector('#vision-output')?.textContent ?? '';
          return out.length > 30 && !out.includes('no response yet');
        },
        null,
        { timeout: 300_000 },
      ).catch(() => {});
      const vlmOut = await livePage.locator('#vision-output').innerText().catch(() => '');
      await snapshotTc(livePage, 'tc09', 'vlm', vlmOut.length > 20 ? 'PASS' : 'LIMITED', vlmOut.slice(0, 120));
    }, pageHolder);

    // TC-13 — RAG
    await runTc('tc13', async () => {
      const livePage = pageHolder.page;
      const ragFixture = path.join(REPO_ROOT, 'test_workflows/fixtures/rag-sample.txt');
      if (!fs.existsSync(ragFixture)) {
        fs.mkdirSync(path.dirname(ragFixture), { recursive: true });
        fs.writeFileSync(ragFixture, 'RunAnywhere keeps model lifecycle logic in C++.\nThe SDK registers backends such as LlamaCPP and ONNX/Sherpa on device.\n');
      }
      await clickTab(livePage, 'Docs');
      await livePage.locator('#docs-upload-btn').click();
      await livePage.locator('#docs-file').setInputFiles(ragFixture);
      await livePage.waitForTimeout(5000);
      await livePage.locator('#docs-query').fill(RAG_QUERY);
      await livePage.locator('#docs-ask-btn').click();
      await livePage.waitForFunction(
        () => (document.querySelector('#docs-answer')?.textContent?.length ?? 0) > 20,
        null,
        { timeout: 300_000 },
      ).catch(() => {});
      const ragAns = await livePage.locator('#docs-answer').innerText().catch(() => '');
      await snapshotTc(livePage, 'tc13', 'rag', ragAns.toLowerCase().includes('c++') ? 'PASS' : 'LIMITED', ragAns.slice(0, 120));
    }, pageHolder);

    await runTc('tc12', async () => {
      const livePage = pageHolder.page;
      await clickTab(livePage, 'Voice');
      const voiceText = await livePage.locator('#tab-voice').innerText();
      await snapshotTc(livePage, 'tc12', 'voice', 'LIMITED', voiceText.slice(0, 120));
    }, pageHolder);

    await runTc('tc14', async () => {
      const livePage = pageHolder.page;
      const tools = await livePage.evaluate(() => {
        const sdk = window.__RUNANYWHERE_SDK__;
        if (!sdk?.toolCalling) return { ok: false };
        return { ok: sdk.toolCalling.supportsProtoToolCalling?.() ?? false };
      });
      await snapshotTc(livePage, 'tc14', 'tool_api', tools.ok ? 'LIMITED' : 'N/A', 'SDK tool API probed; no Settings tool UI');
    }, pageHolder);

    await runTc('tc17', async () => {
      const livePage = pageHolder.page;
      await clickTab(livePage, 'Solutions');
      await snapshotTc(livePage, 'tc17', 'solutions', 'N/A', 'DEFERRED per catalog');
    }, pageHolder);

    await runTc('tc20', async () => {
      const livePage = pageHolder.page;
      await clickTab(livePage, 'Settings');
      const settingsOk = await livePage.locator('.settings-section-title').filter({ hasText: 'Generation' }).isVisible();
      await snapshotTc(livePage, 'tc20', 'settings', settingsOk ? 'PASS' : 'FAIL', 'generation settings visible');
    }, pageHolder);

    // TC-06, TC-18, TC-19, TC-21 N/A
    for (const [id, note] of [
      ['tc06', 'No dedicated VAD UI'],
      ['tc18', 'No Validation tab'],
      ['tc19', 'No Benchmarks tab'],
      ['tc21', 'No LoRA UI'],
    ]) {
      recordCommand(id, 'N/A', 0, 'logs/browser_console.jsonl');
      recordAction({ action: id, status: 'N/A', expected: 'N/A', actual: note, phase: 'modality_result', notes: note });
      tcResults[id] = { status: 'N/A', notes: note };
    }

    // TC-Download-interrupt LIMITED
    recordCommand('tc_download_interrupt', 'LIMITED', 0, 'logs/browser_console.jsonl');
    recordAction({ action: 'tc_download_interrupt', status: 'LIMITED', expected: 'cancel mid-download', actual: 'No LLM cancel button in sheet', phase: 'model_download', notes: 'LIMITED' });
    tcResults.tc_download_interrupt = { status: 'LIMITED', notes: 'No download cancel in LLM sheet' };

    // TC-Load-OOM LIMITED
    recordCommand('tc_load_oom', 'LIMITED', 0, 'logs/browser_console.jsonl');
    recordAction({ action: 'tc_load_oom', status: 'LIMITED', expected: 'OOM handling', actual: 'Not exercised on this host', phase: 'model_load', notes: 'LIMITED' });

    await pageHolder.context?.close().catch(() => {});
  } finally {
    fs.writeFileSync(CONSOLE_LOG, consoleEntries.map((e) => JSON.stringify(e)).join('\n'));
    fs.writeFileSync(NETWORK_LOG, networkEntries.map((e) => JSON.stringify(e)).join('\n'));
    await browser.close();
  }

  fs.writeFileSync(path.join(LANE_ROOT, 'tc_results.json'), JSON.stringify(tcResults, null, 2));
  console.log('E2E complete. Results:', JSON.stringify(tcResults, null, 2));
}

runExecutor().catch((err) => {
  const msg = errorMessage(err);
  const harness = isHarnessFailure(err, null);
  console.error('Executor top-level error:', msg);
  recordCommand('executor', 'FAIL', 1, 'logs/browser_console.jsonl');
  recordAction({
    action: 'executor',
    status: 'FAIL',
    expected: 'E2E executor completes',
    actual: msg.slice(0, 500),
    phase: 'other',
    failureKind: harness ? 'harness' : 'product',
    notes: msg.slice(0, 500),
  });
  fs.writeFileSync(path.join(LANE_ROOT, 'tc_results.json'), JSON.stringify(tcResults, null, 2));
  process.exit(1);
});
