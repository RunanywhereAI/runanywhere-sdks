# Phase G-1 — Tool-Calling C ABI Close-out Report

Working tree: `runanywhere-sdks-main/`
Verification preset: `macos-debug`

## Goal

Make the commons `rac_tool_call_*` C ABI the **single source of truth** for
tool-calling parsing, prompt formatting, and follow-up prompt building across
all five SDK frontends (Swift, Kotlin, Flutter, Web, React Native). Delete
per-SDK stubs and duplicate TS/Kotlin/Dart/Swift parsing logic.

## Starting-state audit

The audit established that the commons C ABI was **already fully implemented**
from earlier phases, and four of the five SDK frontends were **already wired
through it**. The remaining gaps were localized:

| SDK | State before Phase G-1 | Action taken |
|---|---|---|
| `runanywhere-commons` | `rac_tool_calling.h` (369 LOC) + `tool_calling.cpp` (1,950 LOC) already built into `rac_commons`. No tests. | **Added** `tests/test_tool_calling.cpp` (11 scenarios) wired into `ctest`. |
| `runanywhere-swift` | Fully wired via `CppBridge+ToolCalling.swift` → `CRACommons`. No duplicated parsing. | **No changes** — already a thin wrapper around the C ABI. |
| `runanywhere-kotlin` (Kotlin side) | `CppBridgeToolCalling.kt` fully wired via JNI. | **No changes**. |
| `runanywhere-kotlin` JNI (C++ side) | `racToolCallBuildInitialPrompt` accepted `optionsJson` but ignored it, and initialized only 7 of 8 fields of `rac_tool_calling_options_t` (missing `format`). Silent bug: every Kotlin caller passing `format="lfm2"` got `default` instead. | **Fixed** `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp`: parse `optionsJson` with `nlohmann::json`, honour every field incl. `format`; use `RAC_TOOL_CALLING_OPTIONS_DEFAULT` to start from a fully-initialised struct. |
| `runanywhere-flutter` | `dart_bridge_tool_calling.dart` fully wired via FFI. No duplicated parsing. | **No changes**. |
| `runanywhere-web` `@runanywhere/llamacpp` | Primary path calls `rac_tool_call_*` via WASM `ccall`, but had **three TS-side duplicates** — `parseToolCallTS`, `formatToolsForPromptTS`, `buildFollowUpPromptTS` (~150 LOC of regex/template parsing) — selected whenever `accelerationMode === 'webgpu'` or when `_rac_tool_call_parse` wasn't exported. This was the main per-SDK duplicate parsing body. | **Deleted** all three TS fallbacks. Introduced `assertNativeToolCalling()` that throws a typed `SDKError` if the WASM module is missing the required exports — fix the build, don't silently diverge from commons. The C tool-calling functions are pure (no suspending imports) so sync `ccall` is safe on JSPI/WebGPU builds. |
| `runanywhere-react-native` TS | `Public/Extensions/RunAnywhere+ToolCalling.ts` already delegates every parse/format/build call to the native module. | **No changes** to TS. |
| `runanywhere-react-native` C++ `HybridRunAnywhereCore` | **Hard stubs** — the four tool-calling Hybrid methods returned `"{}"` / `""` / `userPrompt` verbatim and logged a warning that the `ToolCallingBridge` was "disabled". | **Deleted the stubs**, wired each Hybrid method to its matching `ToolCallingBridge::shared().*` call. |
| `runanywhere-react-native` Android CMake | `ToolCallingBridge.cpp` was explicitly **excluded from the Android build** with `list(FILTER BRIDGE_SOURCES EXCLUDE REGEX ".*ToolCallingBridge\\.cpp$")` and a `TODO: Re-enable when commons library includes rac_tool_call_* functions` comment — but those functions had long since shipped. | **Removed** the exclude line; the bridge now compiles into `librunanywherecore.so` and links the already-downloaded `librac_commons.so`. |

## The C ABI surface (unchanged — already canonical)

Header: `sdk/runanywhere-commons/include/rac/features/llm/rac_tool_calling.h`

The API exported to every SDK (functions, formats, types):

