/**
 * Preferences window — five tabs matching Swift `MacSettingsTabs`
 * (CombinedSettingsView.swift): General, Models, Tools, Advanced, About.
 *
 * Lives in its own BrowserWindow (560×460). Persistence goes through
 * `appStore` + the shared settings types; HF token goes to the SDK secure store.
 */
import './design/tokens.css';
import './design/base.css';
import './design/components.css';

import type { AppSettings } from '@shared/settings';
import type { ThemePreference } from '@shared/ipc-contract';

import { icon, type IconName } from './components/icons';
import { showError, showToast } from './components/toast';
import { formatSize } from './services/format';
import { logger } from './services/logger';
import { loadAppSettings, saveAppSettings } from './services/settings';
import { installTheme } from './services/theme';

const log = logger('settings');

const SettingsPane = {
  General: 'general',
  Models: 'models',
  Tools: 'tools',
  Advanced: 'advanced',
  About: 'about',
} as const;

type SettingsPane = (typeof SettingsPane)[keyof typeof SettingsPane];

const PANE_KEY = 'ra.settings.pane';

interface PaneMeta {
  readonly id: SettingsPane;
  readonly title: string;
  readonly icon: IconName;
}

const PANES: readonly PaneMeta[] = [
  { id: SettingsPane.General, title: 'General', icon: 'gearshape' },
  { id: SettingsPane.Models, title: 'Models', icon: 'square.stack.3d.up' },
  { id: SettingsPane.Tools, title: 'Tools', icon: 'wrench.and.screwdriver' },
  { id: SettingsPane.Advanced, title: 'Advanced', icon: 'slider.horizontal.3' },
  { id: SettingsPane.About, title: 'About', icon: 'info.circle' },
];

/** Built-in demo tools shown in the Tools pane (registration happens in Chat). */
const BUILT_IN_TOOLS: readonly { readonly name: string; readonly description: string }[] = [
  { name: 'get_weather', description: 'Current weather for a city (Open-Meteo).' },
  { name: 'get_current_time', description: "This device's local date and time." },
  { name: 'calculate', description: 'Evaluate a math expression safely.' },
];

function readStoredPane(): SettingsPane {
  const raw = localStorage.getItem(PANE_KEY);
  const match = PANES.find((pane) => pane.id === raw);
  return match?.id ?? SettingsPane.General;
}

function section(title: string, body: HTMLElement, footer?: string): HTMLElement {
  const el = document.createElement('section');
  el.className = 'ra-prefs-section';
  const heading = document.createElement('h2');
  heading.className = 'ra-prefs-section-title';
  heading.textContent = title;
  el.append(heading, body);
  if (footer !== undefined) {
    const note = document.createElement('p');
    note.className = 'ra-prefs-footer';
    note.textContent = footer;
    el.append(note);
  }
  return el;
}

function labeledRow(label: string, control: HTMLElement): HTMLElement {
  const row = document.createElement('div');
  row.className = 'ra-prefs-row';
  const name = document.createElement('div');
  name.className = 'ra-prefs-label';
  name.textContent = label;
  const slot = document.createElement('div');
  slot.className = 'ra-prefs-control';
  slot.append(control);
  row.append(name, slot);
  return row;
}

function switchControl(checked: boolean, onChange: (next: boolean) => void): HTMLElement {
  const label = document.createElement('label');
  label.className = 'ra-switch';
  const input = document.createElement('input');
  input.type = 'checkbox';
  input.checked = checked;
  input.addEventListener('change', () => onChange(input.checked));
  const track = document.createElement('span');
  track.className = 'ra-switch-track';
  label.append(input, track);
  return label;
}

class SettingsApp {
  private readonly root: HTMLElement;
  private readonly tablist: HTMLElement;
  private readonly panels: HTMLElement;
  private settings: AppSettings;
  private pane: SettingsPane = readStoredPane();
  private setThemePreference: ((preference: ThemePreference) => Promise<void>) | null = null;
  private hfDraft = '';
  private hfBusy = false;
  private hfMessage: { text: string; error: boolean } | null = null;
  private disposeSettingsWatch: (() => void) | null = null;

