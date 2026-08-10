/**
 * Settings Tab - Generation params, API config, logging, about.
 *
 * Mirrors iOS SettingsViewModel.swift (Features/Settings/SettingsViewModel.swift):
 * generation settings (temperature / maxTokens / systemPrompt / thinkingMode)
 * persist across sessions and are read by the Chat tab at send time; API
 * credentials are applied by `main.ts` through an explicit runtime
 * reinitialization action.
 *
 * Persistence: generation preferences and the base URL use localStorage. The
 * API key is intentionally session-only because browsers do not provide a
 * Keychain-equivalent secret store to a normal Web application.
 */

import { RunAnywhere } from '@runanywhere/web';
import { icon } from '../components/icons';
import { escapeHtml } from '../services/escape-html';
import {
  isUsableCredential,
  normalizeProductionBaseURL,
} from '../services/network-configuration';

let container: HTMLElement;

const STORAGE_KEY = 'runanywhere-settings';

/**
 * Max-token bounds, named because they are enforced in three places that must
 * agree: the stepper's clamp, the persisted-value validator, and the hint that
 * tells the user what the range is. They were previously literals in the first
 * two and absent from the third, so the ceiling was invisible until generation
 * time.
 */
const TOKENS_MIN = 500;
const TOKENS_MAX = 20_000;
const TOKENS_STEP = 500;

// Generation defaults mirror iOS. A persisted explicit preference still wins
// in loadSettings().
const DEFAULT_SYSTEM_PROMPT = 'You are a helpful, concise AI assistant.';

interface AppSettings {
  temperature: number;
  maxTokens: number;
  systemPrompt: string;
  thinkingModeEnabled: boolean;
  apiKey: string;
  baseURL: string;
}

interface PersistedAppSettings {
  temperature?: number;
  maxTokens?: number;
  systemPrompt?: string;
  thinkingModeEnabled?: boolean;
  baseURL?: string;
}

type JsonObject = Readonly<Record<string, unknown>>;

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function decodePersistedSettings(value: unknown): PersistedAppSettings | null {
  if (!isJsonObject(value)) return null;

  const decoded: PersistedAppSettings = {};
  if (
    typeof value.temperature === 'number'
    && Number.isFinite(value.temperature)
    && value.temperature >= 0
    && value.temperature <= 2
  ) {
    decoded.temperature = value.temperature;
  }
  if (
    typeof value.maxTokens === 'number'
    && Number.isInteger(value.maxTokens)
    && value.maxTokens >= TOKENS_MIN
    && value.maxTokens <= TOKENS_MAX
    && value.maxTokens % TOKENS_STEP === 0
  ) {
    decoded.maxTokens = value.maxTokens;
  }
  if (typeof value.systemPrompt === 'string') {
    decoded.systemPrompt = value.systemPrompt;
  }
  if (typeof value.thinkingModeEnabled === 'boolean') {
    decoded.thinkingModeEnabled = value.thinkingModeEnabled;
  }
  if (value.baseURL === '') {
    decoded.baseURL = '';
  } else if (typeof value.baseURL === 'string') {
    const normalizedURL = normalizeProductionBaseURL(value.baseURL);
    if (normalizedURL) decoded.baseURL = normalizedURL;
  }
  return decoded;
}

const settings: AppSettings = {
  temperature: 0.7,
  maxTokens: 10000,
  systemPrompt: DEFAULT_SYSTEM_PROMPT,
  // Opt-in: thinking-capable models answer directly unless the user enables this.
  thinkingModeEnabled: false,
  apiKey: '',
  baseURL: '',
};

let loaded = false;

export interface APIConfiguration {
  apiKey: string;
  baseURL: string;
}

export interface APIConfigurationApplyResult {
  environment: string;
  telemetryEnabled: boolean;
}

/**
 * Resolve optional build-time production configuration for hosted clients.
 * Vite exposes `VITE_*` values to the browser bundle, so this is suitable
 * only for a publishable client key, never a server-side secret. The key is
 * not copied into Settings or localStorage. Keep the hosted key and URL paired
 * so a previously persisted custom URL cannot receive the hosted credential.
 */
