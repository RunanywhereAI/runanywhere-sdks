# Android Use Agent

A fully on-device autonomous Android agent powered by the RunAnywhere SDK. Navigates your phone's UI to accomplish tasks using local LLM inference via llama.cpp -- no cloud dependency required.

## Demo

X post demo — Qwen3 4B, 6 steps, 3 real LLM inferences, goal-aware element filtering, ~4 min end-to-end.

<video src="https://raw.githubusercontent.com/RunanywhereAI/runanywhere-sdks/main/Playground/android-use-agent/assets/android_agent_muted.mp4" controls width="640"></video>

> Full write-up and run trace: [X_POST.md](X_POST.md)

## Architecture

The agent follows an observe-reason-act loop. Each step captures the current screen state, reasons about the next action using an on-device LLM, and executes that action via the Android Accessibility API.

```text
                         +---------------------+
                         |     User Goal       |
                         | "Play lofi on YT"   |
                         +----------+----------+
                                    |
                                    v
                         +---------------------+
                         |    Pre-Launch        |
                         | Intent-based app     |
                         | opening (YouTube,    |
                         | Settings, etc.)      |
                         +----------+----------+
                                    |
                    +===============+===============+
                    |         AGENT LOOP            |
                    |    (max 30 steps / 10 min)    |
                    +===============+===============+
                                    |
                    +---------------v---------------+
                    |      Self-Detection Guard     |
                    | If foreground == agent app,   |
                    | switch back to target app     |
                    +---------------+---------------+
                                    |
                    +---------------v---------------+
                    |   Accessibility Tree Parsing  |
                    |   (ScreenParser)              |
                    | Extracts interactive elements |
                    | as compact indexed list:      |
                    | "0: Search (EditText) [edit]" |
                    | "1: Home (Button) [tap]"      |
                    +---------------+---------------+
                                    |
                    +---------------v---------------+
                    |    Screenshot Capture          |
                    | Base64 JPEG via Accessibility  |
                    | API (half-res, 60% quality)    |
                    +---------------+---------------+
                                    |
                    +---------------v---------------+
                    |   Optional VLM Analysis       |
                    | LFM2-VL 450M analyzes the     |
                    | screenshot for visual context  |
                    +---------------+---------------+
                                    |
                    +---------------v---------------+
                    |    Prompt Construction         |
                    | GOAL + SCREEN_ELEMENTS +       |
                    | PREVIOUS_ACTIONS + LAST_RESULT |
                    | + VISION_HINT (if VLM active)  |
                    +---------------+---------------+
                                    |
                    +---------------v---------------+
                    |   Samsung Foreground Boost     |
                    | Bring agent to foreground      |
                    | during inference to avoid      |
                    | efficiency-core throttling     |
                    +---------------+---------------+
                                    |
                    +---------------v---------------+
                    |     On-Device LLM Inference   |
                    | RunAnywhere SDK + llama.cpp    |
                    | Produces <tool_call> XML or    |
                    | ui_func(args) function call    |
                    +---------------+---------------+
                                    |
                    +---------------v---------------+
                    |     Tool Call Parsing          |
                    | (ToolCallParser)               |
                    | Parses: <tool_call>{...}       |
                    | </tool_call>, ui_tap(index=5), |
                    | or JSON decision objects       |
                    +---------------+---------------+
                                    |
                    +---------------v---------------+
                    |     Action Execution          |
                    | (ActionExecutor)              |
                    | Tap, type, swipe, back, home  |
                    | via Accessibility gestures     |
                    +---------------+---------------+
                                    |
                    +---------------v---------------+
                    |   Loop Detection + Recovery   |
                    | Detects repeated actions,      |
                    | dismisses blocking dialogs,    |
                    | scrolls to reveal elements     |
                    +-------+-----------+-----------+
                            |           |
                  (continue)|    (done) |
                            |           v
                            |   +-------+-------+
                            |   |  Task Complete |
                            |   +---------------+
                            |
                            +----> (back to top of loop)
```

## Key Features

