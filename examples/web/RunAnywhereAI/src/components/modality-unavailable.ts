/**
 * "This modality has no browser engine yet" — the designed state for a surface
 * that cannot run at all in this build.
 *
 * WHY THIS EXISTS. Segmentation and Diarization each rendered their complete
 * working screen — a "Load Segmentation Model" button in the toolbar, a file
 * picker, a disabled Run — with a paragraph underneath admitting that no browser
 * engine ships and that the picker above is empty. So the screen's *shape* said
 * "choose a model above and press Run" while its prose said "you cannot". The
 * button opened a sheet with nothing in it, which is the one outcome a picker
 * must never have: a control that exists implies something is behind it.
 *
 * This is not an error state and must not look like one. Nothing failed; a
 * capability simply is not part of the Web build yet. So it wears neutral ink
 * rather than the brand's action colour or the red of a failure, and it answers
 * the three questions the user actually has: what would this do, why can't it,
 * and what would have to change.
 *
 * Shared rather than written twice, for the same reason `engine-notice.ts` is:
 * two surfaces describing the same class of state in two different vocabularies
 * is how an interface stops being trustworthy.
 */

import { escapeHtml } from '../services/escape-html';
import { icon, type IconName } from './icons';

export interface ModalityUnavailableView {
  /** The modality's glyph — the same one its model rows would carry. */
  glyph: IconName;
  /** The surface's own name, as the nav spells it ("Segmentation"). */
  title: string;
  /** One plain sentence: what this would do for the user. No SDK vocabulary. */
  summary: string;
  /**
   * What would have to become true, in order, ending with what happens then.
   * Written as facts about this build, never as instructions to the user —
   * there is no action available to them here.
   */
  requirements: readonly string[];
  /** The exact call this screen makes once it can run. */
  verb: string;
  /** Where the same capability works today. */
  elsewhere: string;
}

/**
 * The markup. Returns a string so a view that builds its body with `innerHTML`
 * can interpolate it; there is nothing to wire, because there is deliberately no
 * control on this screen.
 */
export function renderModalityUnavailable(view: ModalityUnavailableView): string {
  const requirements = view.requirements
    .map((line) => `<li>${escapeHtml(line)}</li>`)
    .join('');

  return `
    <div class="feature-unavailable">
      <div class="feature-unavailable__icon">${icon(view.glyph, { size: 32 })}</div>
      <h2>${escapeHtml(view.title)} doesn&rsquo;t run in the browser yet</h2>
      <p class="feature-unavailable__description">${escapeHtml(view.summary)}</p>
      <ul class="feature-unavailable__list">
        ${requirements}
        <li>
          This screen already calls <code>${escapeHtml(view.verb)}</code>. It turns
          into the live flow the moment an engine registers &mdash; nothing here
          has to change.
        </li>
      </ul>
      <p class="feature-unavailable__hint">${escapeHtml(view.elsewhere)}</p>
    </div>
  `;
}
