/**
 * Structured — extract typed JSON via `llm.generateStructured`.
 */
import { generationOptions, loadAppSettings } from '../services/settings';
import { showError } from '../components/toast';
import type { ViewFactory } from '../shell/app';
import type { JsonSchema } from '@runanywhere/electron';

const PERSON_SCHEMA: JsonSchema = {
  type: 'object',
  properties: {
    name: { type: 'string' },
    age: { type: 'integer' },
    interests: { type: 'array', items: { type: 'string' }, maxItems: 5 },
  },
  required: ['name', 'age', 'interests'],
};

export const createStructuredView: ViewFactory = ({ root }) => {
  let busy = false;

  const scroll = document.createElement('div');
  scroll.className = 'ra-view-scroll ra-stack';
  scroll.innerHTML =
    `<section class="ra-card ra-stack">` +
    `<h2 class="ra-section-title">Extract a person</h2>` +
    `<p class="ra-muted">The model is constrained to a fixed schema so the JSON always parses.</p>` +
    `<textarea class="ra-textarea" id="struct-text" rows="4">Marie Curie was a 66 year old Polish physicist who loved chemistry.</textarea>` +
    `<button type="button" class="ra-btn-primary" id="struct-go">Extract</button>` +
    `<pre class="ra-code-out" id="struct-out"></pre>` +
    `</section>`;
  root.append(scroll);

  const textEl = scroll.querySelector<HTMLTextAreaElement>('#struct-text');
  const goBtn = scroll.querySelector<HTMLButtonElement>('#struct-go');
  const out = scroll.querySelector<HTMLElement>('#struct-out');
  if (textEl === null || goBtn === null || out === null) return {};

  goBtn.addEventListener('click', () => {
    void (async () => {
      if (busy) return;
      const text = textEl.value.trim();
      if (text === '') return;
      busy = true;
      goBtn.disabled = true;
      out.textContent = 'Extracting…';
      try {
        await loadAppSettings();
        const result = await window.runanywhere.llm.generateStructured(
          `Extract the person as JSON. Text: "${text}"`,
          PERSON_SCHEMA,
          generationOptions(),
        );
        out.textContent = JSON.stringify(result.value, null, 2);
      } catch (error) {
        showError(error, 'Structured extraction failed');
        out.textContent = error instanceof Error ? error.message : 'Failed';
      } finally {
        busy = false;
        goBtn.disabled = false;
      }
    })();
  });

  return {};
};
