# Generated code contract

Linked from `AGENTS.md`. Read this before touching `idl/*.proto` or debugging a build that
can't find generated types.

## Nothing generated is tracked

A fresh clone has no C++, Kotlin, Swift, TypeScript, Dart, React Native or Python bindings
until codegen runs. `./scripts/setup/setup.sh` runs it first for exactly that reason;
`./run codegen` runs it on demand. The hooks below mean almost nobody has to know that.

| tree | who generates it | when |
|---|---|---|
| `core/src/generated/proto/` (76 files, ~336k lines) | `core/CMakeLists.txt`, at **configure** time when the files are absent | every `cmake --preset …`, i.e. all ~29 native CI runner instances, the Electron addon, the Python wheel, the C++ desktop kit, and WASM |
| `core/include/rac/rac_defaults_generated.h` | same block | same. A SHIPPED public header: `install(DIRECTORY include/)` puts it in the XCFramework `Headers/` and the Linux/Windows dist, and five shipped `rac_{llm,stt,tts,vad,vlm}_types.h` `#include` it — so it must exist before packaging, which configure time guarantees |
| `bindings/kotlin/.../sdk/generated/` (373 files) | the `generateIdlKotlinBindings` Gradle task, wired into `preBuild` | every `assemble*` / `compile*Kotlin` / `test*` / ktlint / detekt, including JitPack |
| `bindings/swift/Sources/RunAnywhere/Generated/` | `sync-dist-repo.sh` | ships in the SwiftPM tag |
| `bindings/proto-ts/src/` and `dist/` | each `package-sdk.sh` | `dist` ships in 7 npm packages |
| `bindings/flutter/packages/runanywhere/lib/generated/` | `bindings/flutter/scripts/package-sdk.sh` | ships in the pub package |
| the two `RADefaultsPool.kt` under flutter/ and react-native/ | the same packaging scripts | ship inside the pub / npm packages |
| `bindings/python/runanywhere/_proto/`, `_generated_{errors,defaults}.py` | the in-tree PEP 517 backend | ship in the sdist + wheel |

One CI job reads generated C/C++ **without** configuring CMake and therefore carries an
explicit `generate-idl` step with `cpp`: `pr-build.rn-typecheck` (`-fsyntax-only` over
`core/include`).

`idl/codegen/generated_trees.txt` is the machine-readable version of that table, plus
the eight hand-written files that live *inside* those trees and stay tracked (the
`.gitignore` negations exist for them, and `check_generated_trees.sh` fails if one
ever stops being tracked — and fails the other way if a generated file becomes tracked).

## The toolchain is downloaded, not assumed

protoc stamps its own patch version into every C++ header (`#if PROTOBUF_VERSION !=
7035001`) and every ts-proto banner, and Wire renames files between releases, so the
output is a function of the tool versions and not only of the schemas. The package
managers this repo would otherwise reach for do not offer that guarantee —
`brew install protobuf` gives whatever is current, `apt-get install protobuf-compiler`
gives whatever the distro froze, neither selects a per-platform archive by checksum, and
Homebrew's `wire` is a different product entirely. protobuf and Maven Central both
publish immutable per-platform archives, so the pins are *obtainable*:

| script | resolves | pinned by | verified against |
|---|---|---|---|
| `idl/codegen/bootstrap_protoc.sh` | protoc | `core/VERSIONS::PROTOC_VERSION` | `idl/codegen/protoc.sha256` |
| `idl/codegen/bootstrap_wire.sh` | wire-compiler | `core/VERSIONS::WIRE_VERSION` | `idl/codegen/wire.sha256` |
| `idl/codegen/bootstrap_pyproto.sh` | a python3 with `google.protobuf` + `yaml` | `core/VERSIONS::PYTHON_PROTOBUF_VERSION` | pip, into a cached venv |

Each prints one path on stdout, uses a matching tool already on `PATH` when there is one,
caches under `${XDG_CACHE_HOME:-~/.cache}/runanywhere/`, and refuses to install anything
whose checksum is not recorded — so bumping a pin without refreshing the `.sha256` file is
a hard error rather than an unverified download. `RAC_PROTOC` / `RAC_WIRE_COMPILER` /
`RAC_PYTHON` override; `RAC_PROTOC_NO_DOWNLOAD=1`, `RAC_WIRE_NO_DOWNLOAD=1` and
`RAC_PY_NO_INSTALL=1` make an air-gapped host fail loudly instead of reaching out.

## Every publish path generates before packaging

A de-committed tree that ships inside an artifact must exist at pack time or the
published package is broken in a way that no build step notices — `npm pack` packs an
empty `dist/`, `flutter pub publish --dry-run` validates a package with no
`lib/generated/`, and a Python wheel installs fine and fails at `import`. So each
packaging script calls `idl/codegen/ensure_generated.sh --only <lang>` first, and the
Python SDK carries an in-tree PEP 517 backend (`bindings/python/_build/`) so even a bare
`pip install` cannot skip it.

## Schema version

`idl/VERSION` is hand-maintained semver for the `.proto` surface; `idl/SCHEMA_LOCK` is
machine-written by `generate_all.sh` and records a digest of every `idl/*.proto`. Because
it is tracked and the bindings are not, the lock is the drift signal: editing a schema
without re-running codegen leaves it stale, and CI fails. Changing the schema without
bumping `idl/VERSION` also fails.

```bash
./idl/codegen/schema_lock.sh --print   # which IDL is this checkout?
./idl/codegen/ci-drift-check.sh        # the whole gate, exactly as CI runs it
```

CI `idl-drift-check.yml` is **generate, then verify** — not "regenerate and diff", which
cannot fail for an ignored file.

## Downstream kits (RCLI)

The C++ desktop kit (`package-cpp-desktop`) is how a second repo stays on this
schema without running `protoc`:

1. `idl/*.proto` is the only schema.
2. Commons compiles it **once**; `.pb.cc` lives inside `librac_commons.a`.
3. The kit ships the matching `include/runanywhere/proto/*.pb.h`, vendored
   protobuf/absl headers, and a copy of `idl/SCHEMA_LOCK`.
4. RCLI `find_package(RunAnywhere)` consumes those headers and pins
   `IDL_SCHEMA_SHA256` in `cmake/sdk-pin.cmake`. A kit whose lock does not
   match is a configure error.

Do not add a second codegen path in RCLI. When the schema moves, cut a new
SDK kit and bump the RCLI pin.
