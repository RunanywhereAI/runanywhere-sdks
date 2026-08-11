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
import { icon } from '../components/icons';
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

/** A run that produced numbers — the only kind a chart can plot. */
type CompletedRun = BenchmarkRun & { error?: undefined };

let container: HTMLElement;
let unmounted = false;
let isRunning = false;
let statusText = '';
let history: BenchmarkRun[] = [];
let unsubscribeState: (() => void) | null = null;
/**
 * Watches the chart column so the plot is redrawn at the new pixel width when
 * the window resizes or the drawer opens. See `drawCharts` for why the SVG is
 * sized in real pixels rather than scaled by a viewBox.
 */
let chartObserver: ResizeObserver | null = null;
let lastChartWidth = 0;

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
        chartObserver?.disconnect();
        chartObserver = null;
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
        <div class="docs-actions">
          ${SCENARIOS.map((s) => `
            <button class="btn btn-primary bench-run-btn" data-max-tokens="${s.maxTokens}" data-name="${s.name}" ${canRun ? '' : 'disabled'}>
              ${s.name} (${s.maxTokens} tokens)
            </button>`).join('')}
        </div>
        ${loadedModel ? '' : '<div class="docs-status">Load an LLM from the Chat tab (or the pill above) first.</div>'}
        <div id="bench-status" class="docs-status">${escapeHtml(statusText)}</div>
      </div>

      <div class="docs-section">
        <h3>Results</h3>
        <p class="text-secondary">
          The most recent completed runs, newest at the top. Every run, with its
          exact figures, stays in the History list below.
        </p>
        <div class="bench-charts" id="bench-charts"></div>
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

  drawCharts();
}

// ---------------------------------------------------------------------------
// Charts
//
// The tab collected three numbers per run and printed all of them as text, so
// "is this model getting faster with a shorter budget?" — the only question a
// benchmark screen exists to answer — had to be worked out by reading a column
// of sentences. Two horizontal bar charts answer it at a glance.
//
// TWO CHARTS, NOT ONE WITH TWO AXES. Throughput is tokens per second and
// time-to-first-token is milliseconds; plotting both against a single scale
// would make one of them invisible, and a second y-axis is the classic way to
// make a chart say something untrue. They also point in opposite directions —
// higher is better for one, lower for the other — which each subtitle states.
//
// Inline SVG, no library. Everything below is geometry plus the theme tokens.
// ---------------------------------------------------------------------------

/** How many runs a chart plots. Older ones stay in the History list below. */
const CHART_ROWS = 8;

/** Widest the plot is allowed to get: 8 bars across 1000px is mostly air. */
const CHART_MAX_WIDTH = 640;

interface ChartRow {
  /** Left-hand row label — short, because the axis gutter is narrow. */
  label: string;
  value: number;
  /** Everything about the run, for the native hover tooltip. */
  detail: string;
}

interface ChartSpec {
  title: string;
  /** Names the unit and the direction, so no bar has to repeat either. */
  subtitle: string;
  rows: readonly ChartRow[];
  format: (value: number) => string;
  /** Said in place of the plot when the backend reported nothing to plot. */
  missingNote: string;
}

function isCompleted(run: BenchmarkRun): run is CompletedRun {
  return run.error === undefined;
}

/**
 * Draw (or redraw) both charts at the container's real pixel width.
 *
 * WHY MEASURE RATHER THAN SCALE. The obvious `viewBox` + `width="100%"` makes
 * the SVG scale uniformly, which scales the *text* with it: at a 390px viewport
 * an 11px label renders at 6px, and on a wide desktop pane at 21px. Emitting the
 * SVG at the measured width keeps every label at exactly the size the design
 * system asked for, at any viewport, and keeps hairlines on the pixel grid.
 */
