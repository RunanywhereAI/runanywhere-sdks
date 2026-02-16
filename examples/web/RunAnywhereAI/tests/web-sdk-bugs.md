# Web SDK Bug Report

Bugs found during comprehensive E2E testing.

---

## Test Run 4: Feb 16, 2026 (Post-Rebuild + Persistence Verification)

Total Tests: 78 | PASS: 78 | FAIL: 0 | BUGS: 0

Rebuilt SDK (TypeScript) and restarted dev server from scratch before this run.

### Full UI Verification (All Categories A–T)

| #    | Test                                                                          | Category | Result |
| ---- | ----------------------------------------------------------------------------- | -------- | ------ |
| A1   | All 7 tabs render (Chat, Vision, Voice, Transcribe, Speak, Storage, Settings) | A        | PASS   |
| A2   | CPU badge appears (class: accel-badge--cpu)                                   | A        | PASS   |
| A3   | Console log: "RunAnywhere Web SDK initialized successfully"                   | A        | PASS   |
| A4   | Backend registration: LlamaCpp + ONNX both registered                        | A        | PASS   |
| A5   | No JS errors in console (0 errors, 1 expected warning)                       | A        | PASS   |
| F24  | Storage tab shows "Browser Storage (OPFS)"                                   | F        | PASS   |
| F25  | "Choose Storage Folder" button present                                       | F        | PASS   |
| F26  | "Import Model File" button present                                           | F        | PASS   |
| F27  | Storage stats: model count, total size, available space                      | F        | PASS   |
| F28  | Quota bar renders with usage/total                                           | F        | PASS   |
| F29  | "Clear All Models" button present                                            | F        | PASS   |
| K44  | All 7 tabs render without errors                                             | K        | PASS   |
| K45  | Rapid tab switching (35 switches, 5 full cycles) — no crashes                | K        | PASS   |
| L46  | Console errors: 0 errors total                                               | L        | PASS   |
| L47  | 1 expected warning (WebGPU JSPI fallback) — not a bug                        | L        | PASS   |
| M48  | Settings: Temperature slider renders with "0.7"                              | M        | PASS   |
| M49  | Settings: Temperature slider updates display (changed to 1.2)                | M        | PASS   |
| M50  | Settings: Max Tokens default 2048                                            | M        | PASS   |
| M51  | Settings: Minus button decreases by 500 (2048 to 1548)                       | M        | PASS   |
| M52  | Settings: Plus button increases by 500 (1548 to 2048)                        | M        | PASS   |
| M53  | Settings: API Key input field renders                                        | M        | PASS   |
| M54  | Settings: Base URL input field renders                                       | M        | PASS   |
| M55  | Settings: Analytics toggle renders                                           | M        | PASS   |
| M56  | Settings: Documentation link renders (cursor pointer)                        | M        | PASS   |
| M57  | Settings: About section — SDK v0.1.0, Platform: Web (Emscripten WASM)        | M        | PASS   |
| M58  | Settings: Persistence via localStorage (runanywhere-settings key)            | M        | PASS   |
| N59  | Chat: Send button disabled when input empty                                  | N        | PASS   |
| N60  | Chat: Send button enables after typing                                       | N        | PASS   |
| N63  | Chat: 4 suggestion chips render on empty state                               | N        | PASS   |
| N65  | Chat: "Get Started" overlay visible when no model loaded                     | N        | PASS   |
| N66  | Chat: "Get Started" opens model selection sheet                              | N        | PASS   |
| N67  | Chat: Tools toggle button with "Tools" label                                 | N        | PASS   |
| N68  | Chat: Tools toggle enables — badge "weather, time, calculator" + suggestions | N        | PASS   |
| N70  | Chat: Model selector shows "Select Model"                                    | N        | PASS   |
| N71  | Chat: Empty state (robot icon + "Start a conversation")                      | N        | PASS   |
| O72  | Vision: Model overlay with "Get Started" button                              | O        | PASS   |
| O73  | Vision: Camera container renders                                             | O        | PASS   |
| O74  | Vision: Capture button renders                                               | O        | PASS   |
| O75  | Vision: Live mode toggle button renders                                      | O        | PASS   |
| O76  | Vision: Description panel renders                                            | O        | PASS   |
| O77  | Vision: Copy button renders                                                  | O        | PASS   |
| O78  | Vision: Model selector shows "Select Vision Model"                           | O        | PASS   |
| O79  | Vision: Metrics area renders                                                 | O        | PASS   |
| P80  | Voice: 3 setup cards render (STT, LLM, TTS)                                 | P        | PASS   |
| P81  | Voice: Step numbers 1, 2, 3 shown                                           | P        | PASS   |
| P82  | Voice: "Select" status shown on each card                                    | P        | PASS   |
| P83  | Voice: Start button disabled until all 3 models selected                     | P        | PASS   |
| P84  | Voice: STT card opens with Whisper Tiny English (ONNX, 105 MB)              | P        | PASS   |
| P85  | Voice: LLM card opens with 6 LLM models                                     | P        | PASS   |
| P86  | Voice: TTS card opens with 2 Piper TTS models (ONNX, 65 MB)                 | P        | PASS   |
| P87  | Voice: Back button present in DOM (hidden on setup screen)                   | P        | PASS   |
| Q88  | Transcribe: Batch mode selected by default                                   | Q        | PASS   |
| Q89  | Transcribe: Description "Record first, then transcribe"                      | Q        | PASS   |
| Q90  | Transcribe: Live mode activates, description "Auto-transcribe on silence"    | Q        | PASS   |
| Q91  | Transcribe: Batch mode reactivates correctly                                 | Q        | PASS   |
| Q92  | Transcribe: Mic button with "Tap to start recording"                         | Q        | PASS   |
| Q93  | Transcribe: Waveform animation area renders                                  | Q        | PASS   |
| Q94  | Transcribe: Level bars (20 bars) render                                      | Q        | PASS   |
| Q95  | Transcribe: Result area renders                                              | Q        | PASS   |
| Q96  | Transcribe: Status badge renders                                             | Q        | PASS   |
| Q97  | Transcribe: Model selector "Select STT Model"                               | Q        | PASS   |
| R98  | Speak: Textarea with placeholder "Enter text to speak..."                    | R        | PASS   |
| R99  | Speak: "Surprise me" button renders                                          | R        | PASS   |
| R100 | Speak: "Surprise me" fills textarea with random joke                         | R        | PASS   |
| R101 | Speak: Speed slider default 1.0x                                             | R        | PASS   |
| R102 | Speak: Speed slider updates to 1.5x                                          | R        | PASS   |
| R103 | Speak: Speak button renders                                                  | R        | PASS   |
| R104 | Speak: Model selector "Select TTS Model"                                     | R        | PASS   |
| R105 | Speak: Empty text error "Please enter some text to speak."                   | R        | PASS   |
| T110 | Acceleration badge renders on page load                                      | T        | PASS   |
| T111 | Badge text is "CPU"                                                          | T        | PASS   |
| T112 | Badge persists across tab navigation                                         | T        | PASS   |

