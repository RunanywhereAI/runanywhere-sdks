# RunAnywhere CLI (`rcli`)

Run, manage, and serve on-device AI models from the terminal. One binary, multi-modal: LLM chat, VLM image understanding, speech-to-text, text-to-speech, voice activity detection, and a full voice pipeline — all running locally on the RunAnywhere C++ core.

```console
$ rcli pull qwen3
pulling qwen3-0.6b ▕████████████▏ 100%  639 MB/639 MB  32 MB/s
$ rcli run qwen3 "Reply with exactly: RCLI WORKS" --no-think
RCLI WORKS
$ rcli tts --text "RunAnywhere runs models on device." --output hello.wav
$ rcli stt --input hello.wav
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

| Command | Description |
|---|---|
| `rcli list` (`ls`) | Downloaded models; `--all` includes the full catalog |
| `rcli pull <model>` | Download with progress + resume (catalog id, HuggingFace URL, or direct URL) |
| `rcli rm <model>` | Delete a downloaded model (`-f` skips confirmation) |
| `rcli show <model>` | Model details (URLs, files, path, context length) |
| `rcli run <model> [prompt]` | LLM chat: REPL, one-shot, or piped stdin. `--image` for VLM. Auto-pulls when missing |
| `rcli stt --input a.wav [model]` | Transcribe WAV (default: whisper-tiny) |
| `rcli tts --text "…" --output o.wav [voice]` | Synthesize speech (default: Piper Lessac) |
| `rcli vad --input a.wav [model]` | Speech segments with timestamps (default: silero) |
| `rcli voice --input a.wav [--output reply.wav]` | Full voice turn: STT → LLM → TTS |
| `rcli serve [model]` | OpenAI-compatible HTTP server (`/v1/chat/completions`, `/v1/models`, `/health`) |
| `rcli backends` | Registered inference backends per primitive |
| `rcli info` / `rcli version` | Environment and version info |
| `rcli auth login` | Authenticated control-plane login (production) |

Global flags: `--json` (one machine-readable document on stdout), `--home <dir>`, `-v/--verbose`, `-q/--quiet`, `--no-progress`.

Exit codes: `0` ok · `1` runtime error · `2` usage error · `130` cancelled.

## Interactive REPL

Launch with no prompt when stdin is a TTY:

```bash
rcli run qwen3
```

Features line editing and history (`~/.local/state/runanywhere/history`; disable with `RUNANYWHERE_NOHISTORY=1`).

Slash commands: `/set system <text>`, `/set temp <f>`, `/set max-tokens <n>`, `/show`, `/bye` (or Ctrl-D). One Ctrl-C cancels the current generation.

Thinking models (qwen3 family): thought tokens stream dimmed to **stderr**, answers to **stdout**; `--no-think` disables the thinking phase.

## Model catalog

`rcli list --all` shows the built-in catalog — Qwen3, Llama 3.2, SmolLM2, SmolVLM2, Whisper, Piper voices, Silero VAD, MiniLM embeddings, and more. Short aliases work everywhere: `qwen3`, `whisper-tiny`, `piper`, `smolvlm2`, …

Pull models outside the catalog:

```bash
rcli pull hf.co/Qwen/Qwen3-0.6B-GGUF/Qwen3-0.6B-Q8_0.gguf
rcli pull https://example.com/model.gguf
```

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

Requires CMake ≥ 3.22, a C++20 compiler, and libcurl dev headers on Linux (`apt install libcurl4-openssl-dev`).

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

## Support

- Documentation: [docs.runanywhere.ai](https://docs.runanywhere.ai)
- Discord: [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- Email: [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

## License

See the repository [LICENSE](../../LICENSE).
