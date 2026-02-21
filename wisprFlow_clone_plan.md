# WisprFlow iOS Keyboard App — Full Design Specification for Swift Recreation

## Executive Summary

WisprFlow is an AI-powered voice dictation keyboard app that works across any text input field on iOS, turning natural speech into polished, formatted text. Unlike Apple's built-in dictation, WisprFlow uses cloud-based ASR models combined with LLM post-processing to remove filler words, fix grammar, add punctuation, and adapt writing style to context. The app is architecturally split into two components: a **keyboard extension** (the input surface) and a **containing app** (the recording engine, settings hub, and history manager). This document provides a complete technical and feature specification for recreating WisprFlow from scratch in Swift for iOS.[1][2][3][4][5]

***

## App Architecture Overview

### Two-Target Structure

WisprFlow on iOS consists of two distinct targets bundled together:[6]

1. **Containing App (Main App)** — The full application that handles microphone recording, ASR processing, settings management, dictation history, custom dictionary management, and user authentication.[1]
2. **Keyboard Extension** — A custom keyboard extension (`com.apple.keyboard-service`) that provides the voice input UI surface within any host app. It contains a minimal key layout (number pad, symbols, voice button, globe key) rather than a full QWERTY keyboard.[7][8]

### The "Flow Session" Model

The central architectural innovation is the **Flow Session** concept, which works around iOS restrictions on keyboard extensions accessing the microphone:[4][1]

1. User taps the **microphone button** on the WisprFlow keyboard extension.
2. The keyboard extension opens the **containing app** via a deep link / custom URL scheme.[9][10]
3. The containing app activates an `AVAudioSession`, starts microphone recording, and begins a "Flow Session".[11]
4. The containing app automatically bounces the user back to the **host app** (e.g., Messages, Safari) they were previously in.[10][9]
5. While the user is back in the host app, the containing app continues recording audio in the background.[1]
6. The user speaks naturally, and when done, taps the checkmark button on the keyboard to end the dictation segment.
7. Audio is streamed to WisprFlow's cloud, processed through ASR + LLM, and the resulting text is inserted via the keyboard extension's `textDocumentProxy`.[6]

This bounce-back behavior is the core UX trick — apps like WisprFlow achieve the return to the host app selectively (it works for major apps like Messages, Maps, etc., but "not all apps allow the app to reopen").[9]

### Flow Session Duration Settings

Flow Sessions can be configured to automatically end after:[1]
- 5 minutes
- 15 minutes
- 1 hour
- Never (manual end only)

On desktop, sessions run up to 6 minutes with warnings at 5 minutes, after which text auto-saves to the History pane.[12]

***

## iOS Permissions & Entitlements Required

### Keyboard Extension Permissions

| Permission / Config | Purpose | Implementation |
|---|---|---|
| `RequestsOpenAccess = YES` | Enables network access, shared container, microphone prompt | Set in keyboard extension's `Info.plist` under `NSExtensionAttributes`[6] |
| Full Access prompt | Required for network communication and shared data | User must enable in Settings → Keyboards → [Your Keyboard] → Allow Full Access[13][6] |
| `IsASCIICapable` | Declares keyboard can insert ASCII | `Info.plist`[6] |
| `PrimaryLanguage` | Sets the default language | `Info.plist`[6] |

### Containing App Permissions

| Permission | Info.plist Key | Purpose |
|---|---|---|
| Microphone | `NSMicrophoneUsageDescription` | Audio recording for voice dictation[14] |
| Speech Recognition (optional) | `NSSpeechRecognitionUsageDescription` | If using Apple's on-device SFSpeechRecognizer as fallback[14] |
| Background Audio | `UIBackgroundModes` → `audio` | Continue recording when user bounces back to host app[11] |

### App Group (Critical)

Both the containing app and the keyboard extension must share an **App Group** (`group.com.yourapp.shared`):[15][4]
- Used for `UserDefaults(suiteName:)` to pass transcribed text, session state, and settings between the main app and the keyboard extension.
- Used for shared file containers to pass larger data (audio chunks, dictation results).

