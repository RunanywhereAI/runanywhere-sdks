import { defineConfig } from '@playwright/test';

/**
 * Electron end-to-end tests.
 *
 * Playwright drives Electron over CDP, so it renders and screenshots the
 * BrowserWindow **without needing a visible display** — which is what makes this
 * usable on a locked or sleeping machine, and in CI.
 *
 * These are the visual-parity gate: each screen is captured here and compared
 * against the macOS SwiftUI app's reference shots in
 * `thoughts/shared/research/electron-parity/macos-reference-screenshots/`.
 */
export default defineConfig({
  testDir: './test/e2e',
  // The app forks a utility process and loads a 43 MB native addon; a cold first
  // launch is genuinely slow.
  timeout: 120_000,
  expect: { timeout: 15_000 },
  // One Electron app at a time: the main process takes a single-instance lock, so
  // a second worker would quit immediately instead of running its test.
  workers: 1,
  fullyParallel: false,
  reporter: [['list']],
  use: {
    trace: 'retain-on-failure',
  },
});
