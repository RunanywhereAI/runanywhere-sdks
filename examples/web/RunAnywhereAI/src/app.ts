/**
 * RunAnywhere AI - Web Demo App Shell
 *
 * 7-tab navigation:
 * Chat | Vision | Voice | Transcribe | Speak | Storage | Settings
 */

import { initChatTab } from './views/chat';
import { initVisionTab } from './views/vision';
import { initVoiceTab } from './views/voice';
import { initTranscribeTab } from './views/transcribe';
import { initSpeakTab } from './views/speak';
import { initStorageTab } from './views/storage';
import { initSettingsTab } from './views/settings';
import { ModelManager, ModelCategory } from './services/model-manager';

// ---------------------------------------------------------------------------
// Tab Lifecycle
// ---------------------------------------------------------------------------

/**
 * Lifecycle callbacks for tabs that hold resources (camera, mic, generation).
 * Called by the app shell when the user switches between tabs so each view
 * can release expensive resources and avoid background work.
 */
export interface TabLifecycle {
  onActivate?: () => void;
  onDeactivate?: () => void;
}

// ---------------------------------------------------------------------------
// Tab Definitions
// ---------------------------------------------------------------------------

interface TabDef {
  id: string;
  label: string;
  icon: string; // SVG path(s)
}

const TABS: TabDef[] = [
  {
    id: 'chat',
    label: 'Chat',
    icon: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  },
  {
    id: 'vision',
    label: 'Vision',
    icon: '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>',
  },
  {
    id: 'voice',
    label: 'Voice',
    icon: '<path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/>',
  },
  {
    id: 'transcribe',
    label: 'Transcribe',
    icon: '<path d="M2 13a2 2 0 0 0 2-2V7a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V4a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V7a2 2 0 0 1 2-2"/>',
  },
  {
    id: 'speak',
    label: 'Speak',
    icon: '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>',
  },
  {
    id: 'storage',
    label: 'Storage',
    icon: '<path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>',
  },
  {
    id: 'settings',
    label: 'Settings',
    icon: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
  },
];

// ---------------------------------------------------------------------------
// Build App Shell
// ---------------------------------------------------------------------------

let activeTab = 0;

/** Per-tab lifecycle callbacks (indexed same as TABS). */
const tabLifecycles: (TabLifecycle | undefined)[] = new Array(TABS.length).fill(undefined);

function buildSvgIcon(paths: string): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${paths}</svg>`;
}

export function buildAppShell(): void {
  const app = document.getElementById('app')!;

  // Tab content area
  const tabContent = document.createElement('div');
  tabContent.className = 'tab-content';

  for (const tab of TABS) {
    const panel = document.createElement('div');
    panel.className = 'tab-panel';
    panel.id = `tab-${tab.id}`;
    panel.dataset.tab = tab.id;
    tabContent.appendChild(panel);
  }

  // Tab bar
  const tabBar = document.createElement('div');
  tabBar.className = 'tab-bar';

  TABS.forEach((tab, index) => {
    const item = document.createElement('div');
    item.className = 'tab-item';
    item.dataset.index = String(index);
    item.innerHTML = `${buildSvgIcon(tab.icon)}<span>${tab.label}</span>`;
    item.addEventListener('click', () => switchTab(index));
    tabBar.appendChild(item);
  });

  app.appendChild(tabContent);
  app.appendChild(tabBar);

  // Initialize all tab views, capturing lifecycle callbacks
  tabLifecycles[0] = initChatTab(document.getElementById('tab-chat')!);
  tabLifecycles[1] = initVisionTab(document.getElementById('tab-vision')!);
  tabLifecycles[2] = initVoiceTab(document.getElementById('tab-voice')!);
  tabLifecycles[3] = initTranscribeTab(document.getElementById('tab-transcribe')!);
  tabLifecycles[4] = initSpeakTab(document.getElementById('tab-speak')!);
  tabLifecycles[5] = initStorageTab(document.getElementById('tab-storage')!);
  initSettingsTab(document.getElementById('tab-settings')!);

  // Activate default tab
  switchTab(0);
}

/**
 * Map tab IDs to the ModelCategory they primarily use.
 * When switching from a tab that uses one category to a tab that uses
 * a different category, we show an info banner.
 */
const TAB_MODEL_CATEGORY: Record<string, ModelCategory | null> = {
  chat: ModelCategory.Language,
  vision: ModelCategory.Multimodal,
  voice: ModelCategory.Language,        // voice agent uses LLM + STT + TTS
  transcribe: ModelCategory.SpeechRecognition,
  speak: ModelCategory.SpeechSynthesis,
  storage: null,
  settings: null,
};

function switchTab(index: number): void {
  const previousTab = activeTab;
  activeTab = index;

  // Notify the outgoing tab so it can release resources (camera, mic, etc.)
  if (previousTab !== index) {
    try {
      tabLifecycles[previousTab]?.onDeactivate?.();
    } catch (err) {
      console.warn(`[App] Tab ${TABS[previousTab].id} onDeactivate error:`, err);
    }
  }

  // Update panels
  document.querySelectorAll('.tab-panel').forEach((panel, i) => {
    panel.classList.toggle('active', i === index);
  });

  // Update tab items
  document.querySelectorAll('.tab-item').forEach((item, i) => {
    item.classList.toggle('active', i === index);
  });

  // Show model-switch banner if the new tab needs a different model category
  if (previousTab !== index) {
    showModelSwitchBanner(previousTab, index);
  }

  // Notify the incoming tab so it can resume if needed
  if (previousTab !== index) {
    try {
      tabLifecycles[index]?.onActivate?.();
    } catch (err) {
      console.warn(`[App] Tab ${TABS[index].id} onActivate error:`, err);
    }
  }
}

/**
 * Show an informational banner when switching to a tab that uses a different
 * model category, so the user understands that the previous model will be
 * released from memory.
 */
function showModelSwitchBanner(fromIndex: number, toIndex: number): void {
  // Remove any existing banner
  document.querySelector('.model-switch-banner')?.remove();

  const fromCategory = TAB_MODEL_CATEGORY[TABS[fromIndex].id];
  const toCategory = TAB_MODEL_CATEGORY[TABS[toIndex].id];

  // No banner needed if destination tab doesn't need a model
  if (!toCategory) return;
  // No banner needed if categories are the same
  if (fromCategory === toCategory) return;

  // Check if there's actually a model loaded that would be released
  const loadedModel = ModelManager.getLoadedModel();
  if (!loadedModel) return;

  const fromLabel = TABS[fromIndex].label;
  const toLabel = TABS[toIndex].label;

  const panel = document.getElementById(`tab-${TABS[toIndex].id}`);
  if (!panel) return;

  const banner = document.createElement('div');
  banner.className = 'model-switch-banner';
  banner.innerHTML = `
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16"><circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/></svg>
    <span>Switching from <strong>${fromLabel}</strong> to <strong>${toLabel}</strong> will release the current model from memory. You can reload it when you switch back.</span>
    <button class="banner-dismiss" aria-label="Dismiss">&times;</button>
  `;

  banner.querySelector('.banner-dismiss')!.addEventListener('click', () => banner.remove());

  // Auto-dismiss after 6 seconds
  setTimeout(() => banner.remove(), 6000);

  // Insert at the top of the tab panel (after toolbar if present)
  const toolbar = panel.querySelector('.toolbar');
  if (toolbar && toolbar.nextSibling) {
    panel.insertBefore(banner, toolbar.nextSibling);
  } else {
    panel.prepend(banner);
  }
}

// Export for external use
export function getActiveTab(): number {
  return activeTab;
}