### Additional Capabilities

- **Push Notifications** — For session alerts and word limit warnings
- **Network Access** — Cloud ASR requires outbound HTTPS connections
- **iCloud (optional)** — For syncing dictionary and settings across devices[6]

***

## ASR & LLM Processing Pipeline

### How Speech Processing Works

WisprFlow uses a **cloud-based pipeline**, not on-device processing:[5][12]

1. **Audio Capture** — The containing app records audio using `AVAudioEngine` or `AVAudioSession` and streams compressed audio chunks to WisprFlow's cloud servers.
2. **ASR Inference** — Cloud servers run proprietary ASR models (not OpenAI Whisper — they've built custom models achieving ~10% WER vs. Whisper's 27% and Apple's 47%). The ASR is context-conditioned on speaker qualities, surrounding context, and individual history.[5][12]
3. **LLM Post-Processing** — The raw transcript is then processed by a personalized LLM that:[3][5]
   - Removes filler words ("um", "uh", "like")
   - Adds punctuation and capitalization
   - Handles course corrections ("actually, change that to...")
   - Formats lists, paragraphs, and structure
   - Applies user's personal writing style
4. **Text Delivery** — The polished text is sent back to the device and inserted at the cursor position via the keyboard extension's `textDocumentProxy.insertText()`.[6]

### Latency Budget

The total end-to-end latency target is **<700ms** from end of speech to finished text:[5]
- ASR inference: <200ms
- LLM inference: <200ms
- Network round-trip: <200ms

### Context-Aware Processing

The ASR and LLM models are conditioned on:[5]
- **Speaker identity** — Voice characteristics and accent
- **Topic context** — What the user typically talks about
- **App context** — Where the user is typing (email vs. chat vs. code editor)
- **Dictation history** — Previous corrections and preferences
- **Personal dictionary** — Custom names, acronyms, and jargon

***

## Feature Specification

### 1. Voice Dictation (Core Feature)

- **Push-to-Talk**: Hold the mic button on the keyboard, speak, release to submit.[16]
- **Hands-Free Mode**: Tap once to start continuous listening; tap again to stop.[16]
- **Whisper Mode**: Supports sub-audible speech — users can whisper and still get accurate transcription.[8][5]
- **Course Correction**: If the user says "actually" or "wait," the system revises the current sentence mid-stream without requiring a restart.[3][16]
- **Real-time AI Editing**: Filler words removed, punctuation auto-inserted, formatting applied as text streams in.[2][3]

### 2. Personal Dictionary

- Auto-learns proper names, acronyms, and jargon from user corrections.[2][3]
- Manual addition of custom words through the containing app's dictionary UI.[1]
- Syncs across devices (Mac, Windows, iOS) for Pro users.[12]
- Team dictionaries allow shared terminology for enterprise.[12]

### 3. Snippet Library

- Create saved text blocks triggered by a spoken cue word.[3][12]
- Use cases: email signatures, meeting links, scheduling URLs, FAQs, legal disclaimers.
- Speak "my calendly" → inserts full Calendly link + surrounding text.[12]

### 4. Command Mode (Voice Editing)

- Highlight existing text, then speak a command to transform it:[3][12]
  - "Make this more concise"
  - "Translate to Spanish"
  - "Make this formal"
  - "Rewrite as bullet points"
- Uses LLM to rewrite the selected text in-place.[12]

### 5. Styles (Tone Adaptation)

- Adapts writing tone based on context:[3]
  - Formal in documents/email
  - Casual in messaging apps
  - Technical in code editors
- Currently English-only and desktop-only, but the iOS version should plan for this.[3]

### 6. Dictation History

- Full history of all dictation sessions stored in the containing app.[1]
- Searchable and browsable.
- Text auto-saves when sessions end or time out.[12]

### 7. Quick Notes

- A dedicated quick capture feature accessible from the app.[2]
- Speak an idea and it saves as a note.
- Syncs with the desktop app.[2]

### 8. Multi-Language Support

- 100+ languages supported.[2]
- Automatic language detection.[12]
- Code-switching: handle multiple languages within the same sentence.[5]
- Language preferences configurable in settings independently from device language.[1]

***

## Keyboard Extension UI Specification

### Layout

The WisprFlow keyboard is intentionally **not a full QWERTY keyboard**. It consists of:[7][8]

| Element | Description |
|---|---|
| **Microphone Button** (center) | Large, prominent button to start/stop voice recording[17] |
| **Checkmark Button** | End current dictation segment and insert text |
| **Menu Button** (left) | Manually end Flow Session or access quick settings[1] |
| **Number Pad** | Basic numeric and symbol input for typing special characters[8] |
| **Globe Key** | Standard iOS keyboard switcher — **mandatory** per Apple guidelines, call `advanceToNextInputMode()`[6] |
| **Backspace Key** | Delete character via `textDocumentProxy.deleteBackward()`[6] |
| **Return Key** | Insert newline via `textDocumentProxy.insertText("\n")`[6] |

### Visual States

- **Idle** — Mic button inactive, ready to start
- **Recording** — Animated mic button, waveform visualization showing live audio levels
- **Processing** — Loading indicator while cloud processes audio
- **Text Inserted** — Brief success state after text is pasted

### Height

Custom keyboard height should match the system keyboard using Auto Layout constraints on the input view controller's primary view. The default sizing follows screen size and orientation.[6]

***

## Swift Implementation Blueprint

### Project Structure

```
WisprFlowClone/
├── WisprFlowApp/                    # Containing App target
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── Views/
│   │   ├── HomeView.swift           # Main dashboard
│   │   ├── HistoryView.swift        # Dictation history
│   │   ├── DictionaryView.swift     # Custom dictionary management
│   │   ├── SnippetView.swift        # Snippet library
│   │   ├── SettingsView.swift       # App settings
│   │   └── DictationOverlayView.swift  # Recording UI during bounce
│   ├── Services/
│   │   ├── AudioRecordingService.swift   # AVAudioEngine management
│   │   ├── ASRService.swift              # Cloud ASR API client
│   │   ├── LLMFormattingService.swift    # Post-processing API client
│   │   ├── WebSocketService.swift        # Real-time audio streaming
│   │   └── SharedDataService.swift       # App Group UserDefaults + file I/O
│   ├── Models/
│   │   ├── DictationSession.swift
│   │   ├── DictionaryEntry.swift
│   │   ├── Snippet.swift
│   │   └── UserProfile.swift
│   └── Info.plist
├── WisprFlowKeyboard/               # Keyboard Extension target
│   ├── KeyboardViewController.swift  # UIInputViewController subclass
│   ├── KeyboardView.swift            # SwiftUI or UIKit keyboard layout
│   ├── MicButton.swift               # Animated recording button
│   ├── SharedDataBridge.swift        # Reads from App Group
│   └── Info.plist
└── Shared/                           # Shared framework/module
    ├── Constants.swift               # App Group ID, URL schemes
    ├── SharedUserDefaults.swift      # Wrapper for suite defaults
    └── AudioChunkProtocol.swift      # Audio data format
```

### Key Implementation Details

#### 1. Keyboard Extension — `KeyboardViewController.swift`

```swift
import UIKit

class KeyboardViewController: UIInputViewController {
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboardUI()
    }
    
    // MARK: - Globe Key (mandatory)
    @objc func handleNextKeyboard() {
        advanceToNextInputMode()
    }
    
    // MARK: - Mic Button Action
    @objc func handleMicTap() {
        // Write "start_recording" flag to shared UserDefaults
        let shared = UserDefaults(suiteName: "group.com.yourapp.shared")
        shared?.set(true, forKey: "shouldStartRecording")
        shared?.set(hostBundleID(), forKey: "returnToBundleID") // if obtainable
        
        // Open containing app via URL scheme
        let url = URL(string: "yourapp://startFlow")!
        openURL(url)
    }
    
    // MARK: - Text Insertion (called when transcription arrives)
    func insertTranscribedText() {
        let shared = UserDefaults(suiteName: "group.com.yourapp.shared")
        if let text = shared?.string(forKey: "transcribedText") {
            textDocumentProxy.insertText(text)
            shared?.removeObject(forKey: "transcribedText")
        }
    }
    
    // MARK: - Backspace
    @objc func handleDelete() {
        textDocumentProxy.deleteBackward()
    }
    
    // Poll for new transcription data or use Darwin notifications
    // to trigger insertTranscribedText()
}
```

**Note on `openURL`**: Keyboard extensions cannot call `UIApplication.shared.open()` directly. The workaround is to traverse the responder chain or use `NSExtensionContext`:[18][4]

```swift
func openURL(_ url: URL) {
    var responder: UIResponder? = self
    while let r = responder {
        if let app = r as? UIApplication {
            app.open(url)
            return
        }
        responder = r.next
    }
}
```

#### 2. Containing App — Audio Recording & Bounce-Back

```swift
// In AppDelegate or SceneDelegate, handle the deep link:
func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url,
          url.scheme == "yourapp",
          url.host == "startFlow" else { return }
    
    // Start audio session
    AudioRecordingService.shared.startRecording()
    
    // Bounce back to host app
    // This is the tricky part — use known URL schemes
    // for common apps (Messages: sms://, Safari: https://, etc.)
    bounceBackToHostApp()
}
```

The bounce-back mechanism works selectively — WisprFlow maintains a mapping of common host app bundle IDs to their URL schemes. For apps without known URL schemes, the user must manually switch back.[9]

#### 3. Audio Streaming to Cloud

```swift
class AudioRecordingService {
    private let audioEngine = AVAudioEngine()
    private let webSocket = WebSocketService()
    
    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            // Compress audio (Opus/AAC) and stream to cloud
            let data = self.compressAudio(buffer: buffer)
            self.webSocket.send(data)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
}
```

#### 4. Inter-Process Communication (IPC)

Communication between the keyboard extension and the containing app uses:[4][15]

- **App Group `UserDefaults`** — For small data (flags, short text, settings).
- **App Group shared file container** — For larger data (audio files, long transcriptions).
- **Darwin Notifications** (`CFNotificationCenter`) — For real-time signaling between processes without polling. The containing app posts a notification when transcription is ready; the keyboard extension observes it and reads the result.

```swift
// Containing app: Post notification when text is ready
let center = CFNotificationCenterGetDarwinNotifyCenter()
CFNotificationCenterPostNotification(center, 
    CFNotificationName("com.yourapp.transcriptionReady" as CFString), 
    nil, nil, true)

// Keyboard extension: Observe notification
CFNotificationCenterAddObserver(center, nil, { _, _, _, _, _ in
    // Read transcribed text from shared UserDefaults and insert
}, "com.yourapp.transcriptionReady" as CFString, nil, .deliverImmediately)
```

***

## iOS-Specific Technical Constraints & Workarounds

### Microphone in Keyboard Extensions

iOS keyboard extensions **cannot directly access the microphone**, despite what the documentation about `RequestsOpenAccess` might suggest. The actual recording must happen in the containing app. Additionally, iOS kills keyboard extensions after ~50 seconds of active audio session usage.[19][20][4]

**Workaround (the WisprFlow approach)**:
1. Keyboard extension triggers the containing app via deep link.[11][4]
2. Containing app starts `AVAudioSession` and records.
3. User is bounced back to the host app.
4. The containing app's background audio mode keeps the recording alive.[11]
5. Transcribed text is passed back via App Group shared storage.[15]

### Returning to the Host App

There is no public API for a keyboard extension to return to the previous app programmatically. WisprFlow achieves this by:[21][9]

- Maintaining a curated list of common app URL schemes (Messages: `sms://`, Safari: `https://`, Maps: `maps://`, etc.).[9]
- The containing app opens the host app's URL scheme after starting the recording.
- This works for major first-party and popular third-party apps but not universally.[9]
- For unsupported apps, the user must manually switch back.

### Keyboard Not Defaulting

iOS does not reliably honor keyboard ordering for third-party keyboards that lack a full QWERTY layout. Users must manually switch to the custom keyboard each time they change apps. This is a known platform limitation.[7]

### Secure Text Fields

Custom keyboards are automatically replaced by the system keyboard in secure text fields (passwords, credit card inputs). This is an iOS enforcement and cannot be overridden.[6]

***

## Backend Infrastructure (What You'd Need to Build)

### Cloud ASR Server

- Accept WebSocket audio streams (Opus or AAC compressed).
- Run ASR model inference (options: fine-tuned Whisper, or custom encoder-decoder model).[12]
- Return timestamped transcriptions.

### LLM Formatting Server

- Accept raw transcription + user context (dictionary, style, app context).
- Run LLM inference for text cleanup, formatting, and style adaptation.[5]
- Return polished text.

### User Data Store

- Personal dictionary entries (synced across devices).
- Snippet library.
- Dictation history.
- User preferences and style profiles.

### For a MVP / Indie Alternative

If building without custom ASR infrastructure:
- Use **OpenAI Whisper API** or **Deepgram** for ASR.
- Use **OpenAI GPT-4o-mini** or **Claude Haiku** for LLM post-processing.
- Use **Firebase** or **Supabase** for user data and auth.
- Estimated cost: ~$3/month for personal use at moderate volume.[19]

***

## Pricing & Business Model Reference

| Tier | Price | Word Limit | Features |
|---|---|---|---|
| Free | $0 | 2,000 words/week (desktop), 1,000/week (iOS) | Basic dictation, limited history |
| Pro | $12/mo (annual) or $15/mo | Unlimited | All features, cross-device sync, priority processing |
| Teams | Custom | Unlimited | Shared dictionaries, admin controls, API access |
| Enterprise | Custom | Unlimited | SSO, compliance, custom deployment |

Data source.[3][12]

***

## Privacy & Security Considerations

### Data Flow

- Audio is streamed to cloud servers for processing — it does **not** stay on-device.[3]
- WisprFlow uses third-party providers (including OpenAI and Meta models) for processing.[3]
- **Zero Data Retention mode** available: immediately deletes transcripts after processing.[12]

### User Trust Design

- Clearly communicate what data leaves the device and why.[6]
- Model training on user data is now **opt-in and off by default** (after earlier controversy).[3]
- Minimize data collected; keystroke data should only be used for providing the service.[6]
- Allow users to delete their dictation history and personal data.

### Apple's Full Access Warning

When a user enables Full Access for a keyboard extension, iOS displays a system warning that the keyboard may collect "everything you type, including passwords and credit card numbers". This cannot be suppressed — the app should clearly explain in onboarding why Full Access is needed and how data is protected.[13][6]

***

## User Experience — End-to-End Keyboard Flow

This section documents the complete user experience of the WisprFlow keyboard, step by step, based on the actual production app behavior.

### State 1: Keyboard Idle — App Not Active in Background

When the user opens the Flow keyboard for the first time (or when the main app is not running in the background), the keyboard displays a compact input surface:

**Layout:**
- **Top toolbar row:** A settings/sliders icon (left), an info `(i)` button (center-right), and a **"Start Flow"** button (far right).
- **Number row:** `1 2 3 4 5 6 7 8 9 0`
- **Special characters row 1:** `- / : ; ( ) $ & @ "`
- **Special characters row 2:** `#+= . , ? ! ' ⌫` (backspace at the end)
- **Bottom row:** `ABC` key (left) | `Flow` spacebar (center, branded with the Flow waveform logo) | `Search` button (right, blue/accent-colored)
- **Globe key:** Bottom-left corner, mandatory iOS keyboard switcher.

The **"Start Flow"** button is the key affordance in this state. It is only shown when the main app is **not** actively running in the background with an audio session. This communicates to the user that they need to activate the microphone before they can dictate.

### State 2: App Launch — Microphone Activation Screen

When the user taps **"Start Flow"**, the keyboard extension opens the containing app via a deep link. The app launches to a dedicated **microphone activation screen** with the following elements:

**Screen layout:**
- **Dynamic Island** (top): Shows an orange recording indicator dot, signaling the app has activated the microphone.
- **Close button** `(X)`: Top-right corner, allows dismissal.
- **Headline text:** "Swipe back to continue" — a clear, bold instruction telling the user to navigate back.
- **Animated phone illustration:** A stylized iPhone mockup in the center of the screen showing an animation that cycles between two frames:
  - **Frame A:** The Flow waveform icon centered on a blank phone screen, with a swipe gesture indicator (circle) at the bottom of the phone mockup suggesting the user should swipe up/back.
  - **Frame B:** The same phone mockup but now showing a keyboard appearing on screen, with the swipe gesture indicator moved to the bottom-right, reinforcing that the user should go back to where they were typing.
- **Explanatory text** (below the phone illustration): *"We wish you didn't have to switch apps to use Flow, but Apple requires this step to activate the microphone"* — this transparently explains the iOS limitation to the user.

This screen serves a single purpose: start the `AVAudioSession` for background recording and instruct the user to go back to their previous app. The animation loop visually guides the user through the swipe-back gesture.

### State 3: Return to Host App — Microphone Ready (Idle Listening)

Once the user swipes back to the host app (e.g., Spotlight Search, Messages, Safari, etc.), the keyboard appearance changes to reflect that the main app is now active in the background with the microphone engaged:

**Layout changes from State 1:**
- **Dynamic Island** (top of screen): Now persistently shows the Flow waveform logo, indicating the app is running in the background.
- **Top toolbar row:** The "Start Flow" button and info `(i)` button are **replaced** by:
  - Settings/sliders icon (left)
  - **"Using iPhone Microphone"** label (center) — tells the user the mic is active
  - **Microphone icon button** (right) — this is the tap target to begin active listening
- **Number row, special characters, bottom row:** Remain the same as State 1.

In this state, the microphone is **technically active** (the app holds a background audio session), but it is **not processing or transcribing** anything yet. The audio session is alive to maintain background execution, but no STT inference is happening. The user must explicitly tap the microphone button to begin dictation.

### State 4: Active Listening — Dictation in Progress

When the user taps the **microphone icon button** on the keyboard, the keyboard transitions to a full listening UI:

**Layout changes:**
- The number pad, special characters, and standard keyboard keys are **hidden**.
- The keyboard area is replaced with a full-width **listening interface**:
  - **Cancel button** `(X)`: Left side — cancels the current dictation without inserting any text.
  - **Checkmark button** `(✓)`: Right side — ends the dictation and triggers transcription + text insertion.
  - **Waveform visualization** (center): A large, animated audio waveform showing live audio levels, confirming the app is actively listening.
  - **"Listening"** label: Below the waveform, confirming the active state.
  - **"iPhone Microphone"** label: Below "Listening", indicating the audio source.
- **Globe key:** Remains visible at the bottom-left for keyboard switching.

During this state:
- The app is actively streaming audio from the background audio session to the processing pipeline.
- The waveform animates in response to the user's voice, providing real-time visual feedback.
- The user speaks naturally without needing to hold any button.

### State 5: Dictation Complete — Text Insertion

When the user taps the **checkmark** `(✓)` button:

1. The audio stream is finalized and sent for ASR processing (on-device or cloud, depending on configuration).
2. The transcribed text is passed back to the keyboard extension via the App Group shared storage / Darwin notifications.
3. The keyboard extension calls `textDocumentProxy.insertText()` to paste the transcribed result at the current cursor position in the host app's text field.
4. The keyboard returns to **State 3** (microphone ready, idle listening) — the user can immediately dictate again without re-launching the app.

**Example from screenshots:** The user dictated "Hello, hello, hello" and it was inserted into the Spotlight Search field. After insertion, the keyboard toolbar shows an **undo button** (circular arrow) alongside the microphone button, allowing the user to undo the last insertion if the transcription was incorrect.

### State 6: Lock Screen — Live Activity Persistent Indicator

Even when the phone is locked or the user is on the lock screen, a **Live Activity** widget is displayed to indicate that Flow is running in the background:

**Live Activity layout:**
- **Background:** Purple/dark blue gradient, matching the Flow brand.
- **Header:** Flow waveform logo + "Flow" label.
- **Word count:** Displays a running total of words dictated in the session (e.g., "1,649 words").
- **Action buttons:**
  - **Power/timer button:** Likely to end the Flow session or show session duration.
  - **Compose button:** Quick action to open the app or start a new dictation.
- **System prompt** (first time): iOS asks *"Do you want to continue to allow Live Activities from Wispr Flow?"* with "Don't Allow" and "Always Allow" options.

The Live Activity also appears in the **Dynamic Island** (on supported devices) as a compact indicator showing the Flow waveform logo, visible across all apps and the home screen. This persistent presence reassures the user that the microphone session is alive without needing to open the app.

### RunAnywhere-Specific Behavior

Our implementation differs from WisprFlow in a few key ways, primarily because we run ASR **on-device** rather than in the cloud.

**Button naming:** The idle keyboard button is called **"Run"** instead of "Start Flow". This aligns with the RunAnywhere brand.

**What happens when the user taps "Run":**

The containing app is launched via deep link and must satisfy the following **preconditions** before the keyboard can transition to the "ready" state:

1. **Microphone permission** — Request/verify `AVAudioSession` recording permission. If not granted, prompt the user.
2. **ASR model downloaded** — Check if the on-device ASR model exists on disk. If not, show a download prompt and download it before proceeding.
3. **ASR model loaded into memory** — Load the model so it is ready for real-time inference. This must complete before the keyboard shows the "ready" state.
4. **Audio session active** — Start the background `AVAudioSession` so the mic stays alive when the user swipes back.

If any precondition fails (e.g., model not downloaded, permission denied), the app stays on the activation screen and surfaces the issue to the user. The keyboard does **not** transition to "ready" until all preconditions are met.

**Swipe-back screen:** Same experience as WisprFlow — the app shows the "Swipe back to continue" animation with the explanation that Apple requires the app switch to activate the microphone. The user swipes back to the host app once the model is loaded and the mic is active.

**Dictation and text insertion flow:**

1. User taps the microphone button on the keyboard (State 4 — Listening).
2. Audio is recorded in the background by the containing app and streamed to the on-device ASR model in real-time.
3. When the user taps the checkmark (or stops talking), the recorded audio is transcribed on-device.
4. The transcribed text is passed to the keyboard extension via App Group shared storage.
5. The keyboard extension inserts the text at the current cursor position using `textDocumentProxy.insertText()`.

**Edge cases:**

- **Model not downloaded:** The "Run" button opens the app, which shows a download screen instead of the swipe-back screen. The keyboard remains in the idle state until download + load completes.
- **Model download in progress:** Show progress in the app. The keyboard stays idle.
- **Microphone permission denied:** The app shows a prompt directing the user to Settings. The keyboard stays idle.
- **App killed by the system:** The keyboard reverts to the idle state with the "Run" button. User must tap "Run" again to re-launch and re-load the model.
- **Live Activity:** Same as WisprFlow — a persistent Live Activity in the Dynamic Island and lock screen indicates the session is active and the model is loaded.

### State Transition Summary

```
┌───────────────────────────────────────────────────────────────────────────┐
│                    KEYBOARD STATE MACHINE (RunAnywhere)                    │
├───────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌──────────────┐   Tap "Run"   ┌──────────────────────────────────┐     │
│  │  State 1:    │ ────────────> │  State 2: App Launch             │     │
│  │  Idle        │               │  Preconditions:                  │     │
│  │  (App Dead)  │               │   1. Mic permission              │     │
│  │  ["Run"      │               │   2. ASR model downloaded?       │     │
│  │   visible]   │               │      → No: show download prompt  │     │
│  └──────────────┘               │   3. Load ASR model into memory  │     │
│        ^                        │   4. Start audio session         │     │
│        │ App killed /           │  Then: show "Swipe back" screen  │     │
│        │ session lost           └──────────────┬───────────────────┘     │
│        │                                       │                         │
│        │                             All preconditions met,              │
│        │                             user swipes back                    │
│        │                                       │                         │
│        │                                       v                         │
│  ┌─────┴────────┐   Tap Microphone   ┌───────────────────────┐          │
│  │              │ <───────────────   │  State 3:             │          │
│  │  State 4:    │                     │  Ready                │          │
│  │  Listening   │                     │  (Mic active, model   │          │
│  │  [Waveform   │                     │   loaded, not         │          │
│  │   + X / ✓]   │                     │   transcribing yet)   │          │
│  └──────┬───────┘                     └───────────────────────┘          │
│         │                                       ^                        │
│         │ Tap ✓ / stop talking                  │                        │
│         v                                       │                        │
│  ┌──────────────┐   Text inserted, ─────────────┘                        │
│  │  State 5:    │   return to State 3                                    │
│  │  Transcribe  │                                                        │
│  │  + Insert    │                                                        │
│  └──────────────┘                                                        │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │  State 6: Live Activity (visible whenever session is active)       │  │
│  │  - Dynamic Island: RunAnywhere indicator                           │  │
│  │  - Lock Screen: Session active widget with word count + controls   │  │
│  └────────────────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────────────────┘
```

### Key UX Design Principles Observed

1. **Transparency over iOS limitations:** The activation screen explicitly tells the user *why* they need to switch apps, building trust rather than hiding the constraint.
2. **Minimal friction re-entry:** After the initial activation, the keyboard stays in State 3 (mic ready) so subsequent dictations are a single tap — no re-launching needed.
3. **Always-visible session indicator:** The Dynamic Island and Lock Screen Live Activity ensure the user always knows Flow is active, preventing confusion about whether the microphone is on.
4. **Clear modal separation:** The listening state (State 4) is a full takeover of the keyboard area, making it unmistakable that dictation is in progress and preventing accidental key presses.
5. **Undo safety net:** After text insertion, an undo button is immediately available in case the transcription was wrong.
6. **Branded but minimal:** The keyboard is not a full QWERTY — it provides just enough keys (numbers, punctuation, special characters) for quick edits alongside the primary voice input workflow.

***

## Development Checklist for Swift Recreation

### Phase 1 — Foundation
- [ ] Create Xcode project with two targets: main app + keyboard extension
- [ ] Configure App Group for shared data
- [ ] Set up `Info.plist` for keyboard extension (`RequestsOpenAccess`, `PrimaryLanguage`, etc.)
- [ ] Implement basic keyboard UI with mic button, globe key, number pad, backspace, return
- [ ] Implement deep link from keyboard extension to containing app
- [ ] Implement `AVAudioEngine` recording in containing app
- [ ] Implement bounce-back to host app via URL scheme mapping

### Phase 2 — Cloud Pipeline
- [ ] Set up WebSocket audio streaming to cloud server
- [ ] Integrate ASR API (Whisper API / Deepgram / custom)
- [ ] Integrate LLM API for text post-processing
- [ ] Implement App Group IPC to pass transcribed text back to keyboard
- [ ] Implement `textDocumentProxy.insertText()` for text insertion
- [ ] Add Darwin notification signaling between processes

### Phase 3 — Features
- [ ] Dictation history with Core Data or SwiftData persistence
- [ ] Personal dictionary CRUD with sync via App Group
- [ ] Snippet library with trigger word matching
- [ ] Flow Session timer with configurable duration
- [ ] Multi-language selection and automatic detection
- [ ] Quick Notes capture feature

### Phase 4 — Polish
- [ ] Animated mic button with audio level visualization
- [ ] Onboarding flow explaining permissions and Full Access
- [ ] Settings UI (language, session duration, privacy controls)
- [ ] Command Mode for voice-based text editing
- [ ] Whisper mode optimization (low-volume audio handling)
- [ ] Error handling for network failures and session timeouts

### Phase 5 — Production
- [ ] Rate limiting and word count tracking (free tier)
- [ ] Subscription management via StoreKit 2
- [ ] Analytics and crash reporting
- [ ] Privacy policy and terms of service
- [ ] App Store submission with proper review notes explaining keyboard extension behavior