/**
 * Settings Tab - Generation params, tool calling, API config, logging, about
 * Matches iOS CombinedSettingsView.
 */

let container: HTMLElement;

// Settings state
const settings = {
  temperature: 0.7,
  maxTokens: 2048,
  apiKey: '',
  baseURL: '',
  analytics: true,
};

export function initSettingsTab(el: HTMLElement): void {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Settings</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="settings-form">

      <!-- Generation -->
      <div class="settings-section">
        <div class="settings-section-title">Generation</div>
        <div class="setting-row">
          <span class="setting-label">Temperature</span>
          <div style="display:flex;align-items:center;gap:var(--space-sm-md);">
            <span class="setting-value" id="settings-temp-val">${settings.temperature.toFixed(1)}</span>
            <input type="range" id="settings-temp" min="0" max="2" step="0.1" value="${settings.temperature}">
          </div>
        </div>
        <div class="setting-row">
          <span class="setting-label">Max Tokens</span>
          <div style="display:flex;align-items:center;gap:var(--space-sm-md);">
            <button class="btn btn-sm" id="settings-tokens-minus">-</button>
            <span class="setting-value" id="settings-tokens-val">${settings.maxTokens}</span>
            <button class="btn btn-sm" id="settings-tokens-plus">+</button>
          </div>
        </div>
      </div>

      <!-- API Configuration -->
      <div class="settings-section">
        <div class="settings-section-title">API Configuration</div>
        <div class="setting-row" style="flex-direction:column;align-items:stretch;gap:var(--space-sm-md);">
          <label style="font-size:var(--font-size-sm);color:var(--text-secondary);">API Key</label>
          <input type="password" class="text-input" id="settings-api-key" placeholder="Enter API key..." value="${settings.apiKey}" style="width:100%;">
        </div>
        <div class="setting-row" style="flex-direction:column;align-items:stretch;gap:var(--space-sm-md);">
          <label style="font-size:var(--font-size-sm);color:var(--text-secondary);">Base URL</label>
          <input type="url" class="text-input" id="settings-base-url" placeholder="https://api.runanywhere.ai" value="${settings.baseURL}" style="width:100%;">
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
          <span class="setting-value">0.1.0</span>
        </div>
        <div class="setting-row">
          <span class="setting-label">Platform</span>
          <span class="setting-value">Web (Emscripten WASM)</span>
        </div>
        <div class="setting-row" style="cursor:pointer;" id="settings-docs-link">
          <span class="setting-label" style="color:var(--color-primary);">Documentation</span>
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

  // Toggles
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

  // Load saved settings
  loadSettings();
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
    localStorage.setItem('runanywhere-settings', JSON.stringify(settings));
  } catch { /* storage may not be available */ }
}

function loadSettings(): void {
  try {
    const saved = localStorage.getItem('runanywhere-settings');
    if (saved) {
      Object.assign(settings, JSON.parse(saved));
      // Update UI
      (container.querySelector('#settings-temp') as HTMLInputElement).value = String(settings.temperature);
      container.querySelector('#settings-temp-val')!.textContent = settings.temperature.toFixed(1);
      container.querySelector('#settings-tokens-val')!.textContent = String(settings.maxTokens);
      container.querySelector('#settings-analytics-toggle')!.classList.toggle('on', settings.analytics);
      (container.querySelector('#settings-api-key') as HTMLInputElement).value = settings.apiKey;
      (container.querySelector('#settings-base-url') as HTMLInputElement).value = settings.baseURL;
    }
  } catch { /* storage may not be available */ }
}

export function getSettings(): typeof settings {
  return { ...settings };
}
