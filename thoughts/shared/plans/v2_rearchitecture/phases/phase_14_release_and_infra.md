# Phase 14 — Cross-SDK release + repo infrastructure finalisation

> Goal: now that commons + all five SDK frontends + all example apps
> are on the new architecture, tidy up the cross-repo infrastructure.
> Coordinated version bump, release pipelines, root CI, top-level
> scripts, repo README. The last phase. After this the v2
> rearchitecture is done.

---

## Prerequisites

- Phases 0–13 merged to `main`. Every SDK + every example app
  builds against the same commons tag.
- All per-SDK CI workflows green.

---

## What this phase delivers

1. **Synchronized release**. All six artifacts tagged together:
   - `commons-v2.0.0`
   - `runanywhere-swift-v2.0.0` (SPM)
   - `runanywhere-kotlin-v2.0.0` (Maven Central + Maven Local)
   - `runanywhere-flutter-v2.0.0` (pub.dev)
   - `@runanywhere/react-native@2.0.0` (npm)
   - `@runanywhere/web@2.0.0` (npm)

2. **Top-level CI consolidation** — one workflow file per
   artifact, path-filtered, running on PRs. One "release" workflow
   that takes a git tag and publishes all six.

3. **Pre-commit hooks** updated to cover every SDK language's
   linter in one go. Root `.pre-commit-config.yaml`.

4. **Top-level README rewritten** with the new architecture
   explanation, links to each SDK, quickstarts.

5. **Migration guide** — a single doc describing how to migrate
   from v1 to v2 for each SDK language.

6. **Versioning policy** written down: semver per artifact;
   commons bump triggers a frontend bump; a frontend-only fix can
   ship without a commons bump.

7. **Examples runnable from root** via a top-level `scripts/`
   entrypoint.

---

## Exact file-level deliverables

### Top-level layout after this phase

```text
runanywhere-sdks/
├── README.md                              REWRITE
├── ARCHITECTURE.md                        NEW — high-level arch doc, links to commons/ARCHITECTURE.md
├── MIGRATION_V1_TO_V2.md                  NEW
├── CHANGELOG.md                           UPDATED
├── VERSIONS                               NEW — single source for all 6 version numbers
├── sdk/
│   ├── runanywhere-commons/               (Phases 0-8)
│   ├── runanywhere-swift/                 (Phase 9)
│   ├── runanywhere-kotlin/                (Phase 10)
│   ├── runanywhere-flutter/               (Phase 11)
│   ├── runanywhere-react-native/          (Phase 12)
│   └── runanywhere-web/                   (Phase 13)
├── examples/
│   ├── ios/                               (Phase 9)
│   ├── android/                           (Phase 10)
│   ├── intellij-plugin-demo/              (Phase 10)
│   ├── flutter/                           (Phase 11)
│   ├── react-native/                      (Phase 12)
│   └── web/                               (Phase 13)
├── scripts/
│   ├── build-all.sh                       NEW — builds every SDK + example
│   ├── test-all.sh                        NEW — runs every per-SDK test suite
│   ├── release.sh                         NEW — tags + publishes
│   ├── bump-versions.sh                   NEW — bumps the VERSIONS file and propagates
│   └── verify-versions.sh                 NEW — asserts every SDK's version matches VERSIONS
├── tools/
│   ├── ci/                                shared CI helpers
│   └── perf-dashboard/                    optional benchmark aggregator
├── .github/
│   └── workflows/
│       ├── commons-sanitizers.yml         (Phase 6)
│       ├── commons-bench.yml              (Phase 6)
│       ├── ios-sdk.yml                    UPDATED
│       ├── ios-app.yml                    UPDATED
│       ├── android-sdk.yml                UPDATED
│       ├── android-app.yml                UPDATED
│       ├── flutter-sdk.yml                NEW
│       ├── flutter-app.yml                NEW
│       ├── rn-sdk.yml                     NEW
│       ├── rn-app.yml                     NEW
│       ├── web-sdk.yml                    UPDATED
│       ├── web-app.yml                    NEW
│       ├── release.yml                    NEW — tag-triggered; publishes all six
│       ├── pr-gates.yml                   NEW — meta-job that gates merge on all relevant per-SDK jobs
│       └── codeql.yml                     existing; unchanged
├── .pre-commit-config.yaml                UPDATED
└── .gitattributes / .gitignore            cleaned up
```

