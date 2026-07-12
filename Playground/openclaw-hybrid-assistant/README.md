# OpenClaw Hybrid Assistant

A lightweight Linux voice channel for OpenClaw. Audio is processed locally for voice activity detection, speech recognition, and speech synthesis; requests are sent to OpenClaw over WebSocket. No local LLM is included.

## Pipeline

```text
microphone -> VAD -> STT -> OpenClaw WebSocket -> TTS -> speaker
```

The playground uses the public RunAnywhere component APIs with the Sherpa backend:

- Silero VAD
- Parakeet TDT-CTC 110M EN int8 by default, or Whisper Tiny EN
- Piper Lessac Medium by default, or Kokoro v0.19

Listening is continuous and gated by VAD.

Wake-word activation is not supported: RunAnywhere Commons does not ship an
executable wake-word backend.

## Requirements

- Linux with ALSA
- CMake 3.16 or newer
- A C++20 compiler
- `curl`, `tar`, and `bzip2`
- `sox` to generate the acknowledgment sound
- A running OpenClaw WebSocket gateway

## Build

From the repository root:

```bash
bash sdk/runanywhere-commons/scripts/linux/download-sherpa-onnx.sh
bash sdk/runanywhere-commons/scripts/build-linux.sh

cd Playground/openclaw-hybrid-assistant
./scripts/download-models.sh
./build.sh
```

Alternative model downloads:

```bash
./scripts/download-models.sh --whisper
./scripts/download-models.sh --kokoro
./scripts/download-models.sh --whisper --kokoro
```

Models are stored under `~/.local/share/runanywhere/Models/Sherpa/`. The acknowledgment sound is stored under `~/.local/share/runanywhere/Models/ONNX/earcon/`.

## Run

```bash
./build/openclaw-assistant
./build/openclaw-assistant --openclaw-url ws://openclaw-host:8082
```

Available options:

```text
--list-devices
--input <device>
--output <device>
--openclaw-url <url>
--device-id <id>
--debug-vad
--debug-stt
--debug-audio
--help
```

Use `Ctrl+C` to stop the assistant.

## Tests

The build produces two test executables:

```bash
./build/test-components --run-all
./build/test-integration --run-all
```

Component test options:

```text
--test-vad-stt <wav>
--test-full <wav>
--test-noise <wav>
--run-all
```

Integration test options:

```text
--test-tts-queue
--test-chime
--test-interruption
--test-sanitization
--test-tts
--test-openclaw-flow [--delay <seconds>]
--run-all
```

See [tests/README.md](tests/README.md) for the test matrix.

## systemd

`scripts/openclaw-voice.service` is an example user service. Update its repository path and gateway URL before installation.

```bash
mkdir -p ~/.config/systemd/user
cp scripts/openclaw-voice.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now openclaw-voice.service
```

## Troubleshooting

- Missing native libraries: add `sdk/runanywhere-commons/dist/linux/lib` and the Sherpa library directory to `LD_LIBRARY_PATH`.
- Missing models: rerun `./scripts/download-models.sh`.
- No microphone input: run `./build/openclaw-assistant --list-devices` and select a device with `--input`.
- Cannot reach OpenClaw: verify the gateway URL and that its WebSocket port is reachable.
