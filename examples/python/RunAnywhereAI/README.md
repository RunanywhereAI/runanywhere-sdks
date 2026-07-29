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

## Running

`chat.py` loads the LLM, runs one unary completion, then two streamed completions
showing the v2 generation options: `max_output_tokens`, and `ReasoningOptions` with
`include_in_output` off (thinking stripped) and on (thought tokens printed, prefixed
with `~`).

```bash
.venv/bin/python chat.py            # or: .venv/bin/python chat.py qwen2.5-0.5b
```

`rag.py` opens a RAG session over the `minilm` embedder plus the same small LLM,
ingests three short documents, and asks one grounded question with generation options
on the query.

```bash
.venv/bin/python rag.py
```

`server_demo.sh` starts `runanywhere serve` on port 8000 (override with `PORT=`),
waits for `/health`, sends one `/v1/chat/completions` request with curl, and shuts the
server down.

```bash
./server_demo.sh
```
