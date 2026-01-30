# RunAnywhere Voice Assistant

On-device voice AI for Raspberry Pi 5 (Linux aarch64). Say **"Hey Jarvis"** to activate.

---

## Option 1: Full Moltbot Integration (Easiest & Recommended)

Complete AI assistant with WhatsApp, Voice, and local LLM.

### Step 1: Install Pre-built Binaries

```bash
# Download and install RunAnywhere
curl -fsSL https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/voice-assistant-v0.1.0/runanywhere-voice-assistant-linux-aarch64.tar.gz | tar -xzf - -C /tmp
cd /tmp/runanywhere-release && ./install.sh

# Fix library symlinks (REQUIRED)
cd ~/.local/runanywhere/lib && for lib in *.so; do ln -sf "$lib" "${lib}.1"; done
```

### Step 2: Download AI Models (~2.5GB)

```bash
# Download default model (qwen3-1.7b)
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/Playground/linux-voice-assistant/scripts/download-models.sh | bash

# For better quality (recommended for 8GB Pi), download qwen3-4b:
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/Playground/linux-voice-assistant/scripts/download-models.sh | bash -s -- --llm qwen3-4b
```

**Available LLM Models:**

| Model | Size | Context | Description |
|-------|------|---------|-------------|
| qwen3-0.6b | ~639MB | 32K | Smallest, fastest |
| qwen3-1.7b | ~1.8GB | 32K | Good balance |
| qwen3-4b | ~2.5GB | 32K | Best quality (recommended for 8GB Pi) |

### Step 3: Install Moltbot

```bash
# Clone
git clone https://github.com/RunanywhereAI/clawdbot.git ~/moltbot
cd ~/moltbot

# Install pnpm and dependencies
npm install -g pnpm
pnpm install
pnpm build
```

### Step 4: Run Moltbot Onboarding

```bash
cd ~/moltbot && pnpm moltbot onboard
```

**Answer the prompts as follows:**

| Prompt | Answer |
|--------|--------|
| Security warning - Continue? | **Yes** |
| Onboarding mode | **QuickStart** |
| Config handling | **Use existing values** |
| Model/auth provider | **Skip for now** |
| Filter models by provider | **All providers** |
| Default model | **Keep current** |
| Select channel | **WhatsApp (QR link)** or skip |
| Link WhatsApp now? | **Yes** (scan QR with your phone) |
| WhatsApp phone setup | **This is my personal phone number** |
| Your WhatsApp number | Enter your number (e.g., +15551234567) |
| Configure skills now? | **Yes** |
| Show Homebrew install? | **Yes** (or No) |
| Preferred node manager | **npm** |
| Install missing skill dependencies | **Skip for now** |
| API keys (GOOGLE_PLACES, etc.) | **No** for all (or add if you have them) |
| Enable hooks? | **Skip for now** |
| How to hatch your bot? | **Do this later** |

### Step 5: Configure RunAnywhere as Model Provider

Edit `~/.moltbot/moltbot.json` to add RunAnywhere as the model provider:

```bash
nano ~/.moltbot/moltbot.json
```

**Complete moltbot.json configuration:**

```json
{
  "meta": {
    "lastTouchedVersion": "2026.1.29",
    "lastTouchedAt": "2026-01-30T01:39:23.045Z"
  },
  "models": {
    "providers": {
      "runanywhere": {
        "baseUrl": "http://localhost:8080/v1",
        "apiKey": "local",
        "api": "openai-completions",
        "models": [
          {
            "id": "qwen3-4b",
            "name": "Qwen3 4B (Local)",
            "contextWindow": 16384,
            "maxTokens": 4096
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "runanywhere/qwen3-4b"
      },
      "compaction": {
        "mode": "safeguard"
      },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      },
      "workspace": "/home/runanywhere/clawd"
    }
  },
  "messages": {
    "ackReactionScope": "group-mentions"
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto"
  },
  "plugins": {
    "entries": {
      "runanywhere": {
        "enabled": true
      },
      "voice-assistant": {
        "enabled": true
      },
      "whatsapp": {
        "enabled": true
      }
    }
  },
  "gateway": {
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "YOUR_TOKEN_HERE"
    },
    "port": 18789,
    "bind": "loopback",
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    }
  },
  "channels": {
    "whatsapp": {
      "selfChatMode": true,
      "dmPolicy": "allowlist",
      "allowFrom": [
        "+YOUR_PHONE_NUMBER"
      ]
    }
  },
  "skills": {
    "install": {
      "nodeManager": "npm"
    },
    "entries": {}
  },
  "wizard": {
    "lastRunAt": "2026-01-30T01:39:23.032Z",
    "lastRunVersion": "2026.1.29",
    "lastRunCommand": "onboard",
    "lastRunMode": "local"
  }
}
```

