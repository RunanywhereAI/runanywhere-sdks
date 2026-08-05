# RunAnywhere Python SDK

On-device AI for Python — LLM, VLM, STT, TTS, embeddings, and voice pipelines run entirely on the host. Inference needs no network; the network is used only to download models.

**Current release:** `0.20.11`

## Install

```bash
pip install runanywhere==0.20.11
```

Wheels bundle the compiled native runtime and dependent libraries on Windows, macOS, and Linux. Python **3.9+** and `numpy >= 1.21` are required.

Optional extras:

```bash
pip install "runanywhere[rag]==0.20.11"      # RAG / document Q&A
pip install "runanywhere[server]==0.20.11"   # OpenAI-compatible local server
```

## Quick start

One `initialize()` call, then a namespace per modality:

```python
import runanywhere as ra
from runanywhere import LlmOptions

ra.initialize()
print(ra.llm.generate("Explain quantum computing in one sentence.",
                      LlmOptions(model="smollm2-360m")).text)
```

`options.model` takes a catalog id (downloaded on first use), a local `.gguf` path, an
`https://` URL, or a HuggingFace repo. Once a model is loaded it stays resident, so later
calls can leave `model` out. `ra.reset()` unloads everything.

`RUNANYWHERE_HOME` changes where models and state are cached (default `~/.runanywhere`).

## Text generation

```python
result = ra.llm.generate("What is the capital of France?", LlmOptions(max_output_tokens=32))
print(result.text, result.output_tokens, result.tokens_per_second)

for event in ra.llm.generate_stream("Describe a sunset."):
    if event.is_token:
        print(event.text, end="", flush=True)
    elif event.is_completed:
        r = event.result
        print(f"\n{r.output_tokens} tokens, {r.tokens_per_second:.1f} tok/s")
```

Multi-turn is a list of messages, not a separate object:

```python
from runanywhere import ChatMessage, Role

ra.llm.generate([
    ChatMessage(Role.SYSTEM, "You are terse."),
    ChatMessage(Role.USER, "Who wrote Hamlet?"),
])
```

Every verb that blocks has an `a`-prefixed async twin (`agenerate`, `agenerate_stream`,
`atranscribe`, `aembed`, `aquery`, …).

### Structured output and tools

```python
schema = {
    "type": "object",
    "properties": {"city": {"type": "string"}, "temp_c": {"type": "integer"}},
    "required": ["city", "temp_c"],
}
result = ra.llm.generate_structured("Weather in Paris, as JSON.", schema)
print(result.value, result.valid)

from runanywhere import ToolDefinition

ra.llm.tools.register(
    ToolDefinition(name="get_weather", parameters=schema, description="Current weather"),
    lambda args: {"temp_c": 21},
)
result = ra.llm.generate("Weather in Berlin?")   # the SDK runs the tool and continues
print(result.tool_calls, result.text)
```

## Vision, speech, and voice

```python
from runanywhere import AudioInput, ImageInput, SttOptions, TtsOptions

print(ra.vlm.generate(ImageInput.file("photo.jpg"), "Describe this image.").text)

transcript = ra.stt.transcribe(AudioInput.file("speech.wav"), SttOptions(model="whisper-base"))
audio = ra.tts.synthesize("Hello from RunAnywhere.", TtsOptions(voice="piper-amy"))
speech = ra.vad.detect(AudioInput.file("speech.wav"))
```

`ra.voice.create_session(...)` is defined but not available in this SDK: the native bridge
binds no voice agent and the package has no microphone or speaker adapter, so it raises
`SDKException` naming the missing symbols. Compose `stt` → `llm` → `tts` yourself.
`ra.rerank`, `ra.images`, `ra.diarization`, `ra.segmentation` and `ra.lora` raise for the
same reason.

## Embeddings and RAG

```python
from runanywhere import EmbedOptions, ModelRef, RagDocument

# numpy float32, L2-normalized, returned in input order
vectors = ra.embeddings.embed(["hello world"], EmbedOptions(model="minilm"))

with ra.rag.open(ModelRef("minilm"), ModelRef("qwen2.5-0.5b")) as session:
    session.ingest(RagDocument("Paris is the capital of France."))
    print(session.search("capital of France?"))        # retrieval only
    print(session.query("What is the capital of France?").answer)
```

Install `runanywhere[rag]` for RAG support.

## Models

Catalog ids (`smollm2-360m`, `qwen2.5-0.5b`, `smolvlm-256m`, `minilm`, `whisper-base`,
`piper-amy`, …) download on first load. Anything the generation verbs accept as
`options.model` also works here.

```python
from runanywhere import DownloadEventKind, ModelFilter

for event in ra.models.download("smollm2-360m"):
    if event.kind == DownloadEventKind.PROGRESS:
        print(f"{event.percent}%")

ra.models.list(ModelFilter(downloaded=True))
ra.models.load("smollm2-360m")      # pay the load cost now instead of on first generate
ra.models.state()                   # what is resident + disk used/free
```

## Local OpenAI-compatible server

```bash
pip install "runanywhere[server]==0.20.11"
runanywhere serve          # http://127.0.0.1:8000
runanywhere models         # list catalog + download state
```

Point any OpenAI client at `http://localhost:8000/v1`. Supports chat/completions (including vision and tools), embeddings, transcriptions, and speech synthesis — all local.

Production defaults restrict clients to catalog model ids, disable server-side image URL fetching (SSRF), and support optional Bearer auth via `--api-key` or `RUNANYWHERE_API_KEY`.

```python
from openai import OpenAI
client = OpenAI(base_url="http://localhost:8000/v1", api_key="not-needed")
print(client.chat.completions.create(model="qwen2.5-0.5b",
    messages=[{"role": "user", "content": "Hi"}]).choices[0].message.content)
```

## CLI

`pip install runanywhere` also installs a `runanywhere` command with parity to the C++ `rcli`:

```bash
runanywhere run qwen2.5-0.5b "Capital of France?"
runanywhere chat qwen2.5-0.5b
runanywhere stt -i speech.wav
runanywhere tts -t "hello" -o out.wav
runanywhere list --all
runanywhere serve
```

Use `--json` for machine-readable output. For the standalone binary, see the [RunAnywhere CLI](../runanywhere-cli/README.md).

## Errors

```python
from runanywhere import SDKException

try:
    ra.models.load("missing.gguf")
except SDKException as e:
    print(e.code, e.message, e.recovery_suggestion)
```

Verbs raise a typed `SDKException`; nothing returns a result object with a success flag, and
nothing hides an error message in a text field. An option the native bridge cannot carry
raises rather than being silently ignored.

## Notes

- One generation at a time per resident model; a concurrent `generate` raises immediately.
- One model per category is resident; asking for a different id in the same category swaps it.
- Prompts, responses, audio, and images never leave the host during inference.
- Pass `api_key` + `base_url` (production) and `initialize` runs the two-phase control-plane
  handshake — authenticate, then flush telemetry — over the bundled libcurl transport. With no
  credentials it does no network work. A wheel built without the desktop adapter
  (`RAC_DESKTOP_ADAPTER=OFF`) has no control plane and ignores both, warning if a key is passed.

## Support

- Documentation: [docs.runanywhere.ai](https://docs.runanywhere.ai)
- Discord: [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- Email: [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

## Contributing

Local build and test instructions: [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md).

## License

Copyright (c) 2026 RunAnywhere, Inc. See the repository [LICENSE](../../LICENSE). For commercial licensing, contact [founders@runanywhere.ai](mailto:founders@runanywhere.ai).
