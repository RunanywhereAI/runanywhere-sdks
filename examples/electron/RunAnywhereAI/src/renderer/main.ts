/**
 * Renderer entry.
 *
 * Boot order matters and mirrors the macOS app's cold start
 * (RunAnywhereAIApp.swift:88-107): show the shell immediately, bring the SDK up
 * behind it, and surface a real error rather than a blank window if that fails.
 */
import './design/tokens.css';
import './design/base.css';
import './design/components.css';

import { DEFAULT_SETTINGS, type AppSettings } from '@shared/settings';

import { showError, showToast } from './components/toast';
import { logger } from './services/logger';
import { loadAppSettings } from './services/settings';
import { installTheme } from './services/theme';
import { Shell, type ViewFactory } from './shell/app';
import { Route } from './shell/routes';
import { createAdvancedView } from './views/advanced';
import { createBenchmarksView } from './views/benchmarks';
import { createChatView } from './views/chat';
import { createDiarizationView } from './views/diarization';
import { createEmbeddingsView } from './views/embeddings';
import { createKnowledgeView } from './views/knowledge';
import { createModelsView } from './views/models';
import { createSegmentationView } from './views/segmentation';
import { createSpeakView } from './views/speak';
import { createStorageView } from './views/storage';
import { createStructuredView } from './views/structured';
import { createToolsView } from './views/tools';
import { createTranscribeView } from './views/transcribe';
import { createVadView } from './views/vad';
import { createVisionView } from './views/vision';
import { createVoiceView } from './views/voice';

const log = logger('renderer');

const views: Record<Route, ViewFactory> = {
  [Route.Chat]: createChatView,
  [Route.Models]: createModelsView,
  [Route.Advanced]: createAdvancedView,
  [Route.Voice]: createVoiceView,
  [Route.Transcribe]: createTranscribeView,
  [Route.Speak]: createSpeakView,
  [Route.Vad]: createVadView,
  [Route.Diarization]: createDiarizationView,
  [Route.Vision]: createVisionView,
  [Route.Segmentation]: createSegmentationView,
  [Route.Knowledge]: createKnowledgeView,
  [Route.Embeddings]: createEmbeddingsView,
  [Route.Structured]: createStructuredView,
  [Route.Tools]: createToolsView,
  [Route.Benchmarks]: createBenchmarksView,
  [Route.Storage]: createStorageView,
};

async function boot(): Promise<void> {
  const mount = document.getElementById('app');
  if (mount === null) throw new Error('#app is missing from index.html');

  await installTheme();

  const platform = await window.appStore.platformInfo();

  const shell = new Shell({
    mount,
    views,
    // The footer states the app's central promise, and it is literally true:
    // inference runs in the utility process on this machine.
    privacyNote: 'Inference runs on this device',
  });
  shell.start();

  // Settings are needed before the first generation, not before the first paint.
  let settings: AppSettings = DEFAULT_SETTINGS;
  try {
    settings = await loadAppSettings();
  } catch (error) {
    log.warn('settings load failed, using defaults', error);
  }

  try {
    const saved = await window.appStore.loadConversations();
    shell.setConversations(saved.conversations, saved.conversations[0]?.id ?? null);
  } catch (error) {
    log.warn('conversation load failed', error);
  }

  // Bring the SDK up behind the shell. The window is already usable; a failure
  // here disables generation but must not blank the app.
  try {
    await window.runanywhere.ready();
    const backend = await window.appStore.backendConfig();
    // E2E: pin secure/base dirs under the isolated userData so the visual gate
    // never discovers models from a developer machine (no downloads in CI).
    const e2e = new URLSearchParams(window.location.search).get('e2e') === '1';
    const secureDir = e2e ? `${platform.userDataDirectory}/secure` : undefined;
    const baseDir = e2e ? platform.modelsDirectory : undefined;
    await window.runanywhere.initialize(secureDir, baseDir, {
      apiKey: backend.apiKey,
      baseUrl: backend.baseUrl,
      environment: backend.environment,
    });
    log.info('sdk ready', await window.runanywhere.version(), 'on', platform.platform, platform.arch);
  } catch (error) {
    log.error('sdk initialize failed', error);
    showError(error, 'On-device AI could not start. Model actions are unavailable.');
  }

  void settings;
}

boot().catch((error: unknown) => {
  log.error('boot failed', error);
  showToast('RunAnywhere AI could not start.', 'danger');
});

// A rejection that reaches here is a bug, not a user-facing condition — log it
// with a scope so the main-side file log says where it came from.
window.addEventListener('unhandledrejection', (event) => {
  log.error('unhandled rejection', event.reason);
});
