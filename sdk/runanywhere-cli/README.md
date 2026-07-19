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

**Homebrew** (macOS Apple Silicon or Linux x86_64):

```bash
brew install runanywhere-ai/tap/rcli
```

**Install script** (macOS Apple Silicon or Linux x86_64):

```bash
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/sdk/runanywhere-cli/scripts/install.sh | sh
```

**PowerShell installer** (Windows x86_64; no administrator shell required):

```powershell
irm https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/sdk/runanywhere-cli/scripts/install.ps1 | iex
```

The Windows installer verifies the release checksum, installs `rcli.exe` and
its pinned ONNX Runtime/Sherpa DLLs under `%LOCALAPPDATA%\Programs\rcli\bin`,
and adds that `bin` directory to the current user's `PATH`. The Windows build
ships llama.cpp + Sherpa/ONNX; `rcli serve` (the OpenAI-compatible HTTP server)
is macOS/Linux-only.

The macOS GitHub Release also includes a Developer ID signed, notarized, and
stapled disk image. Its `rcli-macos-arm64` directory has the same relocatable
layout as the Homebrew tarball.

Published release assets are platform-specific:

| Platform | Asset | Included engines |
|---|---|---|
| macOS Apple Silicon | `rcli-macos-arm64-vX.Y.Z.tar.gz` and signed/notarized DMG | llama.cpp + MLX + Sherpa-ONNX + ONNX Runtime + CoreML |
| Linux x86_64 | `rcli-linux-x86_64-vX.Y.Z.tar.gz` | llama.cpp + Sherpa-ONNX + ONNX Runtime |
| Windows x86_64 | `rcli-windows-x86_64-vX.Y.Z.zip` | llama.cpp + Sherpa-ONNX + ONNX Runtime |

MLX is Apple Silicon/macOS-only. The command surface is shared across all
three platforms; commands that require an unavailable platform engine return a
clear unsupported-backend error.

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
# macOS CMake smoke build (arm64; llama.cpp + the MLX bridge/catalog, but no
# Swift callbacks — use the combined host below for real MLX inference):
cmake --preset rcli-macos-release
cmake --build build/rcli-macos-release -j 2

# Full macOS host (arm64; llama.cpp + working MLX LLM/VLM/STT/TTS):
CONFIGURATION=release ./sdk/runanywhere-cli/scripts/build-mlx-cli.sh

# Linux (x86_64/aarch64) — fetch sherpa/onnxruntime prebuilts first:
./sdk/runanywhere-commons/scripts/linux/download-sherpa-onnx.sh
cmake --preset rcli-linux-release
cmake --build build/rcli-linux-release -j 2

# Windows x86_64 (PowerShell, with vcpkg available on VCPKG_INSTALLATION_ROOT):
& "$env:VCPKG_INSTALLATION_ROOT\vcpkg.exe" install curl:x64-windows-static
sdk\runanywhere-commons\scripts\windows\download-sherpa-onnx.bat
cmake --preset rcli-windows-release
cmake --build --preset rcli-windows-release
./sdk/runanywhere-cli/scripts/package-rcli-windows.ps1

# Lean dev loop (no backends — lifecycle/UX work only):
cmake --preset macos-debug -DRAC_DESKTOP_ADAPTER=ON -DRAC_BUILD_CLI=ON
cmake --build build/macos-debug -j 2 --target rcli test_rcli_unit
```

The tagged macOS release packages the `RunAnywhereMLXCLI` product as `bin/rcli`
together with `mlx.metallib`, its SwiftPM resource bundles, and any deployment-
target Swift compatibility libraries. The CMake `rcli` binary remains the fast,
credential-free pull-request smoke target; it registers llama.cpp and exposes
the dual catalog but cannot execute MLX without the Swift callbacks.

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

CI: `pr-build.yml` builds macOS, Linux, and Windows rcli targets and runs unit,
backend-registration, relocatable-package, and modelless smoke checks. Windows
is built natively on `windows-2022`. `release.yml` requires all three rcli
packages before publishing the GitHub Release.

## macOS distribution signing

`release.yml` builds the combined Swift/C++ host from the same Apple artifacts
as the SDK release, imports a Developer ID Application certificate into an
ephemeral keychain, signs the executable and compatibility libraries with the
hardened runtime and secure timestamp, notarizes a DMG, staples and validates
its ticket, then deletes the temporary keychain and credential files.

The repository stores no signing material. Configure the Developer ID secrets
and one complete notarization credential set before creating a release tag:

- `RCLI_DEVELOPER_ID_CERT_P12_BASE64`
- `RCLI_DEVELOPER_ID_CERT_PASSWORD`

Preferred App Store Connect API-key notarization:

- `RCLI_NOTARY_API_KEY_P8_BASE64`
- `RCLI_NOTARY_KEY_ID`
- `RCLI_NOTARY_ISSUER_ID`

Apple ID fallback notarization:

- `RCLI_NOTARY_APPLE_ID`
- `RCLI_NOTARY_APP_SPECIFIC_PASSWORD`
- `RCLI_NOTARY_TEAM_ID`

When both notarization sets are complete, the workflow uses the App Store
Connect API key. The Apple ID fallback stores its run-scoped notarytool profile
only in the same ephemeral keychain as the imported Developer ID identity,
passes that keychain explicitly during submission, and deletes it after the
package step.

For a local or external release runner, `scripts/package-rcli.sh` accepts an
already-available identity through `RCLI_CODESIGN_IDENTITY` (and optionally
`RCLI_CODESIGN_KEYCHAIN`). Set `RCLI_MACOS_NOTARIZE=1` and authenticate
notarytool either with `RCLI_NOTARYTOOL_PROFILE` (plus
`RCLI_NOTARYTOOL_KEYCHAIN` for a profile in a non-default keychain) or the
API-key path, key ID, and issuer ID variables documented at the top of that
script. The normal credential-free packaging path remains ad-hoc signed for
pull-request smoke.

## Windows distribution signing

The release workflow Authenticode-signs `rcli.exe`, validates the resulting
signature, and only then creates the Windows ZIP. Configure these repository
secrets before creating a release tag:

- `RCLI_WINDOWS_CODESIGN_PFX_BASE64`
- `RCLI_WINDOWS_CODESIGN_PFX_PASSWORD`

Pull-request builds remain credential-free and validate the same unsigned
binary/package layout before the protected release job performs signing.

## Architecture

rcli is a 6th consumer of the `rac_*` C ABI — exactly like the mobile/web
SDKs. Commands are thin (`argv → one commons entry point → render`):
lifecycle-owned model loading (`rac_model_lifecycle_load_proto` auto-pulls,
resolves artifacts incl. VLM mmproj, loads the engine once), proto-byte
streaming generation, the download orchestrator with the desktop libcurl
transport, and the voice-agent pipeline. The reusable desktop platform layer
(native adapter + curl transport) lives in commons
(`include/rac/desktop/rac_desktop.h`) and is shared with
`runanywhere-server`, the tests and the Playground apps.
See `AGENTS.md` for the package layering rules.

## Known limitations

- `serve` is LLM-only and single-model (scope of commons `rac_server`).
- REPL turns are independent (no conversation memory yet).
- `rcli voice` with thinking models (qwen3) speaks the `<think>` text — pick a
  non-thinking LLM (`--llm lfm2`) until voice-agent thinking control lands.
- Raw-URL pulls get inferred metadata (size/modality may show as `-`/generic).
- macOS x86_64, Linux ARM64, and Windows ARM64 binaries are not published yet.