### Persistence Tests (Page Refresh)

| #    | Test                                                                              | Result |
| ---- | --------------------------------------------------------------------------------- | ------ |
| U1   | localStorage: settings saved before refresh (temp=1.2, maxTokens=1548)            | PASS   |
| U2   | localStorage: temperature=1.2 persists after page reload                          | PASS   |
| U3   | localStorage: maxTokens=1548 persists after page reload                           | PASS   |
| U4   | localStorage: apiKey (empty) persists after page reload                           | PASS   |
| U5   | localStorage: analytics=true persists after page reload                           | PASS   |
| U6   | Settings UI: Temperature slider shows "1.2" after reload                          | PASS   |
| U7   | Settings UI: Max Tokens shows "1548" after reload                                 | PASS   |
| U8   | OPFS: models directory persists after page reload                                 | PASS   |
| U9   | OPFS: _metadata.json file persists after reload                                   | PASS   |
| U10  | Storage quota accessible after reload (>0)                                        | PASS   |
| U11  | Storage tab: model count renders after reload                                     | PASS   |
| U12  | Storage tab: total size renders after reload                                      | PASS   |
| U13  | Storage tab: available space renders after reload                                 | PASS   |

### Post-Refresh Stability

| Check                                                     | Result |
| --------------------------------------------------------- | ------ |
| SDK re-initializes after refresh (console confirms)       | PASS   |
| Both backends re-register after refresh                   | PASS   |
| CPU badge renders after refresh                           | PASS   |
| Rapid tab switching (3 cycles) after refresh — no crashes | PASS   |
| Chat empty state renders after refresh                    | PASS   |
| Console errors after all persistence tests: 0             | PASS   |