### `VERSIONS` file

```
commons            = 2.0.0
runanywhere-swift  = 2.0.0
runanywhere-kotlin = 2.0.0
runanywhere-flutter = 2.0.0
runanywhere-rn     = 2.0.0
runanywhere-web    = 2.0.0
```

Each SDK's own `package.json` / `build.gradle.kts` / `Package.swift`
/ `pubspec.yaml` is the source of truth for what version shipped, but
`VERSIONS` is the canonical coordinating number. `verify-versions.sh`
checks them all match before `release.sh` proceeds.

### `release.yml` (the one-click release)

```yaml
name: release

on:
  push:
    tags: ['v*']

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Verify versions match tag
        run: ./scripts/verify-versions.sh --tag ${{ github.ref_name }}

  commons:
    needs: validate
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build XCFramework
        run: sdk/runanywhere-swift/scripts/build-xcframework.sh
      - name: Upload release asset
        uses: softprops/action-gh-release@v2
        with:
          files: sdk/runanywhere-swift/Artifacts/RACCommonsStatic.xcframework.zip

  swift:
    needs: commons
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Tag + publish Swift Package
        run: ./sdk/runanywhere-swift/scripts/release.sh

  kotlin:
    needs: commons
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Publish to Maven Central
        run: ./sdk/runanywhere-kotlin/scripts/release.sh
        env:
          MAVEN_CENTRAL_USER:  ${{ secrets.MAVEN_CENTRAL_USER }}
          MAVEN_CENTRAL_TOKEN: ${{ secrets.MAVEN_CENTRAL_TOKEN }}

  flutter:
    needs: kotlin
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./sdk/runanywhere-flutter/scripts/release.sh
        env:
          PUB_CREDENTIALS: ${{ secrets.PUB_CREDENTIALS }}

  rn:
    needs: [swift, kotlin]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./sdk/runanywhere-react-native/scripts/release.sh
        env:
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}

  web:
    needs: commons
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./sdk/runanywhere-web/scripts/release.sh
        env:
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

### `pr-gates.yml` (merge gate)

```yaml
name: pr-gates
on:
  pull_request:
    branches: [main]

jobs:
  gate:
    runs-on: ubuntu-latest
    needs:
      - commons-sanitizers
      - commons-bench
      - ios-sdk
      - android-sdk
      - flutter-sdk
      - rn-sdk
      - web-sdk
    steps:
      - run: echo "All downstream gates green"