  constructor(root: HTMLElement, settings: AppSettings) {
    this.root = root;
    this.settings = settings;
    this.tablist = document.createElement('div');
    this.tablist.className = 'ra-prefs-tabs';
    this.tablist.setAttribute('role', 'tablist');
    this.tablist.setAttribute('aria-label', 'Settings');
    this.panels = document.createElement('div');
    this.panels.className = 'ra-prefs-panels';
    this.root.append(this.tablist, this.panels);
  }

  async start(theme: Awaited<ReturnType<typeof installTheme>>): Promise<void> {
    this.setThemePreference = (preference) => theme.setPreference(preference);
    this.disposeSettingsWatch = window.appStore.onSettingsChanged((next) => {
      this.settings = next;
      this.render();
    });
    this.render();

    // Utility host is already initialized by the main window; this page only
    // needs the MessagePort. Failures here disable Models/Advanced SDK actions.
    try {
      await window.runanywhere.ready();
    } catch (error) {
      log.warn('sdk ready failed in settings', error);
    }
  }

  dispose(): void {
    this.disposeSettingsWatch?.();
  }

  private async patch(partial: Partial<AppSettings>): Promise<void> {
    try {
      this.settings = await saveAppSettings(partial);
      this.render();
    } catch (error) {
      showError(error, 'Could not save settings');
    }
  }

  private selectPane(pane: SettingsPane): void {
    this.pane = pane;
    localStorage.setItem(PANE_KEY, pane);
    this.render();
  }

  private render(): void {
    this.tablist.replaceChildren();
    for (const pane of PANES) {
      const tab = document.createElement('button');
      tab.type = 'button';
      tab.className = 'ra-prefs-tab';
      tab.setAttribute('role', 'tab');
      tab.setAttribute('aria-selected', pane.id === this.pane ? 'true' : 'false');
      tab.title = pane.title;
      tab.innerHTML = icon(pane.icon, { size: 18 }) + `<span>${pane.title}</span>`;
      tab.addEventListener('click', () => this.selectPane(pane.id));
      this.tablist.append(tab);
    }

    this.panels.replaceChildren();
    const panel = document.createElement('div');
    panel.className = 'ra-prefs-panel';
    panel.setAttribute('role', 'tabpanel');
    switch (this.pane) {
      case SettingsPane.General:
        panel.append(this.buildGeneral());
        break;
      case SettingsPane.Models:
        panel.append(this.buildModels());
        void this.refreshModels(panel);
        break;
      case SettingsPane.Tools:
        panel.append(this.buildTools());
        break;
      case SettingsPane.Advanced:
        panel.append(this.buildAdvanced());
        break;
      case SettingsPane.About:
        panel.append(this.buildAbout());
        break;
      default: {
        const _exhaustive: never = this.pane;
        void _exhaustive;
      }
    }
    this.panels.append(panel);
  }