### Expected Warnings (Run 4)

| #   | Warning                                                              | Classification                              |
| --- | -------------------------------------------------------------------- | ------------------------------------------- |
| 1   | `WebGPU WASM build lacks JSPI support. Falling back to CPU.`        | EXPECTED — WebGPU variant not built with JSPI |

---

## Test Run 3: Feb 16, 2026 (Extended Coverage — Playwright MCP Automated)

Total Tests: 65 | PASS: 65 | FAIL: 0 | BUGS: 0

### New Categories Added (M–T) and Full Re-verification (A–L)

| #    | Test                                                                          | Category | Result |
| ---- | ----------------------------------------------------------------------------- | -------- | ------ |
| A1   | All 7 tabs render (Chat, Vision, Voice, Transcribe, Speak, Storage, Settings) | A        | PASS   |
| A2   | CPU badge appears                                                             | A        | PASS   |
| A3   | Console log: "RunAnywhere Web SDK initialized successfully"                   | A        | PASS   |
| A4   | Backend registration: LlamaCpp + ONNX both registered                        | A        | PASS   |
| A5   | No JS errors in console (0 errors, 1 expected warning)                       | A        | PASS   |
| B6   | Model selector lists 6 LLM models                                            | B        | PASS   |
| B7   | All models show "LlamaCpp" framework badge                                   | B        | PASS   |
| B8   | Model sizes displayed (250 MB – 1.4 GB)                                      | B        | PASS   |
| B9   | Close model selector — no side effects                                       | B        | PASS   |
| F24  | Storage tab shows "Browser Storage (OPFS)"                                   | F        | PASS   |
| F25  | "Choose Storage Folder" button present                                       | F        | PASS   |
| F26  | "Import Model File" button present                                           | F        | PASS   |
| F27  | Storage stats: model count, total size, available space                      | F        | PASS   |
| F28  | Quota bar renders with usage/total                                           | F        | PASS   |
| K44  | All 7 tabs render without errors                                             | K        | PASS   |
| K45  | Rapid tab switching (21 switches, 3 full cycles) — no crashes                | K        | PASS   |
| L46  | Console errors: 0 errors total                                               | L        | PASS   |
| L47  | 1 expected warning (WebGPU JSPI fallback) — not a bug                        | L        | PASS   |
| M48  | Settings: Temperature slider renders with "0.7"                              | M        | PASS   |
| M49  | Settings: Temperature slider updates display (changed to 1.2)                | M        | PASS   |
| M50  | Settings: Max Tokens default 2048                                            | M        | PASS   |
| M51  | Settings: Minus button decreases by 500 (2048 to 1548)                       | M        | PASS   |
| M52  | Settings: Plus button increases by 500 (1548 to 2048)                        | M        | PASS   |
| M53  | Settings: API Key input field renders                                        | M        | PASS   |
| M54  | Settings: Base URL input field renders                                       | M        | PASS   |
| M55  | Settings: Analytics toggle renders                                           | M        | PASS   |
| M56  | Settings: Documentation link renders (cursor pointer)                        | M        | PASS   |
| M57  | Settings: About section — SDK v0.1.0, Platform: Web (Emscripten WASM)        | M        | PASS   |
| M58  | Settings: Persistence via localStorage (runanywhere-settings key)            | M        | PASS   |
| N59  | Chat: Send button disabled when input empty                                  | N        | PASS   |
| N60  | Chat: Send button enables after typing                                       | N        | PASS   |
| N63  | Chat: 4 suggestion chips render on empty state                               | N        | PASS   |
| N65  | Chat: "Get Started" overlay visible when no model loaded                     | N        | PASS   |
| N66  | Chat: "Get Started" opens model selection sheet                              | N        | PASS   |
| N67  | Chat: Tools toggle button with "Tools" label                                 | N        | PASS   |
| N68  | Chat: Tools toggle enables — badge "weather, time, calculator" + suggestions | N        | PASS   |
| N70  | Chat: Model selector shows "Select Model"                                    | N        | PASS   |
| N71  | Chat: Empty state (robot icon + "Start a conversation")                      | N        | PASS   |
| O72  | Vision: Model overlay with "Get Started" button                              | O        | PASS   |
| O73  | Vision: Camera container renders                                             | O        | PASS   |
| O74  | Vision: Capture button renders                                               | O        | PASS   |
| O75  | Vision: Live mode toggle button renders                                      | O        | PASS   |
| O76  | Vision: Description panel renders                                            | O        | PASS   |
| O77  | Vision: Copy button renders                                                  | O        | PASS   |
| O78  | Vision: Model selector shows "Select Vision Model"                           | O        | PASS   |
| O79  | Vision: Metrics area renders                                                 | O        | PASS   |
| P80  | Voice: 3 setup cards render (STT, LLM, TTS)                                 | P        | PASS   |
| P81  | Voice: Step numbers 1, 2, 3 shown                                           | P        | PASS   |
| P82  | Voice: "Select" status shown on each card                                    | P        | PASS   |
| P83  | Voice: Start button disabled until all 3 models selected                     | P        | PASS   |
| P84  | Voice: STT card opens with Whisper Tiny English (ONNX, 105 MB)              | P        | PASS   |
| P85  | Voice: LLM card opens with 6 LLM models                                     | P        | PASS   |
| P86  | Voice: TTS card opens with 2 Piper TTS models (ONNX, 65 MB)                 | P        | PASS   |
| P87  | Voice: Back button present in DOM (hidden on setup screen)                   | P        | PASS   |
| Q88  | Transcribe: Batch mode selected by default                                   | Q        | PASS   |
| Q89  | Transcribe: Description "Record first, then transcribe"                      | Q        | PASS   |
| Q90  | Transcribe: Live mode activates, description "Auto-transcribe on silence"    | Q        | PASS   |
| Q91  | Transcribe: Batch mode reactivates correctly                                 | Q        | PASS   |
| Q92  | Transcribe: Mic button with "Tap to start recording"                         | Q        | PASS   |
| Q93  | Transcribe: Waveform animation area renders                                  | Q        | PASS   |
| Q94  | Transcribe: Level bars (20 bars) render                                      | Q        | PASS   |
| Q95  | Transcribe: Result area renders                                              | Q        | PASS   |
| Q96  | Transcribe: Status badge renders                                             | Q        | PASS   |
| Q97  | Transcribe: Model selector "Select STT Model"                               | Q        | PASS   |
| R98  | Speak: Textarea with placeholder "Enter text to speak..."                    | R        | PASS   |
| R99  | Speak: "Surprise me" button renders                                          | R        | PASS   |
| R100 | Speak: "Surprise me" fills textarea with random joke                         | R        | PASS   |
| R101 | Speak: Speed slider default 1.0x                                             | R        | PASS   |
| R102 | Speak: Speed slider updates to 1.5x                                          | R        | PASS   |
| R103 | Speak: Speak button renders                                                  | R        | PASS   |
| R104 | Speak: Model selector "Select TTS Model"                                     | R        | PASS   |
| R105 | Speak: Empty text error "Please enter some text to speak."                   | R        | PASS   |
| T110 | Acceleration badge renders on page load                                      | T        | PASS   |
| T111 | Badge text is "CPU"                                                          | T        | PASS   |
| T112 | Badge persists across tab navigation                                         | T        | PASS   |