- **Fully on-device AI** -- RunAnywhere SDK with llama.cpp backend. All LLM inference runs locally on the device with no data sent to the cloud.
- **Multiple LLM models** -- Qwen3-4B (recommended), LFM2.5-1.2B, LFM2-8B-A1B MoE, DeepSeek-R1-Qwen3-8B, and LFM2-350M. Models are downloaded on first use.
- **Accessibility-based screen parsing** -- Reads the UI tree via Android's Accessibility API. No root required. Produces a compact indexed element list the LLM can reason over.
- **Tool calling with multiple format support** -- Parses `<tool_call>` XML tags, `ui_tap(index=5)` function-call style, inline `{"tool_call": {...}}` JSON, and legacy JSON decision objects.
- **Samsung foreground boost** -- On Samsung devices (OneUI), background processes are pinned to efficiency cores, causing a ~15x slowdown. The agent automatically brings itself to foreground during inference, then returns to the target app afterward.
- **Smart pre-launch via Android intents** -- Detects the target app from the user's goal and opens it directly via intent before the agent loop begins. Supports YouTube (with search), Spotify (with search), Chrome, Settings (with sub-pages), Clock (timers/alarms), and more.
- **Loop detection and smart recovery** -- Detects when the model repeats the same action and triggers recovery: dismissing blocking dialogs ("No thanks", "Skip", "Accept") or scrolling to reveal new elements.
- **Foreground service with WakeLock** -- `AgentForegroundService` keeps the CPU alive at full speed even when the agent navigates away from its own UI to control other apps.
- **Voice mode** -- On-device Whisper STT (via ONNX) for voice input and Android TTS for spoken progress updates.
- **Optional VLM for visual context** -- LFM2-VL 450M vision-language model analyzes screenshots to provide additional context to the LLM.
- **Optional GPT-4o cloud fallback** -- If an OpenAI API key is configured, the agent falls back to GPT-4o with vision and function calling when the local LLM fails.

## Model Benchmarks

All benchmarks on Samsung Galaxy S24 (Snapdragon 8 Gen 3, 8GB RAM) with foreground boost active.

| Model | Size | Speed (per step) | Element Selection | Agent Compatible |
|---|---|---|---|---|
| Qwen3-4B (/no_think) | 2.5 GB | 72-92s | Correct | Yes (Recommended) |
| LFM2.5-1.2B | 731 MB | 8-10s | Always index 0-2 | No |
| LFM2-8B-A1B MoE | 5.04 GB | 31-41s | Partially correct | No (multi-action plans) |
| DS-R1-Qwen3-8B | 5.03 GB | ~267s | Smart but format issues | No (too slow) |

Note: Qwen3-4B is the only model that reliably selects correct UI elements and follows the single-action-per-turn contract. The `/no_think` suffix disables chain-of-thought to prevent the model from consuming the entire token budget on reasoning. For full benchmarking details, see [ASSESSMENT.md](ASSESSMENT.md).

## Project Structure

```text
app/src/main/java/com/runanywhere/agent/
|-- AgentApplication.kt              # SDK init, model registry (LLM, STT, VLM)
|-- AgentForegroundService.kt        # Foreground service + PARTIAL_WAKE_LOCK
|-- AgentViewModel.kt                # UI state, voice mode, STT/TTS coordination
|-- MainActivity.kt                  # Entry point
|-- accessibility/
|   +-- AgentAccessibilityService.kt # Screen reading, screenshot capture, gesture execution
|-- actions/
|   +-- AppActions.kt                # Intent-based app launching (YouTube, Spotify, etc.)
|-- kernel/
|   |-- ActionExecutor.kt            # Executes tap/type/swipe/etc. via accessibility
|   |-- ActionHistory.kt             # Tracks actions for loop detection
|   |-- AgentKernel.kt               # Main agent loop, LLM orchestration, foreground boost
|   |-- GPTClient.kt                 # OpenAI API client (text + vision + tool calling)
|   |-- ScreenParser.kt              # Parses accessibility tree into indexed element list
|   +-- SystemPrompts.kt             # All LLM prompts (compact, tool-calling, vision)
|-- providers/
|   |-- AgentProviders.kt            # Provider mode enum (LOCAL, CLOUD_FALLBACK)
|   |-- OnDeviceLLMProvider.kt       # On-device LLM provider wrapper
|   +-- VisionProvider.kt            # VLM provider interface and implementation
|-- toolcalling/
|   |-- BuiltInTools.kt              # Utility tools (time, weather, calc, etc.)
|   |-- SimpleExpressionEvaluator.kt # Math expression evaluator for calculator tool
|   |-- ToolCallingTypes.kt          # ToolCall, ToolResult, LLMResponse sealed class
|   |-- ToolCallParser.kt            # Parses <tool_call> XML, function-call, and JSON formats
|   |-- ToolPromptFormatter.kt       # Converts tools to OpenAI format or compact local prompt
|   |-- ToolRegistry.kt              # Tool registration and execution
|   |-- UIActionContext.kt            # Shared mutable screen coordinates per step
|   |-- UIActionTools.kt             # 14 UI action tools (tap, type, swipe, etc.)
|   +-- UnitConverter.kt             # Unit conversion utility
|-- tools/
|   +-- UtilityTools.kt              # Additional utility tool definitions
|-- tts/
|   +-- TTSManager.kt                # Android TTS wrapper
+-- ui/
    |-- AgentScreen.kt               # Main Compose UI (text + voice modes)
    +-- components/
        |-- ModelSelector.kt          # Dropdown for model selection
        |-- ProviderBadge.kt          # Shows LOCAL / CLOUD indicator
        +-- StatusBadge.kt            # Shows IDLE / RUNNING / DONE status
```

