# RunAnywhere — local OpenAI-compatible server

A ~250-line [FastAPI](https://fastapi.tiangolo.com/) server that turns the on-device
[RunAnywhere Python SDK](../../sdk/runanywhere-python/) into a **drop-in OpenAI API** — 100%
local, offline, no API keys, nothing leaves the machine. Point any OpenAI client at
`http://localhost:8000/v1` and it just works.

| OpenAI endpoint | Backed by | Model id (the `model` field) |
|---|---|---|
| `POST /v1/chat/completions` (stream + non-stream) | LLM (llama.cpp / NPU / CUDA) | `qwen2.5-0.5b`, `llama-3.2-1b`, … |
| `POST /v1/embeddings` | Embedder (ONNX) | `minilm` |
| `POST /v1/audio/transcriptions` (Whisper API) | STT (sherpa) | `whisper-tiny`, `whisper-base` |
| `POST /v1/audio/speech` | TTS (sherpa) | `piper-lessac`, `piper-amy`, … |
| `GET /v1/models` | the built-in catalog | — |

Models are downloaded on first use and cached under `~/.runanywhere/models`. The SDK routes
each request to the best engine on the box automatically (CUDA GPU if built with it, the NPU on
a QHexRT build, else CPU).

## Run

```bash
# 1. Install the SDK (a built wheel, or from PyPI once published) + the server deps.
pip install -r requirements.txt
#    ...or, from a source checkout, build the SDK wheel first:
#    (cd ../../sdk/runanywhere-python && pip install .)

# 2. Start it.
uvicorn server:app --host 0.0.0.0 --port 8000

# Health / info:
curl http://localhost:8000/            # {service, backends, models, endpoints}
curl http://localhost:8000/v1/models
```

## Use it — any OpenAI client, pointed local

### Python `openai` library

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:8000/v1", api_key="not-needed")

# Chat (streaming)
stream = client.chat.completions.create(
    model="qwen2.5-0.5b",
    messages=[{"role": "user", "content": "Capital of France? One word."}],
    stream=True,
)
for chunk in stream:
    print(chunk.choices[0].delta.content or "", end="", flush=True)

# Embeddings
emb = client.embeddings.create(model="minilm", input=["hello", "world"])
print(len(emb.data), "vectors of dim", len(emb.data[0].embedding))
```

### curl

```bash
# Chat (non-streaming)
curl http://localhost:8000/v1/chat/completions -H "Content-Type: application/json" -d '{
  "model": "qwen2.5-0.5b",
  "messages": [{"role":"user","content":"Capital of France? One word."}]
}'

# Chat (streaming SSE)
curl -N http://localhost:8000/v1/chat/completions -H "Content-Type: application/json" -d '{
  "model": "qwen2.5-0.5b", "stream": true,
  "messages": [{"role":"user","content":"Write one sentence about Paris."}]
}'

# Embeddings
curl http://localhost:8000/v1/embeddings -H "Content-Type: application/json" -d '{
  "model": "minilm", "input": "on-device AI"
}'

# Speech-to-text (16 kHz mono WAV)
curl http://localhost:8000/v1/audio/transcriptions \
  -F model=whisper-tiny -F file=@sample.wav

# Text-to-speech (returns a WAV)
curl http://localhost:8000/v1/audio/speech -H "Content-Type: application/json" -d '{
  "model": "piper-lessac", "input": "Hello from on-device text to speech."
}' --output speech.wav
```

Because it speaks the OpenAI wire format, existing frameworks (LangChain, LlamaIndex, the
Vercel AI SDK, …) work unchanged — just set the base URL to this server.

## Notes / scope

This is a reference demo, not a production gateway:
- Chat prompt assembly is simple (a single user turn is passed verbatim so the model's chat
  template applies cleanly; multi-turn is serialized into a transcript).
- `usage` token counts are approximate (the SDK backends don't surface exact counts here).
- `/v1/audio/transcriptions` accepts **WAV** (16 kHz mono is ideal; other rates are downsampled);
  convert other formats with `ffmpeg` first. `/v1/audio/speech` returns **WAV**.
- Each loaded model is single-in-flight; the server serializes concurrent requests to the same
  model with a lock. Run behind more workers / multiple model instances for real concurrency.
