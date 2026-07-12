# OpenClaw Hybrid Assistant tests

`./build.sh` builds component and integration test executables. Download the Sherpa models first:

```bash
./scripts/download-models.sh
./tests/scripts/generate-test-audio.sh
```

## Component tests

The component suite exercises the public VAD and STT component APIs and the continuous-listening pipeline with checked-in WAV fixtures.

```bash
./build/test-components --run-all
./build/test-components --test-vad-stt tests/audio/speech.wav
./build/test-components --test-full tests/audio/speech.wav
./build/test-components --test-noise tests/audio/noise.wav
```

The default suite verifies that speech is detected and transcribed, silence produces no transcription, speech reaches the pipeline callback, and noise is rejected.

## Integration tests

The integration suite covers the TTS queue, interruption/cancellation, waiting chime, text sanitization, public TTS component API, and an in-process fake OpenClaw WebSocket server.

```bash
./build/test-integration --run-all
./build/test-integration --test-tts-queue
./build/test-integration --test-chime
./build/test-integration --test-interruption
./build/test-integration --test-sanitization
./build/test-integration --test-tts
./build/test-integration --test-openclaw-flow --delay 5
```

The fake server is local to the test process; it does not require an external OpenClaw deployment.
