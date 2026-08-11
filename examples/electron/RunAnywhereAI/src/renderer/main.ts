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

import { emptyState } from './components/empty-state-mark';
import { showError, showToast } from './components/toast';
import { logger } from './services/logger';
import { installTheme } from './services/theme';
import { Shell, type ViewFactory } from './shell/app';
import { Route, ROUTE_META } from './shell/routes';

const log = logger('renderer');

/**
 * Placeholder for a screen that has not been built yet.
 *
 * Deliberately honest: it names the screen and says it is not ready, rather than
 * rendering an empty panel that looks like a bug. Each one is replaced by its
 * real view as the feature lands.
 */
function pendingView(route: Route): ViewFactory {
  return ({ root }) => {
    const meta = ROUTE_META[route];
    root.append(
      emptyState({
        glyph: meta.icon,
        title: meta.title,
        message: 'This screen is not wired up yet.',
      }),
    );
    return {};
  };
}

const views: Record<Route, ViewFactory> = {
  [Route.Chat]: pendingView(Route.Chat),
  [Route.Models]: pendingView(Route.Models),
  [Route.Advanced]: pendingView(Route.Advanced),
  [Route.Voice]: pendingView(Route.Voice),
  [Route.Transcribe]: pendingView(Route.Transcribe),
  [Route.Speak]: pendingView(Route.Speak),
  [Route.Vad]: pendingView(Route.Vad),
  [Route.Diarization]: pendingView(Route.Diarization),
  [Route.Vision]: pendingView(Route.Vision),
  [Route.Segmentation]: pendingView(Route.Segmentation),
  [Route.Knowledge]: pendingView(Route.Knowledge),
  [Route.Embeddings]: pendingView(Route.Embeddings),
  [Route.Structured]: pendingView(Route.Structured),
  [Route.Tools]: pendingView(Route.Tools),
  [Route.Benchmarks]: pendingView(Route.Benchmarks),
  [Route.Storage]: pendingView(Route.Storage),
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
    settings = window.appStore.migrateSettings(await window.appStore.loadSettings(), DEFAULT_SETTINGS);
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
    await window.runanywhere.initialize(undefined, undefined, {
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
