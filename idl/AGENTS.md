# AGENTS.md — idl/

> `AGENTS.md` is the real file; `CLAUDE.md` beside it is a committed symlink. See the root
> `AGENTS.md` for the repo-wide conventions and architecture — this file covers only what's
> additional to working inside `idl/` itself.

39 `.proto` files (package `runanywhere.v1`) are the single schema root for every
cross-platform type in this monorepo: model/error/event/option types, LLM/VLM/STT/TTS/VAD
configs, and the SDK event catalog. `idl/codegen/` renders them into Swift, Kotlin (Wire),
TypeScript (ts-proto), Dart, C++, and Python. **Read
[`docs/reference/generated-code-contract.md`](../docs/reference/generated-code-contract.md)
first** — it covers what each script generates, where it lands, the pinned-toolchain
bootstrap scripts, and the `idl/VERSION` / `idl/SCHEMA_LOCK` drift gate. This file does not
repeat that; it only covers proto-authoring conventions and what's inside `codegen/` beyond
`generate_all.sh`.

## Adding or editing a `.proto`

1. New file → copy the option-block boilerplate from an existing file (e.g.
   `pipeline.proto`): `syntax = "proto3"`, `package runanywhere.v1`, then
   `cc_enable_arenas`, `java_multiple_files`, `java_package
   ai.runanywhere.proto.v1`, `java_outer_classname`, `objc_class_prefix RAV1`,
   `csharp_namespace Runanywhere.V1`, `swift_prefix RA`, `go_package
   .../idl/v1;runanywherev1`. Every generator relies on all eight being present and
   consistent — a file missing one silently gets default (wrong) names in that language.
2. Edit the message/enum, bump `idl/VERSION` (hand-maintained semver for the schema
   surface: patch = comments/docs only, minor = additive field/message/enum value, major =
   wire-breaking), then run `./idl/codegen/generate_all.sh` — it rewrites `SCHEMA_LOCK` for
   you. `schema_lock.sh --check --require-bump <base-lock>` is what enforces the
   patch/minor/major distinction in CI.
3. Never renumber or reuse a field number on a message that's either wire-stable or
   persisted. Concretely: `model_types.proto`'s `ModelInfo` subgraph is serialized to
   `.rac-manifest.binpb` on disk, so its `reserved` blocks are load-bearing, not decoration
   — removing a field there requires adding it to `reserved`, never deleting the number
   outright. `sdk_events.proto` states the same rule for the whole file: field numbers,
   message names, and enum values are wire-stable; only comments/grouping may change.
   `errors.proto`'s numeric values must match `core/include/rac/core/rac_error.h` exactly —
   changing an existing value is a wire break, adding a new one is safe.
4. `tool_calling.proto` is the only file with a `service` block (`ToolCalling`). It's a
   *logical* contract only — parsing/prompt-formatting/validation shapes — not a wire RPC:
   no gRPC transport runs anywhere in this repo (superseded by the in-process C callback
   path; see root `AGENTS.md`), so adding a `service` elsewhere would generate stub code
   nothing calls.

### `rac_options.proto` — custom field annotations

Nine `FieldOptions`/`EnumValueOptions` extensions in the 50000–99999 org-private range
(`rac_default`, `rac_required`, `rac_min`/`rac_max`, `rac_min_float`/`rac_max_float`,
`rac_display_name`, `rac_analytics_key`, `rac_wire_string`). These aren't consumed by
protoc directly — `codegen/generate_{swift,kotlin,dart,ts}_convenience.py` post-process the
descriptor set and emit `defaults()` / `validate()` / `displayName` / `wireString`
accessors per language, replacing what used to be hand-written per-SDK helpers (see
[`codegen/CONVENIENCE_CODEGEN_DESIGN.md`](codegen/CONVENIENCE_CODEGEN_DESIGN.md) for the
full design and per-language output shape). `validate()` is generated but never
auto-invoked — callers opt in explicitly, and commons enforces its own bounds
independently, so don't treat annotation coverage as the only validation layer.

### `buf.yaml`

Configures `buf lint` (STANDARD ruleset, minus `PACKAGE_VERSION_SUFFIX` and
`PACKAGE_DIRECTORY_MATCH` — this repo doesn't version-suffix packages or mirror the
`runanywhere.v1` package into a matching directory tree) and `buf breaking` (WIRE category,
minus `EXTENSION_NO_DELETE` and `FIELD_SAME_DEFAULT`). Not wired into any CI workflow —
schema-compatibility enforcement here is `SCHEMA_LOCK` + the drift check, not `buf`. Run it
by hand when unsure whether an edit is wire-breaking:

```bash
buf lint idl
buf breaking idl --against '.git#branch=main,subdir=idl'
```

## `codegen/` beyond `generate_all.sh`

Everything `docs/reference/generated-code-contract.md` doesn't already cover:

- **Convenience generators** (`generate_{swift,kotlin,dart,ts}_convenience.py`) — see
  above. `codegen/tests/test_convenience_generators.py` is their regression suite: a
  fixture proto (`codegen/tests/fixtures/test_options.proto`) exercises every `rac_*`
  annotation × scalar type combination and diffs each generator's output against a
  committed golden file (`codegen/tests/golden/`). Run
  `python3 idl/codegen/tests/test_convenience_generators.py` locally (add
  `--update-golden` after changing a generator or the fixture); it's wired into
  `idl-drift-check.yml` as a step that runs before the drift check. See
  [`codegen/tests/README.md`](codegen/tests/README.md) for exit codes and the manual
  (Python-harness-unavailable) fallback procedure.
- **`swift-modality-abi.yaml`** — a manifest (not a proto) that drives
  `generate_swift_modality_abi.py`, which renders `CppBridge+ModalityProtoABI.swift`: the
  dlsym table mapping each `rac_*` C symbol to its request/response proto types and call
  kind (`invoke`, `stream`, `getWithContext`, …). Edit the YAML, not the generated Swift,
  when a modality gains or changes a C entry point; the file's own header comments
  document each `kind` value's wire shape in detail.
- **`generate_cpp_defaults.py`** / **`generate_defaults_pool.py`** — cross-cutting
  post-processors that run once per `generate_all.sh` invocation regardless of `--only`:
  the first emits the shipped public header `rac_defaults_generated.h`, the second emits
  the `RADefaultsPool` default-value constants for all seven per-language targets in one
  pass (so its output is identical no matter which `--only` subset triggered it).
- **`templates/ts_async_iterable.njk`** — the Nunjucks template `generate_streams.sh` uses
  to render the shared TypeScript `AsyncIterable` stream wrapper for every
  server-streaming RPC shape, consumed by both the React Native and Web SDKs via
  `@runanywhere/proto-ts`.
