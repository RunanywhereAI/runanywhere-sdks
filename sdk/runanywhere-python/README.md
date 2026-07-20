# RunAnywhere — Python SDK

On-device AI for Python. Run large language models, vision-language models, speech-to-text,
text-to-speech, text embeddings and voice-activity detection **entirely on the host** — no
network is needed for inference (only to download models). All the heavy lifting is done by a
native C++ runtime bound into a single compiled extension; everything you touch is idiomatic
Python.

## Features

- **LLM text generation** — streaming (sync + async), full-text convenience, structured
  (JSON-schema-constrained) output, and grammar-guaranteed tool calling.
- **VLM captioning** — stream a caption/answer over an image + prompt.
- **Speech-to-text** — transcribe 16 kHz mono PCM16 audio.
- **Text-to-speech** — synthesize text to float32 PCM.
- **Embeddings** — L2-normalized float32 vectors as `numpy` arrays.
- **Voice agent** — one call runs STT → LLM → TTS.
- **Voice-activity detection** — a built-in energy VAD to segment speech.
- **Model catalog + downloader** — load by id (auto-downloaded) or by local path; also load
  straight from a HuggingFace repo or a direct URL.
- **Event bus** — subscribe to lifecycle + generation events.

## Requirements

- Python **3.9+**
- `numpy >= 1.21` (installed automatically)
- Windows, macOS or Linux (prebuilt wheels bundle the native runtime)

## Installation

```bash
pip install runanywhere
```

