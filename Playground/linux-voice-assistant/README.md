# RunAnywhere Voice Assistant

On-device voice AI for Raspberry Pi 5 (Linux aarch64). Say **"Hey Jarvis"** to activate.

---

## Quick Start (Recommended)

Complete AI assistant with WhatsApp, Voice, and local LLM using **LFM 1.2B** model.

### Prerequisites

- Raspberry Pi 5 with 8GB RAM (4GB works with smaller models)
- Raspberry Pi OS Lite (64-bit) or Ubuntu 22.04+ ARM64
- Node.js 22+
- ~3GB disk space for models

### Step 1: Install RunAnywhere Binaries

```bash
# Download and install RunAnywhere
curl -fsSL https://github.com/RunanywhereAI/runanywhere-sdks/releases/download/voice-assistant-v0.1.0/runanywhere-voice-assistant-linux-aarch64.tar.gz | tar -xzf - -C /tmp
cd /tmp/runanywhere-release && ./install.sh

# Fix library symlinks (REQUIRED)
cd ~/.local/runanywhere/lib && for lib in *.so; do ln -sf "$lib" "${lib}.1"; done
```

### Step 2: Download AI Models

```bash
# Download LFM 1.2B (recommended - fast and efficient)
mkdir -p ~/.local/share/runanywhere/Models/LlamaCpp/lfm2.5-1.2b
curl -L -o ~/.local/share/runanywhere/Models/LlamaCpp/lfm2.5-1.2b/LFM2.5-1.2B-Instruct-Q8_0.gguf \
  "https://huggingface.co/lmstudio-community/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q8_0.gguf"

# Or download Qwen3 1.7B (alternative - slightly better quality)
mkdir -p ~/.local/share/runanywhere/Models/LlamaCpp/qwen3-1.7b
curl -L -o ~/.local/share/runanywhere/Models/LlamaCpp/qwen3-1.7b/Qwen3-1.7B-Q8_0.gguf \
  "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf"
```

**Available Models:**

| Model | Size | Speed | Quality | Recommended For |
|-------|------|-------|---------|-----------------|
| **LFM 1.2B (Q8)** | ~1.3GB | Fast | Good | Pi 5 8GB (recommended) |
| Qwen3 1.7B (Q8) | ~1.8GB | Medium | Better | Pi 5 8GB |
| Qwen3 4B (Q4) | ~2.5GB | Slow | Best | Pi 5 8GB (patient users) |

### Step 3: Install Moltbot (RunAnywhere Fork)

```bash
# Clone the RunAnywhere fork
git clone https://github.com/RunanywhereAI/clawdbot.git ~/moltbot
cd ~/moltbot

# Install pnpm and dependencies
npm install -g pnpm
pnpm install
pnpm build
```

### Step 4: Configure Moltbot for Local LLM

The configuration file is `~/.clawdbot/moltbot.json`. Create it with these optimized settings:

```bash
mkdir -p ~/.clawdbot/agents/main/agent
cat > ~/.clawdbot/moltbot.json << 'EOF'
{
  "meta": {
    "lastTouchedVersion": "2026.1.29"
  },
  "models": {
    "providers": {
      "runanywhere": {
        "baseUrl": "http://localhost:8080/v1",
        "apiKey": "local",
        "api": "openai-completions",
        "models": [
          {
            "id": "LFM2.5-1.2B-Instruct-Q8_0",
            "name": "Lobster Brain (LFM 1.2B)",
            "contextWindow": 16384,
            "maxTokens": 4096,
            "reasoning": false,
            "input": ["text"],
            "cost": {
              "input": 0,
              "output": 0,
              "cacheRead": 0,
              "cacheWrite": 0
            }
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "runanywhere/LFM2.5-1.2B-Instruct-Q8_0"
      },
      "promptMode": "local",
      "compaction": {
        "mode": "safeguard"
      },
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      }
    }
  },
  "messages": {
    "ackReactionScope": "group-mentions"
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto"
  },
  "gateway": {
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "YOUR_SECURE_TOKEN_HERE"
    }
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
  "heartbeat": {
    "enabled": false
  }
}
EOF
```

**Critical Configuration Settings:**

| Setting | Value | Purpose |
|---------|-------|---------|
| `promptMode` | `"local"` | **Reduces system prompt from ~30KB to ~8KB** (72% reduction) |
| `contextWindow` | `16384` | Minimum required by Moltbot (must match server `--context`) |
| `apiKey` | `"local"` | Must be non-empty for provider recognition |
| `gateway.mode` | `"local"` | Required for gateway to start |

### Step 5: Create Auth Profile

