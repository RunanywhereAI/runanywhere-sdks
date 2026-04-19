# Decision 08 — Scope boundary

## Question

What's in scope for this plan, and what's explicitly out?

## Choice

**In scope (one plan, one execution window).**

- `sdk/runanywhere-commons/` — the C++ core (Phases 0–8).
- `sdk/runanywhere-swift/` — Swift SDK (Phase 9).
- `sdk/runanywhere-kotlin/` — Kotlin KMP SDK (Phase 10).
- `sdk/runanywhere-flutter/` — Flutter SDK (Phase 11).
- `sdk/runanywhere-react-native/` — React Native SDK (Phase 12).
- `sdk/runanywhere-web/` — Web SDK (Phase 13).
- `examples/ios/`, `examples/android/`, `examples/flutter/`,
  `examples/react-native/`, `examples/web/`,
  `examples/intellij-plugin-demo/` — rewritten alongside their
  corresponding SDK phase.
- Top-level CI, scripts, pre-commit, release pipelines, migration
  guide, root README (Phase 14).
- Absorption of any residual `sdk/runanywhere-android/` behaviour
  into the Kotlin KMP SDK — KMP becomes the single Kotlin track
  covering JVM + Android.

**Out of scope.**

- External consumers outside this monorepo — confirmed none exist,
  so breaking the C ABI is free.
- Any brand-new primitive (e.g. speaker-diarization as a first-class
  streaming operator). This refactor reshapes existing functionality;
  new primitives follow the same pattern in a separate plan.
- `examples/intellij-plugin-demo/` user-facing feature work beyond
  porting to the new Kotlin SDK.

## Reasoning

Earlier draft of this decision staged the frontends into a follow-up
plan. User directive: "it should include the actual implementation
update in all five SDKs who were dependent on the commons at the
same time."

A commons-only plan leaves a long, uncomfortable window where every
SDK pins to an older commons tag while we ship a new one; downstream
teams diverge; the eventual migration is bigger because the commons
has accumulated more drift. Rolling frontends in with commons keeps
the repo in a consistent, shippable state at each phase boundary.

## Ordering rule

The **commons track (Phases 0–8) finishes before the frontend track
(Phases 9–14) starts.** That rule is non-negotiable:

- Commons has sanitizer + benchmark gates that prove the new
  architecture is correct in isolation (Phase 6).
- Every frontend consumes the commons C ABI. If we're still
  reshaping commons while frontends migrate, every frontend PR fights
  a moving target.
- Within the frontend track, phases are ordered but not strictly
  blocking — Swift (9) unblocks RN iOS; Kotlin (10) unblocks RN
  Android; a motivated team could partially parallelise.

The release (Phase 14) is strictly last: it's where all six artifacts
publish their `v2.0.0` tags together.

## Alternatives considered

| Option | Why rejected |
| --- | --- |
| Commons-only now, frontends in a follow-up plan | Long window of API drift; per the user's directive |
| All tracks in parallel from day one | Frontends would chase a moving commons API; rework cost very high |
| Commons + one frontend only | Picks a winner arbitrarily; other SDKs still break |

## Implications

- **15 phase documents** total (0 through 14).
- Frontend SDK phases can tag individual `rc.*` releases of commons
  if the team wants staggered cuts, but the final v2.0.0 is one
  coordinated release.
- Example apps ship with their SDK phase. No separate "examples
  plan" to forget.
- The monorepo is never half-migrated on `main` because each phase
  leaves the repo green before the next starts.
- Top-level infra (CI, pre-commit, scripts, VERSIONS) settles in
  Phase 14 after every SDK has migrated.

## Explicit non-commitments

Once Phase 14 publishes `v2.0.0` this plan is done. Subsequent work
(new primitives, platform features, optimisations) goes through the
normal feature-development flow, not a multi-phase plan.
