# Publishing **RunAnywhere AI** to the Microsoft Store

This is a handover document for whoever owns signing and store accounts. It covers
everything from "source tree" to "listed in the Microsoft Store".

**Who needs to do what**

| Step | Needs | Who |
|---|---|---|
| 1. Build the installer | a Windows dev machine | any engineer |
| 2. Code-sign it | **an EV/OV certificate** | you (the signer) |
| 3. Partner Center account + name reservation | **company identity + payment** | you |
| 4. Store listing + submission | Partner Center access | you |

Steps 2–4 cannot be done by the engineering side without a certificate and a
Partner Center login — that is why this document exists.

---

## 0. What the app is

A Windows desktop app (Electron) that runs AI models **locally**: chat, voice
(speech-to-text → LLM → text-to-speech), image description, semantic search and a
document Q&A ("Knowledge") feature. Inference happens on the user's CPU or NVIDIA
GPU. It is also the official sample app for the `@runanywhere/electron` SDK.

Two facts that matter for the submission:

* **It downloads model files at runtime** (from `huggingface.co` and
  `github.com`) into `%USERPROFILE%\.runanywhere\models`. Nothing is executed
  from those downloads — they are model *weights* read by the bundled inference
  engine — but certification will ask, so answer it up front (see §6).
* **It ships a native module and NVIDIA CUDA runtime DLLs.** The installer is
  large (~1 GB with both the CPU and GPU variants).

---

## 1. Decide the distribution route

We recommend the **Win32 (EXE) route**, and this document assumes it.

| | **Win32 EXE installer** (recommended) | MSIX package |
|---|---|---|
| How | NSIS installer, submitted to the Store as an "EXE or MSI" app | `.msix`, Store-signed |
| Native module + DLLs | works exactly like a normal desktop install | must be `asarUnpack`-ed and marked full-trust |
| Runtime model downloads | normal | draws extra certification scrutiny |
| Updates | ours (`electron-updater`) | Store-managed |
| Risk | low | medium — the CUDA payload and download behaviour complicate it |

Reason for the recommendation: the app is a full-trust desktop program with a
native inference engine and a ~1 GB payload. MSIX adds packaging constraints
without buying us much here.

---

## 2. Build the installer

Prerequisites on the build machine:

* Node.js 22+
* Visual Studio 2022 Build Tools (MSVC v143, C++ workload)
* CMake 3.28+
* The repository, on the release branch

```powershell
# 1. Build the SDK (TypeScript -> dist/)
cd sdk\runanywhere-electron
npm install
npm run build
npm test                 # 418 unit tests must pass

# 2. Build the native addon (CPU) and bundle it
cmake --preset windows-release `
  -DRAC_BUILD_BACKENDS=ON -DRAC_BACKEND_LLAMACPP=ON `
  -DRAC_BACKEND_ONNX=ON -DRAC_RUNTIME_ONNXRT=ON `
  -DRAC_BACKEND_SHERPA=ON -DRAC_STATIC_PLUGINS=ON -DRAC_BUILD_ELECTRON_ADDON=ON
cmake --build build\windows-release --target runanywhere_native --config Release
node sdk\runanywhere-electron\scripts\bundle-native.js

# 3. (Optional, for the GPU build) repeat with the CUDA preset and bundle into
#    prebuilds\win32-x64-cuda\ — requires the CUDA 12.x toolkit.

