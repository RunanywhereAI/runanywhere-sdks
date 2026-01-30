# Clawdbot/Moltbot Configuration for Local LLMs

This folder contains optimized configuration files for running [Moltbot](https://github.com/moltbot/moltbot) with local LLMs via RunAnywhere.

## Overview

These configs are designed for **resource-constrained devices** like Raspberry Pi where prompt size directly impacts response time. The total size is ~3.6KB (reduced from ~13KB default).

## Files

| File | Purpose | Size |
|------|---------|------|
| `IDENTITY.md` | Bot name, personality emoji | 156 bytes |
| `SOUL.md` | Core personality and behavior | 713 bytes |
| `AGENTS.md` | Workspace rules and memory management | 1,252 bytes |
| `USER.md` | User preferences and info | 481 bytes |
| `TOOLS.md` | Tool-specific notes | 858 bytes |
| `HEARTBEAT.md` | Heartbeat behavior config | 167 bytes |

## Usage

1. Copy these files to your Moltbot workspace directory (e.g., `~/clawd/`)
2. Update `IDENTITY.md` with your bot's name
3. Update `USER.md` with your info
4. Configure Moltbot to use RunAnywhere as provider:

```yaml
# ~/.clawdbot/config.yaml
agents:
  defaults:
    models:
      default:
        provider: runanywhere
        model: LFM2.5-1.2B-Instruct-Q8_0

models:
  providers:
    runanywhere:
      baseUrl: "http://localhost:8080/v1"
      apiKey: "local"
```

## Recommended Models

For Raspberry Pi 5 (8GB):
- **LFM 1.2B** - Best balance of speed and quality (2x faster on CPU)
- **Qwen3 0.6B** - Fastest, good for simple tasks

## Tips for Local LLMs

1. **Keep prompts small** - Every KB matters on CPU inference
2. **Disable unused features** - Heartbeats, web search, etc.
3. **Use 16K context** - Enough for most conversations
4. **Monitor with htop** - Watch for swap usage
