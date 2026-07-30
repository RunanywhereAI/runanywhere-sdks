# RunAnywhere CLI (`rcli`)

Run, manage, and serve on-device AI models from the terminal. One binary, multi-modal: LLM chat, VLM image understanding, speech-to-text, text-to-speech, voice activity detection, and a full voice pipeline — all running locally on the RunAnywhere C++ core.

```console
$ rcli models download qwen3
pulling qwen3-0.6b ▕████████████▏ 100%  639 MB/639 MB  32 MB/s
$ rcli llm generate --model qwen3 "Reply with exactly: RCLI WORKS" --reasoning off
RCLI WORKS
$ rcli tts synthesize "RunAnywhere runs models on device." --output hello.wav
$ rcli stt transcribe hello.wav
$ rcli serve qwen3        # OpenAI-compatible API on :8080
```

## Install

**Homebrew** (macOS Apple Silicon or Linux x86_64):

```bash
brew install runanywhere-ai/tap/rcli
```

**Install script** (macOS Apple Silicon or Linux x86_64):

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/sdk/runanywhere-cli/scripts/install.sh | sh
```

**PowerShell** (Windows x86_64):

```powershell
irm https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/sdk/runanywhere-cli/scripts/install.ps1 | iex
```

The Windows installer verifies the release checksum, installs `rcli.exe` and pinned ONNX Runtime/Sherpa DLLs under `%LOCALAPPDATA%\Programs\rcli\bin`, and adds that directory to the user `PATH`.

| Platform | Engines | Notes |
|---|---|---|
| macOS Apple Silicon | llama.cpp, MLX, Sherpa-ONNX, ONNX Runtime, CoreML | Signed/notarized DMG in GitHub Releases |
| Linux x86_64 | llama.cpp, Sherpa-ONNX, ONNX Runtime | |
| Windows x86_64 | llama.cpp, Sherpa-ONNX, ONNX Runtime | `rcli serve` is macOS/Linux-only |

MLX is Apple Silicon only. Commands that require an unavailable engine return a clear unsupported-backend error.

**From source:** see [Building from source](#building-from-source).

## Commands

The command surface is the [public API spec](../../thoughts/shared/plans/public_api_spec.md) spelled in kebab-case: one namespace per modality, the spec's verb under it, and option names that match the spec's option fields (`--max-output-tokens`, `--top-p`, `--reasoning`, `--speed`, `--guidance-scale`). If you know the surface in one SDK you know it here.

| Command | Description |
|---|---|
| `rcli llm generate [prompt]` | Complete a prompt and print the result |
| `rcli llm stream [prompt]` | Complete a prompt, printing tokens as they arrive |
| `rcli vlm generate --image f.png [prompt]` | Answer a prompt about an image |
| `rcli stt transcribe a.wav` | Transcribe an audio file (default: whisper-tiny) |
| `rcli tts synthesize "…" -o o.wav` | Write spoken audio to a WAV file (default: Piper Lessac) |
| `rcli vad detect a.wav` | Report speech segments with timestamps (default: silero) |
| `rcli embed [text]` | Turn text into embedding vectors |
| `rcli rerank <query> -m <model> -d "…"` | Score documents against a query, best first |
| `rcli image generate -p "…" -o o.png` | Render an image from a prompt (Core ML, Apple only) |
| `rcli diarize a.wav -m <model>` | Label who spoke when |
| `rcli segment image.ppm -m <model>` | Label every pixel of an image by class |
| `rcli rag query <question>` | Answer a question over `--doc` / `--file` documents |
| `rcli voice a.wav [-o reply.wav]` | Hold one spoken turn: STT → LLM → TTS |
| `rcli models list` | List models, downloaded ones by default (`--all` for the catalog) |
| `rcli models get <model>` | Show one model's registry entry |
| `rcli models register <url>` | Add a model from a URL or `hf.co` ref |
| `rcli models download <model>` | Fetch a model, resuming a partial download |
| `rcli models delete <model>` | Remove a model's files and registration (`-f` skips the prompt) |
| `rcli models load <model>` | Load a model now instead of on first use |
| `rcli models unload [category]` | Free loaded models, all of them by default |
| `rcli models state` | Report resident models and disk usage |
| `rcli lora {apply,remove,list,catalog,import}` | Attach LoRA adapters to a language model |
| `rcli serve [model]` | OpenAI-compatible HTTP server (`/v1/chat/completions`, `/v1/models`, `/health`) |
| `rcli bench [model]` | Benchmark downloaded LLM/STT/TTS/VLM models |
| `rcli telemetry {emit,blast}` | Drive the control-plane telemetry pipeline (no model needed) |
| `rcli backends` | Registered inference backends per primitive |
| `rcli info` (`doctor`) / `rcli version` | Environment and version info |
| `rcli auth login` | Authenticated control-plane login (production) |

Generation, transcription and synthesis load what they need: name a model with `--model` and rcli downloads it if it is missing, then loads it before the first token. `rcli models load` is for paying that cost when you choose to.

### Aliases

The shorter spellings are the same commands, not separate ones:

| Alias | Namespaced form |
|---|---|
| `rcli run <model> [prompt]`, `rcli chat <model>` | `rcli llm stream` (REPL when no prompt is given) |
| `rcli list`, `rcli ls` | `rcli models list` |
| `rcli show <model>` | `rcli models get` |
| `rcli pull <model>` | `rcli models download` |
| `rcli rm`, `rcli remove` | `rcli models delete` |
| `rcli stt --input a.wav` | `rcli stt transcribe a.wav` |
| `rcli tts --text "…"` | `rcli tts synthesize "…"` |
| `rcli vad --input a.wav` | `rcli vad detect a.wav` |
| `rcli run --image f.png` | `rcli vlm generate --image f.png` |

Older flag spellings keep working next to the spec names: `--max-tokens` for `--max-output-tokens`, `--temp` for `--temperature`, `--system` for `--system-prompt`, `--no-think` for `--reasoning off`, `--negative` for `--negative-prompt`, `--guidance` for `--guidance-scale`, `--min-duration` for `--minimum-duration-ms`, `--merge-gap` for `--merge-gap-ms`.

Global flags: `--json` (one machine-readable document on stdout), `--home <dir>`, `-v/--verbose`, `-q/--quiet`, `--no-progress`, plus the control-plane trio `--environment <development|production>`, `--base-url <url>`, and `--api-key <key>` (see [docs/RELEASING.md](./docs/RELEASING.md)).

Exit codes: `0` ok · `1` runtime error · `2` usage error · `130` cancelled.

## Interactive REPL

Launch with no prompt when stdin is a TTY:

```bash
rcli chat qwen3
```

Features line editing and history (`~/.local/state/runanywhere/history`; disable with `RUNANYWHERE_NOHISTORY=1`).

Slash commands: `/set system <text>`, `/set temperature <f>`, `/set max-output-tokens <n>`, `/show`, `/bye` (or Ctrl-D). One Ctrl-C cancels the current generation.

Thinking models (qwen3 family): thought tokens stream dimmed to **stderr**, answers to **stdout**. `--hide-thinking` keeps the thoughts off your terminal while the model still thinks; `--reasoning off` stops it thinking at all.

## Model catalog

`rcli models list --all` shows the built-in catalog — Qwen3, Llama 3.2, SmolLM2, SmolVLM2, Whisper, Piper voices, Silero VAD, MiniLM embeddings, and more. Short aliases work everywhere: `qwen3`, `whisper-tiny`, `piper`, `smolvlm2`, …

Fetch models outside the catalog:

```bash
rcli models download hf.co/Qwen/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q8_0.gguf
rcli models download https://example.com/model.gguf
```

`rcli models register <url>` does the registration step alone, when you want the entry now and the bytes later.

URL registrations persist under `<home>/RunAnywhere/Registry/`.

## Storage layout

One knob: the RunAnywhere home (`--home`, `$RUNANYWHERE_HOME`, default `~/.local/share/runanywhere`).

```
~/.local/share/runanywhere/Models/{LlamaCpp,Sherpa,ONNX,...}/<model-id>/…
~/.local/share/runanywhere/Registry/        # persisted URL registrations
~/.config/runanywhere/secure/               # secure store (0600 files)
~/.local/state/runanywhere/history          # REPL history
```

Models pulled by `rcli` are shared with other RunAnywhere desktop apps using the same home directory.

## Building from source

Requires CMake ≥ 3.24, a C++20 compiler, and libcurl dev headers on Linux (`apt install libcurl4-openssl-dev`).

```bash
# macOS (full MLX host):
CONFIGURATION=release ./sdk/runanywhere-cli/scripts/build-mlx-cli.sh