function drawCharts(): void {
  const host = container.querySelector<HTMLElement>('#bench-charts');
  if (!host) return;

  const measured = host.clientWidth;
  lastChartWidth = measured;
  // `|| 320` covers the panel being laid out but hidden (an inactive tab reports
  // 0), so a chart drawn off-screen is still a sensible size when it appears.
  const width = Math.min(CHART_MAX_WIDTH, Math.max(240, measured || 320));

  const completed = history.filter(isCompleted).slice(0, CHART_ROWS);
  const failedCount = history.length - history.filter(isCompleted).length;

  if (completed.length === 0) {
    host.innerHTML = `<div class="surface-empty">
        ${icon('gauge', { size: 24 })}
        <p>${escapeHtml(history.length === 0
          ? 'No runs yet. Pick a scenario above and its results are charted here.'
          : `The ${failedCount === 1 ? 'run so far' : `${failedCount} runs so far`} failed, so there is nothing to plot. The errors are in History below.`)}</p>
      </div>`;
    observeChartWidth(host);
    return;
  }

  const throughput = completed
    .filter((run) => run.tokensPerSecond !== null)
    .map((run) => chartRow(run, run.tokensPerSecond!));
  const latency = completed
    .filter((run) => run.ttftMs !== null)
    .map((run) => chartRow(run, run.ttftMs!));

  host.innerHTML =
    barChart({
      title: 'Throughput',
      subtitle: 'Tokens per second — higher is better',
      rows: throughput,
      format: (value) => value.toFixed(1),
      missingNote: 'This backend did not report a token rate for these runs.',
    }, width)
    + barChart({
      title: 'Time to first token',
      subtitle: 'Milliseconds from send to the first token — lower is better',
      rows: latency,
      format: (value) => Math.round(value).toLocaleString(),
      missingNote: 'This backend did not report a first-token time for these runs.',
    }, width);

  observeChartWidth(host);
}

/** One row of a chart, plus the full run description for its tooltip. */
function chartRow(run: CompletedRun, value: number): ChartRow {
  const parts = [
    run.modelId,
    run.completedAt.toLocaleTimeString(),
    run.tokensPerSecond !== null ? `${run.tokensPerSecond.toFixed(1)} tok/s` : null,
    run.ttftMs !== null ? `TTFT ${Math.round(run.ttftMs)} ms` : null,
    run.outputTokens !== null ? `${run.outputTokens} tokens` : null,
  ].filter((part): part is string => part !== null);
  return { label: run.scenario, value, detail: `${run.scenario} · ${parts.join(' · ')}` };
}

/**
 * Redraw on a real width change only.
 *
 * Re-bound on every render, not once: `renderBenchmarks` replaces the panel's
 * whole subtree, so the element observed a moment ago is already detached and
 * would never report again — which left the plot frozen at whatever width it
 * happened to be drawn at when the tab first opened, and scrolling sideways out
 * of a narrow viewport.
 *
 * `drawCharts` writes `innerHTML`, which re-enters this observer; the width
 * comparison is what terminates that loop. 8px of slack keeps a scrollbar
 * appearing or a sub-pixel reflow from triggering a pointless repaint.
 */
function observeChartWidth(host: HTMLElement): void {
  if (typeof ResizeObserver === 'undefined') return;
  chartObserver?.disconnect();
  chartObserver = new ResizeObserver(() => {
    if (unmounted || !host.isConnected) return;
    if (Math.abs(host.clientWidth - lastChartWidth) >= 8) drawCharts();
  });
  chartObserver.observe(host);
}

/**
 * A horizontal bar chart as inline SVG.
 *
 * Marks follow the house spec: a 12px bar (well under the 24px cap, so the row's
 * leftover height is air), a 4px rounded data-end with a square baseline edge,
 * and a hairline baseline. Values ride the bar tips instead of gridlines — with
 * eight rows the direct labels *are* the scale, and a grid behind them would be
 * ink that carries nothing. Colour is carried by the bar alone; every piece of
 * text wears a text token.
 */
