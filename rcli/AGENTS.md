# AGENTS.md — rcli

Rules for AI assistants working in this package. The repo-root AGENTS.md applies in full;
these are the CLI-specific additions.

## What this package is

`rcli` is the RunAnywhere desktop CLI (macOS/Linux): Ollama-style model lifecycle
management plus multi-modal inference (LLM/VLM/STT/TTS/VAD/voice) on top of the
`rac_*` C ABI. It is a **6th consumer** of `core` — the same
role the Swift/Kotlin/Flutter/RN/Web SDKs play.

Plan / design doc: `thoughts/shared/plans/rcli_desktop_cli.md`.

## Command surface (follow the spec, not your taste)

`thoughts/shared/plans/public_api_spec.md` defines the public surface of all SDKs, and
the CLI is one of them. Concretely:

- One subcommand per spec namespace, the spec's verb under it: `rcli llm generate`,
  `rcli models download`, `rcli lora apply`. New capability means a new verb in the
  right namespace, never a new top-level word.
- Flags are the spec's option fields in kebab-case: `--max-output-tokens`,
  `--top-p`, `--system-prompt`, `--reasoning on|off`, `--speed`, `--guidance-scale`,
  `--top-n`. Do not invent a shorter name for a field the spec already names.
- Terminal-friendly spellings (`run`, `chat`, `list`, `pull`, `rm`, `show`, and the
  flat `stt`/`tts`/`vad` forms) are aliases. One `configure_*` function wires the
  options and callback and is attached at both places; two implementations of the
  same verb is a bug. See `src/commands/commands.h`.
- Retired flag spellings ride along as extra names on the same option
  (`--max-output-tokens,--max-tokens`) for one release, then go.
- Help strings are one imperative line that says what the command or flag does
  without restating its name.
- If the spec asks for something the C ABI cannot do, leave the command out and say
  so in README "Known limitations". Never wire a flag that the commons call ignores.

## Layering (the only rule that really matters here)

- Command files (`src/commands/cmd_*.cpp`) are THIN: parse flags → bootstrap() →
  ONE commons entry point → render. No inference logic, no multi-step model
  orchestration, no SDK-internal knowledge (path patterns, framework dirs).
- If a command needs a sequence commons doesn't offer as one call, **fix commons**
  (add/extend a `rac_*` API), don't compose it here.
- The desktop platform adapter + curl transport live in commons
  (`core/src/desktop/`, `include/rac/desktop/rac_desktop.h`),
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

**There is one shipped binary, `rcli`, and on macOS it is the Swift-hosted one.**
`RunAnywhereMLXCLI` is not a second CLI: it is a Swift `@main` that registers the
MLX and ONNX Swift callbacks and then calls `rcli_run_main()`, the same C++ host.
`package-rcli.sh` stages it as `bin/rcli`, and `build-mlx-cli.sh` symlinks it as
`rcli` in the Swift bin dir so the dev name matches the ship name.

The CMake `rcli` links the MLX bridge but **cannot run MLX**: registration needs
Swift callbacks on the MainActor, which a C++ `main` cannot provide. It says so
at startup (`warning: mlx backend requires MLX runtime callbacks`). The catalog
still offers MLX models on purpose, because the models directory is shared
between RunAnywhere binaries, so pulling with one and running with another is
valid; `test_rcli_unit.cpp::mlx_catalog_registration` locks that. Do not "fix" it
by hiding those entries.

So on macOS, build with `build-mlx-cli.sh` when you need MLX, and expect the
CMake `rcli` to be llama.cpp-only.

## Vendored third_party

`third_party/CLI11/CLI11.hpp` (BSD-3) and `third_party/linenoise/` (BSD-2) are
vendored verbatim — never edit them; update by replacing the file from upstream
and noting the version in the PR description.