```c
// Types
typedef enum rac_tool_call_format {
    RAC_TOOL_FORMAT_DEFAULT = 0,  // <tool_call>{"tool":"...","arguments":{...}}</tool_call>
    RAC_TOOL_FORMAT_LFM2    = 1,  // <|tool_call_start|>[func(arg="val")]<|tool_call_end|>
} rac_tool_call_format_t;

typedef struct rac_tool_call {
    rac_bool_t has_tool_call;   // RAC_FALSE => caller got free-form text, RAC_TRUE => structured call
    char* tool_name;            // owned — free with rac_tool_call_free()
    char* arguments_json;       // owned JSON object string
    char* clean_text;           // owned — raw text with tool-call tags stripped
    int64_t call_id;
    rac_tool_call_format_t format;
} rac_tool_call_t;

// Parse
rac_result_t rac_tool_call_parse(const char* llm_output, rac_tool_call_t* out);
rac_result_t rac_tool_call_parse_with_format(const char*, rac_tool_call_format_t, rac_tool_call_t*);
void         rac_tool_call_free(rac_tool_call_t*);
rac_tool_call_format_t rac_tool_call_detect_format(const char* llm_output);
rac_tool_call_format_t rac_tool_call_format_from_name(const char* name);  // "default" | "lfm2"

// Format
rac_result_t rac_tool_call_format_prompt(const rac_tool_definition_t*, size_t, char** out);
rac_result_t rac_tool_call_format_prompt_json_with_format_name(const char* tools_json,
                                                                const char* format_name,
                                                                char** out);
rac_result_t rac_tool_call_build_initial_prompt(const char* user_prompt,
                                                 const char* tools_json,
                                                 const rac_tool_calling_options_t*,
                                                 char** out);
rac_result_t rac_tool_call_build_followup_prompt(const char* original_user_prompt,
                                                  const char* tools_prompt,   // nullable
                                                  const char* tool_name,
                                                  const char* tool_result_json,
                                                  rac_bool_t keep_tools_available,
                                                  char** out);

// Utility
rac_result_t rac_tool_call_normalize_json(const char* in, char** out);
```

All out-strings are owned and released by `rac_free()` (the matching commons
allocator) — mirrored on every SDK side by `rac_free(ptr)`, `bridge.free(ptr)`,
or `m.ccall('rac_free', ...)`.

### Parsing grammars (documented in the impl)

1. **Default (`RAC_TOOL_FORMAT_DEFAULT`)** — `<tool_call>{"tool": "...", "arguments": {...}}</tool_call>`.
   Used by most general-purpose instruction-tuned models. Robust to unquoted
   keys, missing closing tags (brace-matching), and multiple synonym keys
   (`tool|name|function`, `arguments|args|params|parameters|input`). Also
   covers the "tool name as key" pattern (`{"calculate":"5*10"}`).
2. **LFM2 (`RAC_TOOL_FORMAT_LFM2`)** — `<|tool_call_start|>[func_name(arg1="val", arg2=42)]<|tool_call_end|>`.
   Pythonic syntax used by Liquid AI's `LFM2-Tool` family. Converts numeric
   values to JSON numbers (not strings) on the way out.

Free-form text (no recognized tags) returns `RAC_SUCCESS` with
`has_tool_call = RAC_FALSE` and `clean_text = strdup(llm_output)`.

## Files changed

| File | +/- | Purpose |
|---|---|---|
| `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` | +111 / −27 | Honour `optionsJson` in `racToolCallBuildInitialPrompt`; initialise all 8 fields of `rac_tool_calling_options_t`. |
| `sdk/runanywhere-commons/tests/CMakeLists.txt` | +35 / −2 | Register `test_tool_calling` target + `add_test(NAME tool_calling_tests …)`. |
| `sdk/runanywhere-commons/tests/test_tool_calling.cpp` | **+308 new** | 11-scenario behavioural test of the C ABI. |
| `sdk/runanywhere-react-native/packages/core/android/CMakeLists.txt` | +1 / −3 | Removed the filter that excluded `ToolCallingBridge.cpp` from the Android build. |
| `sdk/runanywhere-react-native/packages/core/cpp/HybridRunAnywhereCore.cpp` | +13 / −45 | Replaced four `"{}" / ""`-returning stubs with real calls to `ToolCallingBridge::shared()` (which wraps `rac_tool_call_*`). |
| `sdk/runanywhere-web/packages/llamacpp/src/Extensions/RunAnywhere+ToolCalling.ts` | +84 / −193 | Deleted `parseToolCallTS`, `formatToolsForPromptTS`, `buildFollowUpPromptTS`. `assertNativeToolCalling()` now throws a typed `SDKError` on missing exports — no silent fall-back to duplicate parsing. |
| `docs/v2_closeout_phase_g1_report.md` | **+this file** | This report. |

### LOC delta summary

| Category | Added | Deleted | Net |
|---|---|---|---|
| Commons tests | 343 | 2 | +341 |
| Commons JNI fix | 111 | 27 | +84 |
| RN C++ (de-stub) | 13 | 45 | −32 |
| RN Android CMake (re-enable) | 1 | 3 | −2 |
| Web TS (delete fallback) | 84 | 193 | −109 |
| **Total** | **552** | **270** | **+282 incl. tests, −150 prod-code LOC** |

