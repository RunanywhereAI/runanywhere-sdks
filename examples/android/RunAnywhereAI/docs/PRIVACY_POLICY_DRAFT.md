# RunAnywhere privacy policy draft

> Publication placeholders: replace every bracketed value, have the final text
> reviewed by the publisher, and host it as a public HTTPS web page (not a PDF).

Effective date: [effective date]

RunAnywhere is published by [developer legal name] ("RunAnywhere," "we," or
"us"). Contact us about privacy at [privacy email and postal contact].

## What the app does locally

The app can run language, vision, speech, embedding, and document-retrieval
models on the device. By default, prompts, generated answers, selected images,
camera frames, microphone recordings, document contents, conversation history,
model files, Hugging Face credentials, and cloud-provider credentials are stored
or processed on the device. Production SDK authentication can also store access
and refresh tokens plus backend-assigned device, user, or organization identifiers
in the app's secure storage.
Conversation history and copied attachments remain in app-private storage until
the user deletes the conversation or the app. Android backup and device transfer
are disabled for this app.

## Data sent to RunAnywhere

During the first and each subsequent SDK initialization, the app automatically
authenticates with the RunAnywhere control plane, creates or updates the SDK
installation registration, fetches model assignments, and flushes telemetry. It
sends a randomly generated persistent device identifier; possible backend user
or organization identifiers; app package identifier, app name, version, and build;
locale and timezone; device, operating-system, and SDK details; CPU architecture
and chip name; form factor; total and available memory; neural-acceleration
availability; CPU/GPU/NPU core and battery/power details; model and framework
identifiers; feature lifecycle and cancellation events; performance measurements;
token or character counts; audio duration and size; image count and resolution;
network status; and error diagnostics to [backend operator and country]. This data
is used for SDK authentication and assignment sync and to operate, analyze, secure,
and diagnose the app. The app does not present a separate diagnostics-consent
screen or Settings preference.

Ordinary structured modality telemetry is designed to send measurements and
counts rather than prompt, response, document, image, audio, or transcript bodies.
However, the current telemetry path also transmits raw SDK `error_message` text
without a demonstrated universal content-redaction boundary. An error string may
therefore contain user or generated content, a URL, a local path, a transcript
fragment, or a provider response. Do not publish an absolute claim that diagnostics
never include content, and declare the applicable Play user-content category,
unless every transmitted error path is sanitized and covered by tests before the
final release.

Before publication, state the registration and diagnostics retention
periods here: [retention periods and deletion/anonymization process].

## Optional third-party services

- Model downloads may contact Hugging Face or GitHub. A user-provided Hugging
  Face token is stored with Android encrypted preferences and sent only to
  Hugging Face to authorize private model downloads.
- A user may add a third-party cloud speech-to-text provider. When the user
  configures and selects Hybrid (Beta), the router may choose that provider based
  on network, battery, confidence, and ranking. Microphone audio, language/model
  settings, request metadata, and the provider credential are then sent directly
  to Sarvam, OpenAI, OpenRouter, or the user-configured HTTPS host under that
  provider's privacy terms. Provider API keys are stored with Android encrypted
  preferences.
- Tool calling is disabled by default. If the user enables it and the model
  invokes the built-in web-search tool, the generated search query and ordinary
  network metadata are sent either directly to DuckDuckGo when no proxy URL is
  configured or to [RunAnywhere search-proxy operator/country] and [production
  search provider] when a proxy is configured. The query may be derived from the
  user's prompt. The tested signed APK has no proxy URL and contacts DuckDuckGo
  directly; the Play AAB gate requires a real HTTPS proxy. Name the production
  provider and link all applicable privacy terms before release.
- A user can copy benchmark text to the system clipboard or share it with another
  app. The clipboard, selected app, and operating system handle that exported text
  under their own privacy and retention behavior.
- Opening Documentation, Privacy policy, or social links sends the user to the
  selected website or app and is governed by that service's privacy terms.

List the current subprocessors and links here: [RunAnywhere backend/search proxy],
[production search provider], Hugging Face, GitHub, and each cloud speech provider
offered in the released build.

## Permissions

The app requests microphone access for voice, transcription, and voice-activity
features, and camera access for photo and live-vision features. These permissions
are optional and can be revoked in Android settings.

## Legal bases, sharing, and sale

Describe the legal bases applicable to the publisher and each processing purpose:
[contract, legitimate interests, consent, or other basis]. We do not sell personal
data. We share data only with service providers needed for the functions described
above, when the user directs the app to a third-party provider, or when required by
law. [Confirm and adapt for the publisher's actual practices.]

## Security

Network endpoints required for publication use HTTPS. Credentials stored by the
app use Android encrypted preferences. No security measure is perfect; describe
the publisher's organizational safeguards and incident process here: [details].

## Choices, deletion, and retention

Users can delete individual conversations and their copied attachments, remove
downloaded models, clear caches, clear saved credentials, or uninstall the app to
remove app-private data. Some temporary files are deleted automatically, and
Android may evict cache files. Before claiming that users can delete backend data,
make an operational deletion process available at [privacy email or public
deletion-request URL], expose or otherwise provide a reliable installation-record
lookup method, and document requester verification, responsible operator, response
timeline, deletion scope, and a tested outcome. The current app does not display
its installation identifier, and the current engineering inventory does not prove
that this backend deletion process exists.

## Prominent disclosure and consent release decision

Production authentication, device registration, assignment sync, and diagnostics
begin automatically from `Application.onCreate`, before a user can reach the
Settings privacy link. The current app intentionally has no standalone privacy or
diagnostics-consent screen. Before Play submission, obtain publisher/privacy review
of whether this collection is within users' reasonable expectations. If Google
Play's prominent-disclosure rule applies, the website policy and Settings link are
not sufficient: the app will need an in-flow disclosure and affirmative consent
before collection, despite the current product preference to avoid an extra screen.

## Children and international transfers

State the intended age range and whether the app is directed to children:
[target audience statement]. Describe international transfer safeguards where
applicable: [details].

## Changes

We may update this policy. We will post the revised policy at [public privacy
policy URL], change the effective date, and provide any notice required by law.
