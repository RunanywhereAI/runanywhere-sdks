/**
 * Benchmarks — LLM generation timing (MVP).
 *
 * Mirrors the web/iOS Short·Medium·Long token budgets against
 * `llm.generateStream`, reporting TTFT and tok/s from the completed result.
 */
import { escapeHtml, formatMetrics } from '../services/format';
import { selectedModel } from '../services/settings';
import { showError } from '../components/toast';
import type { ViewFactory } from '../shell/app';

const SCENARIOS = [
  { name: 'Short', maxTokens: 50 },
  { name: 'Medium', maxTokens: 256 },
  { name: 'Long', maxTokens: 512 },
] as const;

const BENCH_PROMPT =
  'Write a very long and detailed explanation of how neural networks work, ' +
  'covering perceptrons, activation functions, backpropagation, gradient descent, ' +
  'loss functions, convolutional layers, recurrent layers, transformers, attention ' +
  'mechanisms, and training procedures. Be as thorough as possible.';

interface BenchmarkRun {
  readonly scenario: string;
  readonly modelId: string;
  readonly ttftMs: number;
  readonly tokensPerSecond: number;
  readonly outputTokens: number;
  readonly totalTimeMs: number;
  readonly completedAt: Date;
  readonly error?: string;
}

const HISTORY_KEY = 'ra.benchmarks.history';
const MAX_HISTORY = 40;

function loadHistory(): BenchmarkRun[] {
  try {
    const raw = localStorage.getItem(HISTORY_KEY);
    if (raw === null) return [];
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed
      .filter((entry): entry is Record<string, unknown> => entry !== null && typeof entry === 'object')
      .map((entry) => ({
        scenario: String(entry.scenario ?? ''),
        modelId: String(entry.modelId ?? ''),
        ttftMs: Number(entry.ttftMs ?? 0),
        tokensPerSecond: Number(entry.tokensPerSecond ?? 0),
        outputTokens: Number(entry.outputTokens ?? 0),
        totalTimeMs: Number(entry.totalTimeMs ?? 0),
        completedAt: new Date(String(entry.completedAt ?? Date.now())),
        error: typeof entry.error === 'string' ? entry.error : undefined,
      }));
  } catch {
    return [];
  }
}

function saveHistory(runs: readonly BenchmarkRun[]): void {
  localStorage.setItem(
    HISTORY_KEY,
    JSON.stringify(
      runs.slice(0, MAX_HISTORY).map((run) => ({
        ...run,
        completedAt: run.completedAt.toISOString(),
      })),
    ),
  );
}

function renderHistory(host: HTMLElement, history: readonly BenchmarkRun[]): void {
  if (history.length === 0) {
    host.innerHTML = `<p class="ra-muted">No runs yet.</p>`;
    return;
  }
  host.innerHTML =
    `<ul class="ra-dense-list">` +
    history
      .map((run) => {
        if (run.error !== undefined) {
          return (
            `<li class="ra-dense-row"><div class="ra-dense-copy">` +
            `<strong>${escapeHtml(run.scenario)} · ${escapeHtml(run.modelId)}</strong>` +
            `<small class="ra-danger-text">${escapeHtml(run.error)}</small>` +
            `</div></li>`
          );
        }
        return (
          `<li class="ra-dense-row"><div class="ra-dense-copy">` +
          `<strong>${escapeHtml(run.scenario)} · ${escapeHtml(run.modelId)}</strong>` +
          `<small>${escapeHtml(
            formatMetrics({
              outputTokens: run.outputTokens,
              tokensPerSecond: run.tokensPerSecond,
              timeToFirstTokenMs: run.ttftMs,
            }),
          )} · ${(run.totalTimeMs / 1000).toFixed(1)}s</small>` +
          `</div></li>`
        );
      })
      .join('') +
    `</ul>`;
}