## UI Action Tools

All UI actions are registered as tools that the LLM can invoke:

| Tool | Description |
|------|-------------|
| `ui_tap(index)` | Tap a UI element by its index from the element list |
| `ui_type(text)` | Type text into the focused/editable field |
| `ui_enter()` | Press Enter to submit a search query or form |
| `ui_swipe(direction)` | Scroll up/down/left/right |
| `ui_back()` | Press the Back button |
| `ui_home()` | Press the Home button |
| `ui_open_app(app_name)` | Launch an app by name via intent |
| `ui_long_press(index)` | Long press an element by index |
| `ui_open_url(url)` | Open a URL in the browser |
| `ui_web_search(query)` | Search Google |
| `ui_open_notifications()` | Open the notification shade |
| `ui_open_quick_settings()` | Open quick settings |
| `ui_wait()` | Wait for the screen to load |
| `ui_done(reason)` | Signal that the task is complete |

## Requirements

- Android 8.0+ (API 26)
- arm64-v8a device (on-device LLM inference requires 64-bit ARM)
- Accessibility service permission (for screen reading and gesture execution)
- (Optional) OpenAI API key for GPT-4o cloud fallback

## Setup

1. Place RunAnywhere SDK AARs in `libs/`.

2. (Optional) Add your OpenAI API key to `gradle.properties` for cloud fallback:
   ```text
   GPT52_API_KEY=sk-your-key-here
   ```

3. Build and install:
   ```bash
   ./gradlew assembleDebug
   adb install -r app/build/outputs/apk/debug/app-debug.apk
   ```

4. Enable the accessibility service: Settings > Accessibility > Android Use Agent.

5. Open the app, select a model (Qwen3-4B recommended), and enter a goal (e.g., "Open YouTube and search for lofi music"). Tap "Start Agent".

6. (Optional) Load the VLM model from the UI for enhanced visual understanding.

7. (Optional) Toggle Voice Mode to speak your goals via on-device Whisper STT.

## How It Works

1. **Goal input** -- The user enters a natural-language goal via text or voice.
2. **Pre-launch** -- The agent detects the target app from the goal and opens it directly via Android intent, skipping the need to find and tap app icons.
3. **Observe** -- The agent reads the current screen via the Accessibility API, producing a compact indexed list of interactive elements (buttons, text fields, checkboxes).
4. **Reason** -- The screen elements, goal, action history, and optional VLM context are assembled into a prompt. The on-device LLM reasons about the next action and emits a tool call.
5. **Act** -- The tool call is parsed and executed via accessibility gestures (tap at coordinates, type text, swipe, press back/home).
6. **Repeat** -- The loop continues until the LLM signals `ui_done`, the maximum step count (30) is reached, or the 10-minute timeout expires.

---

## Inspiration

This project was inspired by [android-action-kernel](https://github.com/Action-State-Labs/android-action-kernel) by Action State Labs.

---

Built by the RunAnywhere team.
For questions, reach out to san@runanywhere.ai