export function getHostedAPIConfiguration(): APIConfiguration | null {
  const apiKey = import.meta.env.VITE_RUNANYWHERE_API_KEY?.trim() ?? '';
  const baseURL = normalizeProductionBaseURL(
    import.meta.env.VITE_RUNANYWHERE_BASE_URL,
  );
  if (!isUsableCredential(apiKey) || !baseURL) return null;
  return { apiKey, baseURL };
}

type APIConfigurationApplyHandler = (
  configuration: APIConfiguration,
) => Promise<APIConfigurationApplyResult>;

let applyAPIConfigurationHandler: APIConfigurationApplyHandler | null = null;

/** Environment the running SDK was initialized with, reported by the bootstrap. */
let activeEnvironment = 'development';

/**
 * Whether a Hugging Face token was set in this session. The SDK deliberately
 * offers no read-back, so this flag only reflects what this view submitted.
 */
let hfTokenConfigured = false;

/**
 * Installed by the application bootstrap so the Settings view stays a thin
 * UI layer while `main.ts` owns SDK/backend lifecycle ordering.
 */
export function setAPIConfigurationApplyHandler(
  handler: APIConfigurationApplyHandler,
): void {
  applyAPIConfigurationHandler = handler;
}

/**
 * Generation settings consumed by the Chat tab — typed counterpart of iOS
 * `SettingsViewModel.getGenerationConfiguration()` (SettingsViewModel.swift:262-269).
 */
export interface GenerationSettings {
  temperature: number;
  maxTokens: number;
  systemPrompt: string;
  thinkingModeEnabled: boolean;
}

export function getGenerationSettings(): GenerationSettings {
  loadSettings();
  return {
    temperature: settings.temperature,
    maxTokens: settings.maxTokens,
    systemPrompt: settings.systemPrompt,
    thinkingModeEnabled: settings.thinkingModeEnabled,
  };
}

/**
 * Set reasoning on or off from outside the Settings tab.
 *
 * The chat composer carries the same toggle (reasoning changes what the next turn
 * does, so it belongs where the turn is composed — iOS and Android both put it
 * there). Both controls write this one persisted value rather than keeping their own
 * copy, so they cannot disagree, and the Settings switch shows the composer's last
 * choice because that view rebuilds its markup from `settings` on mount.
 */
export function setThinkingModeEnabled(enabled: boolean): void {
  loadSettings();
  settings.thinkingModeEnabled = enabled;
  saveSettings();
}

