# Raspberry Pi Setup & Run Instructions

**Target:** Raspberry Pi 5 with `runanywhere-sdks` already cloned
**Branch:** `smonga/rasp`

---

## Prerequisites Check

```bash
# Verify you're on the correct branch
cd ~/runanywhere-sdks  # or wherever the repo is
git branch --show-current
# Should show: smonga/rasp

# Pull latest changes
git pull origin smonga/rasp

# Check if models exist
ls -la ~/.local/share/runanywhere/Models/
```

Expected model structure:
```
~/.local/share/runanywhere/Models/
├── ONNX/
│   ├── silero-vad/silero_vad.onnx
│   ├── whisper-tiny-en/
│   └── vits-piper-en_US-lessac-medium/
└── LlamaCpp/
    └── qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

---

## Step 1: Install Build Dependencies

```bash
sudo apt update
sudo apt install -y \
    build-essential \
    cmake \
    git \
    wget \
    curl \
    libasound2-dev \
    libpulse-dev \
    pkg-config
```

---

## Step 2: Build RunAnywhere Commons

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons

# Download Sherpa-ONNX if not already present
if [ ! -d "third_party/sherpa-onnx-linux" ]; then
    ./scripts/linux/download-sherpa-onnx.sh
fi

# Build with server and all backends
./scripts/build-linux.sh --shared

# Verify build
ls -la dist/linux/aarch64/
# Should see: librac_commons.so, librac_backend_*.so
```

---

## Step 3: Build Voice Assistant

```bash
cd ~/runanywhere-sdks/playground/linux-voice-assistant

# Configure
cmake -B build

# Build
cmake --build build -j4

# Verify
ls -la build/voice-assistant
```

---

## Step 4: Build RunAnywhere Server (Optional - for Moltbot)

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons

# Build with server enabled
cmake -B build-server \
    -DCMAKE_BUILD_TYPE=Release \
    -DRAC_BUILD_SERVER=ON \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BACKEND_LLAMACPP=ON \
    -DRAC_BACKEND_ONNX=ON

cmake --build build-server -j4

# Verify
ls -la build-server/tools/runanywhere-server
```

---

## Step 5: Download Models (if not present)

```bash
cd ~/runanywhere-sdks/playground/linux-voice-assistant

# Run the download script
./scripts/download-models.sh
```

Or manually download:

```bash
# Create directories
mkdir -p ~/.local/share/runanywhere/Models/{ONNX,LlamaCpp}

# Silero VAD
mkdir -p ~/.local/share/runanywhere/Models/ONNX/silero-vad
wget -O ~/.local/share/runanywhere/Models/ONNX/silero-vad/silero_vad.onnx \
    https://github.com/snakers4/silero-vad/raw/master/files/silero_vad.onnx

# Qwen2.5 0.5B (LLM)
mkdir -p ~/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4
wget -O ~/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf \
    https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf
```

---

## Step 6: Run Voice Assistant

```bash
cd ~/runanywhere-sdks/playground/linux-voice-assistant

# List audio devices first
./build/voice-assistant --list-devices

# Run with default devices
./build/voice-assistant

# Or specify devices
./build/voice-assistant --input plughw:1,0 --output plughw:0,0
```

**Controls:**
- Speak to interact
- `Ctrl+C` to exit

---

## Step 7: Run RunAnywhere Server (Optional)

In a separate terminal:

```bash
cd ~/runanywhere-sdks/sdk/runanywhere-commons

# Start server
./build-server/tools/runanywhere-server \
    --model ~/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf \
    --port 8080 \
    --threads 4

# Test it
curl http://localhost:8080/health
curl http://localhost:8080/v1/models
```

---

## Troubleshooting

### No audio input detected
```bash
# Check ALSA devices
arecord -l
aplay -l

# Test recording
arecord -d 5 -f S16_LE -r 16000 -c 1 test.wav
aplay test.wav

# Adjust levels
alsamixer
```

### Permission denied for audio
```bash
sudo usermod -a -G audio $USER
# Then logout and login again
```

### Library not found errors
```bash
# Add library path
export LD_LIBRARY_PATH=~/runanywhere-sdks/sdk/runanywhere-commons/dist/linux/aarch64:$LD_LIBRARY_PATH
```

### Out of memory
```bash
# Check memory
free -h

# Close other applications
# Consider using swap
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

## Quick Test Commands

```bash
# Test LLM directly
curl -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-0.5b-instruct-q4",
    "messages": [{"role": "user", "content": "Hello, what can you do?"}],
    "max_tokens": 100
  }'
```

---

## Running as a Service (Optional)

Create systemd service for auto-start:

```bash
sudo tee /etc/systemd/system/runanywhere-server.service << 'EOF'
[Unit]
Description=RunAnywhere AI Server
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/runanywhere-sdks/sdk/runanywhere-commons
ExecStart=/home/pi/runanywhere-sdks/sdk/runanywhere-commons/build-server/tools/runanywhere-server --model /home/pi/.local/share/runanywhere/Models/LlamaCpp/qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf --port 8080
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable runanywhere-server
sudo systemctl start runanywhere-server
sudo systemctl status runanywhere-server
```

---

## Expected Performance

| Metric | Raspberry Pi 5 |
|--------|----------------|
| STT Latency | ~300-500ms |
| LLM Tokens/sec | ~5-10 tok/s |
| TTS Latency | ~100-200ms |
| Full Pipeline | ~2-3s per turn |
| Power | ~5W |

---

## Files Summary

| Component | Location |
|-----------|----------|
| Voice Assistant | `playground/linux-voice-assistant/build/voice-assistant` |
| Server | `sdk/runanywhere-commons/build-server/tools/runanywhere-server` |
| Libraries | `sdk/runanywhere-commons/dist/linux/aarch64/` |
| Models | `~/.local/share/runanywhere/Models/` |
