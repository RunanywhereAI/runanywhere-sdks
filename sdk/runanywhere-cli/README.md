# rcli — RunAnywhere CLI

Run, manage and serve on-device AI models from the terminal. One binary,
multi-modal: LLM chat, VLM image understanding, speech-to-text, text-to-speech,
voice activity detection and a full voice pipeline — all running locally on the
RunAnywhere C++ core, the same engine behind the iOS / Android / Flutter /
React Native / Web SDKs.

```console
$ rcli pull qwen3
pulling qwen3-0.6b ▕████████████▏ 100%  639 MB/639 MB  32 MB/s
$ rcli run qwen3 "Reply with exactly: RCLI WORKS" --no-think
RCLI WORKS
$ rcli tts --text "RunAnywhere runs models on device." --output hello.wav
hello.wav
$ rcli stt --input hello.wav
 Run anywhere runs models on device.
$ rcli serve qwen3        # OpenAI-compatible API on :8080
```

## Install

**Homebrew** (after the first tagged release; tap publishing is in
`scripts/update-tap.sh`):

```bash
brew install runanywhere-ai/tap/rcli
```

**Install script** (macOS Apple Silicon, Linux x86_64):

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/sdk/runanywhere-cli/scripts/install.sh | sh
```

**From source** — see [Building](#building-from-source).

## Commands

| Command | Description |
|---|---|
| `rcli list` (`ls`) | Downloaded models; `--all` includes the full catalog |
| `rcli pull <model>` | Download with progress + resume. Accepts catalog ids/aliases, `hf.co/org/repo/file.gguf`, or direct URLs |
| `rcli rm <model>` | Delete a downloaded model (confined to the models dir; `-f` skips confirmation) |
| `rcli show <model>` | Model details (URLs, files, path, context length) |
| `rcli run <model> [prompt]` | LLM chat: interactive REPL (no prompt), one-shot, or piped stdin. `--image <png/jpg>` switches to VLM. Auto-pulls when missing |
| `rcli stt --input a.wav [model]` | Transcribe a WAV file (default: whisper-tiny) |
| `rcli tts --text "…" --output o.wav [voice]` | Synthesize speech (default: Piper Lessac) |
| `rcli vad --input a.wav [model]` | Speech segments with timestamps (default: silero) |
| `rcli voice --input a.wav [--output reply.wav]` | Full voice turn: STT → LLM → TTS |
| `rcli serve [model]` | OpenAI-compatible HTTP server (`/v1/chat/completions`, `/v1/models`, `/health`). LLM-only, one model per process |
| `rcli backends` | Registered inference backends per primitive |
| `rcli info` / `rcli version` | Environment / versions |

Global flags: `--json` (one machine-readable document on stdout),
`--home <dir>`, `-v/--verbose`, `-q/--quiet`, `--no-progress`.
Exit codes: `0` ok · `1` runtime error · `2` usage error · `130` cancelled.

### `rcli run` REPL

Launched when you give no prompt and stdin is a TTY. Line editing + history
(`~/.local/state/runanywhere/history`, disable with `RUNANYWHERE_NOHISTORY=1`).
Slash commands: `/set system <text>`, `/set temp <f>`, `/set max-tokens <n>`,
`/show`, `/bye` (or Ctrl-D). One Ctrl-C cancels the current generation.
Turns are independent — cross-turn conversation memory needs a commons
chat-session API and is tracked as a follow-up.

Thinking models (qwen3 family): thought tokens stream dimmed to **stderr**,
answers to **stdout** (pipes stay clean); `--no-think` disables the thinking
phase entirely.

## Model catalog & refs

`rcli list --all` shows the built-in catalog — the same models the example
apps register (Qwen3 0.6B/1.7B/4B, Llama 3.2 3B, LFM2, SmolLM2, SmolVLM2,
LFM2-VL, Qwen2-VL, Whisper Tiny, Piper voices, Silero VAD, MiniLM embeddings).
Short aliases work everywhere: `qwen3`, `whisper-tiny`, `piper`, `smolvlm2`, …

Anything not in the catalog can be pulled directly; commons infers format,
framework and category from the artifact:

```bash
rcli pull hf.co/Qwen/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q8_0.gguf
rcli pull https://example.com/model.gguf
```

URL registrations are persisted under `<home>/RunAnywhere/Registry/` so later
`list`/`run`/`rm` invocations still know them.

## Storage layout

One knob: the RunAnywhere home (`--home`, `$RUNANYWHERE_HOME`, default
`~/.local/share/runanywhere`).

```
~/.local/share/runanywhere/Models/{LlamaCpp,Sherpa,ONNX,...}/<model-id>/…
~/.local/share/runanywhere/Registry/        # persisted URL registrations
~/.config/runanywhere/secure/               # secure store (0600 files)
~/.local/state/runanywhere/history          # REPL history
```

The models directory is shared with the commons Linux test rig and the
Playground apps — models pulled by rcli are visible to them and vice versa
(canonical per-framework directories).

## Building from source

Requires CMake ≥ 3.22, a C++20 compiler, and libcurl dev headers on Linux
(`apt install libcurl4-openssl-dev`).

```bash
# macOS (arm64; preset enables Metal — needs Xcode ≤ 15.x, see note):
cmake --preset rcli-macos-release
cmake --build build/rcli-macos-release -j 2