export function initSettingsTab(el: HTMLElement): void {
  container = el;
  loadSettings();
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Settings</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="settings-form">

      <!-- Generation (iOS parity: SettingsViewModel.swift:20-24 defaults) -->
      <div class="settings-section">
        <div class="settings-section-title">Generation</div>
        <div class="setting-row">
          <label class="setting-label" for="settings-temp">Temperature</label>
          <div class="flex items-center gap-sm">
            <span class="setting-value" id="settings-temp-val" aria-hidden="true">${settings.temperature.toFixed(1)}</span>
            <input type="range" id="settings-temp" min="0" max="2" step="0.1" value="${settings.temperature}"
              aria-describedby="settings-temp-hint">
          </div>
        </div>
        <p class="setting-hint" id="settings-temp-hint">
          0 is repeatable and literal, 2 is loose and inventive. The slider
          reports its own value, so the number beside it is decorative.
        </p>
        <div class="setting-row">
          <span class="setting-label" id="settings-tokens-label">Max Tokens</span>
          <div class="flex items-center gap-sm">
            <button type="button" class="btn btn-sm" id="settings-tokens-minus"
              aria-label="Decrease max tokens by ${TOKENS_STEP}">&minus;</button>
            <span class="setting-value" id="settings-tokens-val" role="status" aria-live="polite"
              aria-labelledby="settings-tokens-label">${settings.maxTokens}</span>
            <button type="button" class="btn btn-sm" id="settings-tokens-plus"
              aria-label="Increase max tokens by ${TOKENS_STEP}">+</button>
          </div>
        </div>
        <p class="setting-hint" id="settings-tokens-hint">
          ${TOKENS_MIN.toLocaleString()}–${TOKENS_MAX.toLocaleString()}, in steps of
          ${TOKENS_STEP}. A model still stops early at its own context limit.
        </p>
        <div class="setting-row setting-row--stacked">
          <label class="label" for="settings-system-prompt">System Prompt</label>
          <textarea class="text-input w-full" id="settings-system-prompt" rows="3"
            placeholder="${escapeHtml(DEFAULT_SYSTEM_PROMPT)}">${escapeHtml(settings.systemPrompt)}</textarea>
        </div>
        <div class="setting-row">
          <span class="setting-label" id="settings-thinking-label">Thinking Mode</span>
          <!-- A real <button role="switch">, not a styled <div>: this was a
               click-only element with tabIndex -1, no role and no state, so it
               was unreachable by keyboard and silent to a screen reader — a fake
               toggle by this app's own truthfulness rule, even though the value
               it wrote was honoured at send time. -->
          <button type="button" class="toggle" id="settings-thinking-toggle"
            role="switch" aria-checked="${settings.thinkingModeEnabled ? 'true' : 'false'}"
            aria-labelledby="settings-thinking-label"
            aria-describedby="settings-thinking-hint"></button>
        </div>
        <p class="setting-hint" id="settings-thinking-hint">
          Off by default. Turn on for thinking-capable models (e.g. Qwen3)
          when you want a visible reasoning phase before the answer.
        </p>
        <p class="setting-saved" id="settings-generation-saved" role="status" aria-live="polite"></p>
      </div>

      <!-- Optional direct-browser API configuration, applied explicitly by
           main.ts through the same runtime reinitialization path as iOS. -->
      <div class="settings-section">
        <div class="settings-section-title">API Configuration</div>
        <div class="setting-row setting-row--stacked">
          <label class="label">API Key</label>
          <input type="password" class="text-input w-full" id="settings-api-key" placeholder="Enter API key..." autocomplete="off" spellcheck="false" value="${escapeHtml(settings.apiKey)}">
        </div>
        <div class="setting-row setting-row--stacked">
          <label class="label">Base URL</label>
          <input type="url" class="text-input w-full" id="settings-base-url" placeholder="https://api.runanywhere.ai" value="${escapeHtml(settings.baseURL)}">
          <p class="setting-hint">
            This client-only example sends the key directly from your browser.
            It stays in memory for this tab only and is never saved. The
            endpoint must support browser CORS; production proxying, secret
            storage, authentication, and rate limiting belong in your own
            backend.
          </p>
          <div class="flex items-center gap-sm">
            <button type="button" class="btn btn-primary" id="settings-apply-api">Apply &amp; Reinitialize</button>
            <span class="setting-hint" id="settings-api-status" role="status" aria-live="polite"></span>
          </div>
        </div>
      </div>

      <!-- Hugging Face access token for restricted model downloads. The SDK owns
           the token (RunAnywhere.setHuggingFaceToken); it is held in memory for the
           current session only and is never persisted to browser storage.

           The hint below is consumer copy and deliberately names none of that:
           it used to say "gated or private models" and quote the SDK method,
           which tells the reader what the code does rather than whether they
           need to do anything. -->
      <div class="settings-section">
        <div class="settings-section-title">Hugging Face Access</div>
        <div class="setting-row">
          <span class="setting-label">Access token</span>
          <span class="setting-value" id="settings-hf-state">${hfTokenConfigured ? 'Configured' : 'Not set'}</span>
        </div>
        <div class="setting-row setting-row--stacked">
          <label class="sr-only" for="settings-hf-token">Hugging Face access token</label>
          <input type="password" class="text-input w-full" id="settings-hf-token" placeholder="hf_..." autocomplete="off" spellcheck="false">
          <p class="setting-hint">
            Optional. Every model in this app downloads without one. You only
            need a token for models Hugging Face asks you to sign in for &mdash;
            a licence you have to accept, or something private of your own.
            It is kept in memory for this tab only, never saved, and never sent
            anywhere but Hugging Face; re-enter it after a reload.
            <a href="https://huggingface.co/settings/tokens" target="_blank" rel="noopener">Get a token</a>.
          </p>
          <div class="flex items-center gap-sm">
            <button type="button" class="btn btn-secondary" id="settings-hf-clear">Clear</button>
            <span class="setting-hint" id="settings-hf-status" role="status" aria-live="polite"></span>
          </div>
        </div>
      </div>

      <!-- Logging -->
      <div class="settings-section">
        <div class="settings-section-title">Logging</div>
        <div class="setting-row">
          <span class="setting-label">Analytics</span>
          <span class="setting-value" id="settings-analytics-state">${telemetryState().label}</span>
        </div>
        <p class="setting-hint" id="settings-analytics-hint">${telemetryState().hint}</p>
      </div>

      <!-- About -->
      <div class="settings-section">
        <div class="settings-section-title">About</div>
        <div class="setting-row">
          <span class="setting-label">SDK Version</span>
          <span class="setting-value">${RunAnywhere.version}</span>
        </div>
        <div class="setting-row">
          <span class="setting-label">Platform</span>
          <!-- Emscripten is the toolchain that produced the binary, not a thing
               the reader is running on. WebAssembly is. -->
          <span class="setting-value">Web browser (WebAssembly)</span>
        </div>
        <a class="setting-row setting-row--link" id="settings-docs-link"
          href="https://docs.runanywhere.ai" target="_blank" rel="noopener noreferrer">
          <span class="setting-label">Documentation</span>
          ${icon('externalLink', { size: 16 })}
        </a>
      </div>

    </div>
  `;

  // Temperature slider
  const tempSlider = container.querySelector('#settings-temp') as HTMLInputElement;
  const tempVal = container.querySelector('#settings-temp-val')!;
  tempSlider.addEventListener('input', () => {
    settings.temperature = parseFloat(tempSlider.value);
    tempVal.textContent = settings.temperature.toFixed(1);
    // `input` fires per pixel of drag, so announce once the drag settles rather
    // than shouting "Saved" a hundred times into the live region.
    saveSettings({ announce: false });
  });
  tempSlider.addEventListener('change', () => saveSettings());

  // Max tokens stepper
  const tokensVal = container.querySelector('#settings-tokens-val')!;
  const minusButton = container.querySelector('#settings-tokens-minus') as HTMLButtonElement;
  const plusButton = container.querySelector('#settings-tokens-plus') as HTMLButtonElement;
  const stepTokens = (delta: number): void => {
    const next = Math.min(TOKENS_MAX, Math.max(TOKENS_MIN, settings.maxTokens + delta));
    if (next === settings.maxTokens) return;
    settings.maxTokens = next;
    tokensVal.textContent = String(settings.maxTokens);
    // Disable at the ends instead of letting a live button do nothing — the
    // ceiling was previously invisible until a model refused the request.
    minusButton.disabled = settings.maxTokens <= TOKENS_MIN;
    plusButton.disabled = settings.maxTokens >= TOKENS_MAX;
    saveSettings();
  };
  minusButton.disabled = settings.maxTokens <= TOKENS_MIN;
  plusButton.disabled = settings.maxTokens >= TOKENS_MAX;
  minusButton.addEventListener('click', () => stepTokens(-TOKENS_STEP));
  plusButton.addEventListener('click', () => stepTokens(TOKENS_STEP));

  // System prompt (iOS parity: SettingsViewModel.swift:251-254 saveSystemPrompt)
  const systemPromptInput = container.querySelector('#settings-system-prompt') as HTMLTextAreaElement;
  systemPromptInput.addEventListener('change', () => {
    settings.systemPrompt = systemPromptInput.value;
    saveSettings();
  });

  // Toggles
  setupToggle('settings-thinking-toggle', (on) => {
    settings.thinkingModeEnabled = on;
    saveSettings();
  });

  // API inputs
  const apiKeyInput = container.querySelector('#settings-api-key') as HTMLInputElement;
  const baseURLInput = container.querySelector('#settings-base-url') as HTMLInputElement;
  apiKeyInput.addEventListener('change', () => {
    settings.apiKey = apiKeyInput.value;
    saveSettings();
  });
  baseURLInput.addEventListener('change', () => {
    settings.baseURL = baseURLInput.value;
    saveSettings();
  });

  const applyButton = container.querySelector('#settings-apply-api') as HTMLButtonElement;
  const status = container.querySelector('#settings-api-status') as HTMLElement;
  applyButton.addEventListener('click', () => {
    void applyAPIConfiguration(apiKeyInput, baseURLInput, applyButton, status);
  });

  // Hugging Face access token. The SDK owns it and holds it in memory for the
  // current session only; the token is never read back or persisted here.
  // Public models need no token; gated/private models download once one is set.
  const hfInput = container.querySelector('#settings-hf-token') as HTMLInputElement;
  const hfState = container.querySelector('#settings-hf-state') as HTMLElement;
  const hfStatus = container.querySelector('#settings-hf-status') as HTMLElement;
  hfInput.addEventListener('change', () => {
    const token = hfInput.value.trim();
    if (!token) return;
    try {
      RunAnywhere.setHuggingFaceToken(token);
      hfTokenConfigured = true;
      hfInput.value = '';
      hfState.textContent = 'Configured';
      hfStatus.textContent = 'Token set for downloads this session.';
    } catch (error) {
      hfStatus.textContent =
        error instanceof Error ? error.message : 'Failed to set the token.';
    }
  });
  container.querySelector('#settings-hf-clear')!.addEventListener('click', () => {
    try {
      RunAnywhere.setHuggingFaceToken(null);
      hfTokenConfigured = false;
      hfInput.value = '';
      hfState.textContent = 'Not set';
      hfStatus.textContent = 'Token cleared.';
    } catch (error) {
      hfStatus.textContent =
        error instanceof Error ? error.message : 'Unable to clear the token. Please try again.';
    }
  });

  // The docs link is a real <a href target="_blank">, so the browser owns
  // opening it — which is what makes it keyboard-reachable, announced as a
  // link, and usable via "open in new window". It was a <div> with a click
  // handler calling window.open(), which none of those are true of.
}

async function applyAPIConfiguration(
  apiKeyInput: HTMLInputElement,
  baseURLInput: HTMLInputElement,
  applyButton: HTMLButtonElement,
  status: HTMLElement,
): Promise<void> {
  status.classList.remove('text-success', 'text-error');

  let configuration: APIConfiguration;
  try {
    configuration = validateAPIConfiguration(apiKeyInput.value, baseURLInput.value);
  } catch (err) {
    status.textContent = err instanceof Error ? err.message : String(err);
    status.classList.add('text-error');
    return;
  }

  if (!applyAPIConfigurationHandler) {
    status.textContent = 'SDK reconfiguration is not available yet.';
    status.classList.add('text-error');
    return;
  }

  applyButton.disabled = true;
  applyButton.textContent = 'Reinitializing…';
  status.textContent = 'Stopping backends and applying production configuration…';

  try {
    const result = await applyAPIConfigurationHandler(configuration);
    settings.apiKey = configuration.apiKey;
    settings.baseURL = configuration.baseURL;
    baseURLInput.value = configuration.baseURL;
    saveSettings();
    updateTelemetryState(result.environment, result.telemetryEnabled);
    status.textContent = 'Production configuration applied. All backends and the model catalog are ready.';
    status.classList.add('text-success');
  } catch (err) {
    status.textContent = err instanceof Error ? err.message : String(err);
    status.classList.add('text-error');
  } finally {
    applyButton.disabled = false;
    applyButton.textContent = 'Apply & Reinitialize';
  }
}

function validateAPIConfiguration(apiKey: string, baseURL: string): APIConfiguration {
  const normalizedKey = apiKey.trim();
  if (!normalizedKey) {
    throw new Error('Enter an API key.');
  }
  if (!isUsableCredential(normalizedKey)) {
    throw new Error('Replace the placeholder API key.');
  }

  const normalizedURL = normalizeProductionBaseURL(baseURL);
  if (!normalizedURL) {
    throw new Error(
      'Enter a valid HTTPS base URL without credentials, query parameters, or fragments.',
    );
  }

  return { apiKey: normalizedKey, baseURL: normalizedURL };
}

function telemetryState(): { label: string; hint: string } {
  if (!RunAnywhere.isReady) {
    return {
      label: 'Unavailable',
      hint: 'Telemetry is controlled by the SDK environment and the SDK is not initialized.',
    };
  }
  const enabled = activeEnvironment === 'production';
  return {
    label: enabled ? 'Enabled' : 'Disabled',
    hint: `Read-only SDK state: ${activeEnvironment} environment ${enabled ? 'sends' : 'does not send'} telemetry.`,
  };
}

function updateTelemetryState(environment: string, enabled: boolean): void {
  activeEnvironment = environment;
  const state = container.querySelector('#settings-analytics-state');
  const hint = container.querySelector('#settings-analytics-hint');
  if (state) state.textContent = enabled ? 'Enabled' : 'Disabled';
  if (hint) {
    hint.textContent = `Read-only SDK state: ${environment} environment ${enabled ? 'sends' : 'does not send'} telemetry.`;
  }
}

/**
 * Wire a `role="switch"` button.
 *
 * `aria-checked` is the state of record and `.on` is only its visual echo, so
 * the two cannot disagree — a screen reader reads the same value the eye sees.
 * Space and Enter come free from using a real `<button>`.
 */
function setupToggle(id: string, onChange: (on: boolean) => void): void {
  const toggle = container.querySelector(`#${id}`)!;
  const render = (on: boolean): void => {
    toggle.setAttribute('aria-checked', on ? 'true' : 'false');
    toggle.classList.toggle('on', on);
  };
  // Sync once up front rather than writing the class in the template too: a
  // switch restored from storage as on would otherwise render visually off,
  // which is the exact disagreement this arrangement exists to rule out.
  render(toggle.getAttribute('aria-checked') === 'true');
  toggle.addEventListener('click', () => {
    const next = toggle.getAttribute('aria-checked') !== 'true';
    render(next);
    onChange(next);
  });
}

