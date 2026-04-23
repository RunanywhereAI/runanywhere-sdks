# archive/

_Historical engineering evidence. Cite-only — these documents are
NOT updated when state changes._

## Why these exist

These are point-in-time records (sprint commit lists, per-phase LOC
tables, audit findings, three-agent verification runs). They preserve
the evidence trail for compliance / archaeology but are NOT the place
to read for "current state".

For current state, see:
- [`../STATE_AND_ROADMAP.md`](../STATE_AND_ROADMAP.md) — single canonical
  state + forward-looking roadmap
- [`../GAP_STATUS.md`](../GAP_STATUS.md) — rolling 11-GAP scoreboard
- [`../HISTORY.md`](../HISTORY.md) — chronological narrative with
  pointers back into this archive

## Layout

```
archive/
├── gap-reports/      ← 11 per-GAP final gate reports (one per GAP)
├── v2-closeout/      ← v2 close-out per-phase records (April 2026)
└── v3-evidence/      ← v3.0.0 + v3.1.0 sprint deliverables
```

### `gap-reports/`

One file per GAP (`gap01` through `gap11`). Each was the closure
artifact for that GAP at the time it shipped. `GAP_STATUS.md` rolls
all 11 into a single scoreboard; the per-file detail is here for
audit citations (specific commit SHAs, per-criterion test logs,
LOC delta tables).

`gap08_kotlin_orphan_natives.md` is an appendix to `gap08` —
documents the JNI orphan-native cleanup methodology.

### `v2-closeout/`

Records from the v2 close-out sprint (early April 2026):

- `v2_closeout_baseline.md` — Phase 0 baseline LOC + spec targets
- `v2_closeout_build_log.md` — Phase 1 GREEN build verification
- `v2_closeout_phase5_cabis.md` — Phase 5 `rac_llm_thinking` C ABI
- `v2_closeout_device_verification.md` — Phase 15 device QA plan
- `v2_closeout_results.md` — Phase 16 final LOC delta + Phase A-D
- `v2_migration_complete.md` — early "ready to ship" summary
- `v2_remaining_work.md` — pre-v3 backlog (now superseded)
- `wave_roadmap.md` — original three-agent audit snapshot
- `voice_event_proto_handoff.md` — GAP 01 → GAP 09 contract handoff
- `gap11_audit_repoint.md` — pre-v3 audit (88 hits / 30 files)

### `v3-evidence/`

Records from the v3.0.0 cut-over + v3.1.0 sprint:

- `v3_phaseB_complete.md` — v3.0.0 Phase B commit ledger
- `v3_phaseB_gate_analysis.md` — the "why we needed `create_impl`"
  decision record (kept for design-rationale citations)
- `v3_audit_summary.md` — v3.0.0 post-release audit
- `v2_current_state.md` — pre-consolidation rolling state doc
  (replaced by top-level `STATE_AND_ROADMAP.md`)
- `v3_1_release_summary.md` — v3.1.0 sprint retrospective
- `v3_1_cmake_normalization.md` — Phase 6 audit + per-engine
  migration paths (post-v3.1 work)
- `v3_1_flutter_split_analysis.md` — Phase 7 Dart language analysis
- `v3_1_kotlin_loc_audit.md` — Phase 8 LOC audit + GAP 08 status
- `v3_1_rn_deprecation_decisions.md` — Phase 1.5 RN deprecation
  decisions

## Policy

- **Don't edit** these files in place to reflect new state. Edit
  the canonical docs (`STATE_AND_ROADMAP.md` / `GAP_STATUS.md` /
  `HISTORY.md`) instead.
- **Do** add new sprint records under `v3-evidence/` (or a future
  `v4-evidence/`) when a sprint ships, then update the canonical
  docs to point at the new evidence.
- **Move** files here when their content is fully subsumed by the
  canonical docs.
