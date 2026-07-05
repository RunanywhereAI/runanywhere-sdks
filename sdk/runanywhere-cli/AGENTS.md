# runanywhere-cli (rcli)

## Info

Global rules: see repo-root AGENTS.md.

`rcli` is the RunAnywhere desktop CLI (macOS/Linux): Ollama-style model lifecycle management plus multi-modal inference (LLM/VLM/STT/TTS/VAD/voice) on the `rac_*` C ABI. It is the 6th consumer of `sdk/runanywhere-commons` — same role as the platform SDKs. Design doc: `thoughts/shared/plans/rcli_desktop_cli.md`.

Layering (the rule that matters most here):
- Command files (`src/commands/cmd_*.cpp`) are THIN: parse flags → `bootstrap()` → ONE commons entry point → render. No inference logic, no multi-step model orchestration, no SDK-internal knowledge (path patterns, framework dirs).
- If a command needs a sequence commons doesn't offer as one call, fix commons (add/extend a `rac_*` API), don't compose it here.
- The desktop platform adapter + curl transport live in commons (`sdk/runanywhere-commons/src/desktop/`, `include/rac/desktop/rac_desktop.h`), NOT here — shared with runanywhere-server, tests, and Playground.
- CLI-only concerns that DO belong here: argv parsing (CLI11), terminal rendering (tables, progress bars), the REPL (linenoise), WAV file I/O, the built-in model catalog (`src/catalog/`), and directory resolution (`RUNANYWHERE_HOME`).

Output discipline (enforced; tested in `tests/test_rcli_unit.cpp`):
- Results → stdout. Logs / progress / banners / prompts → stderr.
- `--json` prints exactly ONE JSON document on stdout (via `rcli::out::JsonWriter`; no JSON library).
- Progress bars only when stderr is a TTY and neither `--json` nor `--no-progress` is set; otherwise plain percentage lines.
- Exit codes: 0 success, 1 runtime/SDK error, 2 usage error.

Vendored `third_party/`: `CLI11/CLI11.hpp` (BSD-3) and `linenoise/` (BSD-2) — never edit; replace wholesale from upstream and note the version in the PR.

## Build Info

rcli builds through the commons CMake tree — `sdk/runanywhere-commons` is the CMake root (presets there; output `sdk/runanywhere-commons/build/<preset>/`). Gated by `RAC_BUILD_CLI` (+ `RAC_DESKTOP_ADAPTER`).

```bash
cd sdk/runanywhere-commons

# Lean dev loop (no backends, fast):
cmake --preset macos-debug -DRAC_DESKTOP_ADAPTER=ON -DRAC_BUILD_CLI=ON     # or linux-debug
cmake --build build/macos-debug --target rcli test_rcli_unit
./build/macos-debug/tests/test_rcli_unit

# Full release build (backends; Metal on macOS):
cmake --preset rcli-macos-release && cmake --build build/rcli-macos-release
cmake --preset rcli-linux-release && cmake --build build/rcli-linux-release

# Packaging / e2e (repo root)
./scripts/release/package-rcli.sh
./scripts/tests/run-cli-e2e-linux.sh
```

Homebrew packaging lives in `packaging/homebrew/`; install script in `scripts/install.sh` (this directory); tap tooling in repo-root `scripts/release/rcli-tap.sh`.

## Work Ground

- (empty)