/**
 * Confirm a preference was stored.
 *
 * Every generation setting writes to localStorage on change and previously did
 * so in complete silence, leaving no way to tell a saved value from a dropped
 * one. Announced through a polite live region so it is spoken as well as seen,
 * and cleared afterwards so a stale "Saved" cannot outlive its edit.
 */
let savedNoticeTimer: number | null = null;

function announceSaved(): void {
  const notice = container?.querySelector('#settings-generation-saved');
  if (!notice) return;
  notice.textContent = 'Saved';
  notice.classList.add('setting-saved--visible');
  // Clears a previous storage failure: if writing works now, the warning it left
  // behind is stale and must not stay on screen in its error colour.
  notice.classList.remove('setting-saved--error');
  if (savedNoticeTimer !== null) window.clearTimeout(savedNoticeTimer);
  savedNoticeTimer = window.setTimeout(() => {
    notice.textContent = '';
    notice.classList.remove('setting-saved--visible');
    savedNoticeTimer = null;
  }, 2000);
}

function saveSettings(options: { announce?: boolean } = {}): void {
  try {
    // iOS parity stops at the Keychain: SettingsViewModel persists the API
    // key via KeychainService (SettingsViewModel.swift:65-72), and browsers
    // have no equivalent secret store. Clear-text localStorage is not an
    // acceptable substitute (CodeQL js/clear-text-storage-of-sensitive-data),
    // so the key is session-only — every other setting round-trips.
    const { apiKey: _apiKey, ...persistable } = settings;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(persistable));
    if (options.announce !== false) announceSaved();
  } catch {
    // Storage can be unavailable (private mode, quota, blocked cookies). Say so
    // rather than reporting a save that did not happen.
    reportSaveFailed();
  }
}

