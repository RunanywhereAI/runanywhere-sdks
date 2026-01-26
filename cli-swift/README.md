# 🍎 RunAnywhere iOS CLI

Native Swift CLI for iOS developers to build, lint, and benchmark AI models on iOS devices.

## Quick Start

```bash
# Build the CLI
cd cli-swift
swift build -c release

# Run it
.build/release/runanywhere-ios --help
```

## 🚀 Automated Benchmarking

### Benchmark Downloaded Models

```bash
# Quick benchmark (fastest)
runanywhere-ios benchmark auto --config quick

# Default benchmark
runanywhere-ios benchmark auto

# Comprehensive benchmark (most thorough)
runanywhere-ios benchmark auto --config comprehensive
```

### Benchmark a New Model (Contributors!)

**Just pass a GGUF model URL** - the CLI handles everything:

```bash
# Benchmark any GGUF model from HuggingFace
runanywhere-ios benchmark auto --model-url "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf"

# With custom name
runanywhere-ios benchmark auto --model-url "https://..." --model-name "My Custom Model"

# Quick config for faster results
runanywhere-ios benchmark auto --model-url "https://..." --config quick
```

**What happens:**
1. CLI detects your connected iPhone/Simulator
2. Launches the RunAnywhere app
3. App downloads the model from the URL
4. Benchmark runs automatically
5. Results displayed in terminal

### Sample Models to Try

```bash
# SmolLM2 360M (small, fast)
--model-url "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf"

# Qwen 2.5 0.5B
--model-url "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf"

# LiquidAI LFM2 350M
--model-url "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf"
```

## Commands

### `benchmark auto`
Run automated benchmarks on connected iOS devices.

```
OPTIONS:
  --config, -c       Configuration: quick, default, comprehensive
  --model-url        URL to a GGUF model to download and benchmark
  --model-name       Custom name for the model
  --models, -m       Comma-separated model IDs (for already downloaded models)
  --timeout, -t      Timeout in seconds (default: 600)
  --output, -o       Output directory for results
```

### `benchmark devices`
List connected iOS devices and simulators.

```bash
runanywhere-ios benchmark devices
```

### `benchmark pull`
Pull benchmark results from devices.

```bash
runanywhere-ios benchmark pull --output ./results
```

### `build`
Build the iOS SDK or sample app.

```bash
runanywhere-ios build sdk
runanywhere-ios build app --launch
```

### `lint`
Run SwiftLint on iOS code.

```bash
runanywhere-ios lint
runanywhere-ios lint --fix
```

### `devices`
List all connected iOS devices.

```bash
runanywhere-ios devices
```

## Benchmark Configurations

| Config | Warmup | Iterations | Use Case |
|--------|--------|------------|----------|
| `quick` | 1 | 3 | Fast testing, CI/CD |
| `default` | 3 | 5 | Standard benchmarks |
| `comprehensive` | 3 | 10 | Detailed analysis |

## Sample Output

```
╔═══════════════════════════════════════════════════════════╗
║        RunAnywhere iOS Benchmark                          ║
║        Just plug in your iPhone and run!                  ║
╚═══════════════════════════════════════════════════════════╝

📱 Step 1: Detecting iOS devices...
✓ Found 1 device(s):
  📲 iPhone 15 Pro (iOS 17.4) [00008140-...]

⚙️  Step 2: Starting benchmarks...
   Config: quick
   Model URL: https://huggingface.co/.../SmolLM2-360M.Q8_0.gguf

▶ Launching on iPhone 15 Pro...
   ✓ App launched!
   📥 Downloading model...
   
📊 Step 3: Results
   ┌────────────────────────────────────────────┐
   │ Model: SmolLM2-360M.Q8_0                   │
   │ Tokens/sec: 45.2                           │
   │ Time to First Token: 120ms                 │
   │ Peak Memory: 380MB                         │
   └────────────────────────────────────────────┘

✓ Results saved to: benchmark_results
```

## Requirements

- macOS 13+
- Xcode 15+ with Command Line Tools
- Swift 5.9+
- iOS device or Simulator

## For Contributors

### Adding a New Model for Benchmarking

1. Find a GGUF model on HuggingFace
2. Get the direct download URL (right-click → Copy Link)
3. Run:
   ```bash
   runanywhere-ios benchmark auto --model-url "YOUR_URL" --config quick
   ```
4. Share your results!

### Supported Model Formats

- **GGUF** (.gguf) - LlamaCpp backend
- Coming soon: ONNX models

## Installation (Optional)

```bash
# Build release
swift build -c release

# Install to PATH
cp .build/release/runanywhere-ios /usr/local/bin/

# Now use from anywhere
runanywhere-ios benchmark auto
```

## Related

- [Android CLI](../cli/README.md) - Kotlin CLI for Android developers
- [Benchmark Config](../examples/benchmark-config.json) - Customize benchmark prompts
