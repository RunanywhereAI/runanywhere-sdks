# AGENTS.md

`@runanywhere/proto-ts` — the shared TypeScript proto package consumed by the Web,
React Native, and Electron SDKs. `CLAUDE.md` is a symlink to this file.

This package has no product logic of its own: it is IDL codegen output (ts-proto
message types + generated convenience helpers + generated stream wrappers) plus a
handful of hand-written files that codegen deliberately does not touch. See the root
[`AGENTS.md`](../../AGENTS.md) for the cross-repo IDL/codegen contract (what's generated
vs. committed, the toolchain pins, `idl/VERSION`/`idl/SCHEMA_LOCK`) — this file only
covers what's specific to the TS output.

## Most of `src/` does not exist in a fresh clone

`git ls-files` on this directory returns exactly these 12 tracked files: `package.json`,
`package-lock.json`, `tsconfig.json`, `LICENSE`, `.gitignore`, and seven `.ts` files —
`src/index.ts`, `src/lifecycle_service.ts`, `src/convenience/_errors.ts`,
`src/convenience/errors_category.ts`, `src/events/public_events.ts`,
`src/streams/_streamFactory.ts`, `src/streams/push.ts`. Every other file you see under
`src/` right now (message types like `llm_service.ts`, generated `*_convenience.ts`
helpers, `defaults/pool.ts`, the generated `streams/*_service_stream.ts` wrappers) is
codegen output, gitignored by `../../.gitignore` (search `Shared TypeScript proto
package`), and present in this working copy only because codegen already ran here. On a
fresh clone `src/` has 7 files, not the 60+ generated files a checkout that's already run
codegen accumulates, and `dist/` (also gitignored, ~130-140 files) does not exist at all
until a build runs.

Regenerate everything with:

```bash
# From the repo root — requires protoc + ts-proto; see scripts/setup/setup-toolchain.sh
./idl/codegen/generate_all.sh --only ts
# or, the single call every packaging script actually makes (also builds dist/):
./idl/codegen/ensure_generated.sh --only ts --with-ts-dist
```

`idl/codegen/generate_ts.sh` (ts-proto, one `.ts` per `.proto`) and
`idl/codegen/generate_ts_convenience.py` (`defaults()`/`validate()`/`wireString` derived
from `rac_*` field-option annotations, see `idl/codegen/CONVENIENCE_CODEGEN_DESIGN.md`)
both write into `src/`; `idl/codegen/generate_streams.sh` writes `src/streams/*_service_stream.ts`.
Never hand-edit a file any of these three scripts own — the next codegen run silently
overwrites it. The 7 tracked files above are the *only* ones safe to hand-edit.

## Commands

```bash
npm run build       # tsc -> dist/ (the only thing the published npm package ships)
npm run typecheck   # tsc --noEmit
npm run clean       # rm -rf dist + remove stray .js/.d.ts that ended up under src/
```

There is no test script and no lint script in this package; verification is
`typecheck` plus whatever consumes the types downstream (Web/RN/Electron `typecheck`).

## Why `tsconfig.json` uses `node16`/`node16`, not `node`

`@bufbuild/protobuf` v2 ships an exports-map-only subpath
(`@bufbuild/protobuf/wire`) that ts-proto v2 output imports. The legacy `node` resolver
cannot read `package.json` "exports" and fails with `TS2307`. `node16` reads exports
maps; because this package has no `"type": "module"` (i.e. is CommonJS), it still emits
`require()`/`module.exports` and still accepts the extensionless relative imports
ts-proto generates — the ESM-only explicit-extension rule doesn't apply to CJS emit — so
`dist/` stays a drop-in for existing `require(...)` consumers. Don't "fix" this back to
`node`; it was deliberately changed away from it (see the comment block at the top of
`tsconfig.json`).

## `index.ts` is intentionally an empty barrel

```ts
export {};
```

