# Decision 06 — Barge-in model

## Question

How does the voice agent handle barge-in (user starts speaking while
the TTS is still playing the previous answer)?

## Choice

**Transactional cancel boundary**: one mutex guards a single atomic
operation that (a) sets `barge_in_flag_`, (b) cancels the LLM,
(c) clears the sentence queue, (d) drains the playback ring buffer.

## Alternatives considered

| Option | Why rejected |
| --- | --- |
| Per-stage cancellation, in sequence | Leaves a race where tokens can enter the TTS queue *between* the LLM cancel and the queue clear. Fails under stress |
| Poll a shared flag at every boundary | Can work but hard to reason about; each stage has to know the flag exists |
| Cooperative cancellation via exception in the LLM thread | Exceptions across worker threads are error-prone; we keep them exceptional |
| Kill and restart the whole DAG on barge-in | Resets too much state; >200 ms recovery |

## Reasoning

The hard bug is the interleaving:

```
  t0  user says "wait, stop"   → VAD emits barge_in
  t1  voice_agent starts cancelling LLM
  t2  LLM emits token X        ← already in flight
  t3  sentence detector ingests X
  t4  sentence detector pushes sentence to TTS
  t5  voice_agent drains playback_rb and clears sentence_edge
  t6  TTS reads the sentence that was pushed at t4
  t7  user hears the tail of the previous answer (BUG)
```

With a mutex around steps 1+5 and `barge_in_flag_` checked at the top
of the TTS loop, the TTS worker never dispatches a sentence if the
flag is set. The mutex ensures the order {set flag → cancel LLM →
clear queue → drain ring} is atomic from any other thread's view.

We also set `barge_in_flag_.store(..., memory_order_release)` and
load with `memory_order_acquire` at each worker's iteration start.
Proven pattern from the `RCLI` reference.

## Implications

- `VoiceAgentPipeline::on_barge_in()` is the only function holding
  `barge_in_mu_`; all other mutations of `barge_in_flag_` and the
  edge queues go through it.
- Target: barge-in → full silence within 50 ms on a dev MacBook.
- Required test: `voice_agent_bargein_test` under TSan. No PCM after
  the barge-in event for at least 100 ms; sentence queue empty
  within 50 ms.

Phase 3 is the load-bearing phase.
