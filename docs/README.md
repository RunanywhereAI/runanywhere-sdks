# RunAnywhere Documentation

_Branch: `feat/v2-architecture` (114 commits ahead of `main`, not yet
released). Updated: 2026-04-22._

## Start here

1. **[`TEAM_STATUS.md`](TEAM_STATUS.md)** — **3-min status read** for
   sharing in standup. Branch state + per-GAP closure + what's left
   + suggested release sequencing.
2. **[`STATE_AND_ROADMAP.md`](STATE_AND_ROADMAP.md)** — architectural
   detail + active backlog + versioning policy + doc map.
3. **[`GAP_STATUS.md`](GAP_STATUS.md)** — rolling 10-GAP scoreboard
   (DONE / MOSTLY DONE / DEFERRED per spec). Update when a GAP ships.
4. **[`HISTORY.md`](HISTORY.md)** — chronological narrative of the
   114 branch commits. Full evidence under `archive/`.

## Reference docs (active)

- **[`building.md`](building.md)** — Kotlin/Gradle build entry
- **[`engine_plugin_authoring.md`](engine_plugin_authoring.md)** —
  Engine plugin (vtable + registration) reference
- **[`graph_primitives.md`](graph_primitives.md)** — DAG primitives
  (CancelToken / RingBuffer / StreamEdge) user guide
- **[`plugins/PLUGIN_AUTHORING.md`](plugins/PLUGIN_AUTHORING.md)** —
  Third-party plugin packaging (static vs `dlopen`)
- **[`impl/lora_adapter_support.md`](impl/lora_adapter_support.md)**
  — LoRA implementation reference
- **[`migrations/VoiceSessionEvent.md`](migrations/VoiceSessionEvent.md)**
  — v2.x → v3.1 voice migration guide

## SDK API references

Refreshed for the branch's proto-stream voice API. Version examples
in the snippets predate the version reset and will be re-swept
when the branch ships.

- [`sdks/flutter-sdk.md`](sdks/flutter-sdk.md)
- [`sdks/kotlin-sdk.md`](sdks/kotlin-sdk.md)
- [`sdks/react-native-sdk.md`](sdks/react-native-sdk.md)

## Historical archive

[`archive/`](archive/) contains 30 historical evidence files from
the v2 close-out + v3.0.0 + v3.1.0 sprints. Cite-only; do not edit
in place. See [`archive/README.md`](archive/README.md) for the
layout.

## Spec set (active engineering targets)

[`../v2_gap_specs/`](../v2_gap_specs/) — the 11 GAP spec files that
the v2-v3.1 sprints close. `GAP_STATUS.md` mirrors their current
state.

## Doc maintenance

When state changes:
1. Edit `STATE_AND_ROADMAP.md` (current architecture / backlog).
2. Edit `GAP_STATUS.md` (per-GAP status flips).
3. Append to `HISTORY.md` (new sprint section).
4. Move per-phase records into `archive/<release>/` if they're
   substantial.
5. Do NOT edit files in `archive/` to reflect new state.
