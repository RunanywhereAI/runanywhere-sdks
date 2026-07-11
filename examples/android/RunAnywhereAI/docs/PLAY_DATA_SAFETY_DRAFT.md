# Google Play Data safety draft

This is an engineering inventory, not the final Console declaration. Recheck the
exact production backend, SDK inventory, cloud-provider list, retention, and
whether each data type is collected ephemerally before submitting.

## App-wide answers

- Data is encrypted in transit: **Yes**, provided every configured production,
  model-host, and optional cloud-provider endpoint uses HTTPS.
- Users can request deletion: **Yes only after** the public deletion/contact
  process in the privacy policy is live and operational.
- Account creation: the current Android app does not create a RunAnywhere user
  account. Reassess if Play Console or backend behavior changes.
- Ads: none in the current source.

## Data collected by RunAnywhere

| Play category | Actual data | Purpose | Notes |
|---|---|---|---|
| Device or other IDs | Random persistent SDK device ID / fingerprint | App functionality, SDK installation registration, fraud/abuse prevention | Transferred automatically to create or update registration during first and subsequent SDK initializations while the production control plane is enabled |
| App activity | Feature lifecycle and interaction events | Analytics, diagnostics, app functionality | Collected automatically in configured production builds; no prompt/response body |
| App info and performance | App/SDK version, model/framework IDs, latency, available-memory and token/count metrics, errors | Analytics, diagnostics, app functionality | Collected automatically in configured production builds |
| Device info | Device/OS details, CPU architecture and chip, form factor, total and available memory, neural-acceleration availability, CPU/GPU/NPU core details, and battery/power details | App functionality, SDK registration, analytics | Collected automatically in configured production builds |
| Search history or User content (confirm the current Play Console taxonomy) | Search query generated from the user's prompt | App functionality | Collected by the RunAnywhere search proxy only when tool calling is enabled and the model invokes `search_web`; describe as ephemeral only after the production backend's deletion behavior is verified |

Mark each row as linked or not linked based on the production backend's ability
to associate it with an identifiable user. SDK installation registration and
feature, performance, and error diagnostics are sent automatically in configured
production builds; the app does not present a separate diagnostics-consent screen
or preference.

## Data sent to third parties at the user's direction

| Recipient | Data | Trigger |
|---|---|---|
| Hugging Face | Authentication token, requested model repository/files, network metadata | Private model download |
| GitHub/model hosts | Requested public model files, network metadata | Public model download |
| User-configured cloud STT provider | Audio, language/model/request metadata, provider API key | User selects and runs Hybrid (Beta)/cloud transcription |
| RunAnywhere search proxy and [production search provider] | Web-search query and ordinary network metadata | User enables tool calling and the model invokes `search_web`; the query may be derived from the user's prompt. Developer builds without the proxy may contact DuckDuckGo directly |

Determine in Play Console whether each flow is a disclosed transfer, collection,
or exempt user-initiated action under the current Data safety definitions. Do not
claim that audio never leaves the device while cloud STT remains in the build.

## Data kept only on device

Prompts, ordinary AI answers, conversation history, copied attachments, documents,
images/camera frames, local microphone recordings/transcripts, model files,
benchmarks, Hugging Face token, and cloud-provider credentials remain app-private
unless the user invokes a cloud or web-search/tool flow, exports/shares a
benchmark, or opens an external service.

## Pre-submission evidence

- Capture the final dependency/SBOM and Play SDK Index results.
- Inspect production network traffic for a clean install and every optional cloud
  flow; compare it to this inventory.
- Publish the final privacy policy at the exact in-app and Play Console URL.
- Record backend retention/deletion behavior.
- Name the production search provider, document its query retention/deletion behavior,
  and verify the provider credential exists only behind the HTTPS proxy, never in the APK.