```bash
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

### Step 6: Start Services

**Terminal 1 - RunAnywhere LLM Server:**

```bash
export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH

# For LFM 1.2B (recommended):
~/.local/runanywhere/bin/runanywhere-server \
  --model ~/.local/share/runanywhere/Models/LlamaCpp/lfm2.5-1.2b/LFM2.5-1.2B-Instruct-Q8_0.gguf \
  --host 0.0.0.0 \
  --port 8080 \
  --threads 4 \
  --context 16384
```

**Terminal 2 - Moltbot Gateway:**

```bash
cd ~/moltbot
pnpm moltbot gateway run
# Or use systemd: systemctl --user start moltbot-gateway
```

**Terminal 3 - Voice Assistant (optional):**

```bash
export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH
~/.local/runanywhere/bin/voice-assistant --wakeword --moltbot
```

### Step 7: Verify Setup

```bash
# Check LLM server
curl http://localhost:8080/v1/models
# Should show: {"data":[{"id":"LFM2.5-1.2B-Instruct-Q8_0",...}]}

# Check Moltbot gateway logs
journalctl --user -u moltbot-gateway | grep "agent model"
# Should show: agent model: runanywhere/LFM2.5-1.2B-Instruct-Q8_0

# Check prompt mode is applied
# First message should show reduced token count (~2500 vs ~7800)
```

---

## Key Optimizations for Raspberry Pi

### 1. `promptMode: "local"` (Critical)

This setting reduces the system prompt size dramatically:

| Mode | Prompt Size | Tokens | Inference Time |
|------|-------------|--------|----------------|
| `"full"` | ~30KB | ~7,800 | 5-10+ minutes |
| `"local"` | ~8KB | ~2,500 | 1-2 minutes |

**What `"local"` mode removes:**
- CLI command reference
- Skills listing (loaded on-demand)
- Memory recall instructions
- Self-update instructions
- Model alias documentation
- Sandbox details

**What `"local"` mode keeps:**
- Tool list with descriptions
- Workspace context
- User identity
- Project context files
- Silent reply handling
- Runtime info

### 2. Context Window Configuration

Both the server and config must use matching context sizes:

```bash
# Server must use --context 16384
runanywhere-server --context 16384 ...