/**
 * Report that the preference did *not* persist.
 *
 * The catch here used to swallow the failure entirely, which — now that the
 * success path says "Saved" — would be the worse kind of dishonesty: a setting
 * that silently reverts on reload while the UI claimed otherwise.
 */
function reportSaveFailed(): void {
  const notice = container?.querySelector('#settings-generation-saved');
  if (!notice) return;
  if (savedNoticeTimer !== null) {
    window.clearTimeout(savedNoticeTimer);
    savedNoticeTimer = null;
  }
  notice.textContent = 'Not saved — this browser blocked local storage, so this applies to the current tab only.';
  notice.classList.add('setting-saved--visible', 'setting-saved--error');
}

function loadSettings(): void {
  if (loaded) return;
  loaded = true;
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      const parsed: unknown = JSON.parse(saved);
      const persisted = decodePersistedSettings(parsed);
      if (!persisted) return;
      if (persisted.temperature !== undefined) settings.temperature = persisted.temperature;
      if (persisted.maxTokens !== undefined) settings.maxTokens = persisted.maxTokens;
      if (persisted.systemPrompt !== undefined) settings.systemPrompt = persisted.systemPrompt;
      if (persisted.thinkingModeEnabled !== undefined) {
        settings.thinkingModeEnabled = persisted.thinkingModeEnabled;
      }
      if (persisted.baseURL !== undefined) settings.baseURL = persisted.baseURL;

      // Keep the persisted object restricted to the current, validated,
      // non-secret settings shape.
      const { apiKey: _apiKey, ...canonical } = settings;
      localStorage.setItem(STORAGE_KEY, JSON.stringify(canonical));
    }
  } catch { /* storage may not be available */ }
}
