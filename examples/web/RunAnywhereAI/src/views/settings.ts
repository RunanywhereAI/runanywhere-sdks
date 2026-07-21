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

import {
  environmentDescription,
  environmentShouldSendTelemetry,
  RunAnywhere,
} from '@runanywhere/web';
import { escapeHtml } from '../services/escape-html';
import {
  isUsableCredential,
  normalizeProductionBaseURL,
} from '../services/network-configuration';

let container: HTMLElement;

const STORAGE_KEY = 'runanywhere-settings';

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
    && value.maxTokens >= 500
    && value.maxTokens <= 20000
    && value.maxTokens % 500 === 0
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
          <span class="setting-label">Temperature</span>
          <div class="flex items-center gap-sm">
            <span class="setting-value" id="settings-temp-val">${settings.temperature.toFixed(1)}</span>
            <input type="range" id="settings-temp" min="0" max="2" step="0.1" value="${settings.temperature}">
          </div>
        </div>
        <div class="setting-row">
          <span class="setting-label">Max Tokens</span>
          <div class="flex items-center gap-sm">
            <button class="btn btn-sm" id="settings-tokens-minus">-</button>
            <span class="setting-value" id="settings-tokens-val">${settings.maxTokens}</span>
            <button class="btn btn-sm" id="settings-tokens-plus">+</button>
          </div>
        </div>
        <div class="setting-row setting-row--stacked">
          <label class="label">System Prompt</label>
          <textarea class="text-input w-full" id="settings-system-prompt" rows="3"
            placeholder="${escapeHtml(DEFAULT_SYSTEM_PROMPT)}">${escapeHtml(settings.systemPrompt)}</textarea>
        </div>
        <div class="setting-row">
          <span class="setting-label">Thinking Mode</span>
          <div class="toggle ${settings.thinkingModeEnabled ? 'on' : ''}" id="settings-thinking-toggle"></div>
        </div>
        <p class="setting-hint">
          Off by default. Turn on for thinking-capable models (e.g. Qwen3)
          when you want a visible reasoning phase before the answer.
        </p>
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
          <span class="setting-value">Web (Emscripten WASM)</span>
        </div>
        <div class="setting-row cursor-pointer" id="settings-docs-link">
          <span class="setting-label text-accent">Documentation</span>
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="var(--color-primary)" stroke-width="1.5" width="16" height="16"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/><polyline points="15 3 21 3 21 9"/><line x1="10" y1="14" x2="21" y2="3"/></svg>
        </div>
      </div>

    </div>
  `;

  // Temperature slider
  const tempSlider = container.querySelector('#settings-temp') as HTMLInputElement;
  const tempVal = container.querySelector('#settings-temp-val')!;
  tempSlider.addEventListener('input', () => {
    settings.temperature = parseFloat(tempSlider.value);
    tempVal.textContent = settings.temperature.toFixed(1);
    saveSettings();
  });

  // Max tokens stepper
  const tokensVal = container.querySelector('#settings-tokens-val')!;
  container.querySelector('#settings-tokens-minus')!.addEventListener('click', () => {
    settings.maxTokens = Math.max(500, settings.maxTokens - 500);
    tokensVal.textContent = String(settings.maxTokens);
    saveSettings();
  });
  container.querySelector('#settings-tokens-plus')!.addEventListener('click', () => {
    settings.maxTokens = Math.min(20000, settings.maxTokens + 500);
    tokensVal.textContent = String(settings.maxTokens);
    saveSettings();
  });

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

  // Docs link
  container.querySelector('#settings-docs-link')!.addEventListener('click', () => {
    window.open('https://docs.runanywhere.ai', '_blank');
  });
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
  const environment = RunAnywhere.environment;
  if (environment === null) {
    return {
      label: 'Unavailable',
      hint: 'Telemetry is controlled by the SDK environment and the SDK is not initialized.',
    };
  }
  const description = environmentDescription(environment);
  const enabled = environmentShouldSendTelemetry(environment);
  return {
    label: enabled ? 'Enabled' : 'Disabled',
    hint: `Read-only SDK state: ${description} environment ${enabled ? 'sends' : 'does not send'} telemetry.`,
  };
}

function updateTelemetryState(environment: string, enabled: boolean): void {
  const state = container.querySelector('#settings-analytics-state');
  const hint = container.querySelector('#settings-analytics-hint');
  if (state) state.textContent = enabled ? 'Enabled' : 'Disabled';
  if (hint) {
    hint.textContent = `Read-only SDK state: ${environment} environment ${enabled ? 'sends' : 'does not send'} telemetry.`;
  }
}

function setupToggle(id: string, onChange: (on: boolean) => void): void {
  const toggle = container.querySelector(`#${id}`)!;
  toggle.addEventListener('click', () => {
    toggle.classList.toggle('on');
    onChange(toggle.classList.contains('on'));
  });
}

function saveSettings(): void {
  try {
    // iOS parity stops at the Keychain: SettingsViewModel persists the API
    // key via KeychainService (SettingsViewModel.swift:65-72), and browsers
    // have no equivalent secret store. Clear-text localStorage is not an
    // acceptable substitute (CodeQL js/clear-text-storage-of-sensitive-data),
    // so the key is session-only — every other setting round-trips.
    const { apiKey: _apiKey, ...persistable } = settings;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(persistable));
  } catch { /* storage may not be available */ }
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
