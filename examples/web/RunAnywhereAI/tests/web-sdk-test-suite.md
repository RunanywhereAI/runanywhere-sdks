# Web SDK Comprehensive Test Suite

## Test Categories

### A. App Load and SDK Initialization

1. Navigate to the app — verify all 7 tabs render (Chat, Vision, Voice, Transcribe, Speak, Storage, Settings)
2. Verify the CPU badge appears in top-right (proves WASM loaded)
3. Check console for SDK initialization logs: "RunAnywhere Web SDK initialized successfully"
4. Check console for backend registration: "LlamaCpp backend registered", "ONNX backend registered"
5. Verify no JavaScript errors in console (exclude expected WASM warnings)

### B. Model Registry and Catalog

1. Open the model selector (Chat > Get Started) — verify models are listed
2. Verify each model shows "LlamaCpp" framework badge (proves multi-package imports work)
3. Verify model sizes are displayed (e.g. "250 MB", "500 MB")
4. Close the model selector without downloading — verify no side effects

### C. Model Download and OPFS Persistence

1. Download the smallest model (LFM2 350M Q4_K_M, ~250 MB)
2. Verify download progress shows in UI
3. After download completes, verify model shows as "downloaded" in Storage tab
4. Verify OPFS contains the model file (check via JS API)
5. Refresh the page — verify model still shows as "downloaded" (OPFS persistence fix)
6. Verify model size and "Last used" timestamp are correct after refresh

### D. Model Loading into WASM Memory

1. After download, load the model (click on it in the model selector)
2. Verify model status changes to "loaded"
3. Verify the chat input becomes available
4. Send a test message and verify text generation starts (tokens stream in)
5. Verify generation completes with a response

### E. Model Unloading and Switching

1. After generation, go to Storage tab — verify model shows as "loaded"
2. Try loading a different model — verify the previous one is unloaded first
3. After unloading, verify model status returns to "downloaded"

### F. Storage Tab — Local File Storage

1. Navigate to Storage tab — verify "Browser Storage (OPFS)" label shown
2. Verify "Choose Storage Folder" button is present
3. Verify "Import Model File" button is present
4. Verify storage stats show correct model count, total size, available space
5. Verify quota bar renders with correct proportions

### G. Import Model File

1. Click "Import Model File" button — verify file picker opens (or input fallback)
2. Cancel the file picker — verify no crash, no side effects
3. (If possible) Import a model file — verify it appears in the model list

### H. Drag and Drop (Desktop)

1. Verify drag-drop zone appears when dragging files over Storage tab
2. Verify drag-drop zone disappears when dragging away

### I. Model Deletion

1. In Storage tab, click "Delete" on a model
2. Verify confirmation dialog appears
3. Cancel deletion — verify model is still there
4. Confirm deletion — verify model is removed from list
5. Verify OPFS no longer contains the deleted model
6. Verify model status returns to "registered" in the model selector

### J. Clear All Models

1. Download a model, then click "Clear All Models"
2. Verify confirmation dialog appears
3. Confirm — verify all models cleared
4. Verify OPFS is empty

### K. Cross-Tab Navigation

1. Navigate to each tab and verify UI renders without errors: Chat, Vision, Voice, Transcribe, Speak, Storage, Settings
2. Navigate rapidly between tabs — verify no crashes

### L. Console Error Audit

1. After all tests, collect all console errors
2. Classify: expected (WASM fallback) vs unexpected (real bugs)

### M. Settings Tab

1. Navigate to Settings — verify Temperature slider renders with value "0.7"
2. Adjust Temperature slider — verify display updates (0.0–2.0, step 0.1)
3. Verify Max Tokens stepper shows default value (e.g. 2048)
4. Click minus button — verify token count decreases by 500 (min 500)
5. Click plus button — verify token count increases by 500 (max 20000)
6. Verify API Key input field renders (type=password)
7. Verify Base URL input field renders
8. Verify Analytics toggle renders and is clickable
9. Verify "Documentation" link points to runanywhere.ai docs
10. Verify About section shows SDK version and platform info
11. Change settings, refresh page — verify settings persist via localStorage

### N. Chat Tab — UI Interaction Details

1. Verify Send button is disabled when input is empty
2. Type a message — verify Send button enables
3. Verify Enter key submits message (without Shift)
4. Verify Shift+Enter creates a newline (does not submit)
5. Verify suggestion chips render on empty state (4 chips)
6. Click a suggestion chip — verify it fills input and sends
7. Verify "Get Started" overlay appears when no model loaded
8. Click "Get Started" — verify model selection sheet opens
9. Verify Tools toggle button renders with label "Tools"
10. Click Tools toggle — verify toggle changes state and badge appears
11. Verify New Chat button clears conversation when messages exist
12. Verify model selector button in toolbar shows "Select Model" initially
13. Verify empty state (robot icon + "Start a conversation") shows initially

### O. Vision Tab — UI Elements