### Additional Verifications

| Check                                                        | Result |
| ------------------------------------------------------------ | ------ |
| OPFS storage accessible (models directory exists)            | PASS   |
| Model sheet device info: Chrome, 8 GB, 16 CPU Cores         | PASS   |
| Backdrop click dismisses model sheet                         | PASS   |
| Tab lifecycle callbacks fire (Vision deactivate logged)      | PASS   |
| Tools toggle off clears badge                                | PASS   |
| localStorage stores settings as JSON (`runanywhere-settings`) | PASS   |
| Final console audit: 0 errors after all tests                | PASS   |

### Expected Warnings (Run 3)

| #   | Warning                                                              | Classification                              |
| --- | -------------------------------------------------------------------- | ------------------------------------------- |
| 1   | `WebGPU WASM build lacks JSPI support. Falling back to CPU.`        | EXPECTED — WebGPU variant not built with JSPI |

---

## Test Run 2: Feb 16, 2026 (Full Capability Test)

Total Tests: 26 | PASS: 26 | FAIL: 0 | BUGS: 0

### Capabilities Tested

| Capability                                        | Test                                               | Result             |
| ------------------------------------------------- | -------------------------------------------------- | ------------------ |
| WASM Init + CPU fallback                          | Both backends registered                           | PASS               |
| Model catalog                                     | 14 models (6 LLM, 4 VLM, 1 STT, 2 TTS, 1 VAD)   | PASS               |
| OPFS Download                                     | 218.7 MB model downloaded to OPFS                  | PASS               |
| OPFS Persistence (refresh)                        | Model survives page refresh                        | PASS               |
| OPFS Persistence (delete + re-download + refresh) | Full cycle tested                                  | PASS               |
| LLM Load into WASM                                | Model loaded in 222ms                              | PASS               |
| LLM Non-streaming generation                      | "Addition." response, 1.6 tok/s                    | PASS               |
| LLM Streaming generation                          | Joke generated, 24.4 tok/s, 49 tokens              | PASS               |
| LLM Unload                                        | Status returns to "downloaded"                     | PASS               |
| STT model registry                                | sherpa-onnx-whisper-tiny.en found                  | PASS               |
| STT without model                                 | Expected error: "Sherpa-ONNX WASM not loaded"      | PASS (correct err) |
| TTS model registry                                | 2 Piper TTS models found                           | PASS               |
| TTS without model                                 | Expected error: "Sherpa-ONNX WASM not loaded"      | PASS (correct err) |
| VAD model registry                                | Silero VAD v5 found                                | PASS               |
| Storage tab UI                                    | All elements render                                | PASS               |
| Import Model File button                          | No crash on click                                  | PASS               |
| Model deletion                                    | OPFS cleaned, status "registered"                  | PASS               |
| Cross-tab navigation                              | All 7 tabs stable, 0 errors                        | PASS               |