**Key configuration sections explained:**

1. **models.providers.runanywhere**: Defines the local LLM server connection
   - `baseUrl`: RunAnywhere server endpoint (default: `http://localhost:8080/v1`)
   - `apiKey`: Set to `"local"` (must be non-empty for Moltbot to recognize the provider)
   - `api`: Must be `"openai-completions"` for compatibility
   - `models`: Array of available models with their capabilities

2. **models[].contextWindow**: **CRITICAL** - Must be at least 16384 (16K) for Moltbot
   - Moltbot requires minimum 16000 tokens context window
   - This must match the `--context` flag when starting RunAnywhere server

3. **agents.defaults.model.primary**: Sets the default model
   - Format: `"provider/model-id"` (e.g., `"runanywhere/qwen3-4b"`)
   - This tells Moltbot which model to use for AI responses

### Step 5b: Create Auth Profile (Required)

Create the auth profile file so Moltbot recognizes the RunAnywhere provider:

```bash
mkdir -p ~/.clawdbot/agents/main/agent
cat > ~/.clawdbot/agents/main/agent/auth-profiles.json << 'EOF'
{
  "version": 2,
  "profiles": {
    "runanywhere:default": {
      "type": "api_key",
      "provider": "runanywhere",
      "key": "local"
    }
  }
}
EOF
chmod 600 ~/.clawdbot/agents/main/agent/auth-profiles.json
```

### Step 6: Start Everything

**Terminal 1 - RunAnywhere Server:**

```bash
export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH

# For qwen3-4b (recommended for 8GB Pi):
~/.local/runanywhere/bin/runanywhere-server \
  --model ~/.local/share/runanywhere/Models/LlamaCpp/qwen3-4b/Qwen3-4B-Q4_K_M.gguf \
  --port 8080 \
  --threads 4 \
  --context 16384

# For qwen3-1.7b (if you have less RAM):
~/.local/runanywhere/bin/runanywhere-server \
  --model ~/.local/share/runanywhere/Models/LlamaCpp/qwen3-1.7b/Qwen3-1.7B-Q8_0.gguf \
  --port 8080 \
  --threads 4 \
  --context 16384
```

**RunAnywhere Server Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `--model, -m` | Path to GGUF model file | Required |
| `--port, -p` | Server port | 8080 |
| `--threads, -t` | CPU threads for inference | 4 |
| `--context, -c` | Context window size | 8192 |
| `--host, -H` | Host to bind to | 127.0.0.1 |
| `--verbose, -v` | Enable verbose logging | Off |

**Terminal 2 - Restart Moltbot Gateway:**

```bash
systemctl --user restart moltbot-gateway
systemctl --user status moltbot-gateway
```

**Terminal 3 - Voice Assistant (optional):**

```bash
export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH
~/.local/runanywhere/bin/voice-assistant --wakeword --moltbot
```

### Step 7: Test

- **Web UI:** http://127.0.0.1:18789 (use token from onboarding)
- **WhatsApp:** Send yourself a message
- **Voice:** Say "Hey Jarvis"

---

## Troubleshooting

### Error: "Model context window too small (8192 tokens). Minimum is 16000"

**Cause:** Moltbot requires at least 16K context window. The RunAnywhere server or moltbot.json config has a smaller context window.

