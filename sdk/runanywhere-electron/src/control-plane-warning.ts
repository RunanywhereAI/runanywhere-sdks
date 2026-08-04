// control-plane-warning.ts — the `initialize({ apiKey, baseUrl })` runtime
// warning, split out of `RunAnywhere.ts` so it has no native (`bridge.ts`)
// dependency and can be unit-tested without a built native addon.
//
// This SDK has no control-plane client: `apiKey`/`baseUrl` are accepted for
// cross-SDK signature parity (the README already documents that they are
// ignored) but nothing authenticates, registers a device, or reports
// telemetry. Matches Python `_runtime.py`'s `initialize` warning.

/** Emit the control-plane warning when `apiKey`/`baseUrl` were passed. */
export function warnIfControlPlaneOptionsIgnored(options: {
  apiKey?: string;
  baseUrl?: string;
}): void {
  if (!options.apiKey && !options.baseUrl) return;
  console.warn(
    '[RunAnywhere] initialize: apiKey/baseUrl are accepted for signature parity ' +
      'but this SDK has no control-plane client — no auth, device registration, or ' +
      'telemetry is performed.'
  );
}