# Linux (x86_64/aarch64) — fetch sherpa/onnxruntime prebuilts first:
./sdk/runanywhere-commons/scripts/linux/download-sherpa-onnx.sh
cmake --preset rcli-linux-release
cmake --build build/rcli-linux-release -j 2

# Lean dev loop (no backends — lifecycle/UX work only):
cmake --preset macos-debug -DRAC_DESKTOP_ADAPTER=ON -DRAC_BUILD_CLI=ON
cmake --build build/macos-debug -j 2 --target rcli test_rcli_unit
```

> Xcode 16+ rejects llama.cpp's Metal ObjC casts — on newer Xcode add
> `-DGGML_METAL=OFF` (CPU inference; CI builds Metal on macos-14 runners).

## Testing

```bash
# Unit tests (ref parsing, catalog, JSON emitter, paths, WAV io):
ctest --test-dir build/macos-debug -R "rcli_unit_tests|desktop_adapter_tests"

# Full Docker e2e (Linux): modelless smoke, hermetic loopback pull/rm,
# tts→stt roundtrip, vad, voice turn, LLM one-shot, serve /health —
# models mounted from ~/.local/share/runanywhere/Models
# (sdk/runanywhere-commons/tests/scripts/download-test-models.sh layout):
bash sdk/runanywhere-commons/tests/scripts/run-cli-e2e-linux.sh
```

CI: `pr-build.yml` builds both rcli presets and runs the modelless smoke +
unit tests; `release.yml` packages `rcli-macos-arm64` / `rcli-linux-x86_64`
tarballs (`scripts/package-rcli.sh`) and gates publishing on their presence.

## Architecture

rcli is a 6th consumer of the `rac_*` C ABI — exactly like the mobile/web
SDKs. Commands are thin (`argv → one commons entry point → render`):
lifecycle-owned model loading (`rac_model_lifecycle_load_proto` auto-pulls,
resolves artifacts incl. VLM mmproj, loads the engine once), proto-byte
streaming generation, the download orchestrator with the desktop libcurl
transport, and the voice-agent pipeline. The reusable desktop platform layer
(POSIX adapter + curl transport) lives in commons
(`include/rac/desktop/rac_desktop.h`) and is shared with
`runanywhere-server`, the tests and the Playground apps.
See `AGENTS.md` (layering rules) and
`thoughts/shared/plans/rcli_desktop_cli.md` (design + implementation log).

## Known limitations

- `serve` is LLM-only and single-model (scope of commons `rac_server`).
- REPL turns are independent (no conversation memory yet).
- `rcli voice` with thinking models (qwen3) speaks the `<think>` text — pick a
  non-thinking LLM (`--llm lfm2`) until voice-agent thinking control lands.
- Raw-URL pulls get inferred metadata (size/modality may show as `-`/generic).
- macOS x86_64 and Windows binaries are not published yet.
