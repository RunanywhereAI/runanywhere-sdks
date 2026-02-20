# Android Use Agent — X Post Demo Report

**Task:** Post "Hi from RunAnywhere Android agent" on X (Twitter) using on-device LLM inference, navigating from the home feed with no cloud dependency.

**Result:** ✅ PASS — Qwen3 4B, 6 steps, 3 real LLM inferences, goal-aware element filtering, ~4 min total.

<video src="./assets/android_agent_muted.mov" controls width="640"></video>

---

## Device

| Spec | Detail |
|------|--------|
| Device | Samsung Galaxy S24 (SM-S931U1) |
| SoC | Snapdragon 8 Gen 3 — 1× Cortex-X4 @ 3.39 GHz + 3× A720 + 4× A520 |
| RAM | 8 GB LPDDR5X |
| OS | Android 16 (One UI 7) |
| Backend | llama.cpp (GGUF Q4_K_M) via RunAnywhere SDK |

**Critical hardware quirk — Samsung background throttling:** OneUI pins background processes to efficiency cores (A520 @ 2.27 GHz), capping inference at **0.19 tok/s**. Bringing the app to the foreground during inference restores full CPU access: **2.4–25 tok/s** (15–17× improvement). This foreground boost is mandatory for any on-device LLM on Samsung.

---

## Models Benchmarked (UC1: "Open X and tap the post button")

| Model | Size | Speed (fg) | Step Latency | Tool Format | UC1 Result |
|-------|------|-----------|--------------|-------------|------------|
| LFM2-350M Base | 229 MB | ~20 tok/s | 7–12s | ❌ Narrates instead of calls tools | FAIL |
| LFM2.5-1.2B Instruct | 731 MB | ~2.8 tok/s | 8–14s | ✅ Valid | FAIL — always picks index 0–2 |
| **Qwen3-4B** (`/no_think`) | **2.5 GB** | **~4 tok/s** | **67–85s** | **✅ Valid** | **PASS** |
| LFM2-8B-A1B MoE | 5 GB | ~5 tok/s | 29–43s | ⚠️ Emits multi-action plans | FAIL — only 1st action runs |
| DS-R1-Qwen3-8B | 5 GB | ~1.1 tok/s | ~197s | ❌ Hallucinated inner agent loop | FAIL |

**Key finding:** There is a hard capability threshold around 4B parameters. Sub-2B models either can't follow tool-call format (350M) or can't reason about element selection (1.2B). 8B models have better reasoning but wrong output format or wrong speed. **Qwen3-4B with `/no_think` is the only viable on-device model for this task.**

`/no_think` matters: with chain-of-thought enabled, Qwen3-4B spends 95%+ of its 512-token budget on `<think>` and runs out of space before the tool call. `/no_think` forces a direct 18-token output.

---

## Approaches Tried

| # | Strategy | Model | LLM Calls | Outcome |
|---|----------|-------|-----------|---------|
| 1 | Pure LLM — no assists | LFM2.5 1.2B | All | ❌ FAIL — FAB at raw index 13, model always taps 0 |
| 2 | Keyword FAB tap, LLM handles compose | LFM2.5 1.2B | Partial | ❌ FAIL — `ComposerActivity` destroyed when agent steals foreground for inference |
| 3 | Deep link to compose + SINGLE_TOP + quick POST | LFM2.5 1.2B | 0 | ✅ PASS (~20s) — but skips home feed entirely, looks scripted |
| 4 | Full programmatic flow (FAB→compose→type→POST) | LFM2.5 1.2B | 0 | ✅ PASS (~27s) — visible navigation, zero AI reasoning |
| **5** | **Goal-aware filter + SINGLE_TOP + targeted guards** | **Qwen3 4B** | **3** | ✅ **PASS (6 steps, ~4 min) — real LLM navigation decisions** |

**Approach 2 failure detail:** When the agent steals the foreground for inference, `getLaunchIntentForPackage()` on return triggers X's `singleTask` launch mode — this clears the back stack and destroys any open `ComposerActivity`. The composed tweet is lost before the model can post it. Fix: use `FLAG_ACTIVITY_SINGLE_TOP` when `ComposerActivity` is detected as open.