# Config must have contextWindow: 16384
"contextWindow": 16384
```

### 3. n_batch Optimization

The SDK includes a fix that sets `n_batch = context_size` instead of the default 512 limit. This allows the full prompt to be processed in a single batch.

---

## Configuration Reference

### Config File Location

Moltbot uses `~/.clawdbot/moltbot.json` as the primary config file.

⚠️ **Note:** There may be a legacy `~/.moltbot/` directory from older versions. If you see unexpected behavior, check that directory doesn't contain conflicting settings.

### Model Provider Configuration

```json
"models": {
  "providers": {
    "runanywhere": {
      "baseUrl": "http://localhost:8080/v1",
      "apiKey": "local",
      "api": "openai-completions",
      "models": [
        {
          "id": "LFM2.5-1.2B-Instruct-Q8_0",
          "name": "Lobster Brain (LFM 1.2B)",
          "contextWindow": 16384,
          "maxTokens": 4096,
          "reasoning": false,
          "input": ["text"],
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
```

### Agent Defaults

```json
"agents": {
  "defaults": {
    "model": {
      "primary": "runanywhere/LFM2.5-1.2B-Instruct-Q8_0"
    },
    "promptMode": "local",
    "compaction": { "mode": "safeguard" },
    "maxConcurrent": 4,
    "subagents": { "maxConcurrent": 8 }
  }
}
```

### RunAnywhere Server Options

| Option | Description | Default | Recommended |
|--------|-------------|---------|-------------|
| `--model, -m` | Path to GGUF model file | Required | — |
| `--port, -p` | Server port | 8080 | 8080 |
| `--threads, -t` | CPU threads | 4 | 4 |
| `--context, -c` | Context window | 8192 | **16384** |
| `--host, -H` | Host to bind | 127.0.0.1 | 0.0.0.0 |

---

## Troubleshooting

### Error: "Model context window too small (8192 tokens). Minimum is 16000"

**Cause:** Moltbot requires 16K+ context window.

**Fix:**
1. Start server with `--context 16384`
2. Set `contextWindow: 16384` in moltbot.json
3. Restart gateway

### Error: "agent model: anthropic/claude-opus-4-5" (wrong model)

**Cause:** Missing or incorrect `agents.defaults.model.primary` or provider config.

**Fix:**
1. Ensure `models.providers.runanywhere` is defined in moltbot.json
2. Ensure `agents.defaults.model.primary` is set to `"runanywhere/MODEL_ID"`
3. Restart gateway: `systemctl --user restart moltbot-gateway`

### Error: "No API key found for provider runanywhere"

**Cause:** Missing auth profile or empty apiKey.

**Fix:**
1. Set `"apiKey": "local"` in provider config (not empty string)
2. Create `~/.clawdbot/agents/main/agent/auth-profiles.json` with the runanywhere profile

### Session caching wrong model

**Symptom:** Changed config but still using old model.

**Cause:** Sessions cache model and provider settings.

**Fix:**
```bash
# Clear session cache
mv ~/.clawdbot/agents/main/sessions/*.json ~/.clawdbot/agents/main/sessions/backup/
mv ~/.clawdbot/agents/main/sessions/*.jsonl ~/.clawdbot/agents/main/sessions/backup/
systemctl --user restart moltbot-gateway
```

### Legacy config directory conflict

**Symptom:** Config changes not being applied.

**Cause:** Both `~/.moltbot/` and `~/.clawdbot/` exist with different settings.

**Fix:**
```bash
# Backup and remove legacy directory
mv ~/.moltbot ~/.moltbot.backup
systemctl --user restart moltbot-gateway
```

### Slow inference (5-10+ minutes)

**Cause:** Large system prompt (~30KB).

**Fix:**
1. Set `"promptMode": "local"` in agents.defaults
2. Restart gateway
3. First message should now be much faster

### libonnxruntime.so.1 not found

**Fix:**
```bash
cd ~/.local/runanywhere/lib
for lib in *.so; do ln -sf "$lib" "${lib}.1"; done
```

---

## Templates

Pre-configured templates are available in the [moltbot repo](https://github.com/RunanywhereAI/clawdbot/tree/main/templates/local-llm):

```bash
# Copy templates to your config
cp ~/moltbot/templates/local-llm/moltbot.json ~/.clawdbot/moltbot.json
cp ~/moltbot/templates/local-llm/workspace/*.md ~/clawd/
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     User Interfaces                          │
├────────────────┬─────────────────┬──────────────────────────┤
│  Voice (8082)  │  WhatsApp       │  Web UI (18789)          │
└───────┬────────┴────────┬────────┴─────────────┬────────────┘
        │                 │                      │
        └─────────────────┼──────────────────────┘
                          │
              ┌───────────▼───────────┐
              │   Moltbot Gateway     │
              │   (Port 18789)        │
              │                       │
              │  - Agent orchestration│
              │  - Tool execution     │
              │  - Prompt management  │
              │  - Session handling   │
              └───────────┬───────────┘
                          │
              ┌───────────▼───────────┐
              │  RunAnywhere Server   │
              │  (Port 8080)          │
              │                       │
              │  - LLM inference      │
              │  - OpenAI-compatible  │
              │  - llama.cpp backend  │
              └───────────────────────┘
```

---

## Memory Requirements

| Pi RAM | Model | Context | Expected Performance |
|--------|-------|---------|---------------------|
| 4GB | LFM 1.2B | 8192 | Marginal |
| 8GB | LFM 1.2B | 16384 | **Good** (recommended) |
| 8GB | Qwen3 1.7B | 16384 | Good |
| 8GB | Qwen3 4B | 16384 | Slow but best quality |

---

## SDK Changes for Local LLM Support

The following changes were made to the RunAnywhere SDK to support local LLM inference:

1. **n_batch fix** (`llamacpp_backend.cpp`): Changed `n_batch` from capped at 512 to use full context size
2. **Context flag fix** (`http_server.cpp`): Server now properly passes `--context` flag to LlamaCPP backend
3. **Debug logging** (`openai_handler.cpp`): Added prompt analysis logging for debugging

---

## Quick Reference

### Start/Stop Services

```bash
# LLM Server (foreground)
export LD_LIBRARY_PATH=~/.local/runanywhere/lib:$LD_LIBRARY_PATH
~/.local/runanywhere/bin/runanywhere-server \
  --model ~/.local/share/runanywhere/Models/LlamaCpp/lfm2.5-1.2b/LFM2.5-1.2B-Instruct-Q8_0.gguf \
  --port 8080 --threads 4 --context 16384

# Moltbot Gateway
systemctl --user start moltbot-gateway
systemctl --user stop moltbot-gateway
systemctl --user restart moltbot-gateway

# View logs
journalctl --user -u moltbot-gateway -f
```

### Verify Configuration

```bash
# Check model
curl -s http://localhost:8080/v1/models | grep id

# Check gateway model
journalctl --user -u moltbot-gateway | grep "agent model"

# Check config
cat ~/.clawdbot/moltbot.json | grep -E '"primary"|"promptMode"|"contextWindow"'
```

---

## License

MIT
