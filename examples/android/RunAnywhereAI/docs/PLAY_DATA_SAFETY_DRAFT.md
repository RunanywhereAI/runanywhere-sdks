# Google Play Data safety draft

This is an engineering inventory, not the final Console declaration. Recheck the
exact production backend, SDK inventory, cloud-provider list, retention, and
whether each data type is collected ephemerally before submitting.

## App-wide answers

- Data is encrypted in transit: **Yes**, provided every configured production,
  model-host, and optional cloud-provider endpoint uses HTTPS.
- Users can request deletion: **No for the current candidate**. Change this to
  **Yes only after** a public deletion/contact process, installation-record lookup,
  requester-verification procedure, responsible operator, and tested deletion
  outcome are live. The app does not currently display its installation ID.
- Account creation: the current Android app does not create a RunAnywhere user
  account. Reassess if Play Console or backend behavior changes.
- Ads: none in the current source.

## Data collected by RunAnywhere

| Play category | Actual data | Purpose | Notes |
|---|---|---|---|
| Device or other IDs | Random persistent SDK device ID / fingerprint | App functionality, SDK installation registration, fraud/abuse prevention | Transferred automatically to create or update registration during first and subsequent SDK initializations while the production control plane is enabled |
| Personal info / User IDs (confirm association) | Backend-returned user or organization identifier when the app credential is associated with one | App functionality, authentication, SDK registration | Verify whether the production backend associates diagnostics with an identifiable user or organization and declare linked status accordingly |
| App activity | Feature lifecycle and interaction events | Analytics, diagnostics, app functionality | Collected automatically in configured production builds; no prompt/response body |
| App info and performance | App/SDK version, model/framework IDs, latency, available-memory and token/count metrics, app and SDK warning/error text, and full throwable stack traces | Analytics, diagnostics, app functionality | Collected automatically in configured production builds. The Android app forwards `RACLog` warnings/errors into the SDK failure-event pipeline after SDK initialization |
| Device info | Device/OS details, app package/name/version/build, locale/timezone, CPU architecture and chip, form factor, total and available memory, neural-acceleration availability, CPU/GPU/NPU core details, and battery/power details | App functionality, SDK registration, analytics | Collected automatically in configured production builds |
| Other user-generated content (until redaction is proven) | Raw app/SDK `error_message` text and complete throwable stacks, which can include user/generated content, URLs, paths, transcript fragments, or provider responses | Diagnostics, app functionality | The current telemetry path sends app and SDK errors without a universal proven content-redaction boundary; do not claim content is excluded unless the final candidate sanitizes and tests every path |
| In-app search history | Search query generated from the user's prompt | App functionality | A blank proxy URL sends the query directly to DuckDuckGo; a configured proxy sends it to RunAnywhere and Brave Search. The release routing must match this declaration. Do not describe either path as ephemeral until the applicable provider and infrastructure retention are verified |

Mark each row as linked or not linked based on the production backend's ability
to associate it with an identifiable user, organization, app credential, or
persistent device ID. Production startup automatically performs SDK authentication,
device registration, model-assignment fetch, and telemetry flush. Feature,
performance, app warning/error, SDK error, and full throwable diagnostics are sent
automatically; the app does not present a separate diagnostics-consent screen or
preference.

## Data sent to third parties at the user's direction

| Recipient | Data | Trigger |
|---|---|---|
| Hugging Face | Authentication token, requested model repository/files, network metadata | Private model download |
| GitHub/model hosts | Requested public model files, network metadata | Public model download |
| Sarvam, OpenAI, OpenRouter, or user-configured HTTPS cloud STT host | Audio, language/model/request metadata, provider API key | User configures and selects Hybrid (Beta); the router can then choose the online provider based on network, battery, confidence, and ranking |
| DuckDuckGo when no proxy is configured; otherwise RunAnywhere search proxy and Brave Search | Web-search query, ordinary network metadata, and, for the proxy path, the persistent RunAnywhere device UUID | User enables tool calling and the model invokes `search_web`; the query may be derived from the user's prompt. The proxy HMAC-pseudonymizes the device UUID before limiter storage and forwards only the query/provider request metadata to Brave |
| System clipboard or user-selected app | Benchmark text selected by the user | User copies or shares a benchmark report |

Determine in Play Console whether each flow is a disclosed transfer, collection,
or exempt user-initiated action under the current Data safety definitions. Do not
claim that audio never leaves the device while cloud STT remains in the build.

## Data kept only on device

Prompts, ordinary AI answers, conversation history, copied attachments, documents,
images/camera frames, local microphone recordings/transcripts, model files,
benchmarks, Hugging Face token, cloud-provider credentials, and production SDK
access/refresh credentials normally remain app-private unless an error string
includes content, the user invokes a cloud or web-search/tool flow, the user
exports/shares a benchmark, or the user opens an external service.

## Pre-submission evidence

- Capture the final dependency/SBOM and Play SDK Index results.
- Inspect production network traffic for a clean install and every optional cloud
  flow; compare it to this inventory.
- Publish the final privacy policy at the exact in-app and Play Console URL.
- Record backend retention/deletion behavior and implement/test the deletion SOP
  before selecting the deletion-request badge.
- Verify Brave's selected plan and query retention/deletion behavior, Railway/proxy
  log retention, and that the provider/HMAC credentials exist only behind the HTTPS
  proxy, never in the APK. Exercise the installation, organization, and global caps.
- Obtain publisher/privacy review of whether automatic pre-UI production collection
  requires an in-flow prominent disclosure and affirmative consent under Play's User
  Data policy. The current Settings link alone is not an in-flow disclosure.
- Inventory every production `RACLog.warn`/`RACLog.error` and SDK failure publisher,
  then test representative prompts, transcripts, provider responses, URLs, local
  paths, and credentials before making any content-exclusion or redaction claim.
