/**
 * RunAnywhere AI - Web Demo App Shell
 *
 * 11-tab navigation (the iOS app's Chat/Vision/Voice tabs plus its More-hub
 * features — Transcribe/Speak/VAD/Docs/Storage/Solutions — and its
 * Settings-hub Benchmarks, flattened into one tab bar):
 * Chat | Vision | Voice | Transcribe | Speak | VAD | Docs | Storage |
 * Solutions | Bench | Settings
 */

import { initChatTab } from './views/chat';
import { initVisionTab } from './views/vision';
import { initVoiceTab } from './views/voice';
import { initTranscribeTab } from './views/transcribe';
import { initSpeakTab } from './views/speak';
import { initVadTab } from './views/vad';
import { initDocumentsTab } from './views/documents';
import { initStorageTab } from './views/storage';
import { initSolutionsTab } from './views/solutions';
import { initBenchmarksTab } from './views/benchmarks';
import { initSettingsTab } from './views/settings';

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
    id: 'vad',
    label: 'VAD',
    icon: '<path d="M2 12h3l3-7 4 14 3-10 2 3h5"/>',
  },
  {
    id: 'documents',
    label: 'Docs',
    icon: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/><polyline points="10 9 9 9 8 9"/>',
  },
  {
    id: 'storage',
    label: 'Storage',
    icon: '<path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>',
  },
  {
    id: 'solutions',
    label: 'Solutions',
    icon: '<polygon points="12 2 2 7 12 12 22 7 12 2"/><polyline points="2 17 12 22 22 17"/><polyline points="2 12 12 17 22 12"/>',
  },
  {
    id: 'benchmarks',
    label: 'Bench',
    icon: '<circle cx="12" cy="12" r="9"/><path d="M12 12l4-4"/>',
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

/** Per-tab lifecycle callbacks keyed by tab id. */
const tabLifecycles: Record<string, TabLifecycle | undefined> = {};

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

  // Initialize all tab views, capturing lifecycle callbacks keyed by tab id.
  const tabInitializers: Record<string, (el: HTMLElement) => TabLifecycle | undefined> = {
    chat: (el) => initChatTab(el),
    vision: (el) => initVisionTab(el),
    voice: (el) => initVoiceTab(el),
    transcribe: (el) => initTranscribeTab(el),
    speak: (el) => initSpeakTab(el),
    vad: (el) => initVadTab(el),
    documents: (el) => initDocumentsTab(el),
    storage: (el) => initStorageTab(el),
    solutions: (el) => initSolutionsTab(el),
    benchmarks: (el) => initBenchmarksTab(el),
    settings: (el) => { initSettingsTab(el); return undefined; },
  };
  for (const tab of TABS) {
    tabLifecycles[tab.id] = tabInitializers[tab.id]?.(document.getElementById(`tab-${tab.id}`)!);
  }

  // Activate default tab
  switchTab(0);
}

function switchTab(index: number): void {
  const previousTab = activeTab;
  activeTab = index;

  // Notify the outgoing tab so it can release resources (camera, mic, etc.)
  if (previousTab !== index) {
    const previousId = TABS[previousTab].id;
    try {
      tabLifecycles[previousId]?.onDeactivate?.();
    } catch (err) {
      console.warn(`[App] Tab ${previousId} onDeactivate error:`, err);
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

  // Notify the incoming tab so it can resume if needed
  if (previousTab !== index) {
    const incomingId = TABS[index].id;
    try {
      tabLifecycles[incomingId]?.onActivate?.();
    } catch (err) {
      console.warn(`[App] Tab ${incomingId} onActivate error:`, err);
    }
  }
}

// Export for external use
export function getActiveTab(): number {
  return activeTab;
}
