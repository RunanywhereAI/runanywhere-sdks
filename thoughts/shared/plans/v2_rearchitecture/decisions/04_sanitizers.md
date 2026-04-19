# Decision 04 — Sanitizers

## Question

Which sanitizers run in CI, and how are they staged?

## Choice

- **ASan + UBSan** in the default Debug build. Both on, both green.
- **TSan** in a dedicated Debug+TSan job. Separate build tree.
- **MSan** not adopted. Out of scope.

## Alternatives considered

| Option | Why rejected |
| --- | --- |
| Release-only CI, no sanitizers | leaks + UB ship to prod; unacceptable |
| All sanitizers in one build | TSan is exclusive with ASan; linker errors if combined |
| MSan on everything | requires rebuilding every transitive dep (protobuf, sherpa-onnx, llama.cpp, USearch) with MSan instrumentation; very high cost, incremental value over ASan |
| Valgrind | too slow for the test matrix; ASan catches 95% of what Valgrind would |

## Reasoning

ASan + UBSan catch the bugs that matter for a C++ library running on
mobile: heap-use-after-free, stack-use-after-return, signed overflow,
nullability, alignment. Both are cheap to enable and live nicely
together.

TSan is orthogonal — it finds real data races the graph scheduler and
barge-in boundary would otherwise hide. It demands its own build
because it can't co-exist with ASan: they each instrument memory
accesses in incompatible ways and the TSan shadow memory layout
conflicts with ASan's redzone scheme.

Covered suppressions live in `tools/ci/sanitizer-suppressions/` and
are versioned. Any new suppression requires a PR comment citing why
the race/leak is in a dep we can't fix.

## Implications

- `cmake/Sanitizers.cmake` exposes `RA_ENABLE_ASAN`,
  `RA_ENABLE_UBSAN`, `RA_ENABLE_TSAN` options.
- `ra_apply_sanitizers()` CMake function errors out if TSan is
  combined with either ASan or UBSan.
- Two GitHub workflow jobs (`commons-sanitizers-asan-ubsan`,
  `commons-sanitizers-tsan`) both required for merge.
- Phase 6 is the load-bearing phase.
