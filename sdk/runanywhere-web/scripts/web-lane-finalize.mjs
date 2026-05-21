#!/usr/bin/env node
/** Finalize web lane artifacts for remaining UI-only TCs */
import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const LANE = process.env.WEB_LANE_ROOT;
const BASE = 'http://127.0.0.1:5173';
const ACTIONS = path.join(LANE, 'actions.jsonl');
const CMD = path.join(LANE, 'command_summary.tsv');
const SHOTS = path.join(LANE, 'screenshots');

function appendAction(row) {
  fs.appendFileSync(ACTIONS, `${JSON.stringify({ ts: new Date().toISOString(), target: '07_web', sdk: 'Web', platform: 'Browser', logs: ['logs/browser_console.jsonl'], modelId: '', screenshot: row.screenshot ?? '', ...row })}\n`);
}
function appendCmd(name, status, code, log) {
  fs.appendFileSync(CMD, `${name}\t${status}\t${code}\t${log}\n`);
}

const tcResults = fs.existsSync(path.join(LANE, 'tc_results.json'))
  ? JSON.parse(fs.readFileSync(path.join(LANE, 'tc_results.json'), 'utf8'))
  : {};

async function snap(page, tc, step, status, notes) {
  const file = `screenshots/${tc}_${step}.png`;
  await page.screenshot({ path: path.join(LANE, file), fullPage: true, timeout: 60_000 });
  appendCmd(`${tc}_${step}`, status, status === 'PASS' ? 0 : 1, 'logs/browser_console.jsonl');
  appendAction({ action: `${tc}_${step}`, phase: 'modality_result', expected: `${tc} ${step}`, actual: notes, status, screenshot: file, notes });
  tcResults[tc] = { status, notes };
}

const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
const logs = [];
page.on('console', (m) => logs.push({ ts: new Date().toISOString(), type: m.type(), text: m.text() }));

await page.goto(BASE);
await page.waitForFunction(() => window.__RUNANYWHERE_AI_READY__?.state === 'interactive', null, { timeout: 120_000 });

for (const [tc, note] of [
  ['tc06', 'N/A — no dedicated VAD UI'],
  ['tc12', 'LIMITED — voice UI only; STT/LLM/TTS load + mic turn not completed'],
  ['tc13', 'BLOCKED — RAG ingest/query not completed (prior run timeout)'],
  ['tc14', 'LIMITED — SDK toolCalling API only; no Settings tool UI'],
  ['tc17', 'N/A — DEFERRED'],
  ['tc18', 'N/A — no Validation tab'],
  ['tc19', 'N/A — no Benchmarks tab'],
  ['tc21', 'N/A — no LoRA UI'],
  ['tc_download_interrupt', 'LIMITED — no LLM download cancel control'],
  ['tc_load_oom', 'LIMITED — not exercised'],
]) {
  const status = note.startsWith('N/A') ? 'N/A' : note.startsWith('BLOCKED') ? 'BLOCKED' : note.startsWith('LIMITED') ? 'LIMITED' : 'N/A';
  appendCmd(tc, status, 0, 'logs/browser_console.jsonl');
  appendAction({ action: tc, phase: 'modality_result', expected: status, actual: note, status, notes: note });
  tcResults[tc] = { status, notes: note };
}

await page.locator('.tab-item').filter({ hasText: 'Voice' }).click();
await snap(page, 'tc12', 'voice_ui', 'LIMITED', 'Voice tab rendered');

await page.locator('.tab-item').filter({ hasText: 'Solutions' }).click();
await snap(page, 'tc17', 'solutions_tab', 'N/A', 'DEFERRED');

await page.locator('.tab-item').filter({ hasText: 'Settings' }).click();
await snap(page, 'tc20', 'settings', (await page.locator('.settings-section-title').filter({ hasText: 'Generation' }).isVisible()) ? 'PASS' : 'FAIL', 'Settings generation section');

const tools = await page.evaluate(() => window.__RUNANYWHERE_SDK__?.toolCalling?.supportsProtoToolCalling?.() ?? false);
await snap(page, 'tc14', 'tool_api', tools ? 'LIMITED' : 'N/A', `supportsProtoToolCalling=${tools}`);

fs.writeFileSync(path.join(LANE, 'logs/browser_console.jsonl'), logs.map((e) => JSON.stringify(e)).join('\n'));
fs.writeFileSync(path.join(LANE, 'tc_results.json'), JSON.stringify(tcResults, null, 2));
await browser.close();
console.log('Finalized', Object.keys(tcResults).length, 'TC entries');
