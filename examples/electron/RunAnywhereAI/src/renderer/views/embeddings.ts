/**
 * Embeddings — cosine similarity between two texts.
 *
 * SDK: `models.load` (embedder) + `embeddings.embed`. Cosine stays in the app.
 */
import { cosineSimilarity } from '../services/cosine';
import { loadAppSettings, selectedModel } from '../services/settings';
import { showError } from '../components/toast';
import type { ViewFactory } from '../shell/app';

export const createEmbeddingsView: ViewFactory = ({ root }) => {
  let busy = false;
  void loadAppSettings();

  const scroll = document.createElement('div');
  scroll.className = 'ra-view-scroll ra-stack';
  scroll.innerHTML =
    `<section class="ra-card ra-stack">` +
    `<h2 class="ra-section-title">Compare two texts</h2>` +
    `<p class="ra-muted">Higher scores mean closer meaning. Everything runs on this device.</p>` +
    `<label class="ra-field"><span class="ra-muted-label">Text A</span>` +
    `<textarea class="ra-textarea" id="emb-a" rows="3">a cat sat on the mat</textarea></label>` +
    `<label class="ra-field"><span class="ra-muted-label">Text B</span>` +
    `<textarea class="ra-textarea" id="emb-b" rows="3">a kitten rested on the rug</textarea></label>` +
    `<button type="button" class="ra-btn-primary" id="emb-go">Compare</button>` +
    `<div id="emb-out" class="ra-stack"></div>` +
    `</section>`;
  root.append(scroll);

  const aEl = scroll.querySelector<HTMLTextAreaElement>('#emb-a');
  const bEl = scroll.querySelector<HTMLTextAreaElement>('#emb-b');
  const goBtn = scroll.querySelector<HTMLButtonElement>('#emb-go');
  const out = scroll.querySelector<HTMLElement>('#emb-out');
  if (aEl === null || bEl === null || goBtn === null || out === null) return {};

  goBtn.addEventListener('click', () => {
    void (async () => {
      if (busy) return;
      const a = aEl.value.trim();
      const b = bEl.value.trim();
      if (a === '' || b === '') {
        showError('Enter both texts');
        return;
      }
      busy = true;
      goBtn.disabled = true;
      out.innerHTML = `<p class="ra-muted">Embedding…</p>`;
      try {
        await loadAppSettings();
        await window.runanywhere.models.load(selectedModel('embedder'));
        const vectors = await window.runanywhere.embeddings.embed([a, b]);
        const ea = vectors.at(0);
        const eb = vectors.at(1);
        if (ea === undefined || eb === undefined) throw new Error('Missing embedding vectors');
        const score = cosineSimilarity(ea.vector, eb.vector);
        const pct = Math.max(0, Math.min(100, Math.round(((score + 1) / 2) * 100)));
        out.innerHTML =
          `<div class="ra-stat">${score.toFixed(3)}</div>` +
          `<div class="ra-muted">Cosine similarity (−1…1)</div>` +
          `<div class="ra-progress-track"><div class="ra-progress-fill" style="width:${pct}%"></div></div>`;
      } catch (error) {
        out.replaceChildren();
        showError(error, 'Embeddings failed');
      } finally {
        busy = false;
        goBtn.disabled = false;
      }
    })();
  });

  return {};
};
