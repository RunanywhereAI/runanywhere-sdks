/**
 * Settings Tab - Generation params, API config, logging, about.
 *
 * Mirrors iOS SettingsViewModel.swift (Features/Settings/SettingsViewModel.swift):
 * generation settings (temperature / maxTokens / systemPrompt / thinkingMode)
 * persist across sessions and are read by the Chat tab at send time; API
 * credentials are read by `main.ts` before `RunAnywhere.initialize()`.
 *
 * Persistence: localStorage is the Web counterpart of iOS UserDefaults +
 * Keychain (see AGENTS.md cross-SDK alignment table — "Secure storage: Web =
 * localStorage").
 */

import { RunAnywhere } from '@runanywhere/web';
import { escapeHtml } from '../services/escape-html';

let container: HTMLElement;

const STORAGE_KEY = 'runanywhere-settings';

// Defaults mirror iOS SettingsViewModel.swift:20-24
// (temperature 0.7, maxTokens 10000, default system prompt, thinking off).
const DEFAULT_SYSTEM_PROMPT = 'You are a helpful, concise AI assistant.';

interface AppSettings {
  temperature: number;
  maxTokens: number;
  systemPrompt: string;
  thinkingModeEnabled: boolean;
  apiKey: string;
  baseURL: string;
  analytics: boolean;
}

const settings: AppSettings = {
  temperature: 0.7,
  maxTokens: 10000,
  systemPrompt: DEFAULT_SYSTEM_PROMPT,
  thinkingModeEnabled: false,
  apiKey: '',
  baseURL: '',
  analytics: true,
};

let loaded = false;

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
 * Stored API key for app launch — iOS parity:
 * `SettingsViewModel.getStoredApiKey()` (SettingsViewModel.swift:65-72).
 */
export function getStoredApiKey(): string | null {
  loadSettings();
  const value = settings.apiKey.trim();
  return value.length > 0 ? value : null;
}

/**
 * Stored base URL for app launch, normalized with an https:// prefix when no
 * scheme is present — iOS parity: `SettingsViewModel.getStoredBaseURL()`
 * (SettingsViewModel.swift:76-88).
 */
export function getStoredBaseURL(): string | null {
  loadSettings();
  const trimmed = settings.baseURL.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  return `https://${trimmed}`;
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
          When off, thinking-capable models (e.g. Qwen3) are asked to answer
          directly without a reasoning phase.
        </p>
      </div>

      <!-- API Configuration (read at startup by main.ts; iOS parity:
           RunAnywhereAIApp.swift:113-138 runSDKInitialize) -->
      <div class="settings-section">
        <div class="settings-section-title">API Configuration</div>
        <div class="setting-row setting-row--stacked">
          <label class="label">API Key</label>
          <input type="password" class="text-input w-full" id="settings-api-key" placeholder="Enter API key..." value="${escapeHtml(settings.apiKey)}">
        </div>
        <div class="setting-row setting-row--stacked">
          <label class="label">Base URL</label>
          <input type="url" class="text-input w-full" id="settings-base-url" placeholder="https://api.runanywhere.ai" value="${escapeHtml(settings.baseURL)}">
          <p class="setting-hint">Reload the page after changing credentials so the SDK re-initializes with them.</p>
        </div>
      </div>

      <!-- Logging -->
      <div class="settings-section">
        <div class="settings-section-title">Logging</div>
        <div class="setting-row">
          <span class="setting-label">Analytics</span>
          <div class="toggle ${settings.analytics ? 'on' : ''}" id="settings-analytics-toggle"></div>
        </div>
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
  setupToggle('settings-analytics-toggle', (on) => {
    settings.analytics = on;
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

  // Docs link
  container.querySelector('#settings-docs-link')!.addEventListener('click', () => {
    window.open('https://docs.runanywhere.ai', '_blank');
  });
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
    const { apiKey, ...persistable } = settings;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(persistable));
  } catch { /* storage may not be available */ }
}

function loadSettings(): void {
  if (loaded) return;
  loaded = true;
  try {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      const parsed = JSON.parse(saved) as Partial<AppSettings>;
      if (typeof parsed.temperature === 'number') settings.temperature = parsed.temperature;
      if (typeof parsed.maxTokens === 'number' && parsed.maxTokens > 0) settings.maxTokens = parsed.maxTokens;
      if (typeof parsed.systemPrompt === 'string') settings.systemPrompt = parsed.systemPrompt;
      if (typeof parsed.thinkingModeEnabled === 'boolean') settings.thinkingModeEnabled = parsed.thinkingModeEnabled;
      if (typeof parsed.baseURL === 'string') settings.baseURL = parsed.baseURL;
      if (typeof parsed.analytics === 'boolean') settings.analytics = parsed.analytics;
    }
  } catch { /* storage may not be available */ }
}
