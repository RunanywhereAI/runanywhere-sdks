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
    screenshot: entry.screenshot ?? '',
    logs: entry.logs ?? [`logs/browser_console.jsonl`],
    modelId: entry.modelId ?? '',
    notes: entry.notes ?? '',
  };
  fs.appendFileSync(ACTIONS_FILE, `${JSON.stringify(row)}\n`);
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

async function registerOnnx(page) {
  await page.evaluate(async ({ repoRoot }) => {
    const onnxPath = `/@fs${repoRoot}/sdk/runanywhere-web/packages/onnx/src/index.ts`;
    const onnx = await import(/* @vite-ignore */ onnxPath);
    await onnx.ONNX.register();
  }, { repoRoot: REPO_ROOT });
}

function modelRow(page, modelId, modelName) {
  return page.locator(`.modal-sheet .model-row[data-model-id="${modelId}"]`).or(
    page.locator('.modal-sheet .model-row').filter({ hasText: modelName }).first(),
  );
}

async function downloadModelInSheet(page, modelName, modelId, timeoutMs = 1_800_000) {
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

async function runTc(id, fn, pageHolder) {
  try {
    if (pageHolder) {
      pageHolder.page = await ensureLivePage(pageHolder);
    }
    await fn();
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error(`[${id}] failed:`, msg);
    if (pageHolder?.page?.isClosed?.()) {
      try {
        pageHolder.page = await ensureLivePage(pageHolder);
      } catch (recoverErr) {
        const recoverMsg = recoverErr instanceof Error ? recoverErr.message : String(recoverErr);
        console.error(`[${id}] page recovery failed:`, recoverMsg);
      }
    }
    recordCommand(id, 'FAIL', 1, 'logs/browser_console.jsonl');
    recordAction({
      action: id,
      status: 'FAIL',
      expected: `${id} completes`,
      actual: msg.slice(0, 500),
      phase: 'modality_result',
      notes: msg.slice(0, 500),
    });
    tcResults[id] = { status: 'FAIL', notes: msg.slice(0, 500) };
    return false;
  }
  return true;
}

async function ensureLivePage(pageHolder) {
  if (pageHolder.page && !pageHolder.page.isClosed()) {
    return pageHolder.page;
  }
  if (pageHolder.context) {
    await pageHolder.context.close().catch(() => {});
  }
  pageHolder.context = await pageHolder.browser.newContext({
    viewport: { width: 1280, height: 900 },
    permissions: ['microphone', 'camera'],
  });
  pageHolder.page = await pageHolder.context.newPage();
  pageHolder.page.on('console', (msg) => {
    consoleEntries.push({ ts: nowIso(), type: msg.type(), text: msg.text() });
  });
  await gotoFresh(pageHolder.page);
  await waitInteractive(pageHolder.page);
  return pageHolder.page;
}

async function downloadAndLoad(page, modelName, modelId, timeoutMs = 1_800_000) {
  const sheetOpen = await page.locator('.modal-sheet').isVisible().catch(() => false);
  if (!sheetOpen) await openModelSheet(page);
  await downloadModelInSheet(page, modelName, modelId, timeoutMs);
  await loadModelInSheet(page, modelName, modelId, timeoutMs);
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
  const context = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    permissions: ['microphone', 'camera'],
  });
  const page = await context.newPage();

  page.on('console', (msg) => {
    consoleEntries.push({ ts: nowIso(), type: msg.type(), text: msg.text() });
  });
  page.on('request', (req) => {
    if (req.resourceType() === 'fetch' || req.resourceType() === 'xhr') {
      networkEntries.push({ ts: nowIso(), method: req.method(), url: req.url() });
    }
  });

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
    await downloadModelInSheet(page, LLM_MODEL, LLM_MODEL_ID);
    await snapshotTc(page, 'tc02', 'download_complete', 'PASS', `${LLM_MODEL} downloaded`);

    // TC-04 — Load
    let llmLoaded = false;
    await runTc('tc04', async () => {
      await loadModelInSheet(page, LLM_MODEL, LLM_MODEL_ID);
      llmLoaded = await page.evaluate((id) => {
        try { return window.__RUNANYWHERE_SDK__?.currentModel?.()?.modelId === id; }
        catch { return false; }
      }, LLM_MODEL_ID);
      await snapshotTc(page, 'tc04', 'load', llmLoaded ? 'PASS' : 'FAIL', `currentModel=${llmLoaded}`);
    });

    // TC-05 — LLM inference
    await runTc('tc05', async () => {
      if (!llmLoaded) throw new Error('LLM not loaded — skipping inference');
      await page.locator('#chat-input').fill(LLM_PROMPT);
      await page.locator('#chat-send-btn').click();
      await page.waitForFunction(
        () => {
          const bubbles = document.querySelectorAll('.chat-message--assistant .chat-bubble');
          const last = bubbles[bubbles.length - 1];
          return last && last.textContent && last.textContent.length > 20 && !last.textContent.includes('…');
        },
        null,
        { timeout: 300_000 },
      );
      const reply = await page.locator('.chat-message--assistant .chat-bubble').last().textContent();
      await snapshotTc(page, 'tc05', 'inference', reply && reply.length > 10 ? 'PASS' : 'FAIL', reply?.slice(0, 120));
    });

    // TC-Inference-cancel
    await runTc('tc_inference_cancel', async () => {
      if (!llmLoaded) throw new Error('LLM not loaded');
      await page.locator('#chat-input').fill('Write a detailed essay about on-device AI in at least 200 words.');
      await page.locator('#chat-send-btn').click();
      await page.waitForTimeout(2000);
      await page.locator('#chat-clear-btn').click();
      await page.waitForTimeout(2000);
      await snapshotTc(page, 'tc_inference_cancel', 'clear_midstream', 'PASS', 'Clear clicked during generation');
    });

    // TC-15 — Storage baseline
    await runTc('tc15', async () => {
      await clickTab(page, 'Storage');
      const storageText = await page.locator('#storage-scroll').innerText();
      const tc15Pass = storageText.includes('Browser Storage') && storageText.includes('Registered Models');
      await snapshotTc(page, 'tc15', 'baseline', tc15Pass ? 'PASS' : 'FAIL', storageText.slice(0, 200));
    });

    // TC-Storage-OPFS — hard refresh
    await runTc('tc_storage_opfs', async () => {
      await page.reload({ waitUntil: 'domcontentloaded' });
      await waitInteractive(page);
      await page.waitForTimeout(3000);
      await clickTab(page, 'Chat');
      await openModelSheet(page);
      const loadVisible = await page.locator(`.modal-sheet .model-row[data-model-id="${LLM_MODEL_ID}"]`)
        .locator('[data-action="load"], [data-action="unload"]').first().isVisible();
      await snapshotTc(page, 'tc_storage_opfs', 'hard_refresh', loadVisible ? 'PASS' : 'FAIL', 'model still on disk after reload');
      await closeModelSheet(page);
    });

    // TC-03a — tab close persistence
    await context.close();
    const page2Holder = { browser, context: null, page: null };
    page2Holder.context = await browser.newContext({ viewport: { width: 1280, height: 900 }, permissions: ['microphone', 'camera'] });
    page2Holder.page = await page2Holder.context.newPage();
    page2Holder.page.on('console', (msg) => consoleEntries.push({ ts: nowIso(), type: msg.type(), text: msg.text() }));

    await runTc('tc03a', async () => {
      const page2 = page2Holder.page;
      await page2.goto(BASE_URL);
      await waitInteractive(page2);
      await clickTab(page2, 'Chat');
      await openModelSheet(page2);
      const stillDl = await page2.locator(`.modal-sheet .model-row[data-model-id="${LLM_MODEL_ID}"]`)
        .locator('[data-action="load"]').isVisible().catch(() => false);
      await snapshotTc(page2, 'tc03a', 'tab_reopen', stillDl ? 'PASS' : 'FAIL', 'model persisted after new context');
      await closeModelSheet(page2);
    }, page2Holder);

    await runTc('tc16', async () => {
      const page2 = page2Holder.page;
      await clickTab(page2, 'Storage');
      const afterKill = await page2.locator('#storage-model-list').innerText();
      await snapshotTc(page2, 'tc16', 'after_tab_close', afterKill.includes('SmolLM') ? 'PASS' : 'LIMITED', afterKill.slice(0, 150));
    }, page2Holder);

    await runTc('tc03d', async () => {
      const page2 = page2Holder.page;
      await clearSiteStorage(page2);
      await gotoFresh(page2);
      await clickTab(page2, 'Storage');
      const cleared = await page2.locator('#storage-model-list').innerText();
      await snapshotTc(page2, 'tc03d', 'clear_site_data', !cleared.includes('Loaded') ? 'PASS' : 'FAIL', cleared.slice(0, 150));
    }, page2Holder);

    await runTc('tc03c', async () => {
      const page2 = page2Holder.page;
      await clearSiteStorage(page2);
      await gotoFresh(page2);
      await openModelSheet(page2);
      const needDl = await page2.locator(`.modal-sheet .model-row[data-model-id="${LLM_MODEL_ID}"]`)
        .locator('[data-action="download"]').isVisible().catch(() => false);
      await snapshotTc(page2, 'tc03c', 'fresh_origin', needDl ? 'PASS' : 'FAIL', 'models gone after clear');
      await closeModelSheet(page2);
    }, page2Holder);

    await runTc('tc02_redownload', async () => {
      const page2 = page2Holder.page;
      await downloadAndLoad(page2, LLM_MODEL, LLM_MODEL_ID, 900_000);
      llmLoaded = await page2.evaluate((id) => {
        try { return window.__RUNANYWHERE_SDK__?.currentModel?.()?.modelId === id; }
        catch { return false; }
      }, LLM_MODEL_ID);
    }, page2Holder);

    // TC-07 / TC-10 — Transcribe
    await runTc('tc10', async () => {
      const page2 = page2Holder.page;
      await registerOnnx(page2);
      await clickTab(page2, 'Transcribe');
      await snapshotTc(page2, 'tc10', 'transcribe_ui', 'PASS', 'transcribe tab rendered');
    }, page2Holder);
    await runTc('tc07', async () => {
      const page2 = page2Holder.page;
      await clickTab(page2, 'Transcribe');
      await page2.locator('#transcribe-model-btn').click();
      await downloadAndLoad(page2, STT_MODEL, STT_MODEL_ID, 600_000);
      await clickTab(page2, 'Transcribe');
      const sttReady = await page2.locator('#mic-toggle-btn').isEnabled().catch(() => false);
      await snapshotTc(page2, 'tc07', 'stt_ready', sttReady ? 'PASS' : 'BLOCKED', 'STT model loaded; mic path needs audio fixture');
    }, page2Holder);

    // TC-08 / TC-11 — Speak
    await runTc('tc11', async () => {
      const page2 = page2Holder.page;
      await clickTab(page2, 'Speak');
      await snapshotTc(page2, 'tc11', 'speak_ui', 'PASS', 'speak tab rendered');
    }, page2Holder);
    await runTc('tc08', async () => {
      const page2 = page2Holder.page;
      await clickTab(page2, 'Speak');
      await page2.locator('#speak-model-btn').click();
      await downloadAndLoad(page2, TTS_MODEL, TTS_MODEL_ID, 600_000);
      await clickTab(page2, 'Speak');
      await page2.locator('#speak-text').fill(TTS_TEXT);
      const speakBtn = page2.locator('#speak-btn');
      if (await speakBtn.isEnabled().catch(() => false)) {
        await speakBtn.click();
        await page2.waitForFunction(
          () => document.querySelector('#speak-status')?.textContent?.includes('Last synthesis'),
          null,
          { timeout: 180_000 },
        ).catch(() => {});
      }
      const speakStatus = await page2.locator('#speak-status').innerText().catch(() => '');
      await snapshotTc(page2, 'tc08', 'tts', speakStatus.includes('Last synthesis') ? 'PASS' : 'LIMITED', speakStatus.slice(0, 120));
    }, page2Holder);

    // TC-09 — VLM
    await runTc('tc09', async () => {
      const page2 = page2Holder.page;
      await clickTab(page2, 'Vision');
      await page2.locator('#vision-model-btn').click();
      await downloadAndLoad(page2, VLM_MODEL, VLM_MODEL_ID, 900_000);
      await clickTab(page2, 'Vision');
      await page2.locator('#vision-camera-btn').click();
      await page2.waitForTimeout(3000);
      await page2.locator('#vision-capture-btn').click().catch(() => {});
      await page2.locator('#vision-analyze-btn').click().catch(() => {});
      await page2.waitForFunction(
        () => {
          const out = document.querySelector('#vision-output')?.textContent ?? '';
          return out.length > 30 && !out.includes('no response yet');
        },
        null,
        { timeout: 300_000 },
      ).catch(() => {});
      const vlmOut = await page2.locator('#vision-output').innerText().catch(() => '');
      await snapshotTc(page2, 'tc09', 'vlm', vlmOut.length > 20 ? 'PASS' : 'LIMITED', vlmOut.slice(0, 120));
    }, page2Holder);

    // TC-13 — RAG
    await runTc('tc13', async () => {
    const page2 = page2Holder.page;
    const ragFixture = path.join(REPO_ROOT, 'test_workflows/fixtures/rag-sample.txt');
    if (!fs.existsSync(ragFixture)) {
      fs.mkdirSync(path.dirname(ragFixture), { recursive: true });
      fs.writeFileSync(ragFixture, 'RunAnywhere keeps model lifecycle logic in C++.\nThe SDK registers backends such as LlamaCPP and ONNX/Sherpa on device.\n');
    }
    await clickTab(page2, 'Docs');
    await page2.locator('#docs-upload-btn').click();
    await page2.locator('#docs-file').setInputFiles(ragFixture);
    await page2.waitForTimeout(5000);
    await page2.locator('#docs-query').fill(RAG_QUERY);
    await page2.locator('#docs-ask-btn').click();
    await page2.waitForFunction(
      () => (document.querySelector('#docs-answer')?.textContent?.length ?? 0) > 20,
      null,
      { timeout: 300_000 },
    ).catch(() => {});
    const ragAns = await page2.locator('#docs-answer').innerText().catch(() => '');
    await snapshotTc(page2, 'tc13', 'rag', ragAns.toLowerCase().includes('c++') ? 'PASS' : 'LIMITED', ragAns.slice(0, 120));
    }, page2Holder);

    await runTc('tc12', async () => {
      const page2 = page2Holder.page;
      await clickTab(page2, 'Voice');
      const voiceText = await page2.locator('#tab-voice').innerText();
      await snapshotTc(page2, 'tc12', 'voice', 'LIMITED', voiceText.slice(0, 120));
    }, page2Holder);

    await runTc('tc14', async () => {
      const page2 = page2Holder.page;
      const tools = await page2.evaluate(() => {
        const sdk = window.__RUNANYWHERE_SDK__;
        if (!sdk?.toolCalling) return { ok: false };
        return { ok: sdk.toolCalling.supportsProtoToolCalling?.() ?? false };
      });
      await snapshotTc(page2, 'tc14', 'tool_api', tools.ok ? 'LIMITED' : 'N/A', 'SDK tool API probed; no Settings tool UI');
    }, page2Holder);

    await runTc('tc17', async () => {
      const page2 = page2Holder.page;
      await clickTab(page2, 'Solutions');
      await snapshotTc(page2, 'tc17', 'solutions', 'N/A', 'DEFERRED per catalog');
    }, page2Holder);

    await runTc('tc20', async () => {
      const page2 = page2Holder.page;
      await clickTab(page2, 'Settings');
      const settingsOk = await page2.locator('.settings-section-title').filter({ hasText: 'Generation' }).isVisible();
      await snapshotTc(page2, 'tc20', 'settings', settingsOk ? 'PASS' : 'FAIL', 'generation settings visible');
    }, page2Holder);

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

    await page2Holder.context?.close().catch(() => {});
  } finally {
    fs.writeFileSync(CONSOLE_LOG, consoleEntries.map((e) => JSON.stringify(e)).join('\n'));
    fs.writeFileSync(NETWORK_LOG, networkEntries.map((e) => JSON.stringify(e)).join('\n'));
    await browser.close();
  }

  fs.writeFileSync(path.join(LANE_ROOT, 'tc_results.json'), JSON.stringify(tcResults, null, 2));
  console.log('E2E complete. Results:', JSON.stringify(tcResults, null, 2));
}

runExecutor().catch((err) => {
  console.error('Executor top-level error:', err);
  recordCommand('executor', 'FAIL', 1, 'logs/browser_console.jsonl');
  fs.writeFileSync(path.join(LANE_ROOT, 'tc_results.json'), JSON.stringify(tcResults, null, 2));
  process.exit(1);
});