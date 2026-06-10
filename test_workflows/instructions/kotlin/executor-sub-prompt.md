# Kotlin Android Executor sub-prompt (CLUSTER-07 / KOTLIN-HARNESS-001)

Fill into **Universal Lane Executor** (§7.3 of `reusable-full-matrix-e2e-loop-prompt.md`) for lane `01_kotlin_android`.

## Lane identifiers

| Field | Value |
| --- | --- |
| LANE_SLUG | `01_kotlin_android` |
| PLATFORM | `kotlin` |
| Package | `com.runanywhere.runanywhereai.debug` |
| Catalog | §4 Android Kotlin |
| README | `test_workflows/instructions/kotlin/README.md` |

## Preconditions

- Exactly one `adb devices` entry; `export RAC_ANDROID_SERIAL=…`
- Log capture **started** before launch: `capture-kotlin-logs.sh start "$RAC_RUN_ID"`
- Fresh install per `kotlin/README.md` (uninstall → assembleDebug → install → grant RECORD_AUDIO + CAMERA)

## Execution mode

**Prefer the automated shell driver** after MCP launch:

```bash
export RAC_RUN_ID=<rac-run-id>
export RAC_ANDROID_SERIAL=<serial>
test_workflows/scripts/kotlin/run-kotlin-executor.sh
```

The script (`run-kotlin-executor.sh` + `_kotlin_tc_flows.sh`) implements the modality catalog. MCP agents should **not** re-implement these steps ad hoc — extend the shell driver if a step is flaky.

## Mandatory keyframes (cross-lane § report_schema.md)

Capture **exact** filenames after each step:

| Index | File | When |
| --- | --- | --- |
| 000 | `000_app_launch.png` | Cold launch, tabs visible |
| 007 | `007_stt_tab.png` | More → Speech to Text, model loaded |
| 008 | `008_stt_transcribed.png` | After batch record + `Batch transcription complete` |
| 009 | `009_tts_tab.png` | More → Text to Speech, Piper loaded |
| 010 | `010_tts_played.png` | After **Generate**; hold until log `[TTS] Synthesis complete` / `Synthesis complete`, then Play |
| 011 | `011_voice_tab.png` | Voice tab, setup complete |
| 012 | `012_voice_response.png` | After Start Voice Assistant + at least one mic tap cycle |
| 013 | `013_vision_tab.png` | Vision → Vision Chat, VLM loaded |
| 014 | `014_vision_response.png` | After Analyze + stream attempt |
| 015 | `015_settings_tab.png` | Settings tab (API / Tool Calling visible) |

Call `capture-kotlin-logs.sh snapshot "$RAC_RUN_ID" tcNN_label` after each TC.

## Modality hold rules (fixes LIMITED grades)

1. **TTS (TC-08, TC-11):** Do not leave Text to Speech until `Synthesis complete` appears in logcat (≤120s). Minimum 15s dwell after Generate even if Play is visible early.
2. **Voice (TC-12):** Start Voice Assistant; wait for `Voice session started` and `Model states synced`. Tap mic to end utterance; hold through `Transcription complete` or STT batch marker when possible.
3. **RAG (TC-13):** Push **`rag-sample.json`** (script converts fixture — picker accepts PDF/JSON only). Complete picker selection → wait for `Ingesting document text` / `Document loaded successfully` → send catalog query → wait for `Querying RAG pipeline`.
4. **Tools (TC-14):** Settings → enable Tool Calling → **Add Demo Tools** → Chat with LLM loaded → prompt: `Use the calculate tool to compute 15 times 7.`
5. **LoRA (TC-21):** More → LoRA Adapters → Download if needed → Chat → LoRA → **Apply** → short inference → Unload / Clear All.
6. **Settings (TC-20):** Open API Configuration sheet (tap API Key row); confirm Logging Configuration section on main Settings scroll.

## TC scope

Run TC-01, TC-06–TC-16 (storage via TC-15 in Settings), TC-19 (Benchmarks optional if time), TC-20, TC-21. Mark TC-17 DEFERRED, TC-18 N/A per catalog.

## Return

`RAC_RUN_ID`, lane path, count of keyframes 007–014 present, blockers. Do **not** write `modality_report.md` (Analyzer §7.4).
