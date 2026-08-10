/**
 * File drop zone — one "put a file here" affordance for the whole app.
 *
 * WHY THIS EXISTS. Three views asked for a file and got three different
 * answers. Documents had a real drop target: a `<button>` wrapping a hidden
 * input, a dashed brand-coloured surface, an enter/leave depth counter so the
 * highlight survives the pointer crossing onto a child, and `dragover`
 * cancellation on the surrounding section so a near-miss doesn't navigate the
 * tab away to the dropped file. Transcribe and Diarization shipped a bare
 * `<input type="file">` — the browser's default grey "Choose File" control,
 * which cannot be styled, ignores the design system, gives no drop target at
 * all, and reads to a screen reader as an unlabelled input.
 *
 * A fourth arrangement was already written and abandoned: `.stt-drop-zone` in
 * `components.css` had a full set of rules and zero markup referencing it, in
 * `--color-blue` rather than the brand orange. With no CSS module scoping, that
 * kind of orphan is invisible — which is exactly why the affordance belongs in
 * one component instead of being re-typed per view.
 *
 * Rendering is split from wiring because every caller builds its body with
 * `innerHTML` and then binds: `renderFileDrop` returns markup, `wireFileDrop`
 * attaches behaviour to whatever that markup became.
 */

import { icon } from './icons';

export interface FileDropOptions {
  /** Unique id prefix; the input and hint derive their ids from it. */
  id: string;
  /** The `accept` attribute — the same list the hint should describe. */
  accept: string;
  /** Primary line, e.g. "Drop an audio file here, or click to choose". */
  title: string;
  /** Secondary line naming the accepted formats. */
  hint: string;
  multiple?: boolean;
  disabled?: boolean;
}

export function renderFileDrop(options: FileDropOptions): string {
  const { id, accept, title, hint, multiple = false, disabled = false } = options;
  return `
    <input type="file" id="${id}-input" accept="${accept}" ${multiple ? 'multiple' : ''} hidden />
    <button type="button" class="docs-dropzone" id="${id}" aria-describedby="${id}-hint"
      ${disabled ? 'disabled' : ''}>
      ${icon('upload', { size: 28, className: 'docs-dropzone-glyph' })}
      <span class="docs-dropzone-title">${title}</span>
      <span class="docs-dropzone-hint" id="${id}-hint">${hint}</span>
    </button>
  `;
}

/**
 * Attach click, drag-highlight and drop handling.
 *
 * `onFiles` receives a non-empty list. A drop or a picker cancellation that
 * yields nothing is not reported, so no caller has to guard against an empty
 * batch before showing a status message.
 */
export function wireFileDrop(
  root: ParentNode,
  id: string,
  onFiles: (files: readonly File[]) => void,
): void {
  const zone = root.querySelector<HTMLButtonElement>(`#${id}`);
  const input = root.querySelector<HTMLInputElement>(`#${id}-input`);
  if (!zone || !input) return;

  zone.addEventListener('click', () => input.click());
  input.addEventListener('change', () => {
    const files = Array.from(input.files ?? []);
    // Reset so choosing the same file twice in a row still fires `change`.
    input.value = '';
    if (files.length > 0) onFiles(files);
  });

  // A depth counter, not `:hover`: a pointer dragging a file does not reliably
  // hover, and a plain `dragleave` fires when crossing onto a child, which would
  // flicker the highlight off while the file is still over the zone.
  let depth = 0;
  const setActive = (active: boolean): void => {
    zone.classList.toggle('docs-dropzone--active', active);
  };

  zone.addEventListener('dragenter', (event) => {
    event.preventDefault();
    depth += 1;
    setActive(true);
  });
  zone.addEventListener('dragover', (event) => {
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy';
  });
  zone.addEventListener('dragleave', () => {
    depth = Math.max(0, depth - 1);
    if (depth === 0) setActive(false);
  });
  zone.addEventListener('drop', (event) => {
    event.preventDefault();
    depth = 0;
    setActive(false);
    const files = Array.from(event.dataTransfer?.files ?? []);
    if (files.length > 0) onFiles(files);
  });

  // Dropping just outside the zone is a miss, not a request to leave the app for
  // the file's own URL — which is the browser default and looks like a crash.
  const section = zone.closest('.docs-section');
  section?.addEventListener('dragover', (event) => event.preventDefault());
  section?.addEventListener('drop', (event) => event.preventDefault());
}
