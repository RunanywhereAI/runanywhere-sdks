# Phase 3 — Voice Agent as a streaming DAG

> Goal: rewrite `src/features/voice_agent/voice_agent.cpp` as a streaming
> DAG with a transactional barge-in cancel boundary. First-audio latency
> target: ≤80 ms on M-series MacBook with a 4 B-parameter LLM on GGUF.

---

## Prerequisites

- Phase 2 complete: LLM, STT, TTS, VAD, and VLM all expose
  `StreamEdge<T>` APIs.
- `rac::core::GraphScheduler`, `StreamEdge`, `CancelToken`, `RingBuffer`
  from Phase 0 are live.
- `PluginRegistry` + `EngineRouter` from Phase 1 are the single path
  to engine sessions.

---

## What this phase delivers

1. **Streaming DAG topology** for voice:
   ```text
   mic ─┬─► vad ─┬───► barge_in_boundary
        │       │           │
        │       └──► stt ─► llm ─► sentence_detector ─► tts ─► audio_sink
        └──── (duplicate audio frames into stt path)
   ```
2. **Transactional barge-in**: on `vad.barge_in`, a single mutex-protected
   operation:
   - Sets `barge_in_flag_` atomically.
   - Calls `llm.cancel()` via the session's cancel token.
   - Clears `sentence_queue_` (`StreamEdge::clear_locked()`).
   - Drains `playback_rb_` (`RingBuffer::drain()`).
3. **LLM → TTS token streaming via `SentenceDetector`**: as LLM emits
   tokens, the sentence detector fires sentence callbacks; TTS synthesizes
   each sentence immediately and pushes PCM to the playback ring buffer.
4. **First-audio ≤80 ms** on M-series MacBook with `qwen3-4b-q4_k_m.gguf`
   + `whisper-base` + `kokoro`. Measured by a new benchmark in
   `tools/benchmark/`.
5. **`SentenceDetector` and `TextSanitizer`** ported from the FastVoice
   reference design (see `MASTER_PLAN.md` for origin).

**Voice agent public API stays the same** (`voice_agent_create`,
`voice_agent_run`, `voice_agent_stop`). The rewrite is entirely under
the hood.

---

## Exact file-level deliverables

### New files

```text
sdk/runanywhere-commons/include/rac/features/voice_agent/
├── rac_voice_agent.h               existing — KEEP public API surface
├── sentence_detector.h             NEW — ported from FastVoice
└── text_sanitizer.h                NEW — strips markdown/<think>/whitespace before TTS

sdk/runanywhere-commons/src/features/voice_agent/
├── voice_agent.cpp                 REWRITTEN — streaming DAG
├── sentence_detector.cpp           NEW
└── text_sanitizer.cpp              NEW
```

### voice_agent.cpp — new shape

```cpp
class VoiceAgentPipeline {
public:
    struct Config { /* llm/stt/tts/vad model ids; sample rate; chunk_ms;
                       enable_barge_in; emit_partials; emit_thoughts */ };

    VoiceAgentPipeline(Config cfg, PluginRegistry& reg, EngineRouter& router);
    ~VoiceAgentPipeline();

    ra_status_t start();   // creates sessions, launches GraphScheduler
    ra_status_t stop();    // cancels root token, joins all threads

    // External audio push (for AUDIO_SOURCE_CALLBACK mode).
    ra_status_t feed_audio(const float* pcm, int n, int sr);

    // Consumer reads events from here.
    StreamEdge<VoiceAgentEvent>& output_stream();

    // Called from vad_loop when a barge-in is detected. Runs the
    // transactional boundary — mutex-protected so the four sub-operations
    // appear atomic to all other pipeline threads.
    void on_barge_in();

private:
    // Worker threads — one per operator.
    void mic_capture_loop();
    void vad_loop();
    void stt_loop();
    void llm_loop();
    void sentence_emitter_loop();
    void tts_loop();
    void audio_sink_loop();

    // Edges, buffers, session handles as per MASTER_PLAN naming.
    StreamEdge<std::vector<float>> vad_audio_edge_;   // mic → vad
    StreamEdge<std::vector<float>> stt_audio_edge_;   // mic → stt (tee)
    StreamEdge<std::string>        transcript_edge_;
    StreamEdge<std::string>        token_edge_;
    StreamEdge<std::string>        sentence_edge_;
    StreamEdge<std::vector<float>> audio_out_edge_;
    RingBuffer<float>              playback_rb_{96000};

    std::atomic<bool>              barge_in_flag_{false};
    std::mutex                     barge_in_mu_;
    std::shared_ptr<CancelToken>   cancel_;
    GraphScheduler                 scheduler_;

    // Engine sessions acquired via PluginRegistry::find + vtable->*_create.
    ra_llm_session_t*  llm_session_ = nullptr;
    ra_stt_session_t*  stt_session_ = nullptr;
    ra_tts_session_t*  tts_session_ = nullptr;
    ra_vad_session_t*  vad_session_ = nullptr;
};
```

