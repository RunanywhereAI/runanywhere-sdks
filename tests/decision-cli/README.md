# decision-cli

One Swift executable over the local SDK source that exercises both decision
backends and the plain text stack, so "is the model actually working" is one
command instead of an ad-hoc rig per backend:

```
decision-cli run     --framework <mlx|llamacpp> --model <id|path>
decision-cli chat    --framework <mlx|llamacpp> --model <id|path>
decision-cli compare --a a.json --b b.json [--tolerance T]
decision-cli models
```

- `run` scores the built-in canonical ticket (team / refund / urgency) through
  the decision component and emits JSON so the two engines can be diffed. It
  prints and records the prompt-wording version the model served, and
  `--prompt-format-version N` refuses to score when the model serves a
  different one (so a wording change can never pass silently).
- `chat` generates text through `RunAnywhere.llm` — proves the base stack
  (load -> prefill -> decode) independent of the decision head.
- `compare` checks probability parity between two `run` JSON outputs.
- `models` lists the built-in catalog.

## Platform support

| Target | Supported | Notes |
|---|---|---|
| macOS 14.5+ (Apple Silicon) | **Yes** | The only supported target. All `Binaries/*.xcframework` ship a `macos-arm64` slice. |
| macOS Intel (x86_64) | No | No x86_64 macOS slice in the XCFrameworks. |
| iOS / iPadOS | No | Slices exist in the XCFrameworks, but this is a command-line executable; iOS cannot run CLIs. |
| Linux / Windows | No | The Swift SDK is Apple-only (XCFramework, URLSession, Keychain); MLX additionally requires Metal. |

To distribute: zip the release binary plus its `*.bundle` directories (see
"Install" below). The binary is arm64-only.

## Prerequisites

- macOS 14.5+ on Apple Silicon, Xcode 26+ / Swift 6.2+ toolchain
  (`swift-tools-version: 6.2`).
- Staged local XCFrameworks (git-ignored). One-time, from the repo root:

  ```bash
  ./bindings/swift/scripts/build-core-xcframework.sh
  ```

  This needs the NeuRT prebuilt slices, `core/third_party/onnxruntime-ios`, and
  `core/third_party/sherpa-onnx-ios`; see `bindings/swift/docs/DEVELOPMENT.md`.
- The `hf` CLI (`pip install -U huggingface_hub`) only if you use catalog ids
  instead of local model paths.
- If the root `Package.swift` in your working tree points its MLX dependencies
  at local checkout paths, those paths must exist. A clean checkout uses the
  committed pinned versions instead.

## Build

The local binaries are git-ignored, so every SwiftPM invocation needs
`RUNANYWHERE_USE_LOCAL_NATIVES=1` — including `swift run`, because SwiftPM
re-evaluates the manifest per invocation.

```bash
cd <repo root>

# debug
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift build --package-path tests/decision-cli

# release
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift build -c release --package-path tests/decision-cli
```

Binaries land at `tests/decision-cli/.build/{debug,release}/DecisionCLI`.

## Run from the build tree

```bash
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift run --package-path tests/decision-cli DecisionCLI models
```

The MLX backend also needs `mlx.metallib` next to the executable. SwiftPM
leaves it somewhere under `.build/` (`find tests/decision-cli/.build -name
mlx.metallib`); in the build tree it is already where the debug binary expects
it. See Troubleshooting if MLX runs abort with exit code 255.

## Install

The executable needs its resource directories (`*.bundle`) and `mlx.metallib`
beside it — a bare copy of the binary will fail on MLX runs.

```bash
cd <repo root>
BUILD=tests/decision-cli/.build/arm64-apple-macosx/release
DEST="$HOME/.local/share/decision-cli/bin"
mkdir -p "$DEST" "$HOME/.local/bin"

cp "$BUILD/DecisionCLI" "$DEST/"
cp -R "$BUILD"/*.bundle "$DEST/" 2>/dev/null || true

# mlx.metallib is configuration-independent; copy it from whichever build has it.
find tests/decision-cli/.build -name mlx.metallib -exec cp {} "$DEST/" \;

cat > "$HOME/.local/bin/decision-cli" <<EOF
#!/bin/sh
exec "$DEST/DecisionCLI" "\$@"
EOF
chmod +x "$HOME/.local/bin/decision-cli"
```

`~/.local/bin` must be on `PATH`.

## Models

`--model` accepts a filesystem path (GGUF file for llamacpp, checkpoint
directory for MLX) or a catalog id. Catalog models download once with `hf` into:

```
~/Library/Application Support/RunAnywhere/DevTools/DecisionCLI/Models/<id>/
```

Override the download location with `DECISION_CLI_MODELS_DIR`. Run
`decision-cli models` for the current list; the decision pair is
`clef-flash-gguf` and `clef-flash-mlx-4bit`.

## Reference numbers

Canonical ticket, both quantizations of the same checkpoint (verified):

```
decision-cli run --framework llamacpp --model clef-flash-gguf       --out a.json
decision-cli run --framework mlx      --model clef-flash-mlx-4bit  --out b.json
decision-cli compare --a b.json --b a.json --tolerance 0.035
```

| field | llamacpp (Q4_K_M) | MLX (4bit) |
|---|---|---|
| team | billing 0.9791 | billing 0.9737 |
| refund | true 0.9284 | true 0.9454 |
| urgency | 2 -> 0.7283 (score 1.6657) | 2 -> 0.7603 (score 1.6997) |

The two backends run different quantization schemes, so the residual delta is
quantization noise (~0.03 on the flat urgency axis). `compare`'s default
tolerance is 0.01; use `--tolerance 0.035` for cross-quantization comparisons.

## Troubleshooting

- **`decision-cli: Decision model not loaded` (release builds only).** The C
  ABI entry points are reached via `dlsym`, so the static linker strips any
  symbol no code references directly. `Package.swift` pins the decision and
  lifecycle entry points with `-Xlinker -u`; when you add a new dlsym-only call
  path, add its symbol there too. Debug builds mask this because `-O0` keeps
  everything.
- **MLX run exits 255 with no output.** `mlx.metallib` is not next to the
  binary; copy it as shown in Install.
- **`catalog entry ... has no repo`.** That catalog row can only be used with a
  local path; catalog downloads need `repo` and `file` set in `Catalog.swift`.
- **`hf download` prompts or fails.** Install/refresh `huggingface_hub`, or
  pass a local `--model` path and skip the catalog entirely.