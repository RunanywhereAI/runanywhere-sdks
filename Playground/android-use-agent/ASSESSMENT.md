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

UC1 used **LLM-only mode** across all five models. VLM (LFM2-VL 450M) was tested separately with the 1.2B model during UC1 and found to be ineffective. UC2–UC5 were run with Qwen3-4B (the only capable model) in LLM-only mode. UC4 and UC5 were planned for VLM evaluation, but UC4 was solved by pre-launch optimization (0 LLM steps) and UC5 stalled before reaching any visual-heavy screen -- see [VLM Analysis](#vlm-analysis-lfm2-vl-450m).

---

## Test Protocol

**Agent Configuration** (all use-cases):
- Max steps: 30, timeout: 10 minutes
- Accessibility tree: up to 25 elements, 40 chars per label
- Tool format: `<tool_call>{"tool":"ui_tap","arguments":{"index":N}}</tool_call>`
- VLM: off by default; tested separately on select use-cases

---

## Use Cases

Five tasks covering a range of agent capabilities, from simple single-tap interactions to multi-step navigation and visual-only UI elements.

| # | Task | Type | Requires | Qwen3-4B Result |
|---|------|------|----------|----------------|
| UC1 | "Open X and tap the post button" | Navigation + tap FAB | Element matching from accessibility tree | ✅ PASS (3 steps, ~3.8 min) |
| UC2 | "Open Settings and enable Airplane Mode" | System settings toggle | Multi-level navigation + toggle | ❌ FAIL (Mobile Hotspot loop) |
| UC3 | "Open Chrome and search for 'weather today'" | App + type + submit | Text input, keyboard interaction | ❌ FAIL (Guardian bookmark loop, max duration) |
| UC4 | "Open YouTube and play the first video" | App + identify + tap | Scrollable list, visual content | ✅ PASS (pre-launch, 0 LLM steps, ~1s) |
| UC5 | "Lower the device volume to minimum" | System action (slider) | No clear text label — visual-only element | ❌ FAIL (ui_back loop, stalled) |

UC4 and UC5 were the primary candidates for VLM value: they involve visual or unlabeled UI elements where the accessibility tree alone may be insufficient. In practice, UC4 was solved instantly by pre-launch optimization without any LLM reasoning, and UC5 stalled on the home screen before any visual-heavy UI was reached.

---

## Results Summary

### UC1: "Open X and tap the post button" ✅

| Model | Steps | Time per Step | Total Time | Element Selection | Tool Format | Result |
|-------|-------|--------------|-----------|-------------------|-------------|--------|
| **Qwen3-4B** (/no_think) | **3** | **67-85s** | **~3.8 min** | **Correct** | **Valid** | **PASS** |
| LFM2-8B-A1B MoE | 19 (timeout) | 29-43s | 10 min | Partially correct | Multi-action plans | FAIL |
| LFM2.5-1.2B | 30 (max steps) | 8-14s | 10+ min | Always index 2 | Valid | FAIL |
| DS-R1-Qwen3-8B | 1 (premature stop) | ~197s | ~3.3 min | Trapped in reasoning | Inside `<think>` tags | FAIL |
| LFM2-350M (Base) | 2 (format failure) | 7-12s | ~20s | Incorrect | Cannot follow format | FAIL |

**Qwen3-4B with `/no_think` is the only model that successfully completes the task.**

### UC2–UC5: Qwen3-4B Results (LLM-only)

| Use Case | Steps | Outcome | Failure Mode |
|----------|-------|---------|--------------|
| UC2: Enable Airplane Mode | ~6 | ❌ FAIL | Navigated into Mobile Hotspot loop; Airplane Mode toggle never found |
| UC3: Chrome + search "weather today" | 8 (timeout) | ❌ FAIL | Guardian bookmark tapped instead of search bar; `ui_open_app("Chrome")` loop until max duration |
| UC4: YouTube first video | 0 LLM steps | ✅ PASS | Pre-launch optimization: goal parsed as YouTube search, "Me at the zoo" played in ~1s |
| UC5: Lower volume to minimum | 2 | ❌ FAIL | `ui_back` from home screen twice; agent stalled (accessibility service blocked, CPU=0) |

**Overall Qwen3-4B task success rate: 2/5 (40%)**. Both passes involve either a simple single-screen task (UC1) or a shortcut that bypasses LLM reasoning entirely (UC4). All three failures involve multi-step navigation through unfamiliar Settings paths.

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

## UC2–UC5 Detailed Results (Qwen3-4B)

### UC2: "Open Settings and enable Airplane Mode" ❌

**Configuration**: Qwen3-4B Q4_K_M, /no_think, LLM-only (no VLM)

| Step | Screen | Action | Result |
|------|--------|--------|--------|
| Pre-launch | — | `ui_open_app("Settings")` | Settings opened |
| 1 | Settings home | `ui_tap` → Connections | Entered Connections page |
| 2 | Connections | Navigation into sub-settings | Mobile Hotspot instead of Airplane Mode |
| 3–6 | Mobile Hotspot settings | Various taps | Loop: repeatedly navigated deeper into hotspot settings |
| — | — | Max steps / stuck | **FAIL** |

**Side effect**: The model accidentally tapped the Wi-Fi toggle during navigation, disabling Wi-Fi (restored manually via `adb shell svc wifi enable`).

**Root cause**: On Samsung One UI, Airplane Mode is located at the top of the Connections page as a toggle, while Mobile Hotspot and other sub-menus appear below. The model confused Airplane Mode with nearby network settings and descended into the wrong sub-tree. Once in Mobile Hotspot settings, the loop-recovery mechanism scrolled but could not break the model out of its current navigation context.

**Why the task is hard for an LLM agent**: The Connections page shows ~15 elements including Wi-Fi, Bluetooth, NFC, Mobile Hotspot, and Airplane Mode. Without knowing exactly which element index maps to "Airplane Mode," the model guesses by semantic similarity -- and "Mobile Hotspot" and other network toggles distract it from the correct target.

---

### UC3: "Open Chrome and search for 'weather today'" ❌

**Configuration**: Qwen3-4B Q4_K_M, /no_think, LLM-only (no VLM)

| Step | Screen | Action | Time | Result |
|------|--------|--------|------|--------|
| 1 | Chrome new tab | `ui_tap(23)` (Guardian bookmark) | ~100s | Navigated to Guardian news website |
| 2 | Guardian website | `ui_open_app("Chrome")` | ~100s | Chrome already open — no-op |
| 3–8 | Guardian website | `ui_open_app("Chrome")` (loop) | ~100s each | Recovery: scroll triggered but no change |
| 8 | Guardian website | — | — | **Max duration (10 min) hit** |

**Root cause**: The Chrome new tab page rendered with the search bar at index 1 and a row of bookmarks below. The Guardian bookmark appeared at index 23 in the element list, and the model selected it (likely associating "search" with a recently-visited news site). Once on the Guardian page, the model repeatedly tried to reopen Chrome rather than navigating back or tapping the address bar. The loop-recovery scroll had no effect since the screen changed correctly with each Chrome reopen attempt.

**Complicating factor**: Chrome's new tab search bar has a content description of "Search or type web address" -- a long label that may be partially truncated in the compact accessibility tree (40-char limit). Bookmarks may appear more "tappable" than the search field due to clearer element boundaries.

**Step latency**: ~100s per step (longest of all use cases). Qwen3-4B evaluates a larger prompt context at this point in the run, slowing prompt evaluation.

---

### UC4: "Open YouTube and play the first video" ✅

**Configuration**: Qwen3-4B Q4_K_M, /no_think, pre-launch optimization active

| Stage | Action | Time | Result |
|-------|--------|------|--------|
| Pre-launch | Detected "YouTube" + "play the first video" in goal | ~0s | Extracted "the first video" as search query |
| Pre-launch | `startActivity(YouTubeSearchIntent("the first video"))` | ~1s | YouTube opened directly with search results for "the first video" |
| Pre-launch | "Me at the zoo" detected as first result | <1s | Video playing |
| LLM steps | — | 0 | Not needed |

**Result: PASS. Total time: ~1 second. LLM inference steps: 0.**

**Why it works**: The agent's pre-launch optimization parses the goal text for app-name + content patterns. "Open YouTube and play the first video" matched the YouTube handler, which extracted "the first video" as a search query and launched YouTube's search intent directly. The first search result for "the first video" is "Me at the zoo" -- the first video ever uploaded to YouTube -- which the YouTube app immediately began playing.

**Note on VLM**: VLM was not loaded or invoked. The pre-launch shortcut resolved the task before any LLM or VLM inference was needed. Whether VLM would help if the pre-launch optimization did not trigger is untested.

---

### UC5: "Lower the device volume to minimum" ❌

**Configuration**: Qwen3-4B Q4_K_M, /no_think, LLM-only (no VLM)

| Step | Screen | Action | Time | Result |
|------|--------|--------|------|--------|
| 1 | Home screen (via "Going home") | — | — | Agent started on home screen |
| 2 | Home screen (25 elements: weather, apps, search bar) | `ui_back` | ~68s | Back from home = no navigation change |
| 3 | Home screen (same) | `ui_back` | Stalled | Inference stopped; process CPU=0; accessibility service blocked |

**Root cause**: The home screen offers no direct path to volume controls in the accessibility tree (no Settings icon, no Quick Settings slider). The model needed to either:
1. Open Settings → Sounds and vibration → Volume sliders, or
2. Swipe down notification panel and interact with the volume slider

Neither strategy was chosen. The model pressed `ui_back` from the home screen — a non-action on Samsung Galaxy — then repeated the same mistake. On the second `ui_back`, the accessibility service callback appeared to hang (all inference threads sleeping, CPU=0 for 6+ minutes), requiring a force-stop.

**Why VLM would not have helped**: Even with a vision model active, the home screen screenshot shows a weather widget, app icons, and a Google search bar — no volume slider visible. The navigation problem (reaching the correct Settings page) is a reasoning/planning challenge, not a visual recognition challenge.

**Deeper issue — missing volume tool**: The agent's tool set includes `ui_tap`, `ui_swipe`, `ui_type`, `ui_open_app`, `ui_back`, `ui_long_press`, and `ui_done`. There is no `ui_press_volume_key` or `ui_adjust_volume` tool. A dedicated volume key tool would allow one-shot resolution: press volume-down 15 times (maximum range). Without it, the model must navigate through Settings UI, which requires multi-level path knowledge it does not have.

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

### UC4 and UC5 VLM Evaluation (Planned, Not Executed)

UC4 and UC5 were the primary candidates for VLM benefit:
- **UC4** was resolved by pre-launch optimization in ~1 second with 0 LLM steps. VLM was never loaded.
- **UC5** stalled on the home screen before reaching any visual-heavy UI (volume sliders, Settings pages with icon-only buttons). Loading VLM would not have changed the outcome -- the failure was in navigation reasoning, not visual element recognition.

**Conclusion**: Neither use case provided a meaningful opportunity to evaluate VLM benefit with Qwen3-4B. The 450M VLM model remains untested on tasks where visual understanding could actually matter (e.g., image-heavy screens, icon-only navigation, non-labeled sliders mid-navigation).

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

### 7. Multi-step Settings navigation is a hard failure class

UC1 and UC4 are "shallow" tasks: they require identifying one element on a known screen (X post button) or exploiting an app-launch shortcut (YouTube). UC2, UC3, and UC5 require multi-level navigation through unfamiliar Settings or app sub-pages. Qwen3-4B fails all three of these. The model does not maintain an accurate internal map of Android Settings hierarchies, leading to wrong sub-tree descent (UC2: Mobile Hotspot), wrong element selection (UC3: Guardian bookmark), or no navigation at all (UC5: ui_back from home screen). This represents a **fundamental limitation of zero-shot prompting** for Settings-navigation tasks.

### 8. Pre-launch optimization is a significant multiplier for app-launch tasks

UC4 completed in ~1 second with 0 LLM inference steps due to the agent's pre-launch optimization -- which parses goal text for app name + content keywords and directly launches the target app via Android intent. For tasks where the goal can be fully expressed as an app launch + search query, this eliminates all LLM latency. Pre-launch coverage (supported apps and intent patterns) is a critical engineering investment.

### 9. Missing system-level tools create hard failures

UC5 failed partly because the agent's tool set lacks a `ui_press_volume_key` tool. Android provides `AudioManager.adjustVolume()` and physical volume key events that could set volume to minimum in a single call. An agent that only sees the accessibility tree cannot reach volume controls without navigating through Settings UI -- a multi-step path the model cannot reliably follow. **Adding system-action tools** (volume, brightness, Bluetooth toggle, Wi-Fi toggle) would convert several "impossible via LLM navigation" tasks into "trivial one-shot tool calls".

---

## Recommendations

1. **Use Qwen3-4B with `/no_think`** as the recommended on-device model. It is the only configuration that successfully completes multi-step UI tasks and the only one tested across UC1-UC5.

2. **Skip sub-2B models entirely** for agentic tasks. At 350M and 1.2B, neither model can produce reliable tool-calling output. The minimum viable parameter count for this task class is approximately 3-4B.

3. **Skip VLM** unless a larger/better vision model is available. The accessibility tree provides better-structured UI information than the current 450M VLM. UC4 and UC5 — the intended VLM test cases — were never bottlenecked on visual understanding.

4. **Add system-level tool actions** for volume, brightness, Wi-Fi, Bluetooth, and Airplane Mode. These are directly addressable via Android APIs (one function call each) and do not require navigating through Settings UI. Adding them would turn UC2 and UC5 from multi-step navigation failures into single-step successes.

5. **Expand pre-launch coverage**. UC4 succeeded because the goal text matched a YouTube intent pattern. Expanding this pattern-matching to cover common navigation targets (Settings sub-pages, specific app views) would improve task coverage without any LLM improvement.

6. **Invest in MoE fine-tuning**. A Mixture-of-Experts model trained to produce single-action tool calls would combine the speed of MoE (29-43s/step) with the reasoning of a larger model.

7. **Consider cloud LLM for latency-critical tasks**. GPT-4o or Claude with function calling can serve as a fast, reliable reasoning backend (sub-second per step) while keeping all other components on-device.

8. **Fine-tune small models for this specific task**. A 1.2B model fine-tuned on "GOAL + SCREEN_ELEMENTS -> correct tool call" pairs could potentially match the 4B model's accuracy at 8-14s per step. UC2/UC3/UC5 failures are likely addressable with supervised fine-tuning on Settings navigation trajectories.

---

## X Compose Shortcut: Why Custom Code Instead of Pure LLM Navigation

The X (Twitter) compose flow uses three pieces of custom code — a deep link, a `ComposerActivity` foreground fix, and a quick POST tap — rather than letting the LLM navigate autonomously. Three compounding problems make pure LLM navigation unviable:

**Problem 1 — Speed**: Qwen3-4B runs at ~0.2 tok/s on a thermally throttled S24, producing 125s per inference step. A minimal write flow (home feed → tap FAB → compose opens → tap text field → type tweet → tap POST) is 5–6 LLM steps minimum. That is 10+ minutes for a single tweet, and failure at any step requires restarting. LFM2.5-1.2B is faster (8–14s/step) but cannot select the correct element from a 22-element X home feed — it always picks index 0–2 regardless of context (see UC1 results).

**Problem 2 — Navigation reliability**: Even with a capable model, the X home feed renders 40-46 accessibility elements including unlabeled `ViewGroup [tap]` and `FrameLayout [tap]` containers from tweet rows. Qwen3-4B successfully found the FAB in UC1 (index 15 out of 22 elements), but that was with a clean, low-noise feed. Under real conditions with 45+ elements including media players, Grok promotions, and nested tweet layouts, the model navigated into Grok and repeated wrong taps across multiple live runs.

**Problem 3 — Compose screen destruction**: The agent must steal the foreground during inference (15-17x CPU boost on Samsung). When returning to X after inference, `getLaunchIntentForPackage()` starts X's main activity which uses `singleTask` launch mode — this clears the back stack and **destroys any open compose screen**. A tweet typed in step 4 would be lost before step 5 executes.

**The three-piece solution**:

| Code | Problem solved |
|------|---------------|
| `openXCompose()` — `twitter://post?message=...` deep link | Opens compose directly with pre-filled text. Eliminates home-feed navigation (Problems 1 + 2) |
| `bringAppToForeground()` with `ComposerActivity + FLAG_ACTIVITY_SINGLE_TOP` | Brings compose back to front after inference without clearing it (Problem 3) |
| `findPostButtonIndex()` quick-tap | Taps POST button directly before any LLM inference step. Eliminates the final LLM step entirely |

**Trigger**: Only activates when the goal contains "post"/"tweet" AND quoted text (e.g. `post "Hello" on X`). Goals without quoted text (e.g. `open X and write a post saying Hello`) skip the deep link and fall through to pure LLM navigation.

**With 3-step assisted flow, LFM2.5-1.2B requires 0 correct LLM decisions**: deep link opens compose with pre-filled text → `findPostButtonIndex` quick-taps POST before LLM is ever called → done. This is the recommended path for 1.2B.

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
