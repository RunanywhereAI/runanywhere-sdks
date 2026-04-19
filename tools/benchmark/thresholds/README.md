# Benchmark thresholds

Each JSON file in this directory is a ceiling — the benchmark output with
the matching stem (e.g. `voice_agent_latency.json` → threshold file
`voice_agent_latency.json`) is checked against these limits by
`tools/ci/check_thresholds.py` after every release build.

A PR that pushes any p-value past the stated ceiling by more than
`tolerance_pct` fails the `commons-bench` workflow.

## Schema

```json
{
  "name":            "<bench_name>",
  "description":     "<one-line purpose>",
  "metric":          "<metric_name in the bench output JSON>",
  "p50_ms":          <number>,
  "p90_ms":          <number>,
  "p99_ms":          <number>,
  "tolerance_pct":   <integer, default 10>
}
```

Bumping a ceiling requires a PR touching only the threshold file so the
regression is reviewed explicitly (not buried in a feature PR). The
`CODEOWNERS` entry for this directory is the perf-reviewers group.
