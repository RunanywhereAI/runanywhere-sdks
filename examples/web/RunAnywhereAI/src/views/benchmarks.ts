/**
 * Benchmarks Tab — MVP web equivalent of the iOS benchmark dashboard
 * (linked from CombinedSettingsView.swift:181 → BenchmarkDashboardView).
 *
 * iOS runs scenario suites per modality (LLM/STT/TTS/VLM) through
 * `BenchmarkRunner`; the web MVP scopes to what the web SDK exposes today:
 * a short `RunAnywhere.llm.generateStream` run against the loaded LLM, reporting
 * time-to-first-token and tokens/sec (iOS parity:
 * LLMBenchmarkProvider.swift:84-90 — SDK stream-result metrics preferred,
 * wall-clock fallback). Results are kept in an in-memory history list.
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  type GenerationResult,
} from '@runanywhere/web';
import {
  findLoadedModelForCategory,
  onModelStateChange,
  openSheet,
} from '../components/model-selection';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const LLM_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_LANGUAGE,
];

/** Scenario token budgets (iOS parity: LLMBenchmarkProvider.swift:15-19). */
const SCENARIOS = [
  { name: 'Short', maxTokens: 50 },
  { name: 'Medium', maxTokens: 256 },
  { name: 'Long', maxTokens: 512 },
] as const;

// Benchmark prompt mirrors LLMBenchmarkProvider.swift:68-74.
const BENCH_PROMPT =
  'Write a very long and detailed explanation of how neural networks work, ' +
  'covering perceptrons, activation functions, backpropagation, gradient descent, ' +
  'loss functions, convolutional layers, recurrent layers, transformers, attention ' +
  'mechanisms, and training procedures. Be as thorough as possible.';

interface BenchmarkRun {
  scenario: string;
  modelId: string;
  ttftMs: number | null;
  tokensPerSecond: number | null;
  outputTokens: number | null;
  totalTimeMs: number;
  completedAt: Date;
  error?: string;
}

let container: HTMLElement;
let unmounted = false;
let isRunning = false;
let statusText = '';
let history: BenchmarkRun[] = [];
let unsubscribeState: (() => void) | null = null;

export function initBenchmarksTab(el: HTMLElement): TabLifecycle {
  container = el;
  unmounted = false;
  renderBenchmarks();
  unsubscribeState = onModelStateChange(() => {
    if (!unmounted) renderBenchmarks();
  });
  return {
    onActivate: () => {
      unmounted = false;
      renderBenchmarks();
    },
    onDeactivate: () => {
      unmounted = true;
      if (!container.isConnected && unsubscribeState) {
        unsubscribeState();
        unsubscribeState = null;
      }
    },
  };
}

