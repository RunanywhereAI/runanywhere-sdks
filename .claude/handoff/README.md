# Claude handoff bundle

Everything needed to pick this work up on another machine. The rest of
`.claude/` is local session state and stays gitignored; this directory is
tracked on purpose (see the `.claude/*` plus `!.claude/handoff/` rules in
`.gitignore`).

## Restoring on a new machine

```bash
# 1. Personal memory. Path is derived from the repo location, so adjust if you
#    clone somewhere other than ~/Projects/runanywhere-sdks.
mkdir -p ~/.claude/projects/-Users-$(whoami)-Projects-runanywhere-sdks/memory
cp .claude/handoff/memory/*.md \
   ~/.claude/projects/-Users-$(whoami)-Projects-runanywhere-sdks/memory/

# 2. Global rules, which apply to every project, not just this one.
cp .claude/handoff/global-CLAUDE.md ~/.claude/CLAUDE.md

# 3. Plans. thoughts/ is gitignored, so these are the only copies that travel.
mkdir -p thoughts/shared/plans
cp .claude/handoff/plans/*.md thoughts/shared/plans/
```

## What is here

`memory/` holds the thirteen memory files plus `MEMORY.md`, the index loaded
each session. These encode working rules: no commit without approval, one-line
commit messages, no AI-slop comments, run the humanizer on prose, use the Edit
tool rather than sed, keep responses short.

`global-CLAUDE.md` is a copy of `~/.claude/CLAUDE.md`. Note that it is personal
and applies to all projects, and this repo is shared with the team, so anyone
with repo access can read it. Nothing in it is sensitive today.

`plans/` carries the three plan documents. `proto_and_sdk_noise_reduction.md`
is the live one and records what each phase did, which audit claims turned out
to be wrong, and the decisions still open.

`scripts/verify_dead_v2.sh` finds genuinely dead proto types. The first version
of this check asked only "does an SDK reference this symbol," which produced
false positives, because a type also stays alive when another `.proto`
references it as a field type or when commons produces it for telemetry that no
SDK reads. This version checks proto field types, oneof arms, map values,
native producers, and enum member usage.

Credentials are deliberately absent. `~/.claude/.credentials.json` is not
copied.

## State of the work

Phases 0 through 2 are complete and Phase 3 is partly done. Phase 3's D3, the
audio-encoding unification, has landed and is verified.

Nothing is committed. At last count 539 files were modified, 451 of them
generated, so the work only reaches another machine once it is committed and
pushed.

Two open PRs: `RunanywhereAI/runanywhere-sdks#605` and the marketing docs at
`RunanywhereAI/runanywhere-marketing#29`.

## macOS notes

The MacBook unblocks two things this Linux host could not do.

`protoc-gen-swift` installs there, so the Swift bindings can finally be
regenerated. They are currently stale against the IDL, and `idl-drift-check`
will keep failing until that runs. This is the single largest outstanding gap.

Xcode makes the Swift SDK buildable, so the Swift changes from Phase 0 (the
`ToolChoice.required` fix) and Phase 3 can be compiled rather than only
inspected.

Two things that needed working around here and should be rechecked on macOS.
The Kotlin proto bindings have no build-time regeneration: `build.gradle.kts`
carries the `wire.runtime` dependency but no Wire Gradle plugin, so the
committed Kotlin files come from the `wire-compiler` CLI. Both
`generate_kotlin.sh` and `setup-toolchain.sh` claim a Gradle plugin handles it,
which is false, and `setup-toolchain.sh` installs the CLI through Homebrew only.
Separately, libarchive turns `-Werror` on for Debug builds and its own sources
trip gcc 14, which broke `cmake --preset linux-debug`; the fix forces
`ENABLE_WERROR=OFF` before `FetchContent_MakeAvailable(libarchive)` in
`sdk/runanywhere-commons/CMakeLists.txt` and should be harmless on macOS.

`sdk/shared/proto-ts` publishes from `dist/`, so React Native and Web read
stale types until it is rebuilt. Run its build after any codegen.

The convenience generators under `idl/codegen/` (`generate_kotlin_convenience.py`
and siblings) are separate from `generate_all.sh` and must be run explicitly
after changing a `rac_default` or a referenced enum.

## Verification commands

```bash
cmake --preset linux-debug && cmake --build build/linux-debug   # macos-debug on Mac
ctest --test-dir build/linux-debug                              # 95/96; the auth
                                                                # segfault is a
                                                                # pre-existing
                                                                # Linux failure
cd sdk/runanywhere-kotlin && ./gradlew compileDebugKotlin testDebugUnitTest ktlintCheck
cd sdk/runanywhere-flutter/packages/runanywhere && dart analyze
cd sdk/runanywhere-web && npm run typecheck -w packages/core
cd sdk/runanywhere-electron && npm run build && npm test
cd sdk/runanywhere-python && python -m pytest -q
bash scripts/validation/gates/check_no_hardcoded_defaults.sh
```
