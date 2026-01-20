# 🤖 RunAnywhere Android CLI

A native Kotlin CLI for Android developers to build, lint, and benchmark RunAnywhere Android apps.

> **For iOS developers**: See the [Swift CLI](../cli-swift/README.md) instead!

## 🚀 Quick Start

```bash
# Build the CLI
./gradlew :cli:shadowJar

# Run it
java -jar cli/build/libs/runanywhere-cli-0.1.0.jar --help

# Or install to your path
./gradlew :cli:installCli
runanywhere --help
```

## 📱 Automated Benchmarking

**The easiest way to benchmark your models:**

```bash
# Just plug in your phone and run:
runanywhere benchmark auto
```

That's it! The CLI will:
1. ✅ Detect your connected device (iOS or Android)
2. ✅ Launch the RunAnywhereAI app
3. ✅ Automatically start the benchmark
4. ✅ Wait for completion
5. ✅ Pull results and show a beautiful report

### Options

```bash
# Quick benchmark (faster, less accurate)
runanywhere benchmark auto --config=quick

# Comprehensive benchmark (slower, more accurate)
runanywhere benchmark auto --config=comprehensive

# Specific models only
runanywhere benchmark auto --models=smollm2-360m,qwen-0.5b

# Custom timeout (default: 10 minutes)
runanywhere benchmark auto --timeout=300

# Save results to specific directory
runanywhere benchmark auto --output=my_results/
```

### Sample Output

```
╔═══════════════════════════════════════════════════════════╗
║        RunAnywhere Automated Benchmark                    ║
║        Just plug in your phone and run!                   ║
╚═══════════════════════════════════════════════════════════╝

📱 Step 1: Detecting devices...
✓ Found 2 device(s):
  📱 iPhone 15 Pro (iOS 17.2)
  🤖 Pixel 7 (Android API 34)

⚙️  Step 2: Starting benchmarks...
   Config: default
   Models: smollm2-360m, qwen-0.5b

▶ Running on iPhone 15 Pro...
   ⏳ Waiting for benchmark to complete... (45s)
   ✓ Pulled 1 result file(s)

▶ Running on Pixel 7...
   ⏳ Waiting for benchmark to complete... (52s)
   ✓ Pulled 1 result file(s)

📊 Step 3: Results

┌────────────────┬─────────────────┬───────────┬────────┬────────┐
│ Model          │ Device          │ Tokens/s  │ TTFT   │ Memory │
├────────────────┼─────────────────┼───────────┼────────┼────────┤
│ SmolLM2 360M   │ iPhone 15 Pro   │ 45.2      │ 89ms   │ 412MB  │
│ SmolLM2 360M   │ Pixel 7         │ 38.7      │ 105ms  │ 523MB  │
│ Qwen 0.5B      │ iPhone 15 Pro   │ 32.1      │ 120ms  │ 580MB  │
│ Qwen 0.5B      │ Pixel 7         │ 28.4      │ 145ms  │ 620MB  │
└────────────────┴─────────────────┴───────────┴────────┴────────┘

Performance Comparison (tokens/sec):

  SmolLM2 360M (iOS)     ████████████████████████████████████████ 45.2
  SmolLM2 360M (Android) █████████████████████████████████ 38.7
  Qwen 0.5B (iOS)        ████████████████████████████ 32.1
  Qwen 0.5B (Android)    ████████████████████████ 28.4

✓ Results saved to: /path/to/benchmark_results
```

## 📋 All Commands

### Build Commands

```bash
runanywhere build --all              # Build all SDKs
runanywhere build swift --setup      # Build Swift SDK
runanywhere build kotlin             # Build Kotlin SDK
runanywhere build flutter            # Build Flutter SDK
runanywhere build react-native       # Build React Native SDK
runanywhere build android-app --run  # Build and run Android app
```

### Lint Commands

```bash
runanywhere lint --all       # Lint all platforms
runanywhere lint ios --fix   # Lint iOS with auto-fix
runanywhere lint android     # Lint Android
```

### Model Commands

```bash
runanywhere models list              # List all available models
runanywhere models list --downloaded # Show only downloaded models
runanywhere models info smollm2-360m # Show model details
```

### Benchmark Commands

```bash
runanywhere benchmark auto           # 🚀 Fully automated benchmark
runanywhere benchmark devices        # List connected devices
runanywhere benchmark run --ios      # Manual run on iOS
runanywhere benchmark pull --all     # Pull results from devices
runanywhere benchmark compare *.json # Compare result files
runanywhere benchmark history        # View historical data
runanywhere benchmark report         # Generate report
```

## 🔧 Requirements

- **Java 17+** - For running the CLI
- **adb** - For Android device communication
- **Xcode Command Line Tools** - For iOS simulator/device communication

## 📝 Customizing Benchmarks

Edit `examples/benchmark-config.json` to add custom prompts:

```json
{
  "prompts": [
    {
      "id": "my-custom-prompt",
      "text": "Your prompt here...",
      "category": "custom",
      "expectedMinTokens": 50
    }
  ]
}
```

## 🤝 Contributing

1. Add new prompts to `benchmark-config.json`
2. Test with multiple models
3. Submit a PR!

See the [main README](../README.md) for full contribution guidelines.