**Fix:**
1. Start RunAnywhere server with `--context 16384`:
   ```bash
   ~/.local/runanywhere/bin/runanywhere-server \
     --model ~/.local/share/runanywhere/Models/LlamaCpp/qwen3-4b/Qwen3-4B-Q4_K_M.gguf \
     --context 16384 \
     --port 8080 --threads 4
   ```

2. Update `~/.moltbot/moltbot.json` to have `contextWindow: 16384`:
   ```json
   "models": [
     {
       "id": "qwen3-4b",
       "contextWindow": 16384,
       "maxTokens": 4096
     }
   ]
   ```

3. Restart gateway: `systemctl --user restart moltbot-gateway`

### Error: "libonnxruntime.so.1 not found"

**Cause:** Missing versioned library symlinks.

**Fix:**
```bash
cd ~/.local/runanywhere/lib
for lib in *.so; do ln -sf "$lib" "${lib}.1"; done
```

### Error: "Unrecognized keys" or "Invalid input" in moltbot.json

**Cause:** Incorrect config format.

**Common mistakes:**
```json
// WRONG - agents.defaults.models.default doesn't exist
"agents": {
  "defaults": {
    "models": {
      "default": { "provider": "runanywhere", "model": "qwen3-4b" }
    }
  }
}

// CORRECT - use model.primary as a string
"agents": {
  "defaults": {
    "model": {
      "primary": "runanywhere/qwen3-4b"
    }
  }
}
```

### Error: "Gateway not using local model"

**Symptom:** Logs show `agent model: anthropic/claude-opus-4-5` instead of `runanywhere/qwen3-4b`

**Fix:**
1. Ensure `agents.defaults.model.primary` is set correctly in moltbot.json
2. Restart gateway: `systemctl --user restart moltbot-gateway`
3. Check logs: `journalctl --user -u moltbot-gateway -n 20`

### Error: "No API key found for provider runanywhere"

**Cause:** Moltbot requires an auth profile for custom providers.

**Fix:**
1. Ensure `apiKey` in moltbot.json is set to `"local"` (not empty string `""`):
   ```json
   "runanywhere": {
     "baseUrl": "http://localhost:8080/v1",
     "apiKey": "local",
     ...
   }
   ```

2. Create the auth-profiles.json file:
   ```bash
   mkdir -p ~/.clawdbot/agents/main/agent
   cat > ~/.clawdbot/agents/main/agent/auth-profiles.json << 'EOF'
   {
     "version": 2,
     "profiles": {
       "runanywhere:default": {
         "type": "api_key",
         "provider": "runanywhere",
         "key": "local"
       }
     }
   }
   EOF
   chmod 600 ~/.clawdbot/agents/main/agent/auth-profiles.json
   ```

3. Restart gateway: `systemctl --user restart moltbot-gateway`

### No audio input

```bash
arecord -l  # List devices
~/.local/runanywhere/bin/voice-assistant --list-devices
```

### Model not found

```bash
# List downloaded models
ls -la ~/.local/share/runanywhere/Models/LlamaCpp/

# Download a specific model
cd ~/runanywhere-sdks/Playground/linux-voice-assistant
./scripts/download-models.sh --llm qwen3-4b
```

### Moltbot can't connect to RunAnywhere

1. Check RunAnywhere server is running:
   ```bash
   curl http://localhost:8080/health
   # Should return: {"model":"...","model_loaded":true,"status":"ok"}
   ```

2. Check config has correct baseUrl in `~/.moltbot/moltbot.json`:
   ```json
   "runanywhere": {
     "baseUrl": "http://localhost:8080/v1",
     ...
   }
   ```

3. Restart gateway: `systemctl --user restart moltbot-gateway`

### Check service logs

```bash
# Moltbot gateway logs
journalctl --user -u moltbot-gateway --no-pager -n 50
moltbot logs --follow

# RunAnywhere server logs (if running in background)
tail -f /tmp/runanywhere-server.log
```

### Memory issues on Raspberry Pi

Check available memory:
```bash
free -h
```

**Recommended configurations by RAM:**

| Pi RAM | Model | Context | Notes |
|--------|-------|---------|-------|
| 4GB | qwen3-0.6b | 8192 | Minimum viable |
| 8GB | qwen3-4b | 16384 | Recommended |
| 8GB | qwen3-1.7b | 32768 | Alternative with more context |