# 4. Smoke-test the app before packaging
cd examples\electron\RunAnywhereAI
npm test                 # the app's own unit tests
npm start                # launches the app; check Chat, Voice, Models
```

### 2.1 Packaging config (NOT YET IN THE REPO — must be added)

> **Status: this is the one engineering task still outstanding.** The repo has no
> `electron-builder` configuration yet, so there is currently no installer to
> sign. Ask the engineering side to land this before you start §3.

Add `electron-builder` to `examples/electron/RunAnywhereAI` with roughly:

```jsonc
{
  "appId": "ai.runanywhere.desktop",
  "productName": "RunAnywhere AI",
  "directories": { "output": "dist-installer" },
  "files": ["**/*", "!test/**"],
  "extraResources": [
    { "from": "../../../sdk/runanywhere-electron/dist", "to": "sdk/dist" },
    { "from": "../../../sdk/runanywhere-electron/prebuilds", "to": "sdk/prebuilds" }
  ],
  // Native modules and their sidecar DLLs MUST stay outside the asar archive —
  // Windows cannot load a .node or a .dll from inside app.asar.
  "asarUnpack": [
    "**/*.node",
    "**/onnxruntime.dll",
    "**/onnxruntime_providers_shared.dll",
    "**/sherpa-onnx-c-api.dll",
    "**/cublas*.dll",
    "**/cudart*.dll"
  ],
  "win": {
    "target": ["nsis"],
    "icon": "assets/icon.ico",
    "signingHashAlgorithms": ["sha256"]
  },
  "nsis": {
    "oneClick": false,
    "perMachine": false,
    "allowToChangeInstallationDirectory": true,
    "license": "../../../LICENSE"
  }
}
```

Then `npx electron-builder --win nsis` produces `dist-installer\RunAnywhere AI Setup <version>.exe`.

---

## 3. Code signing — **your part**

An unsigned Electron installer is flagged by SmartScreen and most users will not
get past it. The Store also expects a signed binary.

1. Obtain a code-signing certificate in the company's legal name:
   * **OV** (Organisation Validation) — cheaper; SmartScreen reputation must be
     earned over time and downloads.
   * **EV** (Extended Validation) — hardware token / cloud HSM; gets SmartScreen
     reputation **immediately**. Recommended if we expect real download volume.
2. Sign with `signtool` (or let electron-builder do it):

```powershell
signtool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
  /f "C:\path\to\cert.pfx" /p "<password>" `
  "dist-installer\RunAnywhere AI Setup 1.0.0.exe"

signtool verify /pa /v "dist-installer\RunAnywhere AI Setup 1.0.0.exe"
```

* **Always timestamp** (`/tr`) — otherwise the signature expires with the cert.
* Never commit the `.pfx` or its password. Use a secure secret store; in CI use
  Azure Trusted Signing or a GitHub secret.

---

## 4. Partner Center setup — **your part**

1. Create/access a **Microsoft Partner Center** account with a *Company* (not
   Individual) identity: <https://partner.microsoft.com/dashboard>
   * One-time registration fee (~$99 company / ~$19 individual).
   * Company accounts require a legal-entity verification that can take days —
     **start this early**, it is the long pole.
2. **Reserve the app name**: Dashboard → Apps and games → New product →
   **EXE or MSI app** → reserve **`RunAnywhere AI`**.
   * If the name is taken, agree an alternative with the team before proceeding.

---

## 5. Store listing assets

Prepare before you start the submission form:

| Asset | Requirement | Status |
|---|---|---|
| App icon | 300×300 PNG | ✅ `assets/icon.png` (from the brand mark) |
| Screenshots | 1366×768 or larger, ≥1 (4–8 recommended) | ⬜ capture Chat, Voice, Models, Knowledge |
| Short description | ≤ 100 chars | draft below |
| Full description | ≤ 10 000 chars | draft below |
| **Privacy policy URL** | **required, publicly hosted** | ⬜ **must be written and hosted** |
| Support contact | email or URL | ⬜ |
| Age rating | questionnaire | ⬜ |

**Short description (draft)**

> Run AI models privately on your own PC — chat, voice, and image understanding, with no cloud.

**Full description (draft)**