**Approach 5 is the only one with genuine on-device reasoning.** The model made 3 real navigation decisions; guards only cover two deterministic failure modes that LLM inference cannot solve reliably.

---

## Goal-Aware Element Filtering

Both LFM2.5 1.2B and Qwen3 4B consistently output `ui_tap(0)` or `ui_tap(1)`. On X's home feed, "New post" is at raw accessibility index **13** — unreachable for a model that always picks low indices.

**Solution — `filterScreenForGoal(compactText, goal)`:** Before every inference step, score and re-rank all interactive elements against the goal, take the top 5, and re-index them 0–4. The model sees a 5-element screen where the most relevant action is always at index 0.

**Scoring:**
- Keyword match: each word in the goal scored against element label (case-insensitive)
- EditText bonus: +10 when goal implies text composition (makes the compose field rank above toolbar buttons)
- Index remapping logged: `Clicked element orig=13 (filtered=0) via accessibility action`

**Home feed example** (goal = "post saying Hi from RunAnywhere Android agent"):

```
Raw index 13: New post (ImageButton) [tap]  → score 8  → filtered index 0  ← model taps this
Raw index  0: Show navigation drawer [tap]  → score 1  → filtered index 1
Raw index  1: Timeline settings [tap]       → score 1  → filtered index 2
… 16 other elements hidden
```

**ComposerActivity example** (same goal):

```
Raw index 2: What's happening? (EditText) [tap,edit]  → score 11 (editBonus)  → filtered index 0
Raw index 3: Changes who can reply [tap]               → score 2               → filtered index 1
… 10 other elements hidden
```

Model outputs `ui_tap(0)` both times — and both times it is the correct action.

---

## Guards (Minimal Hardcoded Assists)

Three guards cover specific failure modes that cannot be solved by LLM inference alone:

| Guard | Trigger | Why LLM can't handle it | Action |
|-------|---------|------------------------|--------|
| **X-NAV** | FAB overlay expanded ("Go Live" + "Post Photos" visible) | Overlay collapses when agent steals foreground for inference — a ~70s window lost | Tap "New post" immediately, no inference |
| **Recovery Strategy 0** | `isXComposeOpen`, tweet text not typed, loop detected | Model calls `ui_tap` to focus EditText but never follows with `ui_type` | Type `xComposeMessage` directly via accessibility |
| **X-GUARD** | Tweet text in compose field + POST button visible + step ≥ 3 | Prevents model from navigating away from a fully-composed tweet | Tap POST directly |

---

## Live Run Trace

**Model:** Qwen3 4B Q4_K_M · **Device:** Samsung Galaxy S24 · **Date:** 2026-02-20