```

The per-SDK workflows are path-filtered so only the relevant ones
actually run on a given PR; `gate` depends on all of them but each
returns success fast if it didn't run.

### Top-level scripts

`scripts/build-all.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
./sdk/runanywhere-commons/scripts/build.sh          --preset commons-release-bench
./sdk/runanywhere-swift/scripts/build-xcframework.sh
(cd sdk/runanywhere-kotlin && ./scripts/sdk.sh build-all)
(cd sdk/runanywhere-flutter && melos bootstrap && melos run build)
(cd sdk/runanywhere-react-native && yarn && yarn build)
(cd sdk/runanywhere-web && ./scripts/build-web.sh --setup)
```

`scripts/test-all.sh` — mirror for tests.

`scripts/bump-versions.sh` — reads a target version from argv,
updates `VERSIONS`, then rewrites every per-SDK manifest file.

`scripts/verify-versions.sh` — reads each manifest, asserts agreement
with `VERSIONS`.

### `.pre-commit-config.yaml`

```yaml
repos:
  - repo: local
    hooks:
      - id: commons-clang-format
        name: commons-clang-format
        files: 'sdk/runanywhere-commons/.*\.(cpp|h|hpp)$'
        language: system
        entry: clang-format -i
      - id: ios-sdk-swiftlint
        name: ios-sdk-swiftlint
        files: 'sdk/runanywhere-swift/.*\.swift$'
        language: system
        entry: swiftlint --fix --quiet
      - id: kotlin-sdk-detekt
        name: kotlin-sdk-detekt
        files: 'sdk/runanywhere-kotlin/.*\.kt$'
        language: system
        entry: (cd sdk/runanywhere-kotlin && ./gradlew detekt)
      - id: flutter-sdk-analyze
        name: flutter-sdk-analyze
        files: 'sdk/runanywhere-flutter/.*\.dart$'
        language: system
        entry: (cd sdk/runanywhere-flutter && melos run analyze)
      - id: rn-sdk-eslint
        name: rn-sdk-eslint
        files: 'sdk/runanywhere-react-native/.*\.(ts|tsx)$'
        language: system
        entry: (cd sdk/runanywhere-react-native && yarn lint --fix)
      - id: web-sdk-eslint
        name: web-sdk-eslint
        files: 'sdk/runanywhere-web/.*\.(ts|tsx)$'
        language: system
        entry: (cd sdk/runanywhere-web && npm run lint --silent -- --fix)
      - id: verify-versions
        name: verify-versions
        files: 'VERSIONS'
        language: system
        entry: ./scripts/verify-versions.sh
