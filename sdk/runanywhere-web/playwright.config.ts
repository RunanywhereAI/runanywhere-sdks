/**
 * Playwright configuration for the Web SDK browser E2E harness.
 *
 * This is an MVP — one smoke test that loads the example app, verifies the
 * SDK initializes end-to-end, and asserts that public API surfaces exist.
 * It does NOT download real models or run actual inference (that lives in a
 * future harness once ONNX WASM is unblocked — see gaps/inconsistencies/web.md G-01).
 *
 * Running locally:
 *   cd sdk/runanywhere-web
 *   npm install
 *   npx playwright install chromium
 *   npm run test:browser
 */
import { defineConfig, devices } from '@playwright/test';

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