> RunAnywhere AI runs modern AI models directly on your computer. Chat with a
> language model, talk to it out loud, describe images, and ask questions about
> your own documents — all processed locally on your CPU or NVIDIA GPU.
>
> • **Chat** — a fast on-device assistant with conversation history
> • **Voice** — speak and hear replies; speech recognition, reasoning and speech
>   synthesis all run on your machine
> • **Vision** — describe and ask questions about images
> • **Knowledge** — add your own documents and get answers grounded in them
> • **Models** — choose from current open models (Qwen3.5, Gemma 4, LFM2.5,
>   Llama 3.2, Phi-4-mini and more) and switch per feature
>
> Your prompts, documents and audio are processed on your device and are not sent
> to a server. Model files are downloaded from their public repositories the first
> time you use them.

⚠️ **Do not claim "100% offline" or "nothing ever leaves your device" without
qualification.** The app downloads model files over the internet on first use.
The wording above is deliberately accurate; the in-app footer says
*"Inference runs on this device"* for the same reason.

---

## 6. Certification notes (paste into "Notes for certification")

> RunAnywhere AI is a local AI inference application.
>
> 1. **Model downloads.** On first use of a feature, the app downloads model
>    weight files (GGUF/ONNX) over HTTPS from huggingface.co and github.com into
>    the user's profile directory. These are passive data files read by the
>    bundled inference engine — no downloaded content is executed as code, and no
>    code is downloaded. Every download is verified against a SHA-256 digest
>    published by the origin before it is used.
> 2. **Network use.** Apart from those model downloads, the app makes no network
>    requests. Prompts, documents, images and audio are processed locally and are
>    never transmitted.
> 3. **Native components.** The app bundles a native inference module
>    (`runanywhere_native.node`) plus ONNX Runtime, sherpa-onnx and (in the GPU
>    build) NVIDIA CUDA runtime libraries.
> 4. **Microphone.** Used only while the user holds/taps the microphone control on
>    the Voice screen; audio is transcribed locally and never uploaded.
> 5. **Third-party model licences.** The catalog offers models under Apache 2.0,
>    the Gemma Terms of Use, the Llama 3.2 Community License and the NVIDIA Open
>    Model License. The applicable licence is shown next to each model in the app
>    with a link to its terms, before the user downloads it.

---

## 7. Submission checklist

- [ ] Version bumped in `examples/electron/RunAnywhereAI/package.json` (currently `0.1.0` — **ship as `1.0.0`**)
- [ ] `npm test` green in both `sdk/runanywhere-electron` and the app
- [ ] Installer built and **installs cleanly on a machine that has never had it**
- [ ] Installer **signed and verified** (`signtool verify /pa`)
- [ ] Launch test on a clean Windows 11 VM: chat works, a model downloads, voice works
- [ ] Uninstall leaves no service/driver behind (models in `%USERPROFILE%\.runanywhere` are deliberately kept — mention this in the description)
- [ ] Privacy policy hosted and reachable
- [ ] Screenshots captured
- [ ] Age rating completed
- [ ] Certification notes (§6) pasted in
- [ ] Submit → typical review 24–72 h

---

## 8. After the first release

* **Updates.** The Store does not update Win32 apps for you. Wire
  `electron-updater` against a GitHub Releases (or blob storage) feed **before**
  you have many users, otherwise you cannot ship a fix.
* **Crash reports.** The app currently logs to the console only; consider a
  crash reporter before scaling up.
* **Reputation.** With an OV certificate, SmartScreen warnings fade as install
  volume accumulates. With EV they do not appear at all.

---

## 9. Known gaps (be aware before you promise a date)

| Gap | Impact | Owner |
|---|---|---|
| **No electron-builder config yet** | there is no installer to sign | engineering |
| **No code-signing certificate** | SmartScreen will block downloads | you |
| **No auto-update** | cannot patch a shipped bug | engineering |
| **Installer ~1 GB** with both CPU + CUDA variants | slow download; consider shipping CPU-only and offering GPU as an optional download | product decision |
| Privacy policy not written/hosted | **blocks submission** | you + legal |
