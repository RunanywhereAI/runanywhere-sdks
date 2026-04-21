# Third-party engine plugin authoring guide

_Closes GAP 03 Phase 7. The companion to [`engine_plugin_authoring.md`](./engine_plugin_authoring.md) (GAP 02) — that doc explains the **vtable contract**; this doc explains how to **package and load** your plugin._

After GAP 02 + GAP 03, RunAnywhere supports two delivery models for engine plugins. Both share the same `rac_engine_vtable_t` contract and the same `rac_plugin_entry_<name>()` symbol. Pick based on platform constraints, not preference.

| Path                | When to use                                                                                       | Loaded via                                              |
|---------------------|---------------------------------------------------------------------------------------------------|---------------------------------------------------------|
| **Static link**     | iOS App Store, WebAssembly, statically-linked CLI tools, anyone who ships a single binary         | `RAC_STATIC_PLUGIN_REGISTER(<name>)` macro at file scope |
| **Dynamic load**    | Android, desktop Linux/macOS/Windows, server deployments that swap engine versions without redeploy | `rac_registry_load_plugin("/path/to/librunanywhere_<name>.so")` |

Both paths funnel through the same `rac_plugin_register()` call, so ABI version + capability_check + dedup behavior is identical.

## Anatomy of a third-party plugin

```
my-onnx-fork/
├── CMakeLists.txt
├── src/
│   ├── my_onnx_engine.cpp          # your inference code
│   └── rac_plugin_entry_myonnx.cpp # the entry symbol — ~30 LOC, see below
├── include/
│   └── my_onnx_ops.h               # internal — your llm/stt/etc. ops structs
└── CMakeLists.txt
```

A plugin only depends on **two** RunAnywhere headers (no `rac_commons` source dependency):

```
rac/plugin/rac_engine_vtable.h    # the vtable shape + RAC_PLUGIN_API_VERSION
rac/plugin/rac_plugin_entry.h     # entry-symbol macro + static-register macro
```