### on_barge_in — exact sequence

```cpp
void VoiceAgentPipeline::on_barge_in() {
    std::lock_guard<std::mutex> lk(barge_in_mu_);
    barge_in_flag_.store(true, std::memory_order_release);

    // (1) Tell the LLM to stop decoding. Session-level cancel token.
    llm_plugin_->vtable.llm_cancel(llm_session_);

    // (2) Drop any PCM that's already queued for playback.
    playback_rb_.drain();

    // (3) Clear any sentences that the detector already dispatched.
    sentence_edge_.clear_locked();

    // (4) Inform the consumer.
    output_stream().push(VoiceAgentEvent::interrupted("user barge-in"));
}
```

The TTS worker loop checks `barge_in_flag_` before each
synthesize call and skips the sentence if set. New utterance clears the
flag via `barge_in_flag_.store(false, std::memory_order_release)` on the
next STT `is_final=true` event.

### Sentence detection — the algorithm

Follows the FastVoice pattern (citations in MASTER_PLAN):

- Accumulate token text character by character.
- Word boundary = whitespace OR terminal punctuation (`.`, `!`, `?`).
- Emit when: terminal punctuation present AND word count ≥
  `min_words_for_emit` (default 2) AND space-gate allows.
- Force-emit when: word count ≥ `max_words_before_force_flush` (default
  30) even without terminal punctuation.

### Text sanitizer — the algorithm

Strips before TTS:
- `<think>…</think>`, `<thought>…</thought>`, `<reasoning>…</reasoning>`
  chain-of-thought blocks.
- Markdown runs: `**`, `__`, triple-backtick code blocks, `# headers`.
- Expand common abbreviations (`Mr.`, `Mrs.`, `Ms.`, `Dr.`, `Jr.`, etc.)
  so TTS pronounces them.
- Normalize whitespace (collapse runs, strip trailing).

Full config struct so the defaults can be tuned without recompile.

### Benchmark

`tools/benchmark/voice_agent_latency.cpp` — loads a fixed WAV with a
known short utterance, runs VoiceAgentPipeline end-to-end with
Stream<T> timestamps, reports:

- End-of-utterance → LLM first token (ms)
- LLM first token → TTS first PCM frame (ms)
- End-of-utterance → first audible audio sample (ms)

CI benchmark gate in Phase 6 checks the third metric is ≤80 ms on macOS
CI runners with a pinned reference model checkpoint.

### Tests

```text
tests/integration/voice_agent_streaming_test.cpp
  — with mock LLM/STT/TTS plugins that emit pre-recorded token streams,
    asserts sequencing: STT final → LLM first token fires within X ms,
    TTS first PCM within Y ms of first complete sentence.

tests/integration/voice_agent_bargein_test.cpp
  — drives a synthetic VAD barge_in event while TTS is actively
    synthesizing. Asserts: no PCM emitted after barge_in event;
    sentence_edge_ is empty within 50 ms; new utterance after barge_in
    starts a fresh LLM generation.

tests/integration/voice_agent_backpressure_test.cpp
  — consumer pops output_stream() slowly; asserts producer blocks and
    never drops audio frames.
```

---

## Implementation order

1. **Port `SentenceDetector` + `TextSanitizer`** from the FastVoice
   reference into `src/features/voice_agent/`. Add unit tests for each
   (already stubbed in Phase 0 tests/core_tests).

2. **Rewrite `voice_agent.cpp`.** Do it as a single commit: the old batch
   loop goes away entirely, the new DAG replaces it. The old commit
   history is still available; no need to preserve it inline.

3. **Wire to PluginRegistry.** Engine sessions from Phase 1 approach.

4. **Verify with mock plugins first.** Write mock llamacpp/sherpa
   plugins that emit fixed streams. Build confidence that the DAG
   plumbing is correct without dragging real models into the test loop.

5. **Enable real models** in a manual integration run. Profile with
   `tools/benchmark/voice_agent_latency`. Confirm ≤100 ms first audio
   on a dev MacBook with the sample models.

6. **Tune**: if first audio exceeds 80 ms, the usual suspects are —
   - `StreamEdge` condvar wakeup latency (measure with tracepoints).
   - TTS ring-buffer chunk size (smaller → faster first frame but worse
     smoothness).
   - Sentence detector's word-gate threshold.

7. **Land barge-in test.** Synthetic test first, then manual test on a
   dev Mac with real mic.

---