function barChart(spec: ChartSpec, width: number): string {
  const head = `
      <div class="bench-chart__title">${escapeHtml(spec.title)}</div>
      <div class="bench-chart__subtitle">${escapeHtml(spec.subtitle)}</div>`;

  if (spec.rows.length === 0) {
    return `<figure class="bench-chart">${head}
      <figcaption class="bench-chart__note">${escapeHtml(spec.missingNote)}</figcaption>
    </figure>`;
  }

  // A narrow viewport buys plot width back from both gutters; the labels are
  // one short word and the values at most five characters.
  const narrow = width < 380;
  const labelWidth = narrow ? 64 : 92;
  const valueWidth = narrow ? 52 : 64;
  const rowHeight = 26;
  const barHeight = 12;
  const plotX = labelWidth;
  const plotWidth = Math.max(24, width - labelWidth - valueWidth);
  const height = spec.rows.length * rowHeight;

  // Scale to the largest bar rather than to a rounded axis maximum: with no
  // gridlines there is no axis to round to, and the tallest bar filling the
  // plot is what makes the shorter ones readable as a proportion of it.
  const max = Math.max(...spec.rows.map((row) => row.value));
  const scale = max > 0 ? plotWidth / max : 0;

  const marks = spec.rows.map((row, index) => {
    const y = index * rowHeight + (rowHeight - barHeight) / 2;
    const length = Math.max(0, row.value * scale);
    const textY = y + barHeight / 2;
    return `
      <g>
        <title>${escapeHtml(row.detail)}</title>
        <text class="bench-chart__label" x="${plotX - 10}" y="${textY}"
          text-anchor="end" dominant-baseline="central">${escapeHtml(row.label)}</text>
        ${barPath(plotX, y, length, barHeight)}
        <text class="bench-chart__value" x="${plotX + plotWidth + 10}" y="${textY}"
          dominant-baseline="central">${escapeHtml(spec.format(row.value))}</text>
      </g>`;
  }).join('');

  // "Highest"/"lowest", not "best"/"worst": which end is good flips between the
  // two charts, and the subtitle is where that is already said.
  const highest = spec.format(Math.max(...spec.rows.map((row) => row.value)));
  const lowest = spec.format(Math.min(...spec.rows.map((row) => row.value)));
  const summary = `${spec.title}: ${spec.rows.length} runs, ranging from ${lowest} to ${highest}. `
    + 'Exact figures per run are in the History list.';

  return `<figure class="bench-chart">${head}
      <svg class="bench-chart__plot" width="${width}" height="${height}"
        role="img" aria-label="${escapeHtml(summary)}">
        <line class="bench-chart__axis" x1="${plotX}" y1="0" x2="${plotX}" y2="${height}" />
        ${marks}
      </svg>
    </figure>`;
}

/**
 * A bar with its data-end rounded and its baseline edge square.
 *
 * A plain `rect rx="4"` would round all four corners, which detaches the bar
 * from the baseline it grows out of. Returns nothing for a bar too short to
 * round — a 1px sliver with a 4px radius renders as a smudge, and a zero value
 * should have no mark at all.
 */
function barPath(x: number, y: number, length: number, height: number): string {
  if (length < 1) return '';
  const radius = Math.min(4, length / 2, height / 2);
  const end = x + length;
  return `<path class="bench-chart__bar" d="M${x} ${y}`
    + `H${end - radius}A${radius} ${radius} 0 0 1 ${end} ${y + radius}`
    + `V${y + height - radius}A${radius} ${radius} 0 0 1 ${end - radius} ${y + height}`
    + `H${x}Z" />`;
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

  try {
    let completed: GenerationResult | null = null;
    for await (const event of RunAnywhere.llm.generateStream(BENCH_PROMPT, {
      maxOutputTokens: maxTokens,
      temperature: 0,
    })) {
      if (event.type === 'completed') {
        completed = event.result;
      }
    }
    // Harness wall for e2e only. TTFT / tok/s / token counts come from commons
    // via GenerationResult — never substitute a local stopwatch or chunk count.
    const totalTimeMs = performance.now() - startedAt;
    const ttftMs = completed && completed.timeToFirstTokenMs > 0
      ? completed.timeToFirstTokenMs
      : null;
    const outputTokens = completed && completed.outputTokens > 0
      ? completed.outputTokens
      : null;
    const tokensPerSecond = completed && completed.tokensPerSecond > 0
      ? completed.tokensPerSecond
      : null;

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
