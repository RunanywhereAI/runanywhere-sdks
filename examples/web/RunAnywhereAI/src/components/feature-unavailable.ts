/**
 * Feature Unavailable Placeholder
 *
 * Renders a consistent "feature pending backend artifacts" panel for views
 * whose Swift-shaped public facade exists but whose Web WASM backend is not
 * shippable yet. The replacement path is the proto-byte WASM bridge installed
 * by backend packages; until the relevant artifacts are present, the example
 * app keeps the tab interactive but refuses to dispatch inference verbs.
 */

import { escapeHtml } from '../services/escape-html';

export interface FeatureUnavailableOptions {
  /** Display name of the tab (Chat, Vision, Voice, Transcribe, ...). */
  title: string;
  /** Short description of what the feature does. */
  description: string;
  /** SDK namespaces / facades the view normally consumes. */
  requires: readonly string[];
}

export function renderFeatureUnavailable(host: HTMLElement, options: FeatureUnavailableOptions): void {
  const requirementList = options.requires
    .map((name) => `<li><code>${escapeHtml(name)}</code></li>`)
    .join('');

  host.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">${escapeHtml(options.title)}</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="feature-unavailable">
      <div class="feature-unavailable__icon" aria-hidden="true">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.4" width="48" height="48">
          <circle cx="12" cy="12" r="10"/>
          <line x1="12" y1="8" x2="12" y2="12"/>
          <line x1="12" y1="16" x2="12.01" y2="16"/>
        </svg>
      </div>
      <h2>${escapeHtml(options.title)} is not wired up</h2>
      <p class="feature-unavailable__description">${escapeHtml(options.description)}</p>
      <p class="feature-unavailable__hint">
        The app uses the Swift-shaped <code>RunAnywhere</code> root facade.
        LLM and VLM route through the llama.cpp proto-byte WASM bridge. The
        ONNX/Sherpa bridge is wired but depends on vendored WASM static
        archives and a build with <code>RAC_WASM_ONNX=ON</code>, so STT/TTS/VAD
        views surface this placeholder until those artifacts are present.
      </p>
      <p class="feature-unavailable__hint">This view normally consumes:</p>
      <ul class="feature-unavailable__list">${requirementList}</ul>
      <p class="feature-unavailable__hint">
        Once the proto-byte bridges install <code>setRunanywhereModule(module)</code>,
        these surfaces will dispatch through commons without further app-side changes.
      </p>
    </div>
  `;
}
