# Phase 7 — Plugin loading: dlopen vs static dual path

> Goal: land the real plugin loader. Every backend from Phase 1 can
> now be loaded either as a shared library at runtime (macOS, Linux,
> Android) or linked statically into the final binary (iOS, WASM,
> any single-binary distribution). Same vtable either way.

---

## Prerequisites

- Phase 1 delivered one `<backend>_plugin.cpp` per backend, each
  exporting a `ra_plugin_entry_<name>` symbol that fills a
  `ra_plugin_info_t` descriptor.
- Phase 0 laid down `plugin_registry.h` + `plugin_loader.h` with
  function signatures and the `RA_STATIC_PLUGIN_REGISTER` /
  `RA_PLUGIN_ENTRY_DECL` macros.

---

## What this phase delivers

1. **Two loader implementations** behind one interface:
   - `PluginLoader::load_dynamic(const std::filesystem::path&)` uses
     `dlopen` on POSIX, `LoadLibrary` on Windows (not a target today
     but the seam stays clean).
   - `PluginLoader::load_static()` walks a link-time
     registry populated by `RA_STATIC_PLUGIN_REGISTER(name)`. No file
     I/O, no dynamic symbol lookup, no fork.

2. **Per-platform build matrix**:
   | Platform | Loader path | Plugins built as | Notes |
   | --- | --- | --- | --- |
   | macOS arm64/x64 | dlopen | `.dylib` per backend | MetalRT dylib chip-gated on arm64 |
   | Linux x64/arm64 | dlopen | `.so` per backend | — |
   | Android arm64 | dlopen | `.so` packaged into the APK's `jniLibs/` | android_linker_namespace-safe |
   | iOS arm64 | static | `.a` archives linked into the XCFramework | App Store policy disallows dlopen of arbitrary binaries |
   | WASM | static | archives linked into `racommons.wasm` | Emscripten's dlopen is unreliable for large archives |