(They're installed into `include/` by the standard `rac_commons` install rule.)

## Step 1 — Write the entry TU

```cpp
// src/rac_plugin_entry_myonnx.cpp
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "my_onnx_ops.h"   // declares g_myonnx_llm_ops

extern "C" {

static const rac_engine_vtable_t g_myonnx_vtable = {
    /* metadata */ {
        .abi_version      = RAC_PLUGIN_API_VERSION,
        .name             = "myonnx",
        .display_name     = "MyOnnx (forked from upstream 1.19)",
        .engine_version   = "1.19.5-fork",
        .priority         = 75,
        .capability_flags = 0,
        .reserved_0 = 0, .reserved_1 = 0,
    },
    /* capability_check */ nullptr,        // or return RAC_ERROR_CAPABILITY_UNSUPPORTED on hosts you can't serve
    /* on_unload        */ nullptr,
    /* llm_ops          */ &g_myonnx_llm_ops,
    /* stt_ops          */ nullptr,
    /* tts_ops          */ nullptr,
    /* vad_ops          */ nullptr,
    /* embedding_ops    */ nullptr,
    /* rerank_ops       */ nullptr,
    /* vlm_ops          */ nullptr,
    /* diffusion_ops    */ nullptr,
    /* reserved_slot_0..9 */
    nullptr, nullptr, nullptr, nullptr, nullptr,
    nullptr, nullptr, nullptr, nullptr, nullptr,
};

__attribute__((visibility("default")))
RAC_PLUGIN_ENTRY_DEF(myonnx) {
    return &g_myonnx_vtable;
}

#if defined(RAC_PLUGIN_MODE_STATIC) && RAC_PLUGIN_MODE_STATIC
RAC_STATIC_PLUGIN_REGISTER(myonnx);
#endif

}  // extern "C"
```

Key invariants:

1. The symbol name MUST be `rac_plugin_entry_<name>` and `<name>` MUST equal `metadata.name`. The loader strips path/lib/extension and synthesizes the symbol name from this convention.
2. `metadata.abi_version` MUST equal `RAC_PLUGIN_API_VERSION` at the time you compile. If the host runs a different version, `rac_plugin_register` returns `RAC_ERROR_ABI_VERSION_MISMATCH`.
3. The vtable MUST live in `.rodata` (i.e. `static const`). The registry stores the pointer; it does not copy the bytes.
4. Default visibility on the entry symbol so `dlsym` can resolve it. Everything else can stay hidden.
5. `RAC_STATIC_PLUGIN_REGISTER` should be guarded by `RAC_PLUGIN_MODE_STATIC` so a SHARED-library build doesn't double-register itself the moment it's `dlopen`'d.

## Step 2 — Pick a CMake recipe

### Dynamic load (Android / Linux / macOS / Windows)

```cmake
# my-onnx-fork/CMakeLists.txt
cmake_minimum_required(VERSION 3.22)
project(my_onnx_fork CXX)

find_package(RunanywhereCommons REQUIRED)   # provides include/rac/plugin/...

add_library(runanywhere_myonnx SHARED
    src/my_onnx_engine.cpp
    src/rac_plugin_entry_myonnx.cpp
)
set_target_properties(runanywhere_myonnx PROPERTIES
    OUTPUT_NAME            runanywhere_myonnx
    C_VISIBILITY_PRESET    hidden
    CXX_VISIBILITY_PRESET  hidden
)
target_include_directories(runanywhere_myonnx PRIVATE include)
target_link_libraries(runanywhere_myonnx PRIVATE RunAnywhere::commons-headers)
install(TARGETS runanywhere_myonnx LIBRARY DESTINATION lib)
```

Output: `librunanywhere_myonnx.so` (Linux/Android) / `librunanywhere_myonnx.dylib` (macOS) / `runanywhere_myonnx.dll` (Windows).

The host loads at runtime:

```c
#include <rac/plugin/rac_plugin_loader.h>

if (rac_registry_load_plugin("/usr/local/lib/librunanywhere_myonnx.so") == RAC_SUCCESS) {
    // myonnx is now in the registry, served via rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT).
}
```

### Static link (iOS / WASM)

```cmake
# my-onnx-fork/CMakeLists.txt — when consumer of your plugin sets RAC_STATIC_PLUGINS=ON.
add_library(runanywhere_myonnx STATIC
    src/my_onnx_engine.cpp
    src/rac_plugin_entry_myonnx.cpp
)
target_include_directories(runanywhere_myonnx PRIVATE include)
target_link_libraries(runanywhere_myonnx PRIVATE RunAnywhere::commons-headers)
```

Consumer (the iOS app) MUST tell the linker not to drop the archive's TUs:

```cmake
# In the consuming app's CMakeLists.txt:
target_link_libraries(my_app PRIVATE
    "$<LINK_LIBRARY:WHOLE_ARCHIVE,runanywhere_myonnx>"   # CMake 3.24+
)
```

Or older syntax:

```cmake
# macOS / iOS:
target_link_options(my_app PRIVATE
    "LINKER:-force_load,$<TARGET_FILE:runanywhere_myonnx>"
)
# GNU / Android:
target_link_options(my_app PRIVATE
    "LINKER:--whole-archive" "LINKER:$<TARGET_FILE:runanywhere_myonnx>" "LINKER:--no-whole-archive"
)
```

Without one of these flags, Apple's linker drops the entire `runanywhere_myonnx.a` because the host has no direct symbol reference into it — the static-init registrar never runs.

`cmake/plugins.cmake` (introduced in GAP 07) wraps these into a single helper `rac_force_load(my_app PLUGINS runanywhere_myonnx)`.

## Step 3 — Verify

Compile your plugin against the public headers, then run a smoke test:

```c
// smoke.c — link against -lrac_commons
#include <stdio.h>
#include <rac/plugin/rac_plugin_loader.h>
#include <rac/plugin/rac_plugin_entry.h>
#include <rac/plugin/rac_primitive.h>

int main(int argc, char** argv) {
    if (argc != 2) { fprintf(stderr, "usage: %s libplugin.so\n", argv[0]); return 2; }
    if (rac_registry_load_plugin(argv[1]) != RAC_SUCCESS) return 1;
    if (rac_plugin_find(RAC_PRIMITIVE_GENERATE_TEXT) == NULL) return 1;
    rac_registry_unload_plugin("myonnx");
    return 0;
}
```

The in-tree fixture (`tests/fixtures/rac_test_plugin.cpp`) is a 60-line proof of the same pattern.

## Bumping `RAC_PLUGIN_API_VERSION`

The host bumps the version when the vtable layout or the per-domain ops structs change in a binary-incompatible way (see `docs/engine_plugin_authoring.md`). When you ship against an older host:

- Plugin v1, host v2: load fails with `RAC_ERROR_ABI_VERSION_MISMATCH` and a single log line `plugin '<name>' ABI mismatch: plugin=1 core=2`. Recompile against the new host headers.
- Plugin v2, host v1: same outcome with reversed numbers.

There is no shim or auto-upgrade. The handshake is intentionally strict to prevent memory corruption from layout drift.

## Path-traversal + untrusted plugin policy

`rac_registry_load_plugin` does not sandbox the loaded code — once `dlopen` succeeds, the plugin's static initializers run with full process privileges. Hosts that load untrusted plugins should:

1. Load only from a controlled directory (e.g. an app-bundled `Plugins/` folder) — never accept the path as user input.
2. Code-sign or content-hash the plugin file before loading.
3. Run `capability_check` to gate on hardware availability — but do NOT rely on it for security.

GAP 03 leaves the policy choice to frontends; the loader is intentionally a thin mechanism.