1. Navigate to Vision — verify model overlay with "Get Started" button appears
2. Verify camera container area renders
3. Verify capture button (bulb icon) renders
4. Verify live mode toggle button renders
5. Verify description panel renders (initially empty)
6. Verify copy button renders in description panel
7. Verify model selector in toolbar shows "Select Vision Model"
8. Verify metrics area renders (hidden until first capture)

### P. Voice Tab — Pipeline Setup

1. Navigate to Voice — verify 3 setup cards render (STT, LLM, TTS)
2. Verify each card shows step number (1, 2, 3)
3. Verify each card shows "Select" status initially
4. Verify "Start Voice Assistant" button is disabled until all 3 models selected
5. Click STT card — verify model selection sheet opens with STT models
6. Click LLM card — verify model selection sheet opens with LLM models
7. Click TTS card — verify model selection sheet opens with TTS models
8. Verify back button is present (returns to setup from voice interface)

### Q. Transcribe Tab — Mode Controls

1. Navigate to Transcribe — verify Batch mode is selected by default
2. Verify mode description matches Batch ("Record audio, then transcribe")
3. Click Live mode — verify it activates and description updates
4. Click Batch mode — verify it reactivates
5. Verify mic button renders with "Tap to record" text
6. Verify waveform animation area renders
7. Verify level bars (20 bars) render
8. Verify result area renders (initially hidden/empty)
9. Verify status badge area renders
10. Verify model selector in toolbar shows "Select STT Model"

### R. Speak Tab — Controls

1. Navigate to Speak — verify textarea with placeholder "Enter text to speak..." renders
2. Verify "Surprise me" button renders
3. Click "Surprise me" — verify textarea fills with random text
4. Verify speed slider renders with default 1.0x
5. Adjust speed slider — verify display value updates (0.5x–2.0x)
6. Verify Speak button renders
7. Verify model selector in toolbar shows "Select TTS Model"
8. Click Speak with empty text — verify error message appears

### S. Model-Switch Banner

1. Load an LLM model on Chat tab, then switch to Vision tab — verify model-switch banner appears
2. Verify banner text explains model category difference
3. Click dismiss button — verify banner disappears
4. Switch between tabs with same model category — verify no banner appears

### T. Acceleration Badge

1. Verify acceleration badge renders on page load
2. Verify badge text is "CPU" or "WebGPU" based on hardware
3. Verify badge is visible in all tabs (persists across navigation)

### U. Telemetry Verification — Development Mode (Supabase)

This section verifies that analytics telemetry is correctly sent to the Supabase backend
in development mode. Credentials are embedded in the WASM module via `development_config.cpp`.

**Dev Endpoint:** `https://<dev-project-id>.supabase.co/rest/v1/telemetry_events` *(URL redacted — stored in dev config)*

**Verification method:** Use DevTools Network tab or Playwright `browser_network_requests` to inspect HTTP POSTs.

#### U1. SDK Init — Device Registration & Telemetry Setup

1. Open app — check console for:
   - `[INFO] [RunAnywhere:HTTPService] Development mode configured with Supabase`
   - `[INFO] [RunAnywhere:TelemetryService] HTTPService configured with WASM dev config (Supabase)`
   - `[INFO] [RunAnywhere:TelemetryService] TelemetryService initialized (env=development, device=<uuid>...)`
   - `[INFO] [RunAnywhere:AnalyticsEventsBridge] Analytics events callback registered`
2. Check `localStorage['rac_device_id']` — verify it is a UUID (e.g. `de9a040f-...`, 36 chars)
3. Refresh page — verify `rac_device_id` is **the same** UUID (persistent)

#### U2. Dev Telemetry POST — Network Inspection

After SDK init (backend registration completes), check Network tab for:

1. At least one POST to the dev Supabase telemetry endpoint (check Network tab — URL contains `supabase.co/rest/v1/telemetry_events`)
2. Response status: `200` or `201` (or `204` for Supabase upsert)
3. Request headers include:
   - `Content-Type: application/json`
   - `apikey: <supabase-anon-key>` (starts with `eyJ`)
   - `Authorization: Bearer <supabase-anon-key>`
4. Request body is valid JSON array or object

#### U3. Telemetry Payload — Required Common Fields

Inspect the POST body of any telemetry request and verify these fields are present:

| Field | Expected Value |
|-------|---------------|
| `event_type` | Non-empty string (e.g. `"llm.backend.registered"`) |
| `device_id` | UUID matching `localStorage['rac_device_id']` |
| `platform` | `"web"` |
| `sdk_version` | `"0.1.0-beta.8"` (or current version) |
| `timestamp_ms` | Integer Unix timestamp in milliseconds |
| `modality` | `"llm"`, `"stt"`, `"tts"`, `"model"`, or `"system"` |

#### U4. Telemetry — LLM Generation Event

*(Requires downloading and loading an LLM model, then running a chat generation)*

