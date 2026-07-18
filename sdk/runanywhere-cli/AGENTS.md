# AGENTS.md — sdk/runanywhere-cli (rcli)

Rules for AI assistants working in this package. The repo-root AGENTS.md applies in full;
these are the CLI-specific additions.

## What this package is

`rcli` is the RunAnywhere desktop CLI (macOS/Linux): Ollama-style model lifecycle
management plus multi-modal inference (LLM/VLM/STT/TTS/VAD/voice) on top of the
`rac_*` C ABI. It is a **6th consumer** of `sdk/runanywhere-commons` — the same
role the Swift/Kotlin/Flutter/RN/Web SDKs play.

Plan / design doc: `thoughts/shared/plans/rcli_desktop_cli.md`.

## Layering (the only rule that really matters here)

- Command files (`src/commands/cmd_*.cpp`) are THIN: parse flags → bootstrap() →
  ONE commons entry point → render. No inference logic, no multi-step model
  orchestration, no SDK-internal knowledge (path patterns, framework dirs).
- If a command needs a sequence commons doesn't offer as one call, **fix commons**
  (add/extend a `rac_*` API), don't compose it here.
- The desktop platform adapter + curl transport live in commons
  (`sdk/runanywhere-commons/src/desktop/`, `include/rac/desktop/rac_desktop.h`),
  NOT here — they're shared with runanywhere-server, tests, and Playground.
- CLI-only concerns that DO belong here: argv parsing (CLI11), terminal
  rendering (tables, progress bars), the REPL (linenoise), WAV file I/O, the
  built-in model catalog, and directory resolution (`RUNANYWHERE_HOME`).

## Output discipline (enforced; tested in tests/test_rcli_unit.cpp)

- Results → stdout. Logs / progress / banners / prompts → stderr.
- `--json` prints exactly ONE JSON document on stdout (built with
  `rcli::out::JsonWriter`; no JSON library).
- Progress bars only when stderr is a TTY and neither `--json` nor
  `--no-progress` is set; otherwise plain percentage lines.
- Exit codes: 0 success, 1 runtime/SDK error, 2 usage error.

## Build

```bash
# Lean dev loop (no backends, fast):
cmake --preset macos-debug -DRAC_DESKTOP_ADAPTER=ON -DRAC_BUILD_CLI=ON
cmake --build build/macos-debug -j 2 --target rcli test_rcli_unit

# Full release build (llama.cpp + MLX + Metal on macOS):
cmake --preset rcli-macos-release && cmake --build build/rcli-macos-release -j 2
```

Always `-j 2` (repo resource discipline). One heavy build at a time.

macOS release CLI keeps **both** `RAC_BACKEND_LLAMACPP=ON` and `RAC_BACKEND_MLX=ON`.
MLX inference needs the Swift host (`RunAnywhereMLXCLI` / `build-mlx-cli.sh`);
the CMake `rcli` binary still links the MLX bridge and ships both catalogs.

## Vendored third_party

`third_party/CLI11/CLI11.hpp` (BSD-3) and `third_party/linenoise/` (BSD-2) are
vendored verbatim — never edit them; update by replacing the file from upstream
and noting the version in the PR description.
