/**
 * Tools — the model picks a registered tool and fills its arguments.
 *
 * Commons runs the loop (`llm.generate` with tools registered + `toolChoice:
 * REQUIRED`). The app only registers the four demo executors and displays the
 * call the SDK returns.
 *
 * ToolChoice is a string literal here (not a value import) so the renderer
 * never pulls SDK runtime into the Vite bundle.
 */
import type { ToolChoice } from '@runanywhere/electron';

import type { ViewFactory, ViewInstance } from '../shell/app';
import { showError } from '../components/toast';
import { demoToolNames, registerDemoTools } from '../services/demo-tools';
import { logger } from '../services/logger';
import { modelLabel } from '../services/modality-models';
import { generationOptions, loadAppSettings, selectedModel } from '../services/settings';

const log = logger('tools');

/** Matches SDK `ToolChoice.REQUIRED` without importing the runtime const. */
const TOOL_CHOICE_REQUIRED = 'REQUIRED' satisfies ToolChoice;

const DEFAULT_PROMPT = 'What time is it right now?';

function formatArgs(args: Record<string, unknown> | undefined): string {
  const entries = Object.entries(args ?? {}).filter(
    ([key, value]) => key !== '' && value !== '' && value != null,
  );
  return entries.length > 0 ? JSON.stringify(Object.fromEntries(entries)) : '';
}

export const createToolsView: ViewFactory = ({ root, refreshChrome }): ViewInstance => {
  let busy = false;

  const scroll = document.createElement('div');
  scroll.className = 'ra-view-scroll';
  scroll.innerHTML = `
    <div class="ra-stack">
      <p class="ra-hint">The model picks a tool and fills its arguments. Available: ${demoToolNames().join(', ')}.</p>
      <div class="ra-card ra-stack">
        <label class="ra-field">
          <span class="ra-label">Prompt</span>
          <textarea class="ra-textarea" data-role="text" rows="2"></textarea>
        </label>
        <button type="button" class="ra-btn-primary" data-action="run">Choose tool</button>
      </div>
      <div>
        <div class="ra-label">Result</div>
        <pre class="ra-out ra-code" data-role="out" data-empty="The tool the model picks, the arguments it fills, and what the tool returned."></pre>
      </div>
    </div>
  `;
  root.append(scroll);

  const textEl = scroll.querySelector<HTMLTextAreaElement>('[data-role="text"]');
  const out = scroll.querySelector<HTMLElement>('[data-role="out"]');
  const runBtn = scroll.querySelector<HTMLButtonElement>('[data-action="run"]');
  if (textEl !== null) textEl.value = DEFAULT_PROMPT;

  const run = async (): Promise<void> => {
    if (busy) return;
    const text = textEl?.value.trim() ?? '';
    if (text === '') {
      showError('Enter a prompt that needs a tool.');
      return;
    }
    await loadAppSettings();
    registerDemoTools();
    busy = true;
    if (runBtn !== null) runBtn.disabled = true;
    refreshChrome();
    if (out !== null) {
      out.textContent = '';
      out.toggleAttribute('data-has-content', false);
    }
    try {
      const result = await window.runanywhere.llm.generate(
        text,
        generationOptions({ toolChoice: TOOL_CHOICE_REQUIRED }),
      );
      const call = result.toolCalls.at(0);
      const payload =
        call === undefined
          ? { name: '(none)', arguments: {}, result: result.text }
          : {
              name: call.name,
              arguments: call.arguments,
              result: call.result ?? '(no result)',
              answer: result.text,
              formatted: `${call.name}(${formatArgs(call.arguments as Record<string, unknown>)})`,
            };
      if (out !== null) {
        out.textContent = JSON.stringify(payload, null, 2);
        out.toggleAttribute('data-has-content', true);
      }
    } catch (error) {
      log.error('tools failed', error);
      showError(error, 'Tool calling failed');
    } finally {
      busy = false;
      if (runBtn !== null) runBtn.disabled = false;
      refreshChrome();
    }
  };

  scroll.addEventListener('click', (event) => {
    const target = (event.target as HTMLElement | null)?.closest<HTMLElement>('[data-action="run"]');
    if (target !== null && target !== undefined) void run();
  });

  void loadAppSettings();

  return {
    model() {
      const id = selectedModel('llm');
      return { name: modelLabel(id), meta: 'Tools' };
    },
    capabilities() {
      return {
        canStopGeneration: busy,
        canShowChatDetails: false,
        canPasteAttachment: false,
      };
    },
  };
};
