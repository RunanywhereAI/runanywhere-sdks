# Decision 02 — Plugin loading model

## Question

How do backend engines (llama.cpp, whisper.cpp, sherpa-onnx, MetalRT,
WhisperKit) get loaded into the host process?

## Choice

**Dual path**:

- **macOS, Linux, Android**: `dlopen(..., RTLD_NOW | RTLD_LOCAL)` from
  a configured plugin directory.
- **iOS, WASM**: static linked at build time using a link-time registry
  (`RA_STATIC_PLUGIN_REGISTER(name)`).

The same `ra_plugin_entry_<name>` function-pointer shape on both paths.

## Alternatives considered

| Option | Pros | Cons |
| --- | --- | --- |
| All static, always | simple build, simple deploy | no way to add a backend without rebuilding the host; iOS fine, Android apps bloat |
| All dynamic, always | small host binary | iOS App Store §3.3.2 forbids loading arbitrary code; Emscripten dlopen is flaky |
| Separate process per plugin, IPC | crash isolation | very high latency on the hot paths we care about (voice first-audio); not viable |
| Java / Kotlin-style classpath registration | familiar | not available in C++ without a runtime we'd have to write |

## Reasoning

iOS App Store explicitly forbids downloading or loading executable
code not in the bundle. That forces static linking on iOS.
Emscripten can do `dlopen` but it's been brittle for large archives;
static linking is the stable path on WASM too.

Everywhere else, dynamic loading buys us:

- Ship new backends without rebuilding the host.
- Optional backends that only load when present (e.g. a MetalRT-only
  build doesn't need llama.cpp on disk).
- Plugin author independence — a backend can be versioned and released
  without touching commons.

The same `ra_plugin_entry_<name>` ABI on both paths means the core
doesn't care which loader ran; code beyond the registry sees no
difference.

## Implications

- Every `<backend>_plugin.cpp` ends with both the extern "C" entry
  and a conditional `RA_STATIC_PLUGIN_REGISTER(name)` under
  `#ifdef RA_STATIC_PLUGINS`.
- `cmake/PluginSystem.cmake` provides `ra_add_plugin()` that chooses
  `MODULE` (dynamic) or `STATIC` (with `WHOLE_ARCHIVE` link) from the
  `RA_STATIC_PLUGINS` option.
- iOS and WASM CI builds force `-DRA_STATIC_PLUGINS=ON`.

Phase 1 introduces the plugin shape; Phase 7 lands the loader pair.
