# On-Device LLM Benchmarks for Autonomous Android Agents

A benchmarking study comparing five on-device LLM models running an autonomous Android agent. All inference runs locally on a Samsung Galaxy S24 with zero cloud dependency, using the RunAnywhere SDK with a llama.cpp backend.

## Device Specifications

| Spec | Detail |
|------|--------|
| Device | Samsung Galaxy S24 (SM-S931U1) |
| SoC | Qualcomm Snapdragon 8 Gen 3 (SM8650) |
| CPU | 1x Cortex-X4 @ 3.39 GHz + 3x Cortex-A720 @ 3.1 GHz + 4x Cortex-A520 @ 2.27 GHz |
| GPU | Adreno 750 |
| RAM | 8 GB LPDDR5X |
| OS | Android 16 (One UI 7) |
| Inference Backend | llama.cpp (GGUF Q4_K_M quantization) via RunAnywhere SDK |
| Agent Framework | Android Use Agent (Accessibility API-based) |

---

## Models Tested

| Model | Architecture | Total Params | Active Params | Quantization | GGUF Size |
|-------|-------------|-------------|--------------|-------------|-----------|
| LFM2-350M (Base) | Dense Transformer (Liquid) | 350M | 350M | Q4_K_M | 229 MB |
| LFM2.5-1.2B Instruct | Dense Transformer (Liquid) | 1.2B | 1.2B | Q4_K_M | 731 MB |
| Qwen3-4B | Dense Transformer | 4B | 4B | Q4_K_M | 2.5 GB |
| LFM2-8B-A1B MoE | Mixture of Experts (Liquid) | 8.3B | 1.5B | Q4_K_M | 5.04 GB |
| DS-R1-Qwen3-8B | Dense Transformer (DeepSeek-R1 distill) | 8B | 8B | Q4_K_M | 5.03 GB |