## API changes

### Public (rac_voice_agent.h) — kept stable

`rac_voice_agent_create / run / stop` unchanged in signature. The input
is a `rac_voice_agent_config_t` struct today; in Phase 5 it becomes a
proto3 `VoiceAgentConfig`.

### Internal — completely new

`VoiceAgentPipeline` class, sentence detector, text sanitizer. No old
symbols survive inside `voice_agent.cpp` — a clean rewrite.

---

## Acceptance criteria

- [ ] End-of-utterance to first PCM frame ≤ 80 ms in CI benchmark on
      macOS-14 runner with pinned sample models.
- [ ] Barge-in test: no PCM emitted after `vad.barge_in` for at least
      100 ms. Sentence queue empty within 50 ms.
- [ ] Backpressure test: slow consumer never loses audio.
- [ ] ASan + UBSan + TSan green on the new tests.
- [ ] Existing voice-agent integration (if any) in `tests/` continues
      to pass after the rewrite.
- [ ] `voice_agent.cpp` LOC: was ~1,100 LOC + worker functions inline;
      after the rewrite, expect ~600 LOC total (the complexity is in
      the scheduler and the edge types, not the glue).

## Validation checkpoint — **MAJOR**

See `testing_strategy.md`. Phase 3 is the highest-user-visible
phase — real streaming voice with barge-in. Checkpoint must be
thorough:

- **Streaming DAG correctness.** `voice_agent_streaming_test` green
  — sequencing order strictly: STT final → LLM first token →
  sentence detector → TTS first PCM. No out-of-order events.
- **Barge-in correctness.** `voice_agent_bargein_test` green under
  TSan. Explicit timings: sentence queue empty within 50 ms; no
  PCM after barge-in for ≥100 ms; fresh LLM generation kicks in on
  the next utterance.
- **Back-pressure.** Slow consumer never drops audio frames under
  the `voice_agent_backpressure_test`.
- **First-audio latency benchmark.** p50 ≤ 80 ms, p90 ≤ 120 ms,
  p99 ≤ 180 ms on macOS-14 CI runner with the pinned reference
  models. Thresholds enforced by `check_thresholds.py`.
- **On-device manual smoke.** At least one run on a real M-series
  MacBook with a real microphone: ask a question, get an audible
  answer, interrupt mid-reply, confirm it stops cleanly, ask a
  follow-up, confirm fresh reply. Human sign-off on the UX.
- **Full feature preservation matrix.** Voice agent rewrite must
  not have broken LLM / STT / TTS / VAD underneath — re-run all
  L3 primitive smokes. Wake word + RAG unchanged, still pass.
- **No memory growth.** Run a 10-minute voice session under
  `leaks` (macOS) + ASan; heap usage stabilises after first
  utterance. No growth per utterance beyond chunk buffers.
- **Sanitizer matrix.** All new voice agent tests green under
  ASan + UBSan + TSan.

**Sign-off before Phase 4**: manual UX test recorded (screen-capture
or audio log); first-audio latency measured on device; barge-in
feel confirmed natural. If subjective UX fails even with benchmark
gates green, tune the sentence detector / ring-buffer sizes and
re-measure.

---

## What this phase does NOT do

- RAG retrieval stays single-path until Phase 4.
- C ABI still carries struct events. The VoiceAgentEvent output stream
  in this phase is C++-internal. A proto3-serializing shim at the C
  ABI is added in Phase 5.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| Barge-in race: token enters TTS synthesize_to_ring_buffer **after** on_barge_in drained the buffer | Medium | TTS worker's first statement on each iteration: check `barge_in_flag_.load(memory_order_acquire)`. Proven pattern from RCLI `src/pipeline/orchestrator.h:215-218` |
| Sentence detector fires sentence with `SomeWord.` (single word ending a period) and TTS says "SomeWord period" | Low | `min_words_for_emit=2` default; unit tests cover single-word edge |
| TTS synthesizer latency spikes on first sentence cause >80 ms first audio | Medium | Phase 6 benchmark gate catches this; first-sentence pre-warming can be added to `tts_loop` if needed |
| `StreamEdge::clear_locked()` during barge-in races with a concurrent `push()` from the LLM callback | Medium | `clear_locked()` takes the edge's mutex, which the pushing thread must acquire to append. Atomic from caller's perspective. Tested under TSan |
| Scheduler thread count × worker count > available cores on low-end Android → scheduler contention | Low | 7 nodes × 1 thread each = 7 threads. Baseline Android target has 8 cores |
| Tee of `mic → {vad, stt}` duplicates audio frame and adds memory pressure | Low | 20 ms @ 16 kHz mono = 640 samples × 4 B = 2.5 kB per copy. Negligible |
