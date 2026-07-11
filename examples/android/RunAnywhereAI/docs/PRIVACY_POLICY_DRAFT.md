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
model files, and Hugging Face credentials are stored or processed on the device.
Conversation history and copied attachments remain in app-private storage until
the user deletes the conversation or the app. Android backup and device transfer
are disabled for this app.

## Data sent to RunAnywhere

During the first and each subsequent SDK initialization, the app automatically
sends a randomly generated persistent device identifier; device, operating-system,
app, and SDK details; CPU architecture and chip name; form factor; total and
available memory; neural-acceleration availability; CPU/GPU/NPU core and
battery/power details; model identifiers; feature lifecycle events; performance
measurements; token or character counts; audio duration and size; image count and
resolution; and error diagnostics to [backend operator and country]. This data is
used to create or update the SDK installation registration and to operate, analyze,
and diagnose the app. These diagnostics do not include prompt text, generated
response text, document contents, images, raw audio, or transcripts. The app does
not present a separate diagnostics-consent screen or Settings preference.

Before publication, state the registration and diagnostics retention
periods here: [retention periods and deletion/anonymization process].

## Optional third-party services

- Model downloads may contact Hugging Face or GitHub. A user-provided Hugging
  Face token is stored with Android encrypted preferences and sent only to
  Hugging Face to authorize private model downloads.
- A user may add a third-party cloud speech-to-text provider. When the user
  explicitly uses that provider, microphone audio and the provider request are
  sent directly to the configured provider under that provider's privacy terms.
  Provider API keys are stored with Android encrypted preferences.
- Tool calling is disabled by default. If the user enables it and the model
  invokes the built-in web-search tool, the generated search query and ordinary
  network metadata are sent to [RunAnywhere search-proxy operator/country] and
  [production search provider]. The query may be derived from the user's prompt.
  Developer builds without the production proxy may send it directly to DuckDuckGo.
  Name the production provider and link both applicable privacy terms before release.
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
downloaded models, clear caches and temporary files, clear saved credentials, or
uninstall the app to remove app-private data. To request deletion of telemetry
associated with a device identifier, contact [privacy email or public
deletion-request URL]. State verification steps and response timelines here:
[details].

## Children and international transfers

State the intended age range and whether the app is directed to children:
[target audience statement]. Describe international transfer safeguards where
applicable: [details].

## Changes

We may update this policy. We will post the revised policy at [public privacy
policy URL], change the effective date, and provide any notice required by law.
