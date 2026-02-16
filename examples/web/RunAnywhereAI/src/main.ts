/**
 * RunAnywhere AI - Web Demo Application
 *
 * Full-featured demo matching the iOS example app.
 * 5-tab navigation: Chat, Vision, Voice, More, Settings.
 */

import './styles/design-system.css';
import './styles/commons.css';
import './styles/components.css';
import { buildAppShell } from './app';

// ---------------------------------------------------------------------------
// Cross-Origin Isolation (enables SharedArrayBuffer on Safari/iOS)
// ---------------------------------------------------------------------------

/**
 * Registers a service worker that injects COOP/COEP headers for browsers
 * that don't support `credentialless` COEP (Safari/WebKit).
 *
 * - On Chrome/Firefox: `crossOriginIsolated` is already true via server
 *   headers, so this is a no-op (SW registers silently for future use).
 * - On Safari/iOS: `crossOriginIsolated` is false, so the SW installs
 *   and the page reloads once to activate it.
 */
async function ensureCrossOriginIsolation(): Promise<void> {
  if (crossOriginIsolated) {
    console.log('[COI] Already cross-origin isolated');
    return;
  }

  if (!('serviceWorker' in navigator)) {
    console.warn('[COI] Service workers not supported — SharedArrayBuffer may be unavailable');
    return;
  }

  const registration = await navigator.serviceWorker.register('/coi-serviceworker.js');

  // If the SW is already active and controlling this page, COI should be
  // enabled. If we're still not isolated, something else is wrong.
  if (navigator.serviceWorker.controller) {
    console.warn('[COI] Service worker active but page is not cross-origin isolated');
    return;
  }

  // Wait for the newly installed SW to activate, then reload so its
  // fetch handler can inject the required headers.
  const sw = registration.installing || registration.waiting;
  if (sw) {
    await new Promise<void>((resolve) => {
      sw.addEventListener('statechange', () => {
        if (sw.state === 'activated') resolve();
      });
      // If it's already activated by the time we check
      if (sw.state === 'activated') resolve();
    });
    console.log('[COI] Service worker activated — reloading for cross-origin isolation');
    window.location.reload();
    // Halt execution — the reload will re-enter main()
    await new Promise(() => {});
  }
}

// ---------------------------------------------------------------------------
// Initialization Flow (matches iOS RunAnywhereAIApp.swift)
// ---------------------------------------------------------------------------

async function main(): Promise<void> {
  // Step 0: Ensure cross-origin isolation for SharedArrayBuffer (Safari/iOS)
  await ensureCrossOriginIsolation();

  // Show loading screen while SDK initializes
  showLoadingScreen();

  try {
    // Step 1: Initialize the SDK (load WASM, register backends)
    await initializeSDK();

    // Step 2: Hide loading screen and show the app
    hideLoadingScreen();
    buildAppShell();
  } catch (error) {
    // Show error view with retry
    const message = error instanceof Error ? error.message : String(error);
    showErrorView(message);
  }
}

// ---------------------------------------------------------------------------
// SDK Initialization
// ---------------------------------------------------------------------------

async function initializeSDK(): Promise<void> {
  // Try to import and initialize the SDK
  // This is optional -- the demo app works without WASM for UI development
  try {
    const { RunAnywhere, SDKEnvironment } = await import(
      '../../../../sdk/runanywhere-web/packages/core/src/index'
    );

    await RunAnywhere.initialize({
      environment: SDKEnvironment.Development,
      debug: true,
      // acceleration: 'auto' is the default — detects WebGPU automatically
    });

    console.log(
      '[RunAnywhere] SDK initialized, version:', RunAnywhere.version,
      '| acceleration:', RunAnywhere.accelerationMode,
    );

    // Show an acceleration badge so the user knows which backend is active
    showAccelerationBadge(RunAnywhere.accelerationMode);
  } catch (err) {
    // SDK not built or WASM not available -- continue in demo mode
    console.warn('[RunAnywhere] SDK not available, running in demo mode:', err);
  }
}

/**
 * Display a small floating badge indicating the active hardware acceleration.
 */
function showAccelerationBadge(mode: string): void {
  const badge = document.createElement('div');
  badge.id = 'accel-badge';
  const isGPU = mode === 'webgpu';
  badge.textContent = isGPU ? 'WebGPU' : 'CPU';
  badge.className = `accel-badge ${isGPU ? 'accel-badge--gpu' : 'accel-badge--cpu'}`;
  document.body.appendChild(badge);
}

// ---------------------------------------------------------------------------
// Loading Screen
// ---------------------------------------------------------------------------

function showLoadingScreen(): void {
  const screen = document.createElement('div');
  screen.className = 'loading-screen';
  screen.id = 'loading-screen';
  screen.innerHTML = `
    <div class="loading-logo">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
        <defs>
          <linearGradient id="logo-grad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:#FF5500"/>
            <stop offset="100%" style="stop-color:#E64500"/>
          </linearGradient>
        </defs>
        <circle cx="50" cy="50" r="45" fill="url(#logo-grad)" opacity="0.15"/>
        <circle cx="50" cy="50" r="30" fill="url(#logo-grad)" opacity="0.3"/>
        <text x="50" y="58" text-anchor="middle" fill="url(#logo-grad)" font-size="28" font-weight="bold" font-family="-apple-system, system-ui, sans-serif">RA</text>
      </svg>
    </div>
    <div class="loading-text">
      <h2>Setting Up Your AI</h2>
      <p>Preparing your private AI assistant...</p>
    </div>
    <div class="loading-bar">
      <div class="loading-bar-fill"></div>
    </div>
    <p class="text-sm text-tertiary">Initializing SDK...</p>
  `;
  document.body.appendChild(screen);
}

function hideLoadingScreen(): void {
  const screen = document.getElementById('loading-screen');
  if (screen) {
    screen.classList.add('hidden');
    setTimeout(() => screen.remove(), 500);
  }
}

// ---------------------------------------------------------------------------
// Error View
// ---------------------------------------------------------------------------

function showErrorView(message: string): void {
  hideLoadingScreen();

  const app = document.getElementById('app')!;
  app.innerHTML = `
    <div class="error-view">
      <div class="error-icon">&#9888;&#65039;</div>
      <h2>Initialization Failed</h2>
      <p class="text-secondary max-w-md">${message}</p>
      <button class="btn btn-primary btn-lg" id="retry-btn">Retry</button>
    </div>
  `;

  document.getElementById('retry-btn')!.addEventListener('click', () => {
    app.innerHTML = '';
    main();
  });
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

main();