3. **Plugin discovery rules**:
   - Dynamic: scan a directory list (env var `RA_PLUGIN_PATH` +
     compiled-in default `/usr/local/lib/runanywhere/plugins` on Linux;
     the app bundle's `Plugins/` on macOS; app lib dir on Android).
     Files matching `*.ra_plugin.{dylib,so}` are loaded.
   - Static: the registry holds a list of `ra_plugin_info_t
     (*)(void)` function pointers baked in at link time; the loader
     calls each one and registers the result.

4. **ABI version handshake**: every plugin returns
   `ra_plugin_info_t { abi_version, name, engines[] }`. The loader
   rejects plugins whose `abi_version` doesn't match
   `RA_PLUGIN_ABI_VERSION` compiled into commons. Mismatch → log +
   skip, don't crash.

5. **Sanboxing / dlopen isolation**: on Android the plugins live under
   the app's data dir and load with `RTLD_LOCAL | RTLD_NOW`. On macOS
   we use `RTLD_LOCAL` + `RTLD_FIRST` to avoid symbol bleed between
   plugins. We don't run plugins in a separate process — that's a
   future goal behind a proto3-over-pipe transport.

---

## Exact file-level deliverables

### Loader implementations

```text
sdk/runanywhere-commons/src/registry/
├── plugin_loader.cpp                       ← new: umbrella dispatch
├── plugin_loader_posix.cpp                 ← new: dlopen / dlsym
├── plugin_loader_windows.cpp               ← stub: LoadLibrary / GetProcAddress
├── plugin_loader_static.cpp                ← new: link-time list walker
└── plugin_registry.cpp                     ← from Phase 0, filled in here
```

`plugin_loader.cpp`:

```cpp
#include "rac/registry/plugin_loader.h"

namespace ra::registry {

std::unique_ptr<PluginLoader> PluginLoader::create_for_platform() {
#if defined(RA_STATIC_PLUGINS)
    return make_static_loader();
#elif defined(_WIN32)
    return make_windows_loader();
#elif defined(__unix__) || defined(__APPLE__)
    return make_posix_loader();
#else
    #error "No plugin loader for this platform"
#endif
}

} // namespace
```

`plugin_loader_posix.cpp` (sketch — full impl in the file):

```cpp
class PosixPluginLoader final : public PluginLoader {
public:
    ra_status_t load_from_directory(const std::filesystem::path& dir,
                                    PluginRegistry& reg) override {
        namespace fs = std::filesystem;
        std::error_code ec;
        if (!fs::is_directory(dir, ec)) return RA_STATUS_NOT_FOUND;

        for (auto& entry : fs::directory_iterator(dir, ec)) {
            auto& path = entry.path();
            auto ext = path.extension().string();
            if (ext != ".dylib" && ext != ".so") continue;
            if (path.stem().string().find(".ra_plugin") == std::string::npos) continue;

            void* handle = dlopen(path.c_str(), RTLD_LOCAL | RTLD_NOW);
            if (!handle) {
                RA_LOG_WARN("dlopen({}) failed: {}", path.string(), dlerror());
                continue;
            }

            using entry_fn = const ra_plugin_info_t* (*)(void);
            auto fn = reinterpret_cast<entry_fn>(dlsym(handle, "ra_plugin_entry"));
            if (!fn) {
                RA_LOG_WARN("{} missing ra_plugin_entry — unloading", path.string());
                dlclose(handle);
                continue;
            }

            const ra_plugin_info_t* info = fn();
            if (!info || info->abi_version != RA_PLUGIN_ABI_VERSION) {
                RA_LOG_WARN("abi mismatch: plugin={} got={} want={}",
                            path.string(), info ? info->abi_version : 0,
                            RA_PLUGIN_ABI_VERSION);
                dlclose(handle);
                continue;
            }

            reg.register_plugin(*info, /*dlopen_handle=*/handle);
        }
        return RA_STATUS_OK;
    }

    ra_status_t load_from_path(const std::filesystem::path& file,
                               PluginRegistry& reg) override { /* single-file variant */ }

    ~PosixPluginLoader() override {
        // Handles close when reg.unregister runs; loader just owns the
        // factory method, not the lifetimes.
    }
};
```

`plugin_loader_static.cpp`:

```cpp
// Populated at link time by RA_STATIC_PLUGIN_REGISTER(name) macro
// expansions in each <backend>_plugin.cpp.
namespace ra::registry::detail {
    std::vector<StaticPluginEntry>& static_plugin_list() {
        static std::vector<StaticPluginEntry> inst;
        return inst;
    }
}

class StaticPluginLoader final : public PluginLoader {
public:
    ra_status_t load_all(PluginRegistry& reg) override {
        for (const auto& e : detail::static_plugin_list()) {
            const ra_plugin_info_t* info = e.entry_fn();
            if (!info || info->abi_version != RA_PLUGIN_ABI_VERSION) {
                RA_LOG_WARN("static plugin {} abi mismatch", e.name);
                continue;
            }
            reg.register_plugin(*info, /*handle=*/nullptr);
        }
        return RA_STATUS_OK;
    }
};
```

### RA_STATIC_PLUGIN_REGISTER macro

`include/rac/registry/plugin_macros.h`:

```c
#define RA_STATIC_PLUGIN_REGISTER(NAME)                                \
    namespace ra::registry::detail {                                   \
        extern "C" const ra_plugin_info_t* ra_plugin_entry_##NAME(void); \
        static const StaticPluginAutoRegistrar                         \
            g_static_plugin_##NAME{#NAME, &ra_plugin_entry_##NAME};    \
    }

struct StaticPluginAutoRegistrar {
    StaticPluginAutoRegistrar(const char* name,
                              const ra_plugin_info_t* (*fn)(void)) {
        ra::registry::detail::static_plugin_list().push_back({name, fn});
    }
};
```

Each `<backend>_plugin.cpp` ends with:

```cpp
extern "C" const ra_plugin_info_t* ra_plugin_entry_llamacpp(void) {
    return &g_llamacpp_info;   // defined earlier in the file
}

#ifdef RA_STATIC_PLUGINS
RA_STATIC_PLUGIN_REGISTER(llamacpp)
#endif
```

### CMake additions

New file `cmake/PluginSystem.cmake` (grew in Phase 0, finalised here):

```cmake
option(RA_STATIC_PLUGINS "Link plugins statically into commons" OFF)

function(ra_add_plugin NAME)
    set(options )
    set(oneValueArgs )
    set(multiValueArgs SOURCES LIBRARIES INCLUDE_DIRS PLATFORMS)
    cmake_parse_arguments(P "" "" "${multiValueArgs}" ${ARGN})

    # Filter by platform if PLATFORMS specified.
    if(P_PLATFORMS AND NOT CMAKE_SYSTEM_NAME IN_LIST P_PLATFORMS)
        message(STATUS "Skipping plugin ${NAME} — platform mismatch")
        return()
    endif()

    if(RA_STATIC_PLUGINS)
        add_library(ra_plugin_${NAME} STATIC ${P_SOURCES})
        target_compile_definitions(ra_plugin_${NAME} PRIVATE RA_STATIC_PLUGINS)
        target_link_libraries(ra_plugin_${NAME} PUBLIC runanywhere_commons ${P_LIBRARIES})
        target_include_directories(ra_plugin_${NAME} PRIVATE ${P_INCLUDE_DIRS})
        target_link_libraries(runanywhere_commons_link_all INTERFACE
                              "$<LINK_LIBRARY:WHOLE_ARCHIVE,ra_plugin_${NAME}>")
    else()
        add_library(ra_plugin_${NAME} MODULE ${P_SOURCES})
        target_link_libraries(ra_plugin_${NAME} PRIVATE runanywhere_commons ${P_LIBRARIES})
        target_include_directories(ra_plugin_${NAME} PRIVATE ${P_INCLUDE_DIRS})
        set_target_properties(ra_plugin_${NAME} PROPERTIES
            PREFIX ""
            OUTPUT_NAME "${NAME}.ra_plugin"
            SUFFIX $<IF:$<PLATFORM_ID:Darwin>,.dylib,.so>)
    endif()
endfunction()
```

### Each backend's `CMakeLists.txt`

`sdk/runanywhere-commons/plugins/llamacpp/CMakeLists.txt`:

```cmake
ra_add_plugin(llamacpp
    SOURCES
        llamacpp_plugin.cpp
        llamacpp_llm_session.cpp
        llamacpp_embed_session.cpp
    LIBRARIES
        llama
    INCLUDE_DIRS
        ${llamacpp_SOURCE_DIR}/include)
```

Matching files under `plugins/{whispercpp,sherpa_onnx,metalrt,whisperkit_coreml,...}/CMakeLists.txt`.

Platform-gated plugins pass `PLATFORMS Darwin` / `PLATFORMS iOS` /
`PLATFORMS Emscripten` as appropriate.

### App/bundle packaging side

- **macOS / Linux**: build output is
  `build/plugins/{name}.ra_plugin.{dylib,so}`. The OpenAI server and
  CLI tool copy them into `{bundle or prefix}/lib/runanywhere/plugins/`.
- **Android**: each `.so` lands in the AAR's `jniLibs/<abi>/`. The
  Android SDK bridge extracts them at first launch if needed.
- **iOS / WASM**: static linked into the xcframework / `.wasm`. Zero
  runtime discovery cost; trade-off is binary size.

### Tests

```text
tests/integration/plugin_loader_dynamic_test.cpp
  — builds a throwaway `.ra_plugin.dylib` in the test fixtures dir
    with a test-only entry; asserts PosixPluginLoader picks it up and
    registers one named engine. Skipped on iOS/WASM.

tests/integration/plugin_loader_static_test.cpp
  — links a test plugin statically, asserts StaticPluginLoader calls
    its entry_fn exactly once and the registry sees it.

tests/integration/plugin_abi_mismatch_test.cpp
  — builds a plugin whose entry returns info with abi_version = 0;
    asserts the loader rejects it with a warning log and the registry
    doesn't contain it.

tests/integration/plugin_discovery_env_test.cpp
  — sets RA_PLUGIN_PATH to a temp dir containing two plugin .dylibs;
    asserts both load in filesystem order.

tests/integration/plugin_unload_test.cpp
  — loads, registers, unregisters, dlcloses. Asserts TSan/ASan clean.
```

---

## Implementation order

1. **Stub out the Windows loader** (returns `RA_STATUS_UNIMPLEMENTED`).
   Keeps the seam clean without shipping Windows support.

2. **Write `plugin_loader_posix.cpp`.** Exercise it with a unit test
   that loads a fake test plugin from a fixture directory.

3. **Write `plugin_loader_static.cpp` + `StaticPluginAutoRegistrar`.**
   Smoke test: compile commons with `RA_STATIC_PLUGINS=ON`, link one
   real plugin statically, confirm it registers at startup.

4. **Add `ra_add_plugin` CMake function.** Refactor every backend's
   CMakeLists under `plugins/` to use it.

5. **Add the discovery env var + default search paths.** Test by
   dropping a plugin `.dylib` into `/tmp/ra-plugins` and setting
   `RA_PLUGIN_PATH=/tmp/ra-plugins`.

6. **Add ABI version handshake.** Bump `RA_PLUGIN_ABI_VERSION` on a
   branch, rebuild plugins, confirm the loader rejects them.

7. **Android packaging.** Build the AAR with one backend. Extract on
   device; dlopen from `${applicationInfo.nativeLibraryDir}`.

8. **iOS static linking.** Build the xcframework with
   `RA_STATIC_PLUGINS=ON`, verify no dlopen symbols are referenced
   (`nm -u` on the framework binary).

9. **WASM.** Same static path. Emscripten `MAIN_MODULE=0`.

10. **Integration tests.** All five tests green under ASan + TSan
    except on iOS/WASM where dynamic loading isn't applicable.

---

## API changes

### New public symbols

```cpp
namespace ra::registry {

struct PluginRegistry { /* from Phase 0 */ };

struct PluginLoader {
    static std::unique_ptr<PluginLoader> create_for_platform();
    virtual ~PluginLoader() = default;
    virtual ra_status_t load_from_directory(const std::filesystem::path&,
                                            PluginRegistry&) = 0;
    virtual ra_status_t load_from_path(const std::filesystem::path&,
                                        PluginRegistry&) = 0;
    virtual ra_status_t load_all(PluginRegistry&) { return RA_STATUS_UNIMPLEMENTED; }
};

} // ra::registry
```

### Removed

- Anything related to the old hard-coded `rac_backend_*_register.cpp`
  calls (already removed in Phase 1; the loader is what replaces
  them). Grep-gated in Phase 1's acceptance criterion.

### Changed

- `RA_PLUGIN_ABI_VERSION` moves from a stubbed `0` in Phase 0 to a
  real versioned integer starting at `1` in this phase. Bumped on any
  breaking change to the `ra_engine_vtable_t` shape.

---

## Acceptance criteria

- [ ] `cmake -DRA_STATIC_PLUGINS=ON` builds a commons that links all 5
      backends statically; `nm` shows no `dlopen` / `dlsym` undefined
      imports.
- [ ] `cmake -DRA_STATIC_PLUGINS=OFF` builds `*.ra_plugin.dylib` /
      `.so` files for each backend; commons binary doesn't link any of
      them directly.
- [ ] `plugin_loader_dynamic_test` green (macOS + Linux).
- [ ] `plugin_loader_static_test` green on all platforms.
- [ ] `plugin_abi_mismatch_test` green — mismatched plugin refused.
- [ ] Under TSan, loading and unloading 10 plugins in parallel is race
      clean.
- [ ] Under ASan, dlclose of a plugin after the registry is torn down
      leaks nothing.
- [ ] An iOS xcframework builds with no dlopen references.
- [ ] A WASM build loads and runs a static-linked llama.cpp plugin.

## Validation checkpoint

See `testing_strategy.md`. Phase 7 changes how engines ship; the
runtime behaviour must remain identical.

- **Dynamic loading correctness on Linux + macOS + Android.**
  `plugin_loader_dynamic_test` green. The feature preservation
  matrix run at the end of Phase 8 will be the ultimate check;
  here we confirm loader mechanics.
- **Static loading correctness on iOS + WASM.** Both produce a
  working binary. iOS: `nm -u` confirms no `dlopen` symbols.
  WASM: example page loads, instantiates, runs a trivial LLM
  prompt.
- **Platform-matrix build.** macOS-14 (dynamic), Linux (dynamic),
  Android arm64 (dynamic), iOS arm64 (static), WASM (static) —
  all five green in CI.
- **ABI mismatch refusal.** `plugin_abi_mismatch_test` green —
  plugin with wrong version logged + skipped, registry does not
  contain it.
- **Unload cleanliness.** Load 10 plugins in parallel, unload all,
  `leaks` / ASan green.
- **Size budget.** Commons + all 5 statically-linked plugins
  together ≤ 35 MB for iOS; ≤ 20 MB for WASM default variant.
  Reported in CI as a fail-gate.
- **Feature preservation across the two paths.** Run the matrix
  once with dynamic loading (macOS) and once with static loading
  (iOS simulator) — both produce identical behaviour.

---

## What this phase does NOT do

- Out-of-process plugins. Plugins run in-process. A future
  "proto3-over-pipe" transport could isolate a risky backend but
  isn't part of this phase.
- Hot reload. Once loaded, a plugin sticks until shutdown. Reload
  during runtime is not supported; restart the host.
- Cryptographic signing of plugins. The loader trusts any file it
  finds at the configured path. Deploying signed plugins is a
  packaging concern, not a loader concern.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| Two plugins export the same engine name — collision at registry time | Medium | `PluginRegistry::register_plugin` returns `RA_STATUS_DUPLICATE`; first wins, second logs and is rejected. Keep plugin names distinct (llamacpp vs metalrt vs onnx) |
| `dlopen` symbol clash: two plugins link different versions of the same C symbol (e.g. two `protobuf`s) | High | `RTLD_LOCAL` prevents cross-plugin symbol bleed. Each plugin links protobuf-lite statically into itself. Document this constraint for backend authors |
| Android's linker namespace blocks loading a plugin that depends on a non-public NDK lib | Medium | Plugins only depend on libc / libc++ / pthreads (all namespace-open). If a backend pulls in, e.g., libvulkan, we ship it in `jniLibs/` alongside. Documented in plugin authoring guide |
| iOS App Store rejects binaries that reference `dlopen` with a user path | High | `RA_STATIC_PLUGINS` is forced on for iOS builds; CI asserts no dlopen symbol present. Impossible-to-misconfigure |
| WASM build balloons to 80 MB+ with five backends statically linked | High | Make backend linkage selectable at CMake configure time. Web build defaults to just `llamacpp` + `sherpa_onnx`, not MetalRT / whisperkit_coreml (Apple-only) |
| ABI version mismatch silently skips a plugin — the app looks like it loaded but runs with zero engines | Medium | Post-load, `PluginRegistry::engine_count()` is checked at first-use. If zero, the first feature call returns `RA_STATUS_UNAVAILABLE` with a clear message. Also logged at load time |
| A flaky plugin `dlopen` spews errors on every app start | Low | Rate-limit the log, cache the skip decision per-path until file mtime changes |
| Static linking with `WHOLE_ARCHIVE` isn't portable to older CMakes | Low | The `$<LINK_LIBRARY:WHOLE_ARCHIVE,...>` generator expression requires CMake ≥ 3.24. Document min CMake in the root CMakeLists and enforce |