function renderBenchmarks(): void {
  const loadedModel = findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);
  const modelLabel = loadedModel?.name ?? 'Select LLM Model';
  const canRun = Boolean(loadedModel) && !isRunning;

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Benchmarks</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="bench-model-btn">${escapeHtml(modelLabel)}</button>
      </div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>LLM generation</h3>
        <p class="text-secondary">Runs a streamed generation against the loaded
        LLM via <code>RunAnywhere.llm.generateStream</code> and reports
        time-to-first-token and tokens/sec.</p>
        <div class="toolbar-actions">
          ${SCENARIOS.map((s) => `
            <button class="btn btn-primary bench-run-btn" data-max-tokens="${s.maxTokens}" data-name="${s.name}" ${canRun ? '' : 'disabled'}>
              ${s.name} (${s.maxTokens} tokens)
            </button>`).join('')}
        </div>
        ${loadedModel ? '' : '<div class="docs-status">Load an LLM from the Chat tab (or the pill above) first.</div>'}
        <div id="bench-status" class="docs-status">${escapeHtml(statusText)}</div>
      </div>

      <div class="docs-section">
        <h3>History</h3>
        ${history.length === 0
          ? '<p class="text-secondary">No runs yet.</p>'
          : `<ul class="docs-list">${history.map(renderRun).join('')}</ul>`}
      </div>
    </div>
  `;

  container.querySelector('#bench-model-btn')?.addEventListener('click', () => {
    openSheet({
      title: 'Select LLM Model',
      filterCategories: LLM_PICKER_FILTER,
    });
  });
  container.querySelectorAll<HTMLButtonElement>('.bench-run-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const maxTokens = Number(btn.dataset.maxTokens);
      const name = btn.dataset.name ?? `${maxTokens} tokens`;
      void runBenchmark(name, maxTokens);
    });
  });
}

function renderRun(run: BenchmarkRun): string {
  if (run.error) {
    return `
      <li class="docs-item">
        <div>
          <div class="docs-item-title">${escapeHtml(run.scenario)} — ${escapeHtml(run.modelId)}</div>
          <div class="docs-item-meta">Failed: ${escapeHtml(run.error)}</div>
        </div>
      </li>`;
  }
  const parts = [
    run.ttftMs != null ? `TTFT ${run.ttftMs.toFixed(0)} ms` : null,
    run.tokensPerSecond != null ? `${run.tokensPerSecond.toFixed(1)} tok/s` : null,
    run.outputTokens != null ? `${run.outputTokens} tokens` : null,
    `${(run.totalTimeMs / 1000).toFixed(2)} s total`,
  ].filter(Boolean);
  return `
    <li class="docs-item">
      <div>
        <div class="docs-item-title">${escapeHtml(run.scenario)} — ${escapeHtml(run.modelId)}</div>
        <div class="docs-item-meta">${escapeHtml(parts.join(' · '))} · ${run.completedAt.toLocaleTimeString()}</div>
      </div>
    </li>`;
}

async function runBenchmark(scenario: string, maxTokens: number): Promise<void> {
  if (isRunning) return;
  const loadedModel = findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);
  if (!loadedModel) return;

  isRunning = true;
  statusText = `Running ${scenario} (${maxTokens} tokens)...`;
  renderBenchmarks();

  const startedAt = performance.now();
  let firstTokenAt: number | null = null;
  let tokenCount = 0;

  try {
    let completed: GenerationResult | null = null;
    for await (const event of RunAnywhere.llm.generateStream(BENCH_PROMPT, {
      maxOutputTokens: maxTokens,
      temperature: 0,
    })) {
      if (event.type === 'textDelta') {
        if (firstTokenAt == null) firstTokenAt = performance.now();
        tokenCount += 1;
      } else if (event.type === 'completed') {
        completed = event.result;
      }
    }
    const wallMs = performance.now() - startedAt;

    // Every generation result carries the same metrics block, so the wall-clock
    // fallbacks below only apply when a backend reports zeros.
    const totalTimeMs = wallMs;
    const ttftMs = completed && completed.timeToFirstTokenMs > 0
      ? completed.timeToFirstTokenMs
      : firstTokenAt != null ? firstTokenAt - startedAt : null;
    const outputTokens = completed && completed.outputTokens > 0
      ? completed.outputTokens
      : tokenCount;
    const tokensPerSecond = completed && completed.tokensPerSecond > 0
      ? completed.tokensPerSecond
      : totalTimeMs > 0 ? outputTokens / (totalTimeMs / 1000) : null;

    history.unshift({
      scenario,
      modelId: loadedModel.id,
      ttftMs,
      tokensPerSecond,
      outputTokens,
      totalTimeMs,
      completedAt: new Date(),
    });
    statusText = 'Done.';
  } catch (err) {
    history.unshift({
      scenario,
      modelId: loadedModel.id,
      ttftMs: null,
      tokensPerSecond: null,
      outputTokens: null,
      totalTimeMs: performance.now() - startedAt,
      completedAt: new Date(),
      error: formatError(err),
    });
    statusText = 'Run failed.';
  } finally {
    if (history.length > 50) history = history.slice(0, 50);
    isRunning = false;
    if (!unmounted) renderBenchmarks();
  }
}
