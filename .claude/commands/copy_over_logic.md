---
description: Port RunAnywhere SDK components from one platform/framework to another.
argument-hint: '[from] [to] [component(s)]'
---

You are RunAnywhere's SDK migration engineer.

Your job is to take code from a **source** SDK / framework / platform (“from”) and implement the equivalent in a **target** SDK / framework / platform (“to”), preserving behaviour and fitting cleanly into the target architecture.

Typical examples:
- iOS SDK → Android SDK
- Android SDK → React Native / Flutter wrapper
- Core Kotlin lib → iOS Swift package
- Sample app in one platform → sample app in another

---

## 0. Inputs & setup

- Make sure the user has clearly defined: **{from} → {to}**  
  - “From” can be a language / project / platform (e.g., “iOS SDK”, “android/app”, “KMP core lib”).
  - “To” can be another language / project / platform (e.g., “Android SDK”, “React Native bridge”, “Web demo”).
- Clarify *what* they want ported:
  - A specific component (e.g., `ConversationScreen`, `VoicePipelineConfig`)
  - A group of files or folders
  - A feature (“the offline transcription flow”, “the onboarding wizard”)

If the user mentions multiple components or features, **treat each as a separate sub-task** and process them one by one to keep context clear.

---

## 1. Understand the **from** side

For each component/feature requested, launch a TASK for each of them:

1. **Locate the code**
   - Find all relevant files, folders, and tests.
   - Include:
     - Business logic
     - UI components / views
     - Configuration, DI wiring, routing/navigation
     - Any RunAnywhere-specific pieces (on-device models, pipelines, config objects, telemetry)

2. **Build a concise mental model**
   - What is the responsibility and public API?
   - What data flows through it? Where does it come from and go?
   - What other modules does it depend on (core SDK, platform glue, third-party libs)?
   - How are errors, edge cases, and retries handled?
   - What constants, colors, strings, or assets does it rely on?

3. **Summarize the “from” design** in a few bullets before you start coding on the “to” side.

---

## 2. Inspect the **to** side and launch a SINGLE task for this:

1. **Find the right home**
   - Identify the module / package / directory in the target project where this functionality should live:
     - e.g., platform bridge, UI layer, shared core module, example app.

2. **Check what already exists**
   - If an equivalent or partial implementation already exists:
     - Compare behaviour and responsibilities.
     - Note gaps, mismatches, and duplication risks.

3. **Align with existing architecture**
   - Respect the target project’s:
     - Naming conventions
     - Layering (core vs platform-specific)
     - DI / service location patterns
     - Navigation / routing / state management conventions
     - Error & logging patterns

---

## 3. Design the mapping ({from} → {to}) - Launch another TASK.

Before writing code, plan the mapping:

- How do classes, types, and functions in **from** map into **to**?
  - E.g., Swift async/await → Kotlin coroutines; delegates → callbacks/flows; ViewControllers → Activities/Fragments/Compose.
- Decide what should stay **shared/core** vs what must be **platform-specific**.
  - Push cross-platform logic into shared modules when possible.
  - Keep platform glue thin and focused on UI + system APIs.
- Handle platform differences explicitly:
  - Lifecycle, threading, permissions, background execution, storage, etc.

Write a short mapping plan (even just bullets) before implementing.

---

## 4. Implement the port in the **to** project - Launch another task for implementation

For each component/feature:

1. **Create / update code**
   - Implement the equivalent functionality using idiomatic patterns for the target language/framework.
   - Keep behaviour as close as possible to the source unless platform constraints require changes.

2. **Wire it into the system**
   - Update:
     - DI containers / service locators
     - Routing / navigation
     - RunAnywhere SDK configuration / initialization if needed
     - Gradle/SPM/Pods/module exports where applicable

3. **Keep the public surface consistent**
   - Prefer keeping API names, parameter semantics, and events consistent across platforms where it makes sense for SDK consumers.

4. **Avoid duplication**
   - If you see duplicated logic, consider refactoring it into a shared/core module instead of copy-pasting.

---

## 5. Quality + correctness checks - Launch a verification task

- Ensure the **to** project still compiles.
  - Fix imports, types, build settings, and module wiring.
- Run any available tests relevant to the change.
- If there were tests on the **from** side:
  - Re-use/adapt them for the **to** side where practical, or at least mirror the key cases.
- Manually sanity-check:
  - Main happy path
  - Important edge cases (failures, timeouts, offline scenarios, permission denials, etc.)
- Check:
  - No obvious lint/style violations.
  - No hard-coded values that should be shared constants or config.

If something cannot be fully implemented (missing platform capability, unclear design), explicitly call that out and propose alternatives.

---

## 6. Summarize back to the user - Produce a final summary

At the end, respond with:

1. **High-level summary** (3–6 bullets) of what you did and why.
2. **File-level summary**:
   - New files added in {to}
   - Existing files modified in {to} (and, if relevant, in {from})
3. **Behavioural summary**:
   - Confirmed behaviours that now match {from}
   - Any intentional behaviour differences and why
4. **Follow-ups & TODOs**:
   - Remaining gaps
   - Tests or refactors you recommend next
   - Any questions that require product/architecture input

Always write the summary so that another engineer on the RunAnywhere team can quickly understand the change and continue the work.

