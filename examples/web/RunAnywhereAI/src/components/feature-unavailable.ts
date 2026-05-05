/**
 * Feature Unavailable Placeholder
 *
 * Renders a consistent "feature pending V2 backend wiring" panel for views
 * that depended on legacy SDK APIs (ModelManager, ExtensionPoint, STT/TTS/VAD
 * facades). After the V2 dead-code purge those facades were deleted; the
 * replacement is a thin proto-byte WASM bridge that backend packages will
 * install once the new wiring lands. Until then the example app loads the
 * Phase 1 SDK init flow but refuses to dispatch inference verbs.
 */

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
    .map((name) => `<li><code>${escape(name)}</code></li>`)
    .join('');

  host.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">${escape(options.title)}</div>
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
      <h2>${escape(options.title)} is not wired up</h2>
      <p class="feature-unavailable__description">${escape(options.description)}</p>
      <p class="feature-unavailable__hint">
        After the V2 SDK cleanup the legacy <code>ModelManager</code>,
        <code>ExtensionPoint</code>, and provider registry were removed. The
        replacement is a proto-byte WASM bridge installed by the backend
        packages — currently <code>@runanywhere/web-llamacpp</code> and
        <code>@runanywhere/web-onnx</code> are intentionally empty stubs that
        will receive the new wiring in a follow-up.
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

function escape(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