export const createBenchmarksView: ViewFactory = ({ root }) => {
  let disposed = false;
  let running = false;
  let history = loadHistory();

  const scroll = document.createElement('div');
  scroll.className = 'ra-view-scroll ra-stack';
  scroll.innerHTML =
    `<section class="ra-card ra-stack">` +
    `<h2 class="ra-section-title">LLM generation</h2>` +
    `<p class="ra-muted">Runs a streamed generation against the selected language model and reports time-to-first-token and tokens/sec.</p>` +
    `<div class="ra-row" id="bench-actions">` +
    SCENARIOS.map(
      (s) =>
        `<button type="button" class="ra-btn-primary" data-scenario="${s.name}" data-max-tokens="${s.maxTokens}">` +
        `${s.name} (${s.maxTokens})` +
        `</button>`,
    ).join('') +
    `</div>` +
    `<div id="bench-status" class="ra-muted"></div>` +
    `</section>` +
    `<section class="ra-stack">` +
    `<div class="ra-row" style="justify-content:space-between">` +
    `<h2 class="ra-section-title">History</h2>` +
    `<button type="button" class="ra-btn-quiet" data-action="clear">Clear</button>` +
    `</div>` +
    `<div id="bench-history"></div>` +
    `</section>`;
  root.append(scroll);

  const status = scroll.querySelector<HTMLElement>('#bench-status');
  const historyHost = scroll.querySelector<HTMLElement>('#bench-history');
  const actions = scroll.querySelector<HTMLElement>('#bench-actions');
  if (status === null || historyHost === null || actions === null) return {};

  const setBusy = (busy: boolean): void => {
    running = busy;
    actions.querySelectorAll<HTMLButtonElement>('button').forEach((button) => {
      button.disabled = busy;
    });
  };

  const paint = (): void => {
    renderHistory(historyHost, history);
  };
  paint();

  const runScenario = async (name: string, maxTokens: number): Promise<void> => {
    if (running) return;
    setBusy(true);
    const modelId = selectedModel('llm');
    status.textContent = `Running ${name} on ${modelId}…`;
    const started = performance.now();
    try {
      let resultMetrics = { outputTokens: 0, tokensPerSecond: 0, timeToFirstTokenMs: 0 };
      for await (const event of window.runanywhere.llm.generateStream(BENCH_PROMPT, {
        model: modelId,
        maxOutputTokens: maxTokens,
        temperature: 0.3,
      })) {
        if (disposed) return;
        if (event.type === 'completed') {
          resultMetrics = {
            outputTokens: event.result.outputTokens,
            tokensPerSecond: event.result.tokensPerSecond,
            timeToFirstTokenMs: event.result.timeToFirstTokenMs,
          };
        } else if (event.type === 'failed') {
          throw new Error(event.error.message || 'Benchmark failed');
        }
      }
      const run: BenchmarkRun = {
        scenario: name,
        modelId,
        ttftMs: resultMetrics.timeToFirstTokenMs,
        tokensPerSecond: resultMetrics.tokensPerSecond,
        outputTokens: resultMetrics.outputTokens,
        totalTimeMs: performance.now() - started,
        completedAt: new Date(),
      };
      history = [run, ...history].slice(0, MAX_HISTORY);
      saveHistory(history);
      status.textContent = formatMetrics(resultMetrics);
      paint();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      history = [
        {
          scenario: name,
          modelId,
          ttftMs: 0,
          tokensPerSecond: 0,
          outputTokens: 0,
          totalTimeMs: performance.now() - started,
          completedAt: new Date(),
          error: message,
        },
        ...history,
      ].slice(0, MAX_HISTORY);
      saveHistory(history);
      paint();
      showError(error, 'Benchmark failed');
      status.textContent = message;
    } finally {
      if (!disposed) setBusy(false);
    }
  };

  scroll.addEventListener('click', (event) => {
    const button = (event.target as HTMLElement).closest<HTMLButtonElement>('button');
    if (button === null) return;
    if (button.dataset.action === 'clear') {
      history = [];
      saveHistory(history);
      paint();
      status.textContent = '';
      return;
    }
    const scenario = button.dataset.scenario;
    const maxTokens = Number(button.dataset.maxTokens);
    if (scenario === undefined || !Number.isFinite(maxTokens)) return;
    void runScenario(scenario, maxTokens);
  });

  return {
    dispose() {
      disposed = true;
    },
  };
};