---

## Option 2: Pre-built Binaries (Standalone)

Simple voice assistant without Moltbot. No WhatsApp, no tools.

```bash
# Download and install
curl -fsSL https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/voice-assistant-v0.1.0/runanywhere-voice-assistant-linux-aarch64.tar.gz | tar -xzf - -C /tmp
cd /tmp/runanywhere-release && ./install.sh

# Fix library symlinks
cd ~/.local/runanywhere/lib && for lib in *.so; do ln -sf "$lib" "${lib}.1"; done

# Download AI models (~2.5GB)
curl -fsSL https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/smonga/rasp/Playground/linux-voice-assistant/scripts/download-models.sh | bash

# Run
~/.local/runanywhere/run.sh
```

---

## Option 3: Build from Source

For development or custom configurations.

### Prerequisites

```bash
sudo apt-get update
sudo apt-get install -y cmake build-essential libasound2-dev libpulse-dev git

# Node.js 22+ (for Moltbot)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### Build Steps

```bash
# Clone the SDK
git clone -b smonga/rasp https://github.com/RunanywhereAI/runanywhere-sdks.git ~/runanywhere-sdks
cd ~/runanywhere-sdks/sdk/runanywhere-commons

# Build SDK with shared libraries
./scripts/build-linux.sh --shared

# Build the server
mkdir -p build-server && cd build-server
cmake .. -DCMAKE_BUILD_TYPE=Release \
    -DRAC_BUILD_BACKENDS=ON \
    -DRAC_BUILD_SERVER=ON \
    -DRAC_BACKEND_LLAMACPP=ON \
    -DRAC_BACKEND_ONNX=ON \
    -DRAC_BACKEND_WHISPERCPP=OFF
make -j$(nproc)

# Build voice assistant
cd ~/runanywhere-sdks/Playground/linux-voice-assistant
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)

# Download models
cd ~/runanywhere-sdks/Playground/linux-voice-assistant
./scripts/download-models.sh
```

---

## What's Running

| Component | Port | Purpose |
|-----------|------|---------|
| runanywhere-server | 8080 | Local LLM inference |
| Moltbot gateway | 18789 | AI orchestration, WhatsApp, tools |
| Voice assistant | — | Wake word, STT, TTS |
| Voice gateway | 8082 | Voice assistant WebSocket bridge |

---

## Usage

Say **"Hey Jarvis"** to activate, then speak your question.

### Command Line Options

```
voice-assistant [options]
  --list-devices    List available audio devices
  --input <device>  Audio input device (default: "default")
  --output <device> Audio output device (default: "default")
  --wakeword        Enable wake word detection
  --moltbot         Enable Moltbot integration
  --moltbot-url     Moltbot voice bridge URL (default: "http://localhost:8082")
```

---

## Quick Reference

### Start/Stop Services

```bash
# Start RunAnywhere server (foreground)
export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH
~/.local/runanywhere/bin/runanywhere-server \
  --model ~/.local/share/runanywhere/Models/LlamaCpp/qwen3-4b/Qwen3-4B-Q4_K_M.gguf \
  --port 8080 --threads 4 --context 16384

# Start RunAnywhere server (background)
nohup ~/.local/runanywhere/bin/runanywhere-server \
  --model ~/.local/share/runanywhere/Models/LlamaCpp/qwen3-4b/Qwen3-4B-Q4_K_M.gguf \
  --port 8080 --threads 4 --context 16384 \
  > /tmp/runanywhere-server.log 2>&1 &

# Moltbot gateway
systemctl --user start moltbot-gateway
systemctl --user stop moltbot-gateway
systemctl --user restart moltbot-gateway
systemctl --user status moltbot-gateway

# View logs
journalctl --user -u moltbot-gateway -f
```

### Verify Setup

```bash
# Check RunAnywhere server
curl http://localhost:8080/health

# Check Moltbot gateway
curl http://localhost:18789/health

# Check which model is active
journalctl --user -u moltbot-gateway | grep "agent model"
```

---

## License

MIT