  private buildGeneral(): HTMLElement {
    const stack = document.createElement('div');
    stack.className = 'ra-stack';

    const responses = document.createElement('div');
    responses.className = 'ra-prefs-group';

    const tempWrap = document.createElement('div');
    tempWrap.className = 'ra-row';
    tempWrap.style.width = '100%';
    const slider = document.createElement('input');
    slider.type = 'range';
    slider.className = 'ra-slider';
    slider.min = '0';
    slider.max = '2';
    slider.step = '0.1';
    slider.value = String(this.settings.temperature);
    const tempVal = document.createElement('span');
    tempVal.className = 'ra-prefs-mono';
    tempVal.textContent = this.settings.temperature.toFixed(2);
    slider.addEventListener('input', () => {
      tempVal.textContent = Number(slider.value).toFixed(2);
    });
    slider.addEventListener('change', () => {
      void this.patch({ temperature: Number(slider.value) });
    });
    tempWrap.append(slider, tempVal);
    responses.append(labeledRow('Creativity', tempWrap));

    const maxWrap = document.createElement('div');
    maxWrap.className = 'ra-row';
    const maxLabel = document.createElement('span');
    maxLabel.className = 'ra-prefs-mono';
    maxLabel.textContent = `${this.settings.maxTokens} tokens`;
    const dec = document.createElement('button');
    dec.type = 'button';
    dec.className = 'ra-btn-secondary';
    dec.textContent = '−';
    const inc = document.createElement('button');
    inc.type = 'button';
    inc.className = 'ra-btn-secondary';
    inc.textContent = '+';
    const bump = (delta: number): void => {
      const next = Math.min(20000, Math.max(500, this.settings.maxTokens + delta));
      maxLabel.textContent = `${next} tokens`;
      void this.patch({ maxTokens: next });
    };
    dec.addEventListener('click', () => bump(-500));
    inc.addEventListener('click', () => bump(500));
    maxWrap.append(dec, maxLabel, inc);
    responses.append(labeledRow('Max Response Length', maxWrap));

    responses.append(
      labeledRow(
        'Thinking Mode',
        switchControl(this.settings.reasoning, (next) => {
          void this.patch({ reasoning: next });
        }),
      ),
    );

    stack.append(
      section(
        'Responses',
        responses,
        this.settings.reasoning
          ? 'Model will use its default thinking/reasoning mode.'
          : 'Thinking disabled. The model will skip its reasoning step when supported.',
      ),
    );

    const promptBody = document.createElement('div');
    promptBody.className = 'ra-prefs-group';
    const area = document.createElement('textarea');
    area.className = 'ra-textarea';
    area.rows = 5;
    area.value = this.settings.systemPrompt;
    area.placeholder = 'How should RunAnywhere respond?';
    let promptTimer: ReturnType<typeof setTimeout> | null = null;
    area.addEventListener('input', () => {
      if (promptTimer !== null) clearTimeout(promptTimer);
      promptTimer = setTimeout(() => {
        void this.patch({ systemPrompt: area.value });
      }, 400);
    });
    promptBody.append(area);
    stack.append(
      section('System Prompt', promptBody, 'Sent ahead of every conversation to set tone and behavior.'),
    );

    const privacy = document.createElement('div');
    privacy.className = 'ra-prefs-group';
    privacy.append(
      labeledRow(
        'Save Performance History',
        switchControl(this.settings.analyticsLogToLocal, (next) => {
          void this.patch({ analyticsLogToLocal: next });
        }),
      ),
    );
    stack.append(
      section('Privacy', privacy, 'Chats, downloads, and performance history stay on this device.'),
    );

    return stack;
  }

  private buildModels(): HTMLElement {
    const stack = document.createElement('div');
    stack.className = 'ra-stack';
    stack.dataset.modelsRoot = '1';

    const summary = document.createElement('div');
    summary.className = 'ra-prefs-group';
    summary.dataset.storageSummary = '1';
    summary.innerHTML = '<p class="ra-prefs-footer">Loading storage…</p>';

    const header = document.createElement('div');
    header.className = 'ra-row';
    header.style.justifyContent = 'space-between';
    const title = document.createElement('h2');
    title.className = 'ra-prefs-section-title';
    title.textContent = 'Storage';
    title.style.margin = '0';
    const refresh = document.createElement('button');
    refresh.type = 'button';
    refresh.className = 'ra-icon-button';
    refresh.title = 'Recount storage';
    refresh.setAttribute('aria-label', 'Refresh storage');
    refresh.innerHTML = icon('arrow.clockwise', { size: 14 });
    refresh.addEventListener('click', () => {
      const host = this.panels.querySelector('[data-models-root]');
      if (host instanceof HTMLElement) void this.refreshModels(host);
    });
    header.append(title, refresh);

    const storageSection = document.createElement('section');
    storageSection.className = 'ra-prefs-section';
    storageSection.append(header, summary);

    const list = document.createElement('div');
    list.className = 'ra-prefs-group';
    list.dataset.modelList = '1';

    const maintenance = document.createElement('div');
    maintenance.className = 'ra-prefs-group';
    const clearCache = document.createElement('button');
    clearCache.type = 'button';
    clearCache.className = 'ra-btn-secondary';
    clearCache.textContent = 'Clear Cache';
    clearCache.addEventListener('click', () => {
      void this.runMaintenance('clearCache');
    });
    const cleanTemp = document.createElement('button');
    cleanTemp.type = 'button';
    cleanTemp.className = 'ra-btn-secondary';
    cleanTemp.textContent = 'Clean Temporary Files';
    cleanTemp.addEventListener('click', () => {
      void this.runMaintenance('cleanTempFiles');
    });
    maintenance.append(clearCache, cleanTemp);

    stack.append(
      storageSection,
      section('Downloaded Models', list),
      section('Maintenance', maintenance, 'Neither removes a downloaded model. Delete those above.'),
    );
    return stack;
  }

