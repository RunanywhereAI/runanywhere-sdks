# Web SDK — migration plan

> `sdk/runanywhere-web/` bundles a WASM module produced by compiling
> `sdk/runanywhere-commons/` through Emscripten. The public TS API
> wraps it via `Module.cwrap`/`ccall`.
>
> **Goal of this migration:** the WASM module is rebuilt from
> `frontends/web/wasm/` (which already links against `core/` +
> `engines/` + `solutions/`). TS bindings regenerate.

## Step 1 — Current interop layer

- `sdk/runanywhere-web/packages/core/wasm/racommons.wasm` — legacy
  commons compiled to WASM.
- `sdk/runanywhere-web/packages/core/wasm/racommons.js` — Emscripten JS
  glue.
- TS wrappers in `src/` call through `Module.cwrap('rac_*')`.

## Step 2 — Symbol inventory

Every `rac_*` entry point called from JS via cwrap. Maps 1:1 onto
`ra_*` entry points in the new core.

## Step 3 — ABI mapping

No compile-time shim needed — TS changes the string passed to `cwrap`
from `'rac_llm_generate'` to `'ra_llm_generate'`, etc. A centralised
`BindingTable` module in TS holds these strings so the rename is a
single file change.

## Step 4 — Native artifact

```bash
cd frontends/web/wasm
cmake --preset wasm-release -S ${ROOT}
cmake --build --preset wasm-release
```

Output: `build/wasm-release/frontends/web/wasm/runanywhere_wasm.{js,wasm}`.

Copy these into `sdk/runanywhere-web/packages/core/wasm/` replacing
the legacy `racommons.{js,wasm}` (keep filename stable so consumer
code doesn't break).

## Step 5 — Wire the interop layer

Update the `BindingTable` TS module to point at the new symbol names.
Verify by running the TS test suite.

## Step 6 — Run the SDK's tests

```
cd sdk/runanywhere-web
npm install
npm run build
npm test
```

## Step 7 — Run the example app

```
cd examples/web/RunAnywhereAI
npm run dev
```

Open http://localhost:5173 in a browser — chat + voice agent should
function exactly as before (with the new WASM underneath).

## Known risks

- **WASM size budget** — the new core + both engines statically linked
  is ~12 MB vs. the legacy ~9 MB. Tree-shaking via `--gc-sections` may
  close the gap. Smaller engines can be omitted at link time.
- **SharedArrayBuffer headers** (`Cross-Origin-Opener-Policy`,
  `Cross-Origin-Embedder-Policy`) needed for pthread-backed features —
  same as legacy.