### Notes on STT/TTS/VAD

STT, TTS, and VAD models were not downloaded during this test (each is 10-50 MB and requires the sherpa-onnx WASM module). The models are correctly registered in the catalog. When attempting to use them without downloading, the SDK correctly throws: "Sherpa-ONNX WASM not loaded. Call ensureLoaded() first." — this is expected behavior, not a bug. To test these fully, download the STT/TTS/VAD models first.

---

## Test Run 1: Feb 16, 2026 (Core Test)

Total Tests: 39 | PASS: 39 | FAIL: 0 | BUGS: 0

No bugs found during this test run.

### Expected Warnings (Run 1)

| #   | Warning                                                              | Classification                                       |
| --- | -------------------------------------------------------------------- | ---------------------------------------------------- |
| 1   | `WebGPU WASM build lacks JSPI support. Falling back to CPU.`        | EXPECTED — WebGPU variant not built                  |
| 2   | `Model NOT found in registry (result=-423), using default framework=1` | EXPECTED — Dynamic model from OPFS                 |
| 3   | `n_ctx_seq (8192) < n_ctx_train (128000)`                           | EXPECTED — Context window limited for browser        |

---

## Previously Fixed Bugs (found during development)

| #   | Bug                                                                                       | Fix                                                         | File                       |
| --- | ----------------------------------------------------------------------------------------- | ----------------------------------------------------------- | -------------------------- |
| 1   | OPFS persistence race condition — refreshDownloadStatus ran before OPFS initialized       | Added await this.storage.initialize() at start              | ModelManager.ts            |
| 2   | Sherpa-ONNX JS files lacked ESM exports                                                   | Added export statements to sherpa JS files                  | packages/onnx/wasm/sherpa  |
| 3   | Module duplication causing singleton mismatch                                             | Added resolve.alias in vite.config.ts                       | vite.config.ts             |
| 4   | Peer dependency version mismatch — semver prerelease issue                                | Changed to >=0.1.0-beta.0                                   | packages/*/package.json    |
