/**
 * Playwright configuration for the Web SDK browser E2E harness.
 *
 * The default suite is smoke-level. Opt-in specs (`RA_RUN_LLM_E2E=1`,
 * `RA_RUN_VLM_E2E=1`, `RA_RUN_FULL_E2E=1`) download real models and run
 * browser inference. The full release journey also enables deterministic fake
 * microphone/camera devices and keeps one worker-scoped browser context so
 * model bytes in OPFS are reused across its serial tests.
 *
 * Running locally:
 *   cd sdk/runanywhere-web
 *   npm install
 *   # Full release defaults to the installed system Chrome for WebGPU.
 *   # Set RA_BROWSER_CHANNEL=chromium to use Playwright Chromium instead.
 *   npx playwright install chromium
 *   npm run test:browser
 *   RUNANYWHERE_API_KEY=... VITE_RUNANYWHERE_RELAY_ENABLED=true npm run test:browser:release
 *
 * Full-suite traces are opt-in (`RA_E2E_TRACE=1`) and are forcibly disabled
 * whenever the server credential is present. Playwright traces retain
 * request headers and DOM snapshots, so redacting the textual diagnostics is
 * not enough to make a credentialed trace safe.
 */
import { defineConfig, devices } from '@playwright/test';
import { resolve } from 'node:path';

const webgpuArgs = [
  '--enable-unsafe-webgpu',
  '--enable-features=SharedArrayBuffer,WebGPUDeveloperFeatures',
];
const runFullE2E = process.env.RA_RUN_FULL_E2E === '1';
const hasRuntimeCredentials = Boolean(
  process.env.RUNANYWHERE_API_KEY?.trim(),
);
const configuredRemoteURL = process.env.RA_E2E_BASE_URL;
const targetsRemoteOrigin = Boolean(configuredRemoteURL && !/^https?:\/\/(?:localhost|127\.0\.0\.1|\[::1\])(?::|\/|$)/i.test(configuredRemoteURL));
const hasSensitiveBrowserState = hasRuntimeCredentials || targetsRemoteOrigin;
const releaseTraceEnabled = process.env.RA_E2E_TRACE === '1' && !hasSensitiveBrowserState;
const fakeAudioPath = resolve(
  __dirname,
  '../../Playground/openclaw-hybrid-assistant/tests/audio/hey-jarvis-real.wav',
);
const fakeMediaArgs = [
  '--use-fake-ui-for-media-stream',
  '--use-fake-device-for-media-stream',
  `--use-file-for-fake-audio-capture=${fakeAudioPath}`,
  '--autoplay-policy=no-user-gesture-required',
];
const enableWebGPU = runFullE2E
  || process.env.RA_RUN_VLM_E2E === '1'
  || process.env.RA_ENABLE_WEBGPU_BROWSER === '1';
const browserChannel = process.env.RA_BROWSER_CHANNEL
  ?? (process.env.RA_RUN_VLM_E2E === '1' || runFullE2E ? 'chrome' : undefined);
const localReleaseURL = 'https://localtest.me:43173';
const baseURL = configuredRemoteURL
  ?? (runFullE2E ? localReleaseURL : 'http://127.0.0.1:5173');
const launchArgs = [
  ...(enableWebGPU ? webgpuArgs : []),
  ...(runFullE2E ? fakeMediaArgs : []),
];

export default defineConfig({
  testDir: './tests/browser',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  timeout: runFullE2E ? 45 * 60_000 : 30_000,
  expect: {
    timeout: runFullE2E ? 120_000 : 5_000,
  },
  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
  ],
  outputDir: 'test-results',

  use: {
    baseURL,
    trace: hasSensitiveBrowserState
      ? 'off'
      : runFullE2E
        ? (releaseTraceEnabled ? 'retain-on-failure' : 'off')
        : 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: hasSensitiveBrowserState ? 'off' : 'retain-on-failure',
    ignoreHTTPSErrors: runFullE2E && !configuredRemoteURL,
    channel: browserChannel,
    launchOptions: launchArgs.length > 0 ? { args: launchArgs } : undefined,
    permissions: runFullE2E
      ? ['microphone', 'camera', 'clipboard-read', 'clipboard-write']
      : [],
    // COOP/COEP headers are set by the example app's Vite config, so the
    // test pages inherit cross-origin isolation automatically.
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  webServer: configuredRemoteURL ? undefined : {
    // The full release gate builds and previews this clone on a dedicated
    // port, never reusing a potentially stale server from another checkout.
    command: runFullE2E
      ? 'cd ../../examples/web/RunAnywhereAI && ./scripts/preview-release-e2e.sh'
      : 'cd ../../examples/web/RunAnywhereAI && npm run dev -- --host 127.0.0.1 --port 5173 --strictPort',
    url: baseURL,
    reuseExistingServer: runFullE2E ? false : !process.env.CI,
    ignoreHTTPSErrors: runFullE2E && !configuredRemoteURL,
    gracefulShutdown: runFullE2E ? { signal: 'SIGTERM', timeout: 5_000 } : undefined,
    timeout: 120_000,
  },
});
