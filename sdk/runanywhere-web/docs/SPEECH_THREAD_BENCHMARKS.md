# Speech multi-thread soak (WASM)

Sherpa/ORT on Web default to **2** intra-op threads (was 1). Configure via:

```ts
await ONNX.register({ threads: 4, requireBackendWorker: true });
```

Clamped to `1..8` to match the Emscripten pthread pool size.

## What to measure

For each model (Whisper Tiny, Canary 180M, Nemotron streaming), on a COI page:

| Metric | How |
|--------|-----|
| Wall time | Transcribe a fixed ~10s wav, median of 5 runs |
| Abort rate | Count of `Aborted()` / worker crashes over 50 runs |
| UI jank | Main-thread long tasks while BackendWorker owns inference |

## Suggested matrix

| threads | Expected |
|---------|----------|
| 1 | Baseline (legacy) |
| 2 | Default — should improve large transducers |
| 4 | Peak on desktop; watch abort rate |
| 8 | Pool max; often no gain vs 4 |

## Pass criteria

- Measurable speedup on Nemotron/Canary at `threads=2` vs `1` on multi-core Chrome
- No increase in `Aborted()` vs baseline in e2e under COOP/COEP
- Badge / `RunAnywhere.runtime.speech.threads` matches the requested value