After `LlamaCPP.register()` and a text generation, verify a POST contains:

| Field | Expected |
|-------|---------|
| `event_type` | `"llm.generation.completed"` |
| `modality` | `"llm"` |
| `output_tokens` | Integer > 0 |
| `tokens_per_second` | Float > 0 |
| `generation_time_ms` | Float > 0 |
| `time_to_first_token_ms` | Float ≥ 0 |
| `model_id` | Non-empty string |
| `framework` | `"llamacpp"` |
| `platform` | `"web"` |

#### U5. Telemetry — LLM Model Load Event

After loading an LLM model, verify a POST contains:

| Field | Expected |
|-------|---------|
| `event_type` | `"llm.model.load.completed"` |
| `modality` | `"llm"` |
| `model_id` | Non-empty string |
| `processing_time_ms` | Float > 0 (load duration) |
| `model_size_bytes` | Integer > 0 |
| `framework` | `"llamacpp"` |
| `platform` | `"web"` |

#### U6. Telemetry — STT Transcription Event

*(Requires ONNX backend loaded with a Whisper STT model and microphone input)*

After a transcription completes, verify a POST contains:

| Field | Expected |
|-------|---------|
| `event_type` | `"stt.transcription.completed"` |
| `modality` | `"stt"` |
| `audio_duration_ms` | Float > 0 |
| `real_time_factor` | Float > 0 |
| `word_count` | Integer ≥ 0 |
| `confidence` | Float 0.0–1.0 |
| `model_id` | Non-empty string |
| `framework` | `"onnx"` |
| `platform` | `"web"` |

#### U7. Telemetry — TTS Synthesis Event

*(Requires ONNX backend loaded with a Piper TTS model and Speak tab usage)*

After a TTS synthesis completes, verify a POST contains:

| Field | Expected |
|-------|---------|
| `event_type` | `"tts.synthesis.completed"` |
| `modality` | `"tts"` |
| `character_count` | Integer > 0 |
| `characters_per_second` | Float > 0 |
| `output_duration_ms` | Float > 0 |
| `audio_size_bytes` | Integer > 0 |
| `sample_rate` | Integer (e.g. 22050 or 44100) |
| `model_id` | Non-empty string |
| `framework` | `"onnx"` |
| `platform` | `"web"` |

#### U8. Telemetry — Model Download Event

*(Requires initiating a model download from the model selector)*

During/after model download, verify a POST contains:

| Field | Expected |
|-------|---------|
| `event_type` | `"model.download.completed"` |
| `modality` | `"model"` |
| `model_id` | Non-empty string |
| `model_size_bytes` | Integer > 0 |
| `processing_time_ms` | Float > 0 (download duration) |
| `platform` | `"web"` |

#### U9. Telemetry — VAD Event

*(Requires Voice tab with VAD active and speech input)*

When speech activity is detected and ends, verify a POST contains:

| Field | Expected |
|-------|---------|
| `event_type` | `"vad.speech.ended"` |
| `modality` | `"system"` |
| `speech_duration_ms` | Float > 0 |
| `platform` | `"web"` |

#### U10. Telemetry Batching Behavior

1. In dev mode (default): telemetry events flush **immediately** on each event (no batching delay)
2. Verify: after backend registration, a POST fires within 1-2 seconds of the SDK init log
3. In prod mode: events batch in groups of 10 or flush after 5-second timeout

#### U11. Device ID Persistence

1. Check `localStorage['rac_device_id']` before page reload
2. Reload page
3. Check `localStorage['rac_device_id']` after reload — must be **identical**
4. Verify all telemetry POSTs use the same `device_id` throughout the session

### V. Telemetry Verification — Production Mode

*(Pending: user to provide production API key and base URL)*

**Prod Endpoint:** `<base-url>/api/v1/sdk/telemetry`

#### V1. Configure Production Credentials

To test production telemetry:
1. Set API key in Settings tab → "API Key" field
2. Set base URL in Settings tab → "Base URL" field
3. Or configure via `RunAnywhere.initialize({ apiKey: '...', baseURL: '...' })`

#### V2. Prod Telemetry POST — Network Inspection

After configuring production credentials, repeat U2-U9 tests and verify:

1. POST goes to `<base-url>/api/v1/sdk/telemetry` (NOT Supabase)
2. Request headers include:
   - `Authorization: Bearer <api-key>`
   - `Content-Type: application/json`
3. Response status: `200` or `202`
4. Payload fields match the same schema as development (same `rac_telemetry_payload_t` fields)

#### V3. Prod Batching — 10 Events or 5s Timeout

In production mode (unlike dev's immediate flush):
1. Trigger multiple events (multiple tab switches, multiple tool calls)
2. Verify batch of 10 events triggers a single POST (not 10 separate POSTs)
3. Or wait 5 seconds after any event — verify POST fires within 5s timeout

---

## Bug Report File

Bugs found during testing will be written to:
`tests/web-sdk-bugs.md`
