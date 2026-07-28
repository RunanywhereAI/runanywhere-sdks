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

`RunAnywhere` is an instantiable client. Use it as a context manager:

```python
from runanywhere import RunAnywhere

with RunAnywhere() as ra:
    llm = ra.load_llm("smollm2-360m")
    print(llm.generate_text("Explain quantum computing in one sentence."))
```

Load by catalog id (downloaded on first use) or by a local `.gguf` path:

```python
with RunAnywhere() as ra:
    llm = ra.load_llm("/path/to/model.gguf")
    for token in llm.generate("Write a haiku.", max_tokens=64):
        print(token, end="", flush=True)
```

Configuration:

```python
ra = RunAnywhere(
    base_dir="~/my-models",        # default: ~/.runanywhere
    environment="production",
)
```

## Text generation

```python
# Full text
answer = llm.generate_text("What is the capital of France?", max_tokens=32)

# Streaming with metrics
for event in llm.generate_stream("Describe a sunset."):
    if event.is_final:
        r = event.result
        print(f"\n{r.token_count} tokens, {r.tokens_per_second:.1f} tok/s")
    else:
        print(event.token, end="", flush=True)
```

Async twins exist for every blocking method (`agenerate`, `agenerate_text`, …).

### Structured output and tools

```python
schema = {
    "type": "object",
    "properties": {"city": {"type": "string"}, "temp_c": {"type": "integer"}},
    "required": ["city", "temp_c"],
}
result = llm.generate_structured("Weather in Paris, as JSON.", schema)

from runanywhere import ToolSpec
tools = [ToolSpec(name="get_weather", description="...", parameters={...},
                  execute=lambda args: {"temp_c": 21})]
run = llm.generate_with_tools("Weather in Berlin?", tools)
```

### Chat

```python
with RunAnywhere() as ra:
    llm = ra.load_llm("smollm2-360m")
    chat = ra.create_chat(llm, system="You are a terse assistant.")
    print(chat.send_text("Who wrote Hamlet?"))
    print(chat.send_text("And when?"))
```

## Vision, speech, and voice

```python
with RunAnywhere() as ra:
    # VLM
    vlm = ra.load_vlm("smolvlm-256m")
    print(vlm.caption_text("photo.jpg", "Describe this image."))

    # STT — 16 kHz mono PCM16 bytes
    stt = ra.load_stt("whisper-base")
    text = stt.transcribe(pcm16_bytes)

    # TTS — returns float32 PCM + sample rate
    tts = ra.load_tts("piper-amy")
    audio = tts.synthesize("Hello from RunAnywhere.")

    # Voice agent (STT → LLM → TTS)
    agent = ra.create_voice_agent(stt, llm, tts)
    turn = agent.process_turn(pcm16_bytes)
```

## Embeddings and RAG

```python
with RunAnywhere() as ra:
    embedder = ra.load_embedder("minilm")
    vec = embedder.embed("hello world")   # numpy float32, L2-normalized

    with ra.create_rag("minilm", llm_model="qwen2.5-0.5b") as rag:
        rag.ingest("Paris is the capital of France.")
        result = rag.query("What is the capital of France?")
        print(result.answer)
```

Install `runanywhere[rag]` for RAG support.

## Models

Catalog ids (`smollm2-360m`, `qwen2.5-0.5b`, `smolvlm-256m`, `minilm`, `whisper-base`, `piper-amy`, …) download on first load. You can also pass:

- a local file path
- an `https://` URL
- a HuggingFace repo (`owner/repo` or `owner/repo:file.gguf`)

Pre-download and inspect status:

```python
ra = RunAnywhere()
path = ra.download_model("smollm2-360m", on_progress=lambda p: print(f"{p.percent}%"))
status = ra.model_status()
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
from runanywhere import SDKException, ErrorCode

try:
    with RunAnywhere() as ra:
        ra.load_llm("missing.gguf")
except SDKException as e:
    print(e.code, e.message, e.recovery_suggestion)
```

## Notes

- One generation at a time per model handle; load separate handles for concurrency.
- Prompts, responses, audio, and images never leave the host during inference.
- Multiple clients share one reference-counted native runtime.

## Support

- Documentation: [docs.runanywhere.ai](https://docs.runanywhere.ai)
- Discord: [discord.gg/N359FBbDVd](https://discord.gg/N359FBbDVd)
- Email: [founders@runanywhere.ai](mailto:founders@runanywhere.ai)

## Contributing

Local build and test instructions: [docs/DEVELOPMENT.md](./docs/DEVELOPMENT.md).

## License

Copyright (c) 2026 RunAnywhere, Inc. See the repository [LICENSE](../../LICENSE). For commercial licensing, contact [founders@runanywhere.ai](mailto:founders@runanywhere.ai).