```

### `MIGRATION_V1_TO_V2.md`

Structured per SDK, each section covers:

- Direct API rename table (old symbol → new symbol).
- One-to-one code example migration (3-5 snippets).
- Removed APIs and their replacements.
- Build-system changes (CocoaPods retirement, KMP module
  consolidation, Flutter FFI vs platform-channel, etc.).
- Common gotchas (Swift 6 strict concurrency, JSI setup, WASM COOP
  headers).

Target length: ≤ 600 lines. Not a textbook; a lookup table.

### `ARCHITECTURE.md`

One-page at the repo root. Links to
`sdk/runanywhere-commons/ARCHITECTURE.md` for the deep architecture
doc. Lists each SDK's public API surface and the bridge it uses to
reach the C ABI.

### Deletions

```text
scripts/*-v1-*.sh                                   DELETE any v1-specific scripts
.github/workflows/*legacy*.yml                      DELETE
root-level Podfile / Gemfile / root package.json    RECONCILE — keep only if needed
any root VERSIONS file that duplicates per-SDK      DELETE
JitPack / bintray bits that no longer apply         DELETE
```

### Tests

```text
tools/ci/verify-artifacts.sh
  — run against a built release tag; download each published
    artifact; smoke-test-import it in a minimal sample project per
    language.

scripts/release-dry-run.sh
  — runs the full release pipeline with publish disabled; exits 0 if
    every step would have succeeded.
```

---

## Implementation order

1. **Draft the VERSIONS file** and the `verify-versions.sh` script.
   Wire it as a pre-commit hook so version drift can't ship.

2. **Write the individual per-SDK `scripts/release.sh`** (or verify
   they exist and match the same shape).

3. **Land `pr-gates.yml`** as a merge-required check.

4. **Draft `release.yml`**; run it in dry-run mode on a prerelease
   tag (e.g. `v2.0.0-rc.1`). Verify each job succeeds without
   publishing.

5. **Do an actual rc publish** to internal npm / Maven snapshot /
   pub dev server; pull it into a fresh consumer project; verify it
   works.

6. **Write MIGRATION guide**. Harvest symbol-rename tables from each
   phase doc's "API changes" section.

7. **Rewrite top-level README**. Diagram the new layered architecture
   up top; link to per-SDK quickstarts below.

8. **Tag `v2.0.0`**. Release. Monitor.

9. **Delete any v1 infrastructure** (JitPack config, old CocoaPods
   pods, etc.) in a final sweep.

---

## API changes

None specific to this phase. All API changes are from Phases 0–13;
this phase only publishes them.

---

## Acceptance criteria

- [ ] `scripts/build-all.sh` green from a clean clone on macOS and
      on Linux (where applicable — Swift skipped on Linux).
- [ ] `scripts/test-all.sh` green.
- [ ] `scripts/verify-versions.sh` green; VERSIONS file source of
      truth.
- [ ] `scripts/release-dry-run.sh` green against a prerelease tag.
- [ ] `v2.0.0` tag published; all six artifacts reachable:
  - `sdk/runanywhere-swift` → via SPM
  - `sdk/runanywhere-kotlin` → Maven Central
  - `sdk/runanywhere-flutter` → pub.dev
  - `@runanywhere/react-native` → npm
  - `@runanywhere/web` → npm
  - commons sources → tagged in the monorepo; xcframework +
    sdk artifacts uploaded as release assets
- [ ] All example apps build from a clean clone.
- [ ] `.pre-commit-config.yaml` passes on `pre-commit run --all-files`.
- [ ] Top-level README + MIGRATION guide published.
- [ ] `pr-gates.yml` required for merge on `main`.
- [ ] Internal deploy: a test project in each language can install
      the released artifact and run the chat quickstart end to end.

## Validation checkpoint — **FINAL**

See `testing_strategy.md`. Phase 14 is the last gate before v2.0.0
goes live. It must pass the union of every prior phase's gates
plus:

- **Full repo build from a clean clone** in ≤ 90 minutes on a
  developer MacBook: `scripts/build-all.sh` green.
- **Full repo test from a clean clone** in ≤ 60 minutes:
  `scripts/test-all.sh` green (commons + every SDK).
- **Every example app runs** on at least one runner each:
  iOS sim, Android emulator, Flutter both, RN both, Web browser.
- **Release dry-run green.** `scripts/release-dry-run.sh` on a
  prerelease tag succeeds end-to-end without actually publishing.
- **Every artifact installs from its registry** in a minimal
  consumer project (Swift SPM, Gradle, pub, npm×2). No version
  resolution issues.
- **Migration guide reviewed.** Two maintainers walk through it
  and can migrate a toy v1 app in each language.
- **Release smoke post-publish.** After the real release, a
  watchdog workflow fetches each artifact and builds a minimal
  smoke project against it. Failure pages the release engineer.

---

## What this phase does NOT do

- No removal of the v1 tagged releases. Old tags remain; anyone who
  pinned an older version still has working links.
- No new features. This is strictly release + infra.
- No Dependabot / automated version bumping. We may add it later.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| Publish order matters (RN depends on Swift + Kotlin being live) | Certain | `release.yml` encodes the DAG; RN job `needs: [swift, kotlin]`. Swift + Kotlin + Web can fan out in parallel from `commons` |
| Maven Central sync latency (~30 min) delays RN Android build that needs the just-published Kotlin artifact | Medium | RN's Android Gradle pulls from `mavenLocal()` first with a fallback to Central; publishing step primes Maven Local on the runner before the RN job starts |
| Versions drift between a per-SDK manifest and the VERSIONS file | Medium | Pre-commit hook + CI gate; impossible to ship drift |
| Release pipeline fails partway through — some artifacts published, some not | High | Each per-SDK release script is idempotent; if a retry uploads the same artifact bytes, the registry accepts or rejects cleanly. If a retry would upload different bytes (e.g. timestamp drift), the release is quarantined and we manually reset |
| Pre-commit hook is too slow — engineers disable it | Medium | Hooks only run on files staged in the commit, not the whole repo. Typical diff runs in ≤ 5 s |
| `CHANGELOG.md` goes unmaintained | Medium | Add a CI check: every PR that touches code must append to CHANGELOG. Lightweight script; easy to skip with a label for trivial PRs |
| Deleting old JitPack / CocoaPods pods breaks someone's pinned old build | Low | User confirmed no external consumers. If one surfaces later, the old tag still publishes — they can pin |
| Flutter `pub` publish requires interactive OAuth | Low | Use a service account + `PUB_CREDENTIALS` JSON in CI. Documented in the Flutter SDK's release script |
