/**
 * RunAnywhere Web SDK Demo Application
 *
 * Demonstrates SDK initialization, capability detection,
 * and (when WASM is built) LLM text generation.
 */

// Note: In a real app, import from '@runanywhere/web'
// For development, we import from the local SDK source
import {
  RunAnywhere,
  SDKEnvironment,
  detectCapabilities,
  SDKLogger,
  LogLevel,
  EventBus,
} from '../../../../sdk/runanywhere-web/packages/core/src/index';

// ---------------------------------------------------------------------------
// UI Helpers
// ---------------------------------------------------------------------------

const logEl = document.getElementById('log')!;
const wasmStatusEl = document.getElementById('wasm-status')!;
const sdkDotEl = document.getElementById('sdk-status-dot')!;

function log(message: string, level: 'info' | 'success' | 'error' | 'warning' = 'info') {
  const time = new Date().toLocaleTimeString('en-US', { hour12: false });
  const line = document.createElement('div');
  line.className = level;
  line.textContent = `[${time}] ${message}`;
  logEl.appendChild(line);
  logEl.scrollTop = logEl.scrollHeight;
}

function updateSDKStatus(initialized: boolean) {
  sdkDotEl.className = `status-dot ${initialized ? 'green' : 'gray'}`;
  wasmStatusEl.textContent = initialized
    ? `WASM: Loaded`
    : `WASM: Not Loaded`;
}

// ---------------------------------------------------------------------------
// Event Listeners
// ---------------------------------------------------------------------------

// Subscribe to all SDK events
EventBus.shared.onAny((event) => {
  log(`Event: ${event.type} [${event.category}]`, 'info');
});

// ---------------------------------------------------------------------------
// Initialize Button
// ---------------------------------------------------------------------------

document.getElementById('btn-init')!.addEventListener('click', async () => {
  log('Initializing RunAnywhere Web SDK...', 'info');
  SDKLogger.level = LogLevel.Debug;

  try {
    await RunAnywhere.initialize({
      environment: SDKEnvironment.Development,
      debug: true,
    });
    log('SDK initialized successfully!', 'success');
    log(`Version: ${RunAnywhere.version}`, 'info');
    log(`Environment: ${RunAnywhere.environment}`, 'info');
    log(`WASM loaded: ${RunAnywhere.isWASMLoaded}`, 'info');
    updateSDKStatus(true);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log(`Initialization failed: ${message}`, 'error');
    log('This is expected if WASM is not yet built.', 'warning');
    log('Build WASM: cd sdk/runanywhere-web/wasm && ./scripts/build.sh', 'warning');
    updateSDKStatus(false);
  }
});

// ---------------------------------------------------------------------------
// Shutdown Button
// ---------------------------------------------------------------------------

document.getElementById('btn-shutdown')!.addEventListener('click', () => {
  RunAnywhere.shutdown();
  log('SDK shut down', 'info');
  updateSDKStatus(false);
});

// ---------------------------------------------------------------------------
// Detect Capabilities Button
// ---------------------------------------------------------------------------

document.getElementById('btn-detect')!.addEventListener('click', async () => {
  log('Detecting browser capabilities...', 'info');

  try {
    const caps = await detectCapabilities();

    const capsGrid = document.getElementById('caps-grid')!;
    const capsSection = document.getElementById('caps-section')!;
    capsSection.style.display = 'block';
    capsGrid.innerHTML = '';

    const items = [
      { label: 'WebGPU', value: caps.hasWebGPU },
      { label: 'SharedArrayBuffer', value: caps.hasSharedArrayBuffer },
      { label: 'Cross-Origin Isolated', value: caps.isCrossOriginIsolated },
      { label: 'WASM SIMD', value: caps.hasWASMSIMD },
      { label: 'OPFS', value: caps.hasOPFS },
      { label: 'Device Memory', value: `${caps.deviceMemoryGB} GB` },
      { label: 'CPU Cores', value: `${caps.hardwareConcurrency}` },
    ];

    for (const item of items) {
      const el = document.createElement('div');
      el.className = 'cap-item';
      const isBoolean = typeof item.value === 'boolean';
      const dotClass = isBoolean ? (item.value ? 'green' : 'red') : 'gray';
      const displayValue = isBoolean ? (item.value ? 'Yes' : 'No') : item.value;
      el.innerHTML = `<span class="status-dot ${dotClass}"></span>${item.label}: ${displayValue}`;
      capsGrid.appendChild(el);
    }

    log(`WebGPU: ${caps.hasWebGPU}, SAB: ${caps.hasSharedArrayBuffer}, SIMD: ${caps.hasWASMSIMD}, Memory: ${caps.deviceMemoryGB}GB`, 'success');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    log(`Capability detection failed: ${message}`, 'error');
  }
});

// ---------------------------------------------------------------------------
// Startup
// ---------------------------------------------------------------------------

log('RunAnywhere Web SDK Demo loaded', 'info');
log('Click "Initialize SDK" to begin (requires WASM build)', 'info');
log('Click "Detect Capabilities" to check browser support', 'info');
