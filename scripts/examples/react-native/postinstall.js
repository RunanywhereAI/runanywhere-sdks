#!/usr/bin/env node
// Postinstall driver for the RunAnywhereAI example.
//
// Skips both the `patch-package` apply and the macOS `pod-install` step when
// running in CI typecheck/install contexts where:
//   - Yarn 3 may hoist `react-native` to the workspace root `node_modules`,
//     causing patch-package to fail with "Patch file found for package
//     react-native which is not present at node_modules/react-native".
//   - `pod-install` is irrelevant outside macOS Xcode builds.
//
// Behavior:
//   - Always skipped when CI=true (typecheck workflows don't build native).
//   - Locally: apply patches if node_modules/react-native exists at the
//     workspace, then run pod-install on Darwin only.

const { existsSync } = require('node:fs');
const { execSync } = require('node:child_process');
const path = require('node:path');

const cwd = process.cwd();

// Always sync the canonical commons solution YAMLs into the generated TS
// module — typecheck imports it, so CI (which skips patch-package + pod-install
// below) still needs this side effect.
try {
  execSync(`node "${path.join(__dirname, 'sync-solutions-yamls.js')}"`, {
    stdio: 'inherit',
    cwd,
  });
} catch (err) {
  process.stderr.write(
    `[postinstall] sync-solutions-yamls failed: ${err.message}\n`
  );
  process.exit(err.status ?? 1);
}

// Generate the gitignored debug keystore (standard, non-secret android /
// androiddebugkey credentials) if absent, so `gradlew assembleDebug` works on a
// fresh checkout / CI without a manual keytool step.
const debugKeystore = path.join(cwd, 'android', 'app', 'debug.keystore');
if (existsSync(path.join(cwd, 'android')) && !existsSync(debugKeystore)) {
  try {
    execSync(
      `keytool -genkeypair -v -keystore "${debugKeystore}" -storepass android ` +
        `-keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 ` +
        `-validity 10000 -dname "CN=Android Debug,O=Android,C=US"`,
      { stdio: 'inherit', cwd }
    );
  } catch (err) {
    process.stderr.write(`[postinstall] debug keystore generation warning: ${err.message}\n`);
  }
}

const isCI = process.env.CI === 'true' || process.env.CI === '1';
if (isCI) {
  process.stdout.write('[postinstall] CI=true detected; skipping patch-package + pod-install.\n');
  process.exit(0);
}

const localRN = path.join(cwd, 'node_modules', 'react-native', 'package.json');

if (existsSync(localRN)) {
  try {
    execSync('npx --no-install patch-package', { stdio: 'inherit', cwd });
  } catch (err) {
    process.stderr.write(`[postinstall] patch-package warning: ${err.message}\n`);
  }
} else {
  process.stdout.write('[postinstall] react-native not in local node_modules (hoisted); skipping patch-package.\n');
}

if (process.platform === 'darwin' && existsSync(path.join(cwd, 'ios', 'Podfile'))) {
  try {
    execSync(`bash "${path.join(__dirname, 'pod-install.sh')}"`, {
      stdio: 'inherit',
      cwd,
    });
  } catch (err) {
    process.stderr.write(`[postinstall] pod-install failed: ${err.message}\n`);
    process.exit(err.status ?? 1);
  }
}
