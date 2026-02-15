# Android Use Agent

An autonomous Android agent that navigates your phone's UI to accomplish tasks. Combines on-device AI (RunAnywhere SDK) with GPT-4o Vision for intelligent screen understanding and action execution.

## Features

- **Autonomous UI Navigation** — Taps, types, swipes, and navigates apps to complete goals
- **GPT-4o Vision (VLM)** — Screenshots sent to GPT-4o for visual understanding of the screen
- **Unified Tool Calling** — All 14 UI actions (tap, type, swipe, open, etc.) registered as proper OpenAI function calling tools
- **On-Device Fallback** — Falls back to local LLM via RunAnywhere SDK when GPT-4o is unavailable
- **Voice Mode** — Speak your goal via on-device Whisper STT, hear progress via TTS
- **Built-in Tools** — Time, weather, calculator, device info, and more via function calling
- **Smart Pre-Launch** — Detects target app from goal and launches it before the agent loop
- **Loop & Failure Recovery** — Detects repeated actions and failed attempts, adjusts prompts

## Architecture

```
User Goal → Agent Kernel → Screen Parser (Accessibility) → LLM Decision → Action Executor
                ↑                                              ↓
           Action History ←────────────────────────────────────┘
```

**Tool Calling Flow (GPT-4o):**
```
GPT-4o → tool_calls → ui_* tool? → ActionExecutor → result → next step
                     → utility tool? → execute → feed result back → GPT-4o decides next
```

**Fallback Flow (Local LLM):**
```
Local LLM → JSON action → parse → Decision → ActionExecutor → result → next step
```

## Project Structure

```
app/src/main/java/com/runanywhere/agent/
├── AgentApplication.kt          # App config, available models
├── AgentViewModel.kt            # UI state, voice mode, STT/TTS
├── MainActivity.kt              # Entry point
├── accessibility/
│   └── AgentAccessibilityService.kt  # Screen reading, screenshot capture, action execution
├── actions/
│   └── AppActions.kt            # Intent-based app launching
├── kernel/
│   ├── ActionExecutor.kt        # Executes tap/type/swipe/etc via accessibility
│   ├── ActionHistory.kt         # Tracks actions for loop detection
│   ├── AgentKernel.kt           # Main agent loop, LLM orchestration
│   ├── GPTClient.kt             # OpenAI API client (text + vision + tools)
│   ├── ScreenParser.kt          # Parses accessibility tree into element list
│   └── SystemPrompts.kt         # All LLM prompts (text, vision, tool-calling)
├── toolcalling/
│   ├── BuiltInTools.kt          # Utility tools (time, weather, calc, etc.)
│   ├── ToolCallingTypes.kt      # ToolCall, ToolResult, LLMResponse sealed class
│   ├── ToolCallParser.kt        # Parses <tool_call> tags from local LLM
│   ├── ToolPromptFormatter.kt   # Converts tools to OpenAI format / local prompt
│   ├── ToolRegistry.kt          # Tool registration and execution
│   ├── UIActionContext.kt       # Shared mutable screen coordinates
│   └── UIActionTools.kt         # 14 UI action tools (tap, type, swipe, etc.)
├── tts/
│   └── TTSManager.kt            # Android TTS wrapper
└── ui/
    ├── AgentScreen.kt           # Main Compose UI (text + voice modes)
    └── components/              # ModelSelector, StatusBadge
```

## Requirements

- Android 8.0+ (API 26)
- arm64-v8a device
- Accessibility service permission
- (Optional) OpenAI API key for GPT-4o Vision + tool calling

## Setup

1. Place RunAnywhere SDK AARs in `libs/`
2. (Optional) Add your OpenAI API key to `gradle.properties`:
   ```
   GPT52_API_KEY=sk-your-key-here
   ```
3. Build and install:
   ```bash
   ./gradlew assembleDebug
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```
4. Enable the accessibility service in Settings > Accessibility > Android Use Agent
5. Enter a goal (e.g., "Open YouTube and search for lofi music") and tap Start

## UI Action Tools

All UI actions are registered as OpenAI function calling tools:

| Tool | Description |
|------|-------------|
| `ui_tap(index)` | Tap a UI element by index |
| `ui_type(text)` | Type text into focused field |
| `ui_enter()` | Press Enter/Submit |
| `ui_swipe(direction)` | Scroll up/down/left/right |
| `ui_back()` | Press Back button |
| `ui_home()` | Press Home button |
| `ui_open_app(app_name)` | Launch an app by name |
| `ui_long_press(index)` | Long press an element |
| `ui_open_url(url)` | Open a URL in browser |
| `ui_web_search(query)` | Search Google |
| `ui_wait()` | Wait for screen to load |
| `ui_done(reason)` | Signal task completion |