  private async refreshModels(host: HTMLElement): Promise<void> {
    const summary = host.querySelector('[data-storage-summary]');
    const list = host.querySelector('[data-model-list]');
    if (!(summary instanceof HTMLElement) || !(list instanceof HTMLElement)) return;

    const mkValue = (text: string): HTMLElement => {
      const span = document.createElement('span');
      span.textContent = text;
      return span;
    };

    try {
      const info = await window.runanywhere.storage.info();
      const device = info.info?.device;
      const models = info.info?.models ?? [];
      const totalModels = info.info?.totalModelsBytes ?? 0;

      summary.replaceChildren();
      summary.append(labeledRow('Models on This Device', mkValue(formatSize(totalModels))));
      summary.append(
        labeledRow('Free Space', mkValue(device !== undefined ? formatSize(device.freeBytes) : '—')),
      );
      summary.append(labeledRow('Downloaded', mkValue(String(models.length))));

      list.replaceChildren();
      if (models.length === 0) {
        const empty = document.createElement('p');
        empty.className = 'ra-prefs-footer';
        empty.textContent = 'No models downloaded yet.';
        list.append(empty);
        return;
      }

      for (const model of models) {
        const row = document.createElement('div');
        row.className = 'ra-prefs-model-row';
        const text = document.createElement('div');
        const name = document.createElement('div');
        name.textContent = model.modelId;
        const meta = document.createElement('div');
        meta.className = 'ra-prefs-footer';
        meta.style.margin = '0';
        meta.textContent = formatSize(model.sizeOnDiskBytes);
        text.append(name, meta);
        const del = document.createElement('button');
        del.type = 'button';
        del.className = 'ra-icon-button';
        del.title = `Delete ${model.modelId}`;
        del.setAttribute('aria-label', `Delete ${model.modelId}`);
        del.innerHTML = icon('trash', { size: 14 });
        del.addEventListener('click', () => {
          void this.deleteModel(model.modelId, host);
        });
        row.append(text, del);
        list.append(row);
      }
    } catch (error) {
      summary.replaceChildren();
      const err = document.createElement('p');
      err.className = 'ra-prefs-footer';
      err.textContent = 'Storage is unavailable until on-device AI finishes starting.';
      summary.append(err);
      list.replaceChildren();
      log.warn('storage.info failed', error);
    }
  }

  private async deleteModel(modelId: string, host: HTMLElement): Promise<void> {
    const ok = window.confirm(`Delete ${modelId}?\n\nThe file is removed from this device. You can download it again later.`);
    if (!ok) return;
    try {
      await window.runanywhere.models.delete(modelId);
      showToast(`Deleted ${modelId}`, 'success');
      await this.refreshModels(host);
    } catch (error) {
      showError(error, 'Could not delete model');
    }
  }

  private async runMaintenance(action: 'clearCache' | 'cleanTempFiles'): Promise<void> {
    try {
      await window.runanywhere.storage[action]();
      showToast(action === 'clearCache' ? 'Cache cleared' : 'Temporary files cleaned', 'success');
      const host = this.panels.querySelector('[data-models-root]');
      if (host instanceof HTMLElement) await this.refreshModels(host);
    } catch (error) {
      showError(error, 'Maintenance failed');
    }
  }

