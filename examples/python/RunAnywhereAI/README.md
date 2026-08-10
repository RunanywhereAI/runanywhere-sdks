# RunAnywhereAI (Python)

Terminal example for the RunAnywhere Python SDK: local LLM chat (unary and streaming),
a small RAG session, and the built-in OpenAI-compatible server. Everything runs on the
host; the network is used only to download model weights.

## Setup

The SDK builds its native extension from the C++ sources in this repo, so an editable
install compiles `runanywhere-commons` plus the llamacpp/onnx/sherpa backends. Use gcc
on Linux machines where clang lacks C++ stdlib headers.

```bash
cd examples/python/RunAnywhereAI
python3 -m venv .venv
CC=gcc CXX=g++ .venv/bin/pip install -e "../../../sdk/runanywhere-python[server,rag]"
```

To reuse an existing repo CMake build tree instead of compiling from scratch, pass it
as the scikit-build build directory:

```bash
CC=gcc CXX=g++ .venv/bin/pip install -e "../../../sdk/runanywhere-python[server,rag]" \
    --no-build-isolation \
    --config-settings=build-dir=../../../build/<your-build-dir>
```

Check the install without downloading anything:

```bash
./scripts/verify.sh
```

## Models

Every script takes a catalog id (default `smollm2-135m`, a 92 MB GGUF). The SDK
downloads it on first use and caches it under `~/.runanywhere`. To fetch it ahead of
time:

```bash
.venv/bin/python -m runanywhere pull smollm2-135m
.venv/bin/python -m runanywhere ls
```

## The API these scripts use

One `runanywhere.initialize()` call, then a namespace per modality: `ra.llm`, `ra.rag`,
`ra.models`, and so on. Options are dataclasses (`LlmOptions`, `RagConfig`), every
generation result carries the same metrics block, and the blocking verbs have an
`a`-prefixed async twin (`agenerate`, `aquery`).

```python
import runanywhere as ra
from runanywhere import LlmOptions

ra.initialize()
print(ra.llm.generate("Hello", LlmOptions(model="smollm2-135m")).text)
```

## Running

`chat.py` walks the `llm` namespace: a unary `generate` with its metrics, a streamed
`generate_stream`, the same stream with `ReasoningOptions(include_in_output=True)` so
thought tokens print prefixed with `~`, a multi-turn `ChatMessage` list, and a
registered tool the SDK calls and feeds back into the loop. It downloads the model
first through `ra.models.download` when it is not cached yet.

```bash
.venv/bin/python chat.py            # or: .venv/bin/python chat.py qwen2.5-0.5b
```

`rag.py` opens a session over the `minilm` embedder plus the same small LLM, ingests
three documents, then shows all three read verbs: `search` (retrieval only), `query`
(grounded answer plus sources), and `query_stream`.

```bash
.venv/bin/python rag.py
```

`server_demo.sh` starts `runanywhere serve` on port 8000 (override with `PORT=`), waits
for `/health`, sends a unary and a streaming `/v1/chat/completions` request with curl,
then shuts the server down. The HTTP surface keeps OpenAI's field names — `max_tokens`,
`response_format`, `stream` — and the server translates them into the SDK's options.

```bash
./server_demo.sh
```
