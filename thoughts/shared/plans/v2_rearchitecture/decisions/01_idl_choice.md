# Decision 01 — IDL for the C ABI wire format

## Question

What serialisation format do we use on the C ABI between commons and
the SDK frontends (Swift, Kotlin, Dart, TS, Web)?

## Choice

**proto3**, using `libprotobuf-lite` inside commons.

## Alternatives considered

| Option | Pros | Cons |
| --- | --- | --- |
| proto3 lite | mature, every target language has a mature runtime, forward-compatible by design | +~300 KB of lite runtime per linked binary |
| FlatBuffers | zero-copy reads, smaller runtime | codegen is less polished on Swift; community runtime lags on features |
| Cap'n Proto | zero-copy, excellent perf | almost no Swift/Dart story; small community |
| Hand-written C structs | no dependency | the reason we're doing this refactor — type drift, rigid ABI |
| Avro / MessagePack | compact | no schema evolution without a wrapper, less tooling per language |

## Reasoning

We touch **five** frontend language runtimes. proto3 is the only IDL
where all five have a first-class, well-maintained runtime: Swift via
`swift-protobuf`, Kotlin via Wire or `protobuf-kotlin`, Dart via
`protobuf`, TypeScript via `protobuf-ts`, Python (for server tests) via
`protobuf`. No alternative comes close on this axis.

The ~300 KB lite runtime is acceptable for every target except possibly
a maximum-minimal WASM build; we can revisit only if bundle size ever
becomes a hard constraint for the web SDK.

proto3's forward compatibility (unknown fields round-trip) means an
older frontend against a newer commons, or vice versa, doesn't break —
critical as the frontend migration is staged across a long window.

## Implications

- `sdk/runanywhere-commons/idl/` holds the schemas; codegen in
  `build/gen/ra/idl/*.pb.{h,cc}` via `cmake/Protobuf.cmake`.
- Frontend plans will each add their own language-specific codegen
  invocation.
- Phase 5 is the load-bearing phase for this choice.