Each generated ts-proto file defines helper types with identical names (`DeepPartial`,
`Exact`, `protobufPackage`), so a star-re-export barrel would create ambiguous bindings.
Consumers import by subpath instead, e.g. `@runanywhere/proto-ts/llm_service`,
`@runanywhere/proto-ts/convenience/errors_category`,
`@runanywhere/proto-ts/streams/push`. `package.json` `exports` declares one wildcard
subpath per top-level directory (root, `convenience/*`, `events/*`, `streams/*`, plus
bare `dist/*` for anything not covered) — do not add a new subpath category without
adding the matching `exports` entry, or `moduleResolution: node16` consumers get `TS2307`.

## The hand-written files, and why codegen skips each one

| File | Why it's hand-written |
|---|---|
| `convenience/_errors.ts` | Defines `ValidationError`, the typed exception the *generated* `validate<Msg>()` helpers throw. Its shape (`code`/`category`/`fieldPath`/`message`) is byte-isomorphic with the proto-backed `SDKException` Swift/Kotlin/Dart throw — see `idl/codegen/CONVENIENCE_CODEGEN_DESIGN.md §9.1`. |
| `convenience/errors_category.ts` | The `ErrorCode` → `ErrorCategory` numeric-range table. The fold exists only as C++ control flow (`rac::foundation::rac_result_to_proto_category` in `core/src/foundation/rac_proto_adapters.cpp`), not as proto annotations, so there is nothing for codegen to read. This TS table intentionally covers more ranges (up to 999) than commons currently maps (100–329, falls through to INTERNAL) — do not "fix" it down to match commons; that's a known, deliberately deferred commons gap. |
| `events/public_events.ts` | The v4 public streaming-event discriminated unions (`GenerationEvent`, `TranscriptionEvent`, `VoiceEvent`, `DownloadEvent`, etc.) shared by Web/RN/Electron. Payload slots are generic type parameters so each SDK binds its own local result/match/segment types without forking the discriminant arms. Deprecated RN-only arms live in separate `*WithDeprecated` aliases — new SDKs must not re-export those. |
| `streams/_streamFactory.ts` | `streamFactory<TReq,TRsp>()`: adapts a subscribe-based transport into a lazy `AsyncIterable`. Generated `streams/*_service_stream.ts` wrappers import this; `idl/codegen/generate_streams.sh` only ever writes the `*_service_stream.ts` files, never this one. |
| `streams/push.ts` | Push→`AsyncIterable` adapters (`pushStream`, `iterableFromSubscription`, `mapStream`, `deferStream`, `forEachStream`, `AsyncQueue`, ...) used across Web/RN/Electron. Three constraints are load-bearing and apply to any addition here: lazy start (producer runs on first `next()`, not construction); cancel-on-`return()`; and Electron `contextBridge`-safety — iterators must be plain object literals with `next`/`return`/`throw`/`Symbol.asyncIterator` as **own** properties, because `contextBridge` strips prototype methods (`AsyncQueue`'s `[Symbol.asyncIterator]` is a class field for the same reason). Also Hermes-safe: nothing here requires `for await...of` (RN/Hermes can't do that over a Nitro-backed iterable — consumers use `forEachStream`/manual `iterator.next()` loops instead). |
| `lifecycle_service.ts` | Currently just declares `protobufPackage` — `lifecycle_service.proto` has no message types, so ts-proto would otherwise emit nothing for it and downstream imports would 404. |
| `index.ts` | The empty barrel, see above. |

## Consumption pattern

Nothing imports this package as a dependency during monorepo development — Web and RN
resolve it as a **sibling npm/yarn workspace member** (`workspace:*` / relative sibling
path), and each of their `package-sdk.sh` scripts runs `npm pack ../proto-ts` to vendor
a real tarball into their own published package (search `package-sdk.sh` for
`proto-ts` in `bindings/web/`, `bindings/react-native/`, `bindings/electron/` for the
exact bundling mechanics — that's packaging-pipeline detail, not authoring detail, and
belongs to those SDKs' own AGENTS.md files, not here). The practical implication for
this package: **its `dist/` must be built before those three SDKs' packaging scripts
run**, since a stale or empty `dist/` there packs into all three silently.
