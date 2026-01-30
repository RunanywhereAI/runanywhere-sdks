# Building from Source

For development or custom configurations.

## Prerequisites

```bash
# Build tools
sudo apt-get update
sudo apt-get install -y cmake build-essential libasound2-dev libpulse-dev git

# Node.js 22+ (for Moltbot)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
```

## Build Steps

### 1. Clone Repository

```bash
git clone -b smonga/rasp https://github.com/RunanywhereAI/runanywhere-sdks.git ~/runanywhere-sdks
cd ~/runanywhere-sdks
```

### 2. Build RunAnywhere Commons

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons

# Download Sherpa-ONNX dependencies
./scripts/linux/download-sherpa-onnx.sh

# Build with shared libraries
./scripts/build-linux.sh --shared
```

### 3. Build RunAnywhere Server

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons
mkdir -p build-server && cd build-server

cmake .. -DCMAKE_BUILD_TYPE=Release \
    -DRAC_BUILD_SERVER=ON \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BACKEND_LLAMACPP=ON \
    -DRAC_BACKEND_ONNX=ON

make -j$(nproc)
```

### 4. Build Voice Assistant

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

### 5. Download Models

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant
./scripts/download-models.sh
```

## Run (Built from Source)

```bash
cd ~/runanywhere-sdks/Playground/linux-voice-assistant
./run.sh
```

## Directory Structure

```
~/runanywhere-sdks/
├── sdk/runanywhere-commons/
│   ├── build-server/tools/runanywhere-server  # LLM server
│   └── dist/linux/aarch64/                    # Shared libraries
└── Playground/linux-voice-assistant/
    └── build/voice-assistant                  # Voice assistant

~/.local/share/runanywhere/Models/
├── ONNX/                                      # STT, TTS, VAD models
└── LlamaCpp/                                  # LLM models
```

## Performance (Raspberry Pi 5)

| Component | Metric |
|-----------|--------|
| STT | ~300-500ms |
| LLM | ~5-10 tok/s |
| TTS | ~100-200ms |
| Full pipeline | ~2-3s per turn |