  private buildTools(): HTMLElement {
    const stack = document.createElement('div');
    stack.className = 'ra-stack';

    const enable = document.createElement('div');
    enable.className = 'ra-prefs-group';
    enable.append(
      labeledRow(
        'Enable Tool Calling',
        switchControl(this.settings.tools, (next) => {
          void this.patch({ tools: next });
        }),
      ),
    );
    stack.append(
      section(
        'Tool Calling',
        enable,
        'When enabled, the chat model may call the built-in tools registered by this app.',
      ),
    );

    const list = document.createElement('div');
    list.className = 'ra-prefs-group';
    for (const tool of BUILT_IN_TOOLS) {
      const row = document.createElement('div');
      row.className = 'ra-prefs-model-row';
      const text = document.createElement('div');
      const name = document.createElement('div');
      name.textContent = tool.name;
      const desc = document.createElement('div');
      desc.className = 'ra-prefs-footer';
      desc.style.margin = '0';
      desc.textContent = tool.description;
      text.append(name, desc);
      row.append(text);
      list.append(row);
    }
    stack.append(section('Built-in Tools', list));
    return stack;
  }

  private buildAdvanced(): HTMLElement {
    const stack = document.createElement('div');
    stack.className = 'ra-stack';

    const themeGroup = document.createElement('div');
    themeGroup.className = 'ra-prefs-group';
    const select = document.createElement('select');
    select.className = 'ra-select';
    for (const option of [
      { value: 'system', label: 'System' },
      { value: 'light', label: 'Light' },
      { value: 'dark', label: 'Dark' },
    ] as const) {
      const el = document.createElement('option');
      el.value = option.value;
      el.textContent = option.label;
      if (this.settings.theme === option.value) el.selected = true;
      select.append(el);
    }
    select.addEventListener('change', () => {
      const preference = select.value as ThemePreference;
      void (async () => {
        await this.setThemePreference?.(preference);
        await this.patch({ theme: preference });
      })();
    });
    themeGroup.append(labeledRow('Appearance', select));
    stack.append(section('Appearance', themeGroup));

    const hf = document.createElement('div');
    hf.className = 'ra-prefs-group';

    const statusRow = document.createElement('div');
    statusRow.className = 'ra-prefs-row';
    const statusLabel = document.createElement('div');
    statusLabel.className = 'ra-prefs-label';
    statusLabel.textContent = 'Hugging Face Token';
    const status = document.createElement('span');
    status.className = this.settings.hfTokenConfigured ? 'ra-prefs-status-ok' : 'ra-prefs-status-warn';
    status.textContent = this.settings.hfTokenConfigured ? 'Configured' : 'Not Set';
    statusRow.append(statusLabel, status);
    hf.append(statusRow);

    const field = document.createElement('input');
    field.type = 'password';
    field.className = 'ra-input';
    field.placeholder = 'hf_...';
    field.value = this.hfDraft;
    field.disabled = this.hfBusy;
    field.autocomplete = 'off';
    field.addEventListener('input', () => {
      this.hfDraft = field.value;
    });
    hf.append(field);

    const hint = document.createElement('p');
    hint.className = 'ra-prefs-footer';
    hint.textContent = 'Used only for downloading models from private Hugging Face repos.';
    hf.append(hint);

    const actions = document.createElement('div');
    actions.className = 'ra-row';
    const save = document.createElement('button');
    save.type = 'button';
    save.className = 'ra-btn-primary';
    save.textContent = 'Save Token';
    save.disabled = this.hfBusy;
    save.addEventListener('click', () => {
      void this.saveHfToken();
    });
    const clear = document.createElement('button');
    clear.type = 'button';
    clear.className = 'ra-btn-secondary';
    clear.textContent = 'Clear';
    clear.disabled = this.hfBusy;
    clear.addEventListener('click', () => {
      void this.clearHfToken();
    });
    actions.append(save, clear);
    if (this.hfBusy) {
      const spin = document.createElement('span');
      spin.className = 'ra-spinner';
      actions.append(spin);
    }
    hf.append(actions);

    if (this.hfMessage !== null) {
      const msg = document.createElement('p');
      msg.className = this.hfMessage.error ? 'ra-prefs-status-warn' : 'ra-prefs-status-ok';
      msg.style.fontSize = 'var(--ra-size-caption)';
      msg.textContent = this.hfMessage.text;
      hf.append(msg);
    }

    stack.append(section('Private Downloads', hf));
    return stack;
  }