Wheels ship the compiled native runtime and its dependent libraries, so no separate toolchain
is needed to *use* the SDK. (To build the SDK from source, see
[Local Development](#local-development).)

## Quick Start

`RunAnywhere` is an instantiable client. Use it as a context manager so the runtime is brought
up on entry and torn down on exit:

```python
from runanywhere import RunAnywhere

with RunAnywhere() as ra:
    # Load by catalog id (downloaded on first use) or by a local .gguf path.
    llm = ra.load_llm("smollm2-360m")
    print(llm.generate_text("Explain quantum computing in one sentence."))
```

Prefer explicit lifecycle? `initialize()` returns the client, so it chains, and `shutdown()`
tears it down:

```python
ra = RunAnywhere().initialize()
llm = ra.load_llm("smollm2-360m")
print(llm.generate_text("Hello!"))
ra.shutdown()
```

Multiple clients share **one** underlying runtime (it is reference-counted): the first client
to initialize starts it, the last to shut down tears it down. Each client unloads the models
it loaded on its own shutdown.

The constructor accepts optional configuration:

```python
ra = RunAnywhere(
    base_dir="~/my-models",        # where models live (default: ~/.runanywhere)
    secure_dir=None,               # secure store dir (default: <base_dir>/secure)
    api_key=None,
    base_url=None,
    environment="production",
)
```

## Generating Text

### Streaming (sync)

`generate` yields tokens as they are produced:

```python
with RunAnywhere() as ra:
    llm = ra.load_llm("smollm2-360m")
    for token in llm.generate("Write a haiku about the sea.", max_tokens=64, temperature=0.7):
        print(token, end="", flush=True)
    print()
```

Breaking out of the loop cleanly stops the underlying decode loop:

```python
for token in llm.generate("Count to a thousand."):
    print(token, end="")
    if "100" in token:
        break   # stops native generation
```

### Streaming (async)

Every streaming/blocking method has an `a`-prefixed async twin. `agenerate` is an async
iterator:

```python
import asyncio
from runanywhere import RunAnywhere

async def main():
    with RunAnywhere() as ra:
        llm = ra.load_llm("smollm2-360m")
        async for token in llm.agenerate("Tell me a joke."):
            print(token, end="", flush=True)
        print()
        # Or collect the whole reply:
        text = await llm.agenerate_text("Summarize the plot of Hamlet.")
        print(text)

asyncio.run(main())
```

### Full text

```python
answer = llm.generate_text("What is the capital of France?", max_tokens=32)
```

Generation options are keyword arguments on any generate call: `max_tokens`, `temperature`,
`top_p`, `top_k`, `system_prompt`, `grammar`. Omit one to use the backend default.

### Stream events with metrics

`generate_stream` yields `LLMStreamEvent`s; the final event carries an
`LLMGenerationResult` with timing/throughput metrics (and is also published on the event bus):

```python
for event in llm.generate_stream("Describe a sunset."):
    if event.is_final:
        r = event.result
        print(f"\n[{r.token_count} tokens, {r.tokens_per_second:.1f} tok/s, "
              f"ttft {r.time_to_first_token_ms:.0f}ms]")
    else:
        print(event.token, end="", flush=True)
```

## Structured Output & Tool Calling

Constrain decoding to a JSON schema and get back a parsed object (guaranteed parseable):

```python
schema = {
    "type": "object",
    "properties": {
        "city": {"type": "string"},
        "temperature_c": {"type": "integer"},
    },
    "required": ["city", "temperature_c"],
}
result = llm.generate_structured("Weather in Paris right now, as JSON.", schema)
print(result["city"], result["temperature_c"])
```

Force the model to pick a tool and emit a well-formed call — and optionally run it:

```python
from runanywhere import ToolSpec

tools = [
    ToolSpec(
        name="get_weather",
        description="Get the current weather for a city.",
        parameters={
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"],
        },
        execute=lambda args: {"temp_c": 21},
    ),
]

run = llm.generate_with_tools("What's the weather in Berlin?", tools)
print(run.name, run.arguments, run.result)   # get_weather {'city': 'Berlin'} {'temp_c': 21}
```

## Chat (multi-turn)

`create_chat` keeps conversation history for you:

```python
with RunAnywhere() as ra:
    llm = ra.load_llm("smollm2-360m")
    chat = ra.create_chat(llm, system="You are a terse assistant.")
    print(chat.send_text("Who wrote Hamlet?"))
    print(chat.send_text("And when?"))     # remembers the previous turn

    # Streaming:
    for token in chat.send("Name one of his other plays."):
        print(token, end="", flush=True)
```

## Vision-Language (VLM)

```python
with RunAnywhere() as ra:
    vlm = ra.load_vlm("smolvlm-256m")   # catalog id includes the mmproj
    caption = vlm.caption_text("photo.jpg", "Describe this image.")
    print(caption)

    # Or stream it:
    for token in vlm.caption("photo.jpg", "What is in the picture?"):
        print(token, end="", flush=True)
```

## Embeddings

```python
with RunAnywhere() as ra:
    embedder = ra.load_embedder("minilm")
    vec = embedder.embed("hello world")   # numpy float32, L2-normalized
    print(vec.shape)
```

## Speech-to-Text

```python
with RunAnywhere() as ra:
    stt = ra.load_stt("whisper-base")
    text = stt.transcribe(pcm16_bytes)    # 16 kHz mono PCM16 bytes
    print(text)
```

Async twin: `await stt.atranscribe(pcm16_bytes)` (runs off the event loop).

## Text-to-Speech

```python
with RunAnywhere() as ra:
    voice = ra.load_tts("piper-amy")
    synthesis = voice.synthesize("Hello from RunAnywhere.")
    print(synthesis.samples.shape, synthesis.sample_rate)   # float32 PCM + sample rate
```

Async twin: `await voice.asynthesize("...")`.

## Voice Agent (STT → LLM → TTS)

Compose loaded models into a single voice turn:

```python
with RunAnywhere() as ra:
    stt = ra.load_stt("whisper-base")
    llm = ra.load_llm("smollm2-360m")
    tts = ra.load_tts("piper-amy")

    agent = ra.create_voice_agent(stt, llm, tts, system_prompt="Answer briefly.")
    turn = agent.process_turn(
        pcm16_bytes,
        on_transcript=lambda t: print("You said:", t),
        on_token=lambda tok: print(tok, end="", flush=True),
    )
    print("\nAssistant:", turn.response)
    # turn.audio is a Synthesis (float32 PCM + sample rate)
```

Async twin: `await agent.aprocess_turn(pcm16_bytes)`.

## Voice-Activity Detection

```python
with RunAnywhere() as ra:
    vad = ra.create_vad(threshold=0.5)
    if vad.detect(frame_float32):        # 16 kHz mono float frame
        print("speech")
    vad.reset()
    vad.close()
```

## Events

Subscribe to lifecycle and generation events via the process-wide bus:

```python
from runanywhere import RunAnywhere, ModelLoadedEvent, GenerationEvent

ra = RunAnywhere()

def on_event(event):
    if isinstance(event, ModelLoadedEvent):
        print("loaded", event.modality, event.id)
    elif isinstance(event, GenerationEvent):
        print("finished:", event.result.tokens_per_second, "tok/s")

off = ra.events.on(on_event)   # returns an unsubscribe function
# ... use the SDK ...
off()
```

## Downloading Models

Loading a catalog id downloads it on first use. You can also pre-download (no `initialize()`
needed — download is pure host I/O), track progress, and check on-disk status:

```python
ra = RunAnywhere()

resolved = ra.download_model("smollm2-360m", on_progress=lambda p: print(f"{p.file} {p.percent}%"))
print(resolved.primary)   # concrete path to the model file

status = ra.model_status()   # dict[id -> ModelStatus(downloaded, size_bytes)]
```

Model sources accepted anywhere you pass an `id_or_path`:

- a built-in **catalog id** (`smollm2-360m`, `qwen2.5-1.5b`, `smolvlm-256m`, `minilm`,
  `whisper-base`, `piper-amy`, …),
- a **local path** to a model file,
- a direct **http(s) URL** to a model file,
- a **HuggingFace repo** (`owner/repo` or `owner/repo:file.gguf`) — a GGUF (plus any mmproj and
  all shards of a split GGUF) is auto-resolved.

STT/TTS/embedder models must come from a catalog id or a local path (URL/HF sources aren't
supported for those yet).

## Error Handling

Every SDK error is an `SDKException` carrying a canonical `code` and `category`:

```python
from runanywhere import RunAnywhere, SDKException, ErrorCode

try:
    with RunAnywhere() as ra:
        llm = ra.load_llm("does-not-exist.gguf")
        print(llm.generate_text("hi"))
except SDKException as e:
    if e.code == ErrorCode.MODEL_LOAD_FAILED:
        print("Could not load the model:", e.message)
    else:
        print(f"[{e.category.name}] {e.message}")
    if e.recovery_suggestion:
        print("Hint:", e.recovery_suggestion)
```

Common codes include `NOT_INITIALIZED`, `MODEL_NOT_FOUND`, `MODEL_LOAD_FAILED`,
`GENERATION_FAILED`, `INVALID_ARGUMENT`, `INVALID_STATE`, and `CANCELLED`.

## Notes

- **One generation at a time per model.** Starting a second concurrent `generate`/`caption` on
  the same model raises `SDKException` (`INVALID_STATE`) rather than blocking. Load separate
  models (or use separate handles) for concurrent work.
- **Everything is on-device.** Prompts, responses, audio and images never leave the host; the
  network is used only to download models.
- The compiled native runtime is loaded lazily on the first `initialize()`, so importing
  `runanywhere` is cheap and side-effect-free.

## Local Development

The SDK builds via [scikit-build-core](https://scikit-build-core.readthedocs.io), which drives
CMake to compile the native `_core` extension from `runanywhere-commons`.

```bash
# Editable install with test extras (compiles the native module)
pip install -e ".[test]"

# Run the test suite (pure Python — no native build required; tests fake the core)
pytest tests
```

See `AGENTS.md` for the full architecture, build details, and the lazy-load design.

## License

See the repository `LICENSE`. For commercial licensing, contact san@runanywhere.ai.