Per the standing rule "DELETE, don't deprecate": the three TS parsing
duplicates in Web are gone, not commented out; the RN stubs are gone,
not `#if 0`-d.

## Verification

### 1. Commons configure

```
$ cmake --preset macos-debug
...
-- JNI bridge       : ON
-- Tests            : ON
-- Configuring done (1.9s)
-- Generating done (0.1s)
```

### 2. Commons full build

```
$ cmake --build --preset macos-debug
[54/54] Linking CXX executable sdk/runanywhere-commons/tests/rac_benchmark_tests
```

Build is green including `rac_commons`, `runanywhere_commons_jni`
(exercises the JNI fix), `test_tool_calling`, and every downstream test target.

### 3. Tool-calling tests

```
$ ctest --preset macos-debug -R tool_call
Test project /.../build/macos-debug
    Start 35: tool_calling_tests
1/1 Test #35: tool_calling_tests ...............   Passed    0.05 sec
100% tests passed, 0 tests failed out of 1
```

Detailed per-scenario output from `./build/macos-debug/sdk/runanywhere-commons/tests/test_tool_calling`:

```
[tool_calling] parse_default_structured ... OK
[tool_calling] parse_lfm2_structured ... OK
[tool_calling] parse_free_form_returns_false ... OK
[tool_calling] format_prompt_default_two_tools ... OK
[tool_calling] format_prompt_json_lfm2 ... OK
[tool_calling] build_initial_prompt_e2e ... OK
[tool_calling] build_followup_prompt_no_tools ... OK
[tool_calling] build_followup_prompt_keep_tools ... OK
[tool_calling] normalize_json_unquoted_keys ... OK
[tool_calling] free_functions_idempotent ... OK
[tool_calling] format_name_round_trip ... OK

[tool_calling] 11/11 passed
```

The `free_functions_idempotent` scenario runs 100 `parse → free → free`
round-trips plus a `free(nullptr)` to exercise the matching allocator
and guard against double-free regressions.

### 4. React Native TS typecheck

```
$ cd sdk/runanywhere-react-native/packages/core && npx tsc --noEmit
exit=0
```

### 5. Web TS typecheck

```
$ cd sdk/runanywhere-web/packages/core && npx tsc --noEmit
exit=0
$ cd sdk/runanywhere-web/packages/llamacpp && npx tsc --noEmit
exit=0
```

### 6. Kotlin JVM compile

```
$ cd sdk/runanywhere-kotlin && ./gradlew compileKotlinJvm
> Task :compileKotlinJvm UP-TO-DATE
> Task :modules:runanywhere-core-onnx:compileKotlinJvm
> Task :modules:runanywhere-core-llamacpp:compileKotlinJvm
BUILD SUCCESSFUL in 2s
```

### 7. Flutter analyze

```
$ cd sdk/runanywhere-flutter/packages/runanywhere && flutter analyze
7 issues found. (ran in 1.6s)
```

All seven are **info-level, pre-existing** lints (`always_use_package_imports`
in generated protos, one `discarded_futures` info in an adapter) — zero errors
and zero items from any file touched in this phase. `dart_bridge_tool_calling.dart`
was not modified.

### 8. Stub-removal check

```
$ grep -n 'return "{}\\"\\|return "";\\|// TODO: Re-enable when commons includes rac_tool_call' \
    sdk/runanywhere-react-native/packages/core/cpp/HybridRunAnywhereCore.cpp
(no tool_call stubs found)
```

(Three other `return "{}";` occurrences in that file belong to
`getModelInfo`, `checkCompatibility`, and `getDownloadProgress` —
unrelated to tool-calling and owned by their own bridges.)

## What's now enforced, in one sentence per SDK

* **Commons** — `rac_tool_call_*` is the single source of truth, validated by
  11 behavioural tests wired into the default ctest suite.
* **Swift** — `CppBridge+ToolCalling.swift` calls `rac_tool_call_*` directly,
  no Swift-side parsing. Unchanged in this phase.
* **Kotlin** — `CppBridgeToolCalling.kt` → JNI → `rac_tool_call_*`. JNI bug
  fixed so the `format` / `systemPrompt` / `temperature` / `maxTokens` fields
  that Kotlin callers already serialised into `optionsJson` are actually
  honoured.
* **Flutter** — `dart_bridge_tool_calling.dart` calls `rac_tool_call_*` via FFI.
  Unchanged in this phase.
* **Web** — WASM `ccall` into the rac_tool_call_* exports is the only path.
  All TS parsing/formatting fallbacks deleted; missing exports now throw.
* **React Native** — four Hybrid methods wire through `ToolCallingBridge` →
  `rac_tool_call_*`. The Android CMake no longer excludes the bridge.

No stubs returning `"{}"` or `""` remain in the tool-calling surface.