  private async saveHfToken(): Promise<void> {
    const token = this.hfDraft.trim();
    if (token.length === 0) {
      this.hfMessage = { text: 'Enter a token before saving.', error: true };
      this.render();
      return;
    }
    this.hfBusy = true;
    this.hfMessage = null;
    this.render();
    try {
      await window.runanywhere.setHfToken(token);
      this.hfDraft = '';
      this.hfMessage = { text: 'Token saved to the secure store.', error: false };
      await this.patch({ hfTokenConfigured: true });
    } catch (error) {
      this.hfMessage = {
        text: error instanceof Error ? error.message : 'Could not save token',
        error: true,
      };
      this.render();
    } finally {
      this.hfBusy = false;
      this.render();
    }
  }

  private async clearHfToken(): Promise<void> {
    this.hfBusy = true;
    this.hfMessage = null;
    this.render();
    try {
      await window.runanywhere.setHfToken(null);
      this.hfDraft = '';
      this.hfMessage = { text: 'Token cleared.', error: false };
      await this.patch({ hfTokenConfigured: false });
    } catch (error) {
      this.hfMessage = {
        text: error instanceof Error ? error.message : 'Could not clear token',
        error: true,
      };
      this.render();
    } finally {
      this.hfBusy = false;
      this.render();
    }
  }

  private buildAbout(): HTMLElement {
    const stack = document.createElement('div');
    stack.className = 'ra-stack';
    const body = document.createElement('div');
    body.className = 'ra-prefs-group';

    const version = document.createElement('div');
    version.className = 'ra-prefs-row';
    const name = document.createElement('div');
    name.className = 'ra-prefs-label';
    name.textContent = 'RunAnywhere';
    const ver = document.createElement('span');
    ver.className = 'ra-prefs-mono';
    ver.textContent = '…';
    void window.appStore.platformInfo().then((info) => {
      ver.textContent = `Version ${info.appVersion}`;
    });
    version.append(name, ver);
    body.append(version);

    const docs = document.createElement('button');
    docs.type = 'button';
    docs.className = 'ra-btn-secondary';
    docs.textContent = 'Documentation';
    docs.addEventListener('click', () => {
      void window.appStore.openExternal('https://docs.runanywhere.ai');
    });
    const x = document.createElement('button');
    x.type = 'button';
    x.className = 'ra-btn-secondary';
    x.textContent = 'Follow on X';
    x.addEventListener('click', () => {
      void window.appStore.openExternal('https://x.com/RunanywhereAI');
    });
    const links = document.createElement('div');
    links.className = 'ra-row';
    links.append(docs, x);
    body.append(links);

    stack.append(
      section('About', body, 'An example app for the RunAnywhere on-device AI SDK.'),
    );
    return stack;
  }
}

async function boot(): Promise<void> {
  const root = document.getElementById('settings-root');
  if (root === null) throw new Error('#settings-root is missing');

  const theme = await installTheme();
  const settings = await loadAppSettings();
  // Keep stored theme preference in sync with the Advanced pane.
  if (settings.theme !== 'system') {
    await theme.setPreference(settings.theme);
  }

  const app = new SettingsApp(root, settings);
  await app.start(theme);
}

boot().catch((error: unknown) => {
  log.error('settings boot failed', error);
  showToast('Settings could not open.', 'danger');
});

window.addEventListener('unhandledrejection', (event) => {
  log.error('unhandled rejection', event.reason);
});
