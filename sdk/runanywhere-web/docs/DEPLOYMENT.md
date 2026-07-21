# Deployment guide

RunAnywhere Web deployments serve browser-side Emscripten modules. The server
must preserve the SDK's security headers and static-asset semantics; a generic
SPA fallback is not sufficient.

## Required isolation headers

Send these headers on the HTML document and relevant static assets:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

For Safari/WebKit, use `Cross-Origin-Embedder-Policy: require-corp` instead of
`credentialless`, and make every cross-origin subresource CORS- or
CORP-compatible. Verify `crossOriginIsolated === true` in production.

## Static WASM assets

Serve `.wasm` files as `Content-Type: application/wasm`. Serve the canonical
Emscripten glue alongside each binary and exclude both extensions from SPA
rewrites. The currently published deployment payload is four pairs (eight
files):

```text
racommons.{js,wasm}
racommons-llamacpp.{js,wasm}
racommons-llamacpp-webgpu.{js,wasm}
racommons-onnx-sherpa.{js,wasm}
```

Diffusion is workspace-only and intentionally excluded from production
packaging until it ships a WASM artifact. A missing or HTML-rewritten canonical
asset can make pthread initialization appear to hang; fail the deployment
verification rather than silently continuing.

## Content Security Policy

Start with a policy that permits the application's own modules and worker
bootstrap:

```text
script-src 'self' 'wasm-unsafe-eval';
worker-src 'self' blob:;
```

Adapt `connect-src`, `img-src`, `media-src`, and model-host origins to the
application. Do not loosen `script-src` to permit arbitrary third-party code.
Test CSP in a real browser because a worker or WASM policy violation can
otherwise look like a runtime initialization failure.

## Environment variables and client configuration

Build tools embed `VITE_*` values in the JavaScript sent to every browser.
They are public configuration, not secret storage: never place API keys,
service credentials, or private endpoints in a `VITE_*` variable. Use a
properly authenticated server-side service for secrets when one is required.

## Memory, storage, and downloads

WASM32 modules have a 4 GiB address space, so the SDK exposes advisory
per-module soft budgets through `RunAnywhere.runtime.memoryBudget`; these are
not hard reservations and do not replace model metadata or browser memory
pressure handling. Keep practical model and concurrent-runtime usage below
these values, especially when CPU and WebGPU variants may coexist during a
switch.

The SDK already performs storage quota preflight. Before downloads, display
the model size, account for extraction and temporary download overhead, and
provide a recovery path when browser quota is insufficient. Avoid initiating
multiple large downloads concurrently on constrained devices.

## Production smoke check

After deployment, run the Playwright smoke suite against the deployed origin:

```bash
RA_E2E_BASE_URL=https://your-production-origin npm run test:browser
```

It records the last readiness step if the app remains pending, while allowing
production identity to finish asynchronously after local readiness is reached.