# Linux x86_64:
./sdk/runanywhere-commons/scripts/linux/download-sherpa-onnx.sh
cmake --preset rcli-linux-release
cmake --build build/rcli-linux-release -j 2

# Windows x86_64 (PowerShell):
sdk\runanywhere-commons\scripts\windows\download-sherpa-onnx.bat
cmake --preset rcli-windows-release
cmake --build --preset rcli-windows-release
```

See [docs/RELEASING.md](./docs/RELEASING.md) for signing, notarization, control-plane validation, and release workflow details.

## Testing

```bash
ctest --test-dir build/macos-debug -R "rcli_unit_tests|desktop_adapter_tests"
bash sdk/runanywhere-commons/tests/scripts/run-cli-e2e-linux.sh
```

## Architecture

`rcli` is a consumer of the `rac_*` C ABI — the same core used by the mobile, web, and desktop SDKs. Commands are thin wrappers: lifecycle-owned model loading, proto-byte streaming generation, the download orchestrator, and the voice-agent pipeline. The reusable desktop platform layer lives in commons (`include/rac/desktop/rac_desktop.h`).

## Known limitations

- `serve` is LLM-only and single-model.
- REPL turns are independent (no conversation memory yet).
- `rcli voice` with thinking models may speak reasoning text — use a non-thinking LLM (`--llm lfm2`) until voice-agent thinking control lands.
- macOS x86_64, Linux ARM64, and Windows ARM64 binaries are not published yet.
- Four spec verbs have no command yet because the C core cannot back them: `tts speak` (commons synthesizes to a buffer and has no playback path), and `rag open` / `rag ingest` / `rag search` (RAG indexes are in-memory per process, and a query needs an LLM even for retrieval). `rcli rag query` opens, ingests and asks in one invocation instead.
- `llm generate` and `llm stream` have no `--seed`: `LLMGenerationOptions` has no seed field. `vlm generate` and `image generate` do, and both take the flag.
- `vlm generate` has no `--frequency-penalty` or `--presence-penalty`; `VLMGenerationOptions` stops at the repetition penalty. Passing them through the `run --image` alias prints a note instead of pretending.
- `models load` takes `--engine` and `--category` only. `ModelLoadRequest` carries no context length, thread count or GPU switch; `rcli serve` has `--context`, `--threads` and `--gpu-layers` for the server it runs.
- `vad detect` exposes `--activation-threshold`. The spec's `minSpeechMs`, `minSilenceMs` and `prefixPaddingMs` are stream-level knobs that the per-frame `rac_vad_component_process` call does not accept.
- `stt transcribe` has no `--translate-to-english`: `rac_stt_options_t` has no field for it.

## Support

- Documentation: [docs.runanywhere.ai](https://docs.runanywhere.ai)
- Discord: [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- Email: [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

## License

See the repository [LICENSE](../../LICENSE).