All models were tested in **LLM-only mode** (no VLM). The VLM (LFM2-VL 450M) was tested separately with the 1.2B model and found to be ineffective -- see [VLM Analysis](#vlm-analysis-lfm2-vl-450m) below.

---

## Test Protocol

**Task**: "Open X and tap the post button"

This task requires the agent to:
1. Confirm the X (Twitter) app is open
2. Parse the accessibility tree to find the "New post" FAB button
3. Output a single tool call targeting the correct element index
4. Execute the tap action

The task is representative of typical agent use: navigating an app and interacting with a specific UI element that is not at the top of the element list (typically index 11-19 depending on feed state).

**Agent Configuration**:
- Max steps: 30, timeout: 10 minutes
- Accessibility tree: up to 25 elements, 40 chars per label
- Pre-launch: X opened via intent before agent loop
- Tool format: `<tool_call>{"tool":"ui_tap","arguments":{"index":N}}</tool_call>`

---

## Results Summary

| Model | Steps to Complete | Time per Step | Total Time | Element Selection | Tool Format | Result |
|-------|------------------|--------------|-----------|-------------------|-------------|--------|
| **Qwen3-4B** (/no_think) | **3** | **67-85s** | **~3.8 min** | **Correct** | **Valid** | **PASS** |
| LFM2-8B-A1B MoE | 19 (timeout) | 29-43s | 10 min | Partially correct | Multi-action plans | FAIL |
| LFM2.5-1.2B | 30 (max steps) | 8-14s | 10+ min | Always index 2 | Valid | FAIL |
| DS-R1-Qwen3-8B | 1 (premature stop) | ~197s | ~3.3 min | Smart but trapped in reasoning | Inside `<think>` tags | FAIL |
| LFM2-350M (Base) | 2 (format failure) | 7-12s | ~20s | Incorrect | Cannot follow format | FAIL |

**Qwen3-4B with `/no_think` is the only model that successfully completes the task.**

---

## Detailed Results

### Qwen3-4B (PASS)

**Configuration**: Q4_K_M (2.5 GB), maxTokens=512, TOOL_CALLING_SYSTEM_PROMPT, `/no_think` appended to suppress chain-of-thought

| Step | Screen State | LLM Output | Tokens | Time | Result |
|------|-------------|-----------|--------|------|--------|
| 1 | X feed (22 elements) | `ui_open_app("X")` | ~19 | 67s | OK (redundant, X already open) |
| 2 | X feed (22 elements) | `ui_tap(15)` | ~19 | 76s | **Correct -- tapped FAB post button at (948, 1896)** |
| 3 | X feed (22 elements) | `ui_done("Tapped the post button in X.")` | ~24 | 85s | **Task complete** |

Element 15 was the floating action button for composing a new post, located at the bottom-right of the screen (coordinates 948, 1896). Element index varies by run (11-19) based on feed content visible in the accessibility tree.

**Why it works**:
- `/no_think` keeps output concise (19-24 tokens vs 381 with think mode enabled)
- 4B parameters provide sufficient reasoning to match "post button" to the FAB element
- `TOOL_CALLING_SYSTEM_PROMPT` gives detailed tool instructions the model follows
- `maxElements=25` ensures the FAB button appears in the element list (it has a high index)

**Performance**:
- Token generation rate: ~4 tok/s
- Prompt eval rate: ~6-7 tok/s
- Step latency dominated by prompt evaluation (~450 input tokens)
- RAM usage: ~2.5 GB (stable on 8 GB device)

**Qwen3-4B with think mode enabled (separate test)**: The model's chain-of-thought reasoning was excellent -- it correctly analyzed screens, identified goals, and planned actions. However, `<think>` consumed 95%+ of the 384-token budget, leaving no room for the tool call. When the model did produce a tool call (2 out of 5 steps), the chosen action was correct. This confirms the model has the reasoning capability; `/no_think` is required to make it actionable within the token budget.

---

### LFM2.5-1.2B Instruct (FAIL)

**Configuration**: Q4_K_M (731 MB), maxTokens=256, COMPACT_SYSTEM_PROMPT

| Step | Correct Element | LLM Chose | Result |
|------|----------------|-----------|--------|
| 1 | `14: New post (ImageButton)` | `index 2` (Timeline settings) | Wrong |
| 2 | `0: Navigate up` | `index 2` ("Nothing here yet") | Wrong |
| 3 | Loop detected | Recovery: scrolled | -- |
| 4 | `0: Navigate up` | `index 1` (Post text) | Accidentally navigated back |
| 5 | `11: New post (ImageButton)` | `index 1` (Show drawer) | Wrong |
| 6 | Loop detected | Recovery: scrolled | -- |
| 7 | `0: Navigate up` | `index 2` | Back to feed |
| ... | ... | Always index 2 | -- |
| 30 | `12: New post (ImageButton)` | `index 2` | **Max steps hit** |

**The model never selected the correct element across 30 attempts.** It consistently outputs indices 0, 1, or 2 regardless of the goal, screen state, or prompt content. This is a fundamental capacity limitation -- a 1.2B parameter model cannot reliably match a natural-language goal ("tap the post button") to the correct element in a list of 22-25 options.

**Performance**: 2.4-3.0 tok/s generation, ~15 tok/s prompt eval, 8-14s per step. Fast inference, but useless output.

---

### LFM2-8B-A1B MoE (FAIL)

**Configuration**: Q4_K_M (5.04 GB), 8.3B total / 1.5B active params, maxTokens=512, TOOL_CALLING_SYSTEM_PROMPT

| Step | Time | First Parsed Action | Screen Context | Result |
|------|------|-------------------|----------------|--------|
| 1 | 31s | `ui_open_app(X)` | X feed, 25 elements | No-op (X already open) |
| 2 | 32s | `ui_tap(18)` | X feed, 25 elements | Tapped bottom nav area |
| 3 | 33s | `ui_open_app(X)` | X feed, 20 elements (14=New post) | No-op (correct tap in plan but not executed) |
| 4 | 32s | `ui_tap(14)` | X feed, 20 elements (14=New post) | **Correct -- tapped FAB** |
| 5 | 36s | `ui_tap(14)` | Expanded FAB (14=Go Live) | Wrong -- index shifted after menu expanded |
| 6-19 | 29-43s | Various | Stuck on Grok page | Recovery loop → timeout |

**Failure mode: Multi-action planning.** The model outputs 3-6 tool calls per response (e.g., `ui_open_app(X)` then `ui_tap(14)` then `ui_done()`), but the agent loop executes only the first call per step. In most steps, the first call was `ui_open_app(X)` -- a no-op since X was already open. The correct `ui_tap` calls were second or third in the plan and never executed.

Step 4 demonstrates the model CAN identify the correct element. When `ui_tap(14)` was emitted as the first action, it correctly targeted "New post (ImageButton)."

**Performance**: 29-43s per step thanks to MoE architecture (only 1.5B active params per token). Generation rate ~5-6 tok/s, prompt eval ~3-4 tok/s. Memory: ~5 GB. Hit 10-minute timeout at step 19.

**Potential fix**: Prompt engineering to enforce single-action output, or modifying the agent loop to execute multi-step plans.

---

### DS-R1-Qwen3-8B (FAIL)

**Configuration**: Q4_K_M (5.03 GB), dense 8B params, maxTokens=512, TOOL_CALLING_SYSTEM_PROMPT

The agent ran for a single step (197 seconds / 213 tokens / 1.08 tok/s) before prematurely terminating.

**LLM output (truncated)**:
```text
1. Open the X app.
2. Tap the post button.

First action: Open X app.
tool: ui_open_app
arguments: {"app_name": "X"}
</think>
{"tool":"ui_open_app","arguments":{"app_name":"X"}}
</think>
The X app is now open. I need to find the post button.
Looking at the screen elements...
Element 20: Try Voice Mode (Button) [tap] -- not the post button.
Element 16: Create Images (Button) [tap] -- might be related...
...
Perhaps the post button is for creating a new [TOKEN LIMIT]
```

**Three compounding failures**:

1. **Too slow**: Dense 8B inference at ~1.08 tok/s means 197 seconds for 213 tokens. A 10-step task would take 30+ minutes.

2. **Reasoning cannot be suppressed**: The model ID contains "qwen" so `/no_think` was appended, but DS-R1 is a DeepSeek-R1 distillation into Qwen3-8B. The reasoning behavior comes from the R1 distillation, not Qwen3's think mode, so `/no_think` has no effect.

3. **Inner agent loop hallucination**: The model simulates executing its own plan within a single output -- it outputs a tool call, then continues as if the action was executed and starts analyzing the "next" screen from memory. This hallucinated inner loop consumes the entire token budget.

**Notably, the reasoning quality is the best of all tested models.** The model correctly planned a two-step approach, methodically analyzed each screen element, and correctly concluded the Grok page does not have a post button. The intelligence is there; the format and speed are not.

---

### LFM2-350M Base (FAIL) ⭐ New

**Configuration**: Q4_K_M (229 MB), maxTokens=256, COMPACT_SYSTEM_PROMPT

| Step | Time | LLM Output | Parsed As | Result |
|------|------|-----------|-----------|--------|
| 1 | ~12s | Narrative instructions mentioning `UI_open_app(YCombinator...)` with `ui_tap("OK")` | `ui_tap(index=OK)` (non-numeric) | Error: index parameter required |
| 2 | ~7s | 905-char narrative explaining a 5-step plan; no tool call | Heuristic: `done` | Premature termination |

**Total runtime: ~20 seconds. Task: FAIL.**

**Failure mode: Cannot follow tool calling format.** The 350M model generates extended natural-language explanations of what it would do rather than structured tool calls. In step 1, the parser found a text inside backticks resembling `ui_tap("OK")` -- a non-numeric "index" that failed validation. In step 2, the model produced only narrative text (905 characters describing a 5-step plan), and the heuristic parser's detection of the word "done" in the text caused premature termination.

**The model cannot distinguish between describing an action and performing one.** It narrates steps like a user manual ("Tap the Y Combinator button. Tap Open to launch.") instead of emitting `<tool_call>` JSON or even a function-call like `ui_tap(index=16)`.

**Performance**:
- Model size: 229 MB (smallest tested)
- Step latency: 7-12s per step (fastest on-device model tested)
- Estimated generation rate: ~18-25 tok/s (3x faster than 1.2B)
- Prompt eval: Very fast due to minimal parameter count

**Why it fails**: At 350M parameters with no instruction-tuning fine-tuning for structured output, the model lacks the capacity to reliably emit JSON or function-call formatted responses. This is not a format compliance issue fixable by prompt engineering -- the model simply doesn't have enough capacity to follow multi-rule output constraints while also reasoning about the task.

---

## Performance Comparison

### Inference Speed

| Model | Generation Rate | Prompt Eval Rate | Step Latency | Steps/min |
|-------|---------------|-----------------|-------------|-----------|
| LFM2-350M (Base) | ~18-25 tok/s | Very fast | 7-12s | ~6-7 |
| LFM2.5-1.2B | 2.4-3.0 tok/s | ~15 tok/s | 8-14s | ~5 |
| LFM2-8B-A1B MoE | ~5-6 tok/s | ~3-4 tok/s | 29-43s | ~1.7 |
| Qwen3-4B (/no_think) | ~4 tok/s | ~6-7 tok/s | 67-85s | ~0.8 |
| Qwen3-4B (think ON) | 4.28 tok/s | ~6-7 tok/s | 89-120s | ~0.6 |
| DS-R1-Qwen3-8B | ~1.08 tok/s | ~1.5 tok/s | ~197s | ~0.3 |

MoE architecture gives LFM2-8B-A1B generation speed comparable to a 1.5B dense model despite having 8.3B total parameters. The Snapdragon 8 Gen 3's NPU and large L3 cache benefit smaller active parameter counts. The 350M model is fastest but unusable.

### Memory Usage

| Model | GGUF Size | RAM Usage | Fits 8 GB Device |
|-------|-----------|-----------|-------------------|
| LFM2-350M (Base) | 229 MB | ~229 MB | Yes (minimal) |
| LFM2.5-1.2B | 731 MB | ~731 MB | Yes (comfortable) |
| Qwen3-4B | 2.5 GB | ~2.5 GB | Yes |
| LFM2-8B-A1B MoE | 5.04 GB | ~5 GB | Yes (tight) |
| DS-R1-Qwen3-8B | 5.03 GB | ~5 GB | Yes (tight) |

All models load and run stably on the 8 GB Galaxy S24. The 5 GB models leave limited headroom for other apps.

### Samsung Background CPU Throttling

| Scheduling | Inference Rate | Impact |
|-----------|---------------|--------|
| Background (efficiency cores only) | 0.19 tok/s | Unusable -- 2+ minutes per LLM call |
| Foreground (all cores available) | 2.4-25 tok/s | 15-17x improvement |

Samsung's One UI scheduler pins background processes to Snapdragon 8 Gen 3 efficiency cores (Cortex-A520 @ 2.27 GHz). The agent's foreground boost workaround brings the app to the foreground during inference, then switches back to the target app afterward. This is a **mandatory optimization** for any on-device LLM application on Samsung devices.

---

## VLM Analysis (LFM2-VL 450M)

The LFM2-VL 450M vision-language model was tested separately with the 1.2B LLM. **VLM was not used with Qwen3-4B or any of the larger models** -- those tests were all LLM-only using the accessibility tree.

| Metric | Value |
|--------|-------|
| Model | LFM2-VL 450M (Q4_0 + Q8_0 mmproj) |
| Size | ~323 MB |
| Output per step | 1 token (empty string) in 3/5 steps; 16 tokens in 2/5 steps |
| Latency per step | 56-180 seconds |
| Impact on LLM decisions | None -- LLM still picked wrong elements regardless of VLM hint |

**VLM + LLM combined mode is strictly worse than LLM-only**: Same failure rate, 7-19x slower per step. The VLM adds 60-180 seconds of latency per step for zero benefit. The accessibility tree already provides sufficient element information for reasoning; a VLM that can actually describe Android screens could add value, but the 450M model is too small.

---

## Key Findings

### 1. There is a hard capability threshold around 4B parameters for UI agent tasks

Models fall into three tiers for this task:
- **Sub-1B (350M)**: Cannot follow structured output format at all. Generates narrative text instead of tool calls. No amount of prompt engineering can fix a model that lacks the capacity to simultaneously follow format constraints and reason about a task.
- **1-2B (1.2B Instruct)**: Follows tool format correctly but cannot reason about element selection. Defaults to low-index elements (0, 1, 2) regardless of goal or context. Format compliance without reasoning.
- **4B+ (Qwen3-4B)**: Both format compliance and reasoning sufficient for the task. Only tier that produces actionable results.

### 2. Output format compliance matters as much as reasoning

LFM2-8B-A1B MoE and DS-R1-Qwen3-8B both demonstrate partial-to-good UI understanding, but fail because they do not comply with the single-action-per-step contract. MoE outputs multi-step plans; DS-R1 hallucinates an inner agent loop. Fine-tuning for format compliance could unlock these models.

### 3. MoE is the right architecture for on-device agents

MoE models (like LFM2-8B-A1B with 1.5B active params out of 8.3B total) achieve fast inference at low compute cost while maintaining a large parameter space for reasoning. A format-compliant MoE model would be ideal: fast like 1.5B, capable like 8B.

### 4. Chain-of-thought must be suppressed for on-device agents

Both Qwen3-4B and DS-R1-Qwen3-8B default to verbose reasoning that consumes the entire token budget. Qwen3's `/no_think` instruction effectively suppresses this; DS-R1's distilled reasoning cannot be suppressed. On-device agents need concise, action-oriented output.

### 5. Samsung foreground boost is non-negotiable

The 15-17x speedup from foreground scheduling turns a 2-minute LLM call into an 8-second one. Any on-device AI application on Samsung devices must implement this workaround or accept unusable performance.

### 6. Accessibility tree > VLM for structured UI understanding

The accessibility tree provides element labels, types, and tap coordinates in a compact text format that LLMs can reason over directly. The 450M VLM adds no value over this structured input. VLM may become useful for visual elements without accessibility labels (images, icons), but the current model cannot meaningfully analyze Android screenshots.

---

## Recommendations

1. **Use Qwen3-4B with `/no_think`** as the recommended on-device model. It is the only configuration that successfully completes multi-step UI tasks.

2. **Skip sub-2B models entirely** for agentic tasks. At 350M and 1.2B, neither model can produce reliable tool-calling output. The minimum viable parameter count for this task class is approximately 3-4B.

3. **Skip VLM** unless a larger/better vision model is available. The accessibility tree provides better-structured UI information than the current 450M VLM.

4. **Invest in MoE fine-tuning**. A Mixture-of-Experts model trained to produce single-action tool calls would combine the speed of MoE (29-43s/step) with the reasoning of a larger model.

5. **Consider cloud LLM for latency-critical tasks**. GPT-4o or Claude with function calling can serve as a fast, reliable reasoning backend (sub-second per step) while keeping all other components on-device.

6. **Fine-tune small models for this specific task**. A 1.2B model fine-tuned on "GOAL + SCREEN_ELEMENTS -> correct tool call" pairs could potentially match the 4B model's accuracy at 8-14s per step.

---

## Agent Pipeline Components

| Component | Implementation | Role |
|-----------|---------------|------|
| Screen Parsing | `ScreenParser` + `AgentAccessibilityService` | Extracts interactive elements from accessibility tree into compact indexed list |
| Screenshot Capture | `AccessibilityService.takeScreenshot()` | Base64 JPEG for optional VLM input |
| Prompt Construction | `SystemPrompts` | Assembles GOAL + SCREEN_ELEMENTS + HISTORY + optional VISION_HINT |
| LLM Inference | RunAnywhere SDK (llama.cpp) | On-device text generation with tool-calling format |
| Tool Call Parsing | `ToolCallParser` | Handles `<tool_call>` XML, `ui_func(args)` style, inline JSON, and legacy format |
| Action Execution | `ActionExecutor` | Dispatches taps, types, swipes via accessibility gestures and coordinates |
| Pre-Launch | `AgentKernel.preLaunchApp()` | Opens target apps via Android intents before agent loop |
| Loop Recovery | `ActionHistory` + `trySmartRecovery()` | Detects repeated actions, dismisses dialogs, scrolls to reveal elements |
| Foreground Boost | `AgentKernel.bringToForeground()` | Brings agent to foreground during inference to bypass Samsung CPU throttling |
| Foreground Service | `AgentForegroundService` | PARTIAL_WAKE_LOCK + THREAD_PRIORITY_URGENT_AUDIO for sustained inference |

---

## Re-Run Validation (Post-PR Fixes)

This assessment was re-run after applying bug fixes from PR #361 to validate that the fixes did not regress agent behavior:

| Fix | Description |
|-----|-------------|
| `@Volatile` on `isRunning` | Thread-safety for stop flag |
| `.flowOn(Dispatchers.IO)` | ANR prevention -- inference now on IO threads |
| LLM error handling | Returns `LLMResponse.Error` instead of fake `wait` JSON |
| Settings goal heuristic | Navigation-only goals auto-complete; action goals keep loop running |
| `ToolCallParser` comma-parsing | Quote-aware split prevents malformed argument extraction |
| HTTP resource leak | `disconnect()` in `finally` block |
| `ActionHistory` guard | `maxEntries.coerceAtLeast(1)` prevents crash |

**Conclusion: Results match the previous assessment.** Qwen3-4B still passes (3 steps, ~3.8 min). All other models show the same failure patterns. The fixes were purely correctness/stability improvements with no behavioral change to model selection logic.

---

Built by the RunAnywhere team.
For questions, reach out to san@runanywhere.ai