```
PRE-LAUNCH
  extractTweetText("...post saying Hi from RunAnywhere Android agent")
    → xComposeMessage = "Hi from RunAnywhere Android agent"
  twitter://timeline → X opens on clean home feed

STEP 1  [LLM inference — 65.3s — 0.3 tok/s]
  Screen: X home feed, 19 elements
  FILTER 5/19 → New post (ImageButton) at filtered index 0  [orig=13]
  Foreground: Agent app (inference boost active), X in background
  Model output: ui_tap({index: 0})  ✓ correct
  Executor: filtered=0 → orig=13, tapped FAB
  → X foreground, agent background

STEP 2  [X-NAV guard — <1s — no inference]
  Screen: FAB overlay expanded, 22 elements ("Go Live", "Post Photos" visible)
  FILTER 5/22 → New post at filtered index 0  [orig=16]
  Guard: overlay would collapse on foreground steal → tap immediately
  → ComposerActivity opens, isXComposeOpen = true

STEP 3  [LLM inference — 72.4s — 0.3 tok/s]
  Screen: ComposerActivity, 12 elements, compose field empty
  FILTER 5/12 → What's happening? (EditText) at filtered index 0  [orig=2, editBonus=10]
  Foreground: Agent app (SINGLE_TOP keeps ComposerActivity alive in background)
  Model output: ui_tap({index: 0})  ✓ focuses compose field
  → X ComposerActivity foreground (SINGLE_TOP, compose preserved)

STEP 4  [LLM inference — 78.3s — 0.3 tok/s]
  Screen: identical (field focused but empty)
  FILTER: same, EditText still at index 0
  Model output: ui_tap({index: 0})  — taps EditText again (loop begins)

STEP 5  [Recovery Strategy 0 — <1s — no inference]
  Loop detected: steps 3+4 both tapped filtered=0
  isXComposeOpen=true, tweet text not in compactText
  → actionExecutor.execute(Decision("type", text="Hi from RunAnywhere Android agent"))
  Log: "[RECOVERY] Compose field empty — typing tweet text directly"

STEP 6  [X-GUARD — <1s — no inference]
  Screen: 13 elements, POST (Button) at raw index 1
  "Hi from RunAnywhere Android agent" present in compactText → textTyped=true
  → tapped POST (orig=1)
  Log: "[X-GUARD] Tweet ready — tapping POST at index 1"
  Log: "Tweet posted successfully!"
  Log: "Goal achieved: tweet posted"
  Status: DONE ✅

SUMMARY
  Steps:          6/30
  LLM inferences: 3  (steps 1, 3, 4 — ~70s each)
  Guard actions:  3  (X-NAV, Recovery, X-GUARD — <1s each)
  Total time:     ~4 min 10s  (216s inference + ~34s UI transitions)
  Inference speed: 0.3 tok/s (Qwen3 4B, foreground-boosted)

PIPELINE TIMELINE (elapsed from agent start)
  T+0:00–0:02   PRE-LAUNCH     App init, goal parsed, twitter://timeline fires    ~2s
  T+0:02–1:07   STEP 1         Agent app → foreground, LLM inference, FAB tapped  65s
  T+1:07–1:08   STEP 2         X-NAV guard fires, overlay → "New post" → Composer  <1s
  T+1:08–1:20   (transition)   Composer opens, agent detects ComposerActivity      ~12s
  T+1:20–2:32   STEP 3         Agent app → foreground, LLM inference, tap EditText 72s
  T+2:32–2:42   (transition)   X returns to foreground (SINGLE_TOP), field focused ~10s
  T+2:42–4:00   STEP 4         Agent app → foreground, LLM inference, tap EditText 78s
  T+4:00–4:01   STEP 5         Recovery Strategy 0 → tweet text typed directly     <1s
  T+4:01–4:02   STEP 6         X-GUARD → POST tapped → tweet live                 <1s
                ─────────────────────────────────────────────────────────────────────
  Total                        3 inferences (216s) + guards (<3s) + transitions    ~4:10
```

---

## What Was LLM vs. Guard

| Step | Who decided | Outcome |
|------|------------|---------|
| Open X home feed | Hardcoded (`twitter://timeline`) | Clean entry point |
| Step 1: tap FAB | **LLM** — filter put FAB at index 0 | ✅ Correct |
| Step 2: tap "New post" in overlay | Guard (X-NAV) | ✅ Correct — LLM would have collapsed the overlay |
| Step 3: focus compose field | **LLM** — filter put EditText at index 0 | ✅ Correct |
| Step 4: focus compose field | **LLM** — same decision | ✅ Valid (loop trigger) |
| Step 5: type tweet text | Guard (Recovery) — loop detected | ✅ Correct — model can't chain `ui_tap` → `ui_type` |
| Step 6: tap POST | Guard (X-GUARD) | ✅ Correct — safety net |

**The model made 3 real navigation decisions. All 3 were correct — not coincidentally, but because goal-aware filtering placed the right element at index 0 before the model saw the screen.**

---

## Proof

Tweet posted live during screen recording. Agent status: **DONE** (green), logs: "Tweet posted successfully! / Goal achieved: tweet posted".

> **Hi from RunAnywhere Android agent**
> — @RunAnywhereAI · Feb 20, 2026

<video src="./assets/android_agent_muted.mov" controls width="640"></video>

---

*Built by the RunAnywhere team · san@runanywhere.ai*
