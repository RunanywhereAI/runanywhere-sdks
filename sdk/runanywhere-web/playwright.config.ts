/**
 * Playwright configuration for the Web SDK browser E2E harness.
 *
 * The default suite is smoke-level. Opt-in specs (`RA_RUN_LLM_E2E=1`,
 * `RA_RUN_VLM_E2E=1`) download real models and run browser inference.
 *
 * Running locally:
 *   cd sdk/runanywhere-web
 *   npm install
 *   npx playwright install chromium
 *   npm run test:browser
 */
import { defineConfig, devices } from '@playwright/test';

const webgpuArgs = [
  '--enable-unsafe-webgpu',
  '--enable-features=SharedArrayBuffer,WebAssemblyJSPI,WebAssemblyStackSwitching,WebGPUDeveloperFeatures',
  '--js-flags=--experimental-wasm-stack-switching',
];
const enableWebGPU = process.env.RA_RUN_VLM_E2E === '1' || process.env.RA_ENABLE_WEBGPU_BROWSER === '1';
const browserChannel = process.env.RA_BROWSER_CHANNEL
  ?? (process.env.RA_RUN_VLM_E2E === '1' ? 'chrome' : undefined);

export default defineConfig({
  testDir: './tests/browser',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: [['list']],

  use: {
    baseURL: 'http://localhost:5173',
    trace: 'retain-on-failure',
    channel: browserChannel,
    launchOptions: enableWebGPU ? { args: webgpuArgs } : undefined,
    // COOP/COEP headers are set by the example app's Vite config, so the
    // test pages inherit cross-origin isolation automatically.
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  webServer: {
    // Serve the example app on the default Vite port. `reuseExistingServer`
    // lets a local dev server keep running across test iterations.
    command: 'cd ../../examples/web/RunAnywhereAI && npm run dev -- --port 5173',
    port: 5173,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});
