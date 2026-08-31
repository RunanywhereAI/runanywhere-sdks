---
name: sdk-publish
description: Manually publish an already-tagged, already-released (non-draft GitHub Release) RunAnywhere SDK version to every package registry (npm, Maven Central, pub.dev, Swift SPM dist repo) plus macOS rcli notarization, with heavy verification that nothing fake/stubbed/broken ships.
---

# SDK Publish

Repo: `~/development/ODLM/MONOREPOOO/Qualcomm/runanywhere-sdks` (verify with `pwd`/`git remote get-url origin` — do not assume this path is still correct, checkouts move). Version source of truth: `core/VERSION`. Throughout, `$VERSION` means the bare semver being published (e.g. `0.20.24`), never prefixed with `v` except in git tags / GitHub Release names.

## THIS PROCESS IS INTENTIONALLY MANUAL

**`release.yml` never publishes anywhere public.** It only builds artifacts, packages them, and creates a draft/published **GitHub Release**. It does not call `npm publish`, does not upload to Maven Central, does not call `flutter pub publish`, and does not push the Swift dist repo. Verify this is still true before trusting it — greps below should all return **zero** matches (grep the whole file, not a snippet):

```bash
cd ~/development/ODLM/MONOREPOOO/Qualcomm/runanywhere-sdks
grep -inE "npm publish|publishReleasePublication|publishAllPublicationsToMavenCentral|flutter pub publish" .github/workflows/release.yml
```

This is a **deliberate safety gate**, not a gap. Every step below is a human (or an agent acting on a human's explicit go-ahead) pushing a button that CI intentionally never pushes. Do not propose wiring any of this into CI as a "fix" — that would remove the gate.

## Precondition check (always run first)

Refuse to proceed if the release is a draft or the asset set looks incomplete.

```bash
gh release view v$VERSION --json isDraft,tagName --jq '{isDraft, tagName}'
# isDraft MUST be false.

gh release view v$VERSION --json assets --jq '.assets[].name' | sort
```

Cross-reference the listing against the `sdk-release` skill's step 8 asset-count expectations (`~/.claude/skills/sdk-release/SKILL.md`). As a second, independent check, also diff against the **previous** tagged release's asset list — same count, same name patterns, only the version token differs:

```bash
gh release view v<PREVIOUS_VERSION> --json assets --jq '.assets[].name' | sed "s/<PREVIOUS_VERSION>/$VERSION/" | sort >/tmp/expected.txt
gh release view v$VERSION --json assets --jq '.assets[].name' | sort >/tmp/actual.txt
diff /tmp/expected.txt /tmp/actual.txt
```

As of the last verified run (**v0.20.25, 65 assets** — up from 55 at v0.20.24 because the 5 public Electron tarballs and their sidecars joined the release; see §6), the full set is: `MANIFEST.txt`; per-platform `RACommons-{android-arm64-v8a,android-armeabi-v7a,android-x86_64,ios,linux-x86_64,web,windows-x64}-v$VERSION.{zip,tar.gz}` + `.sha256`; iOS backend zips `RABackend{LLAMACPP,MLX,NeuRT,ONNX,Sherpa}-ios-v$VERSION.zip` + `.sha256`; `RunAnywhereMLX{Metal,Resources,Runtime}-ios-v$VERSION.zip` + `.sha256`; `rcli-{linux-x86_64,macos-arm64,windows-x86_64}-v$VERSION.tar.gz`/`.zip` + `.sha256`; the 8 npm tarballs `runanywhere-{core,llamacpp,mlx,onnx,proto-ts,web,web-llamacpp,web-onnx}-$VERSION.tgz` + `.sha256`; the **5 Electron npm tarballs** `runanywhere-electron{,-llamacpp,-onnx,-sherpa,-neurt}-$VERSION.tgz` + `.sha256` (new as of v0.20.25); and `runanywhere-kotlin-maven-v$VERSION.zip` + `.sha256`. There is **no** Flutter tarball in the release (Flutter packages are staged from the native archives above, not from a dedicated release asset) and **no** `.dmg` asset in the baseline set (the macOS rcli tarball is what ships; see the notarization section for when a `.dmg` does get produced). If a `qhexrt`-named asset appears anywhere in this list, stop — that would mean `release.yml`'s own manifest assertion should have hard-failed and something is very wrong; do not publish anything from that release.

## 0. MANDATORY GATE — verify the ENTIRE release before pushing anything to any registry

**Run this once, in full, before the first registry push. Do not publish a single package until it passes.** Per-package spot-checks are not a substitute: they are how a bad artifact reaches a registry you cannot un-publish from. Proven end to end on v0.20.25 (2026-08-22), then independently audited and corrected: **34 payloads, 6619 files across 3 nesting levels, 282 binaries, 0 placeholder hits, 38/38 commons binaries carrying the real staging host**. The audit found 4 methodology gaps in the first pass (shallow nesting, missing `MTLB` magic, `.lib` excluded from the positive check, and a set-intersection that could pass vacuously) — every one is called out inline below, because each produced a *confident but under-covered* result.

```bash
VERSION=0.20.25                      # no leading v
REPO=RunanywhereAI/runanywhere-sdks
W=/tmp/relverify-$VERSION
rm -rf "$W" && mkdir -p "$W/assets" "$W/qhexrt" "$W/x" "$W/nested"

# (1) EVERY release asset — no -p filter, get the whole set.
gh release download "v$VERSION" --repo "$REPO" -D "$W/assets"

# (2) The PRIVATE QHexRT artifact is NOT a release asset — pull it from the run.
#     Find the run that produced the release, then:
gh run download <release-run-id> --repo "$REPO" --name sdk-electron-qhexrt-private --dir "$W/qhexrt"
```

### (3) Checksums — `cd` into the directory first

Sidecars contain a **bare basename**, so `shasum -c` fails with a misleading "FAILED open or read" if run from anywhere else. This will make every artifact look broken when nothing is wrong:

```bash
cd "$W/assets"
ok=0; bad=0
for s in *.sha256; do
  if shasum -a 256 -c "$s" >/dev/null 2>&1; then ok=$((ok+1)); else echo "MISMATCH: $s"; bad=$((bad+1)); fi
done
echo "verified=$ok mismatched=$bad"      # bad MUST be 0
(cd "$W/qhexrt" && shasum -a 256 -c ./*.sha256)
```

### (4) Extract everything — INCLUDING nested archives

**The gotcha that matters:** `runanywhere-kotlin-maven-v*.zip` contains `.aar` files, and the `.aar`s are what hold the Android `.so` binaries. A one-level extraction reports "0 binaries" for the Maven bundle and every subsequent scan passes **vacuously**.

**Recurse until the tree is dry — TWO levels are required here, not one.** Each `.aar` also contains a `classes.jar`, holding ~2027 `.class` files that are doubly unreachable: inside an unopened jar *and* excluded by the `.class` suffix rule most magic-byte scanners use. Level 2 adds **2033 files** (0 placeholder hits on v0.20.25); level 3 is empty. Loop until a pass finds no new archives rather than hardcoding a depth.

```bash
cd "$W/assets"
for f in *; do
  case "$f" in *.sha256|MANIFEST.txt) continue;; esac
  d="$W/x/$f"; mkdir -p "$d"
  case "$f" in
    *.zip)              unzip -qq -o "$f" -d "$d" || echo "EXTRACT FAILED: $f" ;;
    *.tar.gz|*.tgz)     tar -xzf "$f" -C "$d"     || echo "EXTRACT FAILED: $f" ;;
    *) echo "UNHANDLED TYPE: $f" ;;
  esac
done
d="$W/x/$(basename "$W"/qhexrt/*.tgz)"; mkdir -p "$d"; tar -xzf "$W"/qhexrt/*.tgz -C "$d"

# nested pass
cd "$W/x"
find . -type f \( -name '*.aar' -o -name '*.jar' -o -name '*.zip' -o -name '*.tgz' -o -name '*.tar.gz' \) \
  | sed 's|^\./||' | while IFS= read -r a; do
    dd="$W/nested/$(printf '%s' "$a" | tr '/' '_')"; mkdir -p "$dd"
    case "$a" in *.aar|*.jar|*.zip) unzip -qq -o "$a" -d "$dd";; *) tar -xzf "$a" -C "$dd";; esac
  done
```

**Prove extraction actually happened** — an empty dir makes "0 hits" meaningless:

```bash
for d in "$W"/x/*/; do
  n=$(find "$d" -type f | wc -l)
  [ "$n" -lt 2 ] && echo "SUSPICIOUSLY EMPTY: $d ($n files)"
done
```

### (5) Placeholder scan — EVERY file, not just binaries

The staging URL can also live in JS/JSON/TS config, so scan by content across all file types, and additionally scan the raw compressed streams in case a member never got extracted:

```bash
find "$W/x" "$W/nested" -type f | wc -l                                     # total files covered
grep -rla "YOUR_STAGING_BASE_URL" "$W/x" "$W/nested" | tee /tmp/ph.txt | wc -l   # MUST be 0
for f in "$W"/assets/*.tgz "$W"/assets/*.tar.gz "$W"/qhexrt/*.tgz; do
  gzip -dc "$f" 2>/dev/null | grep -qa "YOUR_STAGING_BASE_URL" && echo "RAW HIT: $f"
done
```

Find binaries by **magic bytes, not extension** (an unsuffixed framework binary like `RACommons.framework/RACommons` has no extension and a name-based `find` misses it). Signatures to cover:

| Magic | Kind | v0.20.25 count |
|---|---|---|
| `7f454c46` | ELF | 177 |
| `!<arch>` (`213c617263683e0a`) | static `.a` **and `.lib`** | 41 |
| `MZ` | PE | 29 |
| `cffaedfe` / `cefaedfe` | Mach-O | 19 |
| `00 61 73 6d` | wasm | 10 |
| **`4d544c42` (`MTLB`)** | **Metal library** — easy to miss | 5 |
| `cafebabe` / `bebafeca` | fat Mach-O (exclude `.jar`/`.class`) | 1 |

**Total: 282 binaries.** An earlier pass reported 277 because `MTLB` was absent from the signature list — `.metallib` files were invisible to the binary scan (they were still covered by the all-file `grep` in step 5, so the conclusion held, but the count was wrong). If your total comes in materially under ~282 for a comparable release, your detection is leaking.

### (6) POSITIVE staging-URL check — absence of the placeholder is NOT sufficient

A build with an **empty** URL baked in passes a placeholder-only check. `check_plugin_natives.py` only tests absence, so add the positive assertion yourself.

Two traps that produced false confidence on the v0.20.25 pass, both worth avoiding:

- **Include `.lib`.** A `MUST_HAVE` regex of `rac_commons\.(dylib|so|dll|a)$` silently skips
  `RACommons-windows-x64/x64/rac_commons.lib` — an **89 MB** binary that then gets no positive
  check at all. Match `(dylib|so|dll|a|lib)` plus `\.wasm$`. Correct coverage is **38** binaries,
  not 37.
- **Assert per binary, not by set-intersection.** Intersecting "non-public origins across all
  files" yields more than one origin here (`hf.co` *and* the staging host), so a binary carrying
  only `hf.co` would pass **vacuously**. Check each binary individually for the staging host.

```bash
# v0.20.25 baseline: 38 commons/wasm/lib binaries; 0 missing the staging host.
```

Never print the URL — it is a repo secret. Report a truncated SHA-256 fingerprint, or just assert presence/absence counts.

### (7) Routability gate over the whole tree

```bash
python3 scripts/validation/gates/check_plugin_natives.py "$W/x" "$W/nested" > /tmp/gate.txt 2>&1
grep -cE '^  ok ' /tmp/gate.txt; grep -E '^  FAIL' /tmp/gate.txt
```

v0.20.25 baseline: **77 ok, 1 FAIL**. The single expected FAIL is
`RACommons-linux-x86_64/lib/librunanywhere_sherpa.so` — see the known-exception note below. **Any other FAIL blocks the publish.**

### (8) Known exception — Linux sherpa is a non-routable shell (PRE-EXISTING, not a regression)

`RACommons-linux-x86_64-v*.tar.gz` ships **no** `libsherpa-onnx-c-api.so` at all and its `librac_backend_sherpa.so` is a ~156 KB shell (~3 sherpa strings, vs ~31 MB / ~192 for a healthy one on Electron macOS) — the engine is not linked in, so the carrier cannot reference `g_sherpa_{stt,tts,vad}_ops` and **STT/TTS/VAD cannot work from that bundle**. Android's carriers pass on all 3 ABIs, so this is Linux-only.

**Compare the CARRIER, not the backend.** The gate FAILs on `librunanywhere_sherpa.so` (the carrier); citing `librac_backend_sherpa.so` as your evidence is comparing a *different file* and is not proof. The carrier is byte-identical across releases, which is the real proof:

```bash
gh release download "v<PREV>" --repo "$REPO" -p 'RACommons-linux-x86_64-v<PREV>.tar.gz' -D /tmp/prev
tar -xzf /tmp/prev/*.tar.gz -C /tmp/prev
shasum -a 256 /tmp/prev/lib/librunanywhere_sherpa.so "$W"/x/RACommons-linux-*/lib/librunanywhere_sherpa.so
# v0.20.24 and v0.20.25 both: size=15712  sha256=28ef16015b61da86...

# strongest check — run the gate on the PREVIOUS bundle and confirm the identical FAIL:
python3 scripts/validation/gates/check_plugin_natives.py /tmp/prev
```

If it ever regresses *further* (e.g. Android or macOS sherpa also goes hollow), stop and treat it as a blocking defect.

### (9) Account for every payload explicitly

Print a per-artifact table (checksum verdict, binary count, placeholder hits) and confirm the row count equals the payload count. Artifacts that legitimately contain **no** native binaries, and why — do not let these pass silently unexamined:

| Artifact | Why it has no binaries |
|---|---|
| `RunAnywhereMLXResources-ios-*.zip` | 25 third-party license/notice text files |
| `runanywhere-kotlin-maven-v*.zip` | binaries live in the **nested** `.aar`s (step 4) |
| `runanywhere-proto-ts-*.tgz` | pure TS/JS (69 `.ts` + 69 `.js`) |

Everything else must have a non-zero, plausible binary count. A platform suddenly shipping fewer binaries than the previous release is a regression signal worth chasing before publishing.

### (10) Blind spot to be aware of — Windows x64 has NO routability coverage

`RACommons-windows-x64-v*.zip` ships **only** a static `rac_commons.lib` (~89 MB) plus 152 `.h` / 11 `.hpp` headers — **zero backend DLLs**, where Linux/Android/Web each ship 4–5 backend carriers. That is consistent with a static-embedding bundle (consumers link the engines in themselves), but the consequence matters: **no gate can detect a missing or hollow Windows backend**, because there is no carrier to inspect. `check_plugin_natives.py` therefore reports nothing at all for this artifact rather than reporting health.

Windows x64 is also *advisory* in `release.yml` (its absence does not fail the release). So a Windows regression can pass every automated check. If Windows correctness matters for a given release, verify it by actually running something on the real Windows box (see §Electron for how to reach it) — do not infer it from a green pipeline. Worth a deliberate confirmation with the repo owner that the DLL-free shape is intentional.

---

## General verification discipline (every artifact, every registry)

Apply all three checks below to **every** file you're about to publish, before AND after the publish call. Never trust a copy cached locally earlier in the session — re-download.

**(a) Download + verify the sha256 sidecar yourself:**

```bash
gh release download v$VERSION -p '<file>' -p '<file>.sha256' -D /tmp/sdk-publish-$VERSION
cd /tmp/sdk-publish-$VERSION && shasum -a 256 -c '<file>.sha256'
```

**(b) Inspect the actual file listing inside every tarball/AAR/zip** — never assume from the filename alone:

```bash
npm pack <tgz-or-package-dir> --dry-run     # npm packages: prints the exact file list it would publish
unzip -l  <file.zip>                        # AARs, Maven repo zip, native archives
tar -tzf  <file.tar.gz>                     # rcli, RACommons tarballs
```

Sanity-check what comes back:
- No suspiciously-small or empty binaries where a real native library (`.so`, `.dylib`, `.a`, `.dll`) should be — a stub or a zero-byte placeholder means the build silently failed upstream.
- No leftover `workspace:*` or `file:` dependency specs in any `package.json` inside the tarball — those only resolve inside this monorepo and break for a real external installer.
- Version strings inside every manifest (`package.json` `version`, AAR `pom.xml` `<version>`, `pubspec.yaml` `version:`) **exactly** match `$VERSION`.
- **Hard rule, no exceptions:** grep the full file listing for `qhexrt` (any case) and for QNN binary names (`libQnnHtp`, `QnnHtp*.dll`, `rac_commons.dll` bundled with QHexRT, `runanywhere_qhexrt`). If any hit appears in a package meant to be public, stop and do not publish that artifact.

**(c) Confirm baked-in runtime config** (e.g. a staging-vs-prod backend base URL compiled into `rac_commons` at build time) points at the real intended endpoint. This is designed to fail closed if misconfigured — a build that completed and produces working requests against prod is itself decent evidence — but if you have any doubt, `strings <binary> | grep -i "api\.\|staging\."` and eyeball it.

## 1. npm — 8 packages, order matters

Packages: 4 Web (`@runanywhere/proto-ts`, `@runanywhere/web`, `@runanywhere/web-llamacpp`, `@runanywhere/web-onnx`) + 4 React Native (`@runanywhere/core`, `@runanywhere/llamacpp`, `@runanywhere/mlx`, `@runanywhere/onnx`). Never `@runanywhere/qhexrt` (RN) — it exists in `bindings/react-native/packages/qhexrt/` but is excluded from the public npm train by the same policy as Maven/pub.dev QHexRT.

**Publish `@runanywhere/proto-ts` FIRST.** `@runanywhere/web-onnx` deliberately does not bundle its own `proto-ts` copy and needs it resolvable from the live registry for real consumers; publish `proto-ts` before it or a fresh `npm install @runanywhere/web-onnx` fails to resolve.

```bash
gh release download v$VERSION -p 'runanywhere-proto-ts-*.tgz*' -p 'runanywhere-web-*.tgz*' \
  -p 'runanywhere-core-*.tgz*' -p 'runanywhere-llamacpp-*.tgz*' -p 'runanywhere-mlx-*.tgz*' -p 'runanywhere-onnx-*.tgz*' \
  -D /tmp/sdk-publish-$VERSION
cd /tmp/sdk-publish-$VERSION
for f in *.sha256; do shasum -a 256 -c "$f"; done

npm publish runanywhere-proto-ts-$VERSION.tgz --access public   # FIRST, always
npm publish runanywhere-web-$VERSION.tgz --access public
npm publish runanywhere-web-llamacpp-$VERSION.tgz --access public
npm publish runanywhere-web-onnx-$VERSION.tgz --access public
npm publish runanywhere-core-$VERSION.tgz --access public
npm publish runanywhere-llamacpp-$VERSION.tgz --access public
npm publish runanywhere-mlx-$VERSION.tgz --access public
npm publish runanywhere-onnx-$VERSION.tgz --access public
```

`npm whoami` should already show a logged-in account; if it errors, stop and tell the human rather than trying to log in non-interactively.

**GOTCHA — large tarballs can silently die mid-upload.** `@runanywhere/mlx` (~50MB) and `@runanywhere/web-onnx` (unpacks to 300+MB) can exceed a short default shell/tool timeout mid-upload and get killed with no clean error. Use an explicit long timeout (5 minutes / 300000ms) on each publish call.

**GOTCHA — verify via the registry API, not the npm CLI.** `npm view` can lag the CLI's own cache by several seconds right after a fresh publish and falsely report "not found". After **every** publish:

```bash
curl -s "https://registry.npmjs.org/@runanywhere/<pkg>" | python3 -c "import json,sys;print(json.load(sys.stdin)['dist-tags'])"
```
Confirm `latest` equals `$VERSION`.

## 2. Maven Central — 3 AARs only

`io.github.sanchitmonga22:{runanywhere-sdk,runanywhere-llamacpp,runanywhere-onnx}`. **Never `runanywhere-qhexrt-android`** — it was published through 0.20.19 under an earlier, since-reversed policy and is now permanently excluded; `release.yml`'s manifest assertion hard-fails if it reappears in the public asset set.

Full step-by-step lives in `bindings/kotlin/docs/KOTLIN_MAVEN_CENTRAL_PUBLISHING.md`, section **"Option A: Publish with released native archives"** (line ~108 as of this writing — the doc has been corrected mid-release before, so re-read it fresh rather than trusting memory of its contents). Key points, condensed:

1. Download + verify the 3 `RACommons-android-{arm64-v8a,armeabi-v7a,x86_64}-v$VERSION.zip` from the release (sha256 sidecars, per the general discipline above).
2. Stage: `bash bindings/kotlin/scripts/package-sdk.sh --mode local --natives-from <dir-with-the-3-zips>`. This also produces a local Maven-repo zip — diff its size against `runanywhere-kotlin-maven-v$VERSION.zip` already attached to the GitHub Release as a cheap reproducibility check.
3. Before uploading, confirm the OSSRH compatibility service has no dangling open repository for this namespace:
   ```bash
   CENTRAL_BEARER="$(printf '%s:%s' "$MAVEN_CENTRAL_USERNAME" "$MAVEN_CENTRAL_PASSWORD" | base64 | tr -d '\r\n')"
   curl -s -H "Authorization: Bearer $CENTRAL_BEARER" \
     'https://ossrh-staging-api.central.sonatype.com/manual/search/repositories?ip=client&profile_id=io.github.sanchitmonga22'
   ```
   Resolve any stale repository per the doc's troubleshooting table before continuing.
4. Source `MAVEN_CENTRAL_USERNAME`/`MAVEN_CENTRAL_PASSWORD` from `~/.gradle/gradle.properties` (`mavenCentral.username`/`mavenCentral.password` — confirmed present on this machine; never print the values) and run, from `bindings/kotlin/`:
   ```bash
   ./gradlew clean \
     :publishReleasePublicationToMavenCentralRepository \
     :modules:runanywhere-core-llamacpp:publishReleasePublicationToMavenCentralRepository \
     :modules:runanywhere-core-onnx:publishReleasePublicationToMavenCentralRepository \
     -Prunanywhere.useLocalNatives=true -x buildLocalJniLibs --no-daemon
   ```
   GPG signing (`signing.gnupg.keyName`/`signing.gnupg.passphrase` in the same properties file, key id `CC377A9928C7BB18` — confirmed importable via `gpg --list-secret-keys --keyid-format LONG` on this machine) is read from the same properties file automatically; you do not pass it separately.
5. Transfer to Central Portal:
   ```bash
   curl --fail --request POST -H "Authorization: Bearer $CENTRAL_BEARER" \
     'https://ossrh-staging-api.central.sonatype.com/manual/upload/defaultRepository/io.github.sanchitmonga22?publishing_type=automatic'
   ```
   Then find the resulting `portal_deployment_id` — expect **exactly one** fresh repository; if the count isn't 1, stop and investigate rather than guessing which one is yours (see the doc for the exact `jq` filter).
6. Poll `https://central.sonatype.com/api/v1/publisher/status?id=<id>` (POST, same bearer) until `deploymentState` is `PUBLISHED`. Automatic deployments normally go `PENDING -> VALIDATING -> PUBLISHING -> PUBLISHED` within a few minutes. **If it lands on `VALIDATED` instead of proceeding, that means Sonatype is waiting for a manual click in the Central Portal UI** — stop and tell the human; do not loop forever assuming it resolves itself. On `FAILED`, print `.errors` and stop.
7. Verify propagation (allow 10-30 minutes for CDN propagation even after `PUBLISHED`):
   ```bash
   for a in runanywhere-sdk runanywhere-llamacpp runanywhere-onnx; do
     echo "$a: $(curl -s -o /dev/null -w '%{http_code}' "https://repo1.maven.org/maven2/io/github/sanchitmonga22/$a/$VERSION/$a-$VERSION.pom")"
   done
   ```
   Expect `200` for all three.

## 3. pub.dev (Flutter)

**Verify the current package set fresh — do not trust a hardcoded count.** As of this writing the real, non-QHexRT Flutter package set is **4**, not 3: `runanywhere`, `runanywhere_llamacpp`, `runanywhere_onnx`, and `runanywhere_mlx` (mlx was added after some earlier documentation/memory of "3 packages" was written — that assumption is stale; `runanywhere_mlx` is a real, already-published-on-pub.dev package, not new/WIP). Enumerate it yourself instead of trusting this list verbatim next time:
```bash
find bindings/flutter/packages -maxdepth 1 -type d -not -iname '*qhexrt*' -not -path '*/packages'
```
`runanywhere_qhexrt` exists in that directory too — never publish it (same exclusion policy as Maven).

Stage the released iOS xcframeworks + Android `.so` into each package with the Flutter equivalent of `package-sdk.sh` (melos-based monorepo, confirmed at `bindings/flutter/scripts/package-sdk.sh`):

```bash
bash bindings/flutter/scripts/package-sdk.sh --mode local --natives-from <dir-with-xcframeworks-and-android-.so>
```

This script already runs `flutter pub publish --dry-run` internally per package as part of its own validation — but run it again yourself, per package, from each package directory, and **read the output for real, not just the exit code**:

```bash
cd bindings/flutter/packages/runanywhere && flutter pub publish --dry-run
cd ../runanywhere_llamacpp && flutter pub publish --dry-run
cd ../runanywhere_onnx && flutter pub publish --dry-run
cd ../runanywhere_mlx && flutter pub publish --dry-run
```

Expect zero warnings except a benign version-gap hint. Only then run the real publish, same order (core first, since the others depend on it):

```bash
cd bindings/flutter/packages/runanywhere && flutter pub publish
cd ../runanywhere_llamacpp && flutter pub publish
cd ../runanywhere_onnx && flutter pub publish
cd ../runanywhere_mlx && flutter pub publish
```

**Credential note:** pub.dev OAuth is normally cached at `~/Library/Application Support/dart/pub-credentials.json` on macOS (confirmed present on this machine). If it's missing, expired, or `flutter pub publish` prompts for an interactive browser login, **STOP and tell the human** — you cannot complete a fresh Google OAuth flow non-interactively, and forcing/guessing here is not appropriate.

Verify afterward against the live API (not a cached page):
```bash
for p in runanywhere runanywhere_llamacpp runanywhere_onnx runanywhere_mlx; do
  echo "$p: $(curl -s "https://pub.dev/api/packages/$p" | python3 -c "import json,sys;print(json.load(sys.stdin)['latest']['version'])")"
done
```

## 4. Swift SPM distribution repo (`RunanywhereAI/runanywhere-swift`)

A separate, **generated-only** repo mirroring `bindings/swift` (Package.swift + Sources/ + LICENSE + README) so SwiftPM consumers using `from: "<version>"` don't clone the ~340MB monorepo.

**GOTCHA:** this machine may have local directories literally named `runanywhere-swift` that are just checkouts of the **monorepo's** remote, not the distribution repo. Verify before trusting any existing local directory by name:
```bash
git -C <candidate-dir> remote get-url origin
```
Must show `RunanywhereAI/runanywhere-swift`, not `runanywhere-sdks`. Always clone fresh instead of guessing:

```bash
git clone https://github.com/RunanywhereAI/runanywhere-swift.git /tmp/ra-swift

bindings/swift/scripts/sync-dist-repo.sh \
  --zips <exact-verified-Apple-archive-dir-from-the-release> --tag /tmp/ra-swift

RUNANYWHERE_SWIFT_DIST_REPO=/tmp/ra-swift \
  bash scripts/validation/gates/check_swift_dist_repo_sync.sh

git -C /tmp/ra-swift push origin main --follow-tags
```

The `--zips` dir must contain the verified (sha256-checked) release archives — `RACommons-ios-v$VERSION.zip`, `RABackend{LLAMACPP,MLX,NeuRT,ONNX,Sherpa}-ios-v$VERSION.zip`, `RunAnywhereMLX{Metal,Resources,Runtime}-ios-v$VERSION.zip` — downloaded and checked exactly per the general verification discipline, not re-used from an earlier, untrusted local copy.

**The tag on `runanywhere-swift` is bare semver, no `v` prefix** (SwiftPM's `from:` needs that) — do not tag it `v$VERSION` by mistake; `sync-dist-repo.sh --tag` handles this correctly, but double check the pushed tag with `git -C /tmp/ra-swift tag --points-at HEAD` before walking away.

This is enforced, not just documented: once `v$VERSION` is tagged on `runanywhere-sdks`, `check_swift_dist_repo_sync.sh` fails every future PR on the monorepo until `runanywhere-swift` carries the matching bare-semver tag — so don't let this lag behind the other registries.

**GATE GAP — `check_swift_dist_repo_sync.sh` does NOT catch dependency drift, only checksum/version-string drift.** `runanywhere-swift`'s `Package.swift` is manually maintained end to end — `sync-dist-repo.sh` only ever touches `sdkVersion` and the binaryTarget checksums, never the `dependencies:` block (mlx-swift, mlx-swift-lm, mlx-audio-swift, swift-crypto, etc.). If root `runanywhere-sdks/Package.swift` bumps one of those (e.g. a new fork tag), a human has to remember to mirror it into the dist repo by hand, and nothing fails CI if they forget. This exact drift shipped once (2026-08-17): the dist repo pointed `mlx-swift-lm` at unforked `ml-explore/mlx-swift-lm` instead of the `RunanywhereAI` fork, silently breaking every iOS/macOS MLX consumer of that tag until caught by an actual build failure ~40 minutes later. Before trusting a freshly-cut dist-repo tag: diff every `.package(url:` line between root `Package.swift` and the dist repo's `Package.swift` (`grep -n '\.package(url:' Package.swift` on both sides), and actually build a real product that exercises the dependency you're worried about (e.g. `cd /tmp/ra-swift && swift build --product RunAnywhereMLX`) — don't rely on the sync gate alone. If you catch drift on a tag that's only minutes old with no evidence of external consumption, fixing it in place and force-moving the tag (`git tag -f $VERSION && git push origin $VERSION --force`) is the correct call, not a shortcut — a known-broken immutable tag helps no one.

**If you force-move a tag, SwiftPM/Xcode consumers cache the OLD commit in several places — clearing just `Package.resolved` is not enough.** Verifying your own fix (or having a downstream consumer verify it) can silently keep failing even after the fix is correctly pushed, because: (1) any consumer repo's own tracked `*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` pins the exact old resolution and `xcodebuild -resolvePackageDependencies` respects it rather than re-resolving; (2) `~/Library/Caches/org.swift.swiftpm/repositories/<pkg>-<hash>/` is a global shared clone cache keyed by repo, oblivious to a moved tag; (3) `~/Library/org.swift.swiftpm/security/fingerprints/<pkg>-<hash>.json` records the fingerprint SwiftPM saw for that tag and can silently keep using it after a mismatch instead of failing loud. To actually re-resolve after moving a tag: delete the consumer's tracked `Package.resolved`, `rm -rf .build .swiftpm` and any `~/Library/Developer/Xcode/DerivedData/<Scheme>-*`, AND clear the matching entries under both global `org.swift.swiftpm` cache directories for every affected package identity — then resolve fresh.

## 5. macOS rcli notarization

CI (`native_rcli_macos` in `release.yml`) usually already produces a notarized, stapled artifact when Developer ID + notary secrets are configured in repo secrets. **Check the release assets first** before assuming you need to notarize anything yourself locally:

```bash
gh release view v$VERSION --json assets --jq '.assets[].name' | grep -iE 'rcli-macos|\.dmg'
```
Baseline expectation is `rcli-macos-arm64-v$VERSION.tar.gz` (+ `.sha256`); a `.dmg` only appears when `RCLI_MACOS_FULL_RELEASE=1` was set for that build (see below). If a plain tarball is already present and its contents pass the general verification discipline, there is usually nothing further to do here.

**If you do need to notarize locally**, everything lives in `scripts/package-rcli.sh` in the separate `RunanywhereAI/RCLI` repo (read its header comment — it documents its own contract in detail):

- One-time setup, check before redoing: `xcrun notarytool history --keychain-profile runanywhere-notary` (confirmed configured on this machine — a fresh submission history returns without error). If missing: `xcrun notarytool store-credentials "runanywhere-notary" --apple-id <email> --team-id <team> --password <app-specific-password>`.
- Codesign identity: `security find-identity -v -p codesigning | grep "Developer ID Application"` — confirmed present on this machine as `"Developer ID Application: RunAnywhere, Inc (<TEAM_ID>)"`. Grep for it fresh rather than hardcoding the team-id suffix, it can rotate.
- Invocation contract (env vars, from the script header): `RCLI_CODESIGN_IDENTITY`, `RCLI_MACOS_NOTARIZE=1`, `RCLI_MACOS_FULL_RELEASE=1`, `RCLI_MACOS_SWIFT_BIN_DIR=<output of build-mlx-cli.sh>`. `RCLI_MACOS_FULL_RELEASE=1` is what additionally stages `mlx.metallib` and SwiftPM resource bundles and is what causes a notarized, stapled `.dmg` to be emitted alongside the Homebrew-style tarball. `RCLI_CODESIGN_KEYCHAIN` / `RCLI_NOTARYTOOL_KEYCHAIN` matter only if the identity/profile live in a non-default keychain.
- Call shape: `scripts/package-rcli.sh <build-dir> macos-arm64`, run from an `RunanywhereAI/RCLI` checkout, with the env vars above exported.

## 6. Electron — build AND packaging are now in `release.yml`; publish is still manual

**Reversing the earlier "deliberately separate" note**: as of `fix/electron-cicd-staging-url-npu-ane` (2026-08-21), the repo owner asked for Electron to produce ready-to-publish artifacts through the real release train like every other SDK, so `release.yml` now has `native_electron` (invokes `.github/workflows/electron-native-package.yml` as a reusable `workflow_call`) and `sdk_electron` (downloads its `electron-packaged-tarballs` artifact, runs `scripts/release/prepublish_check.py` on every tarball, checksums them, and splits public vs. QHexRT-private). `publish` hard-gates on `sdk_electron` succeeding. `@runanywhere/electron`, `-llamacpp`, `-onnx`, `-sherpa`, `-neurt` land as real, `.sha256`-sidecarred GitHub Release assets, same as the Web/RN npm tarballs. `@runanywhere/electron-qhexrt` still never becomes a public Release asset (policy below) — it's produced and packaged every release, but only reachable as the `sdk-electron-qhexrt-private` workflow artifact on that run, for a human to `npm publish` by hand. Electron is **not** WIP on a branch anymore: the old root `AGENTS.md` "Active issues" section describing `smonga/electron_upgrade` as in-progress is gone entirely as of this checkout — `bindings/electron/` is a fully merged, real SDK on `main`. Re-check that section is still absent before trusting this note.

`.github/workflows/electron-native-package.yml` itself is unchanged in what it builds: every backend for real (llamacpp/onnx/sherpa/neurt on their real platforms, qhexrt on a self-hosted Windows ARM64 runner) with the real `STAGING_BASE_URL` baked in, gated by `check_plugin_natives.py` (which fails closed on the staging-URL placeholder — the exact bug that shipped through `0.20.24`). What's new is that it's also invocable via `workflow_call`, and that `native_win_x64_and_package` now tolerates a failed/skipped QHexRT lane (self-hosted, single machine) rather than losing the other five real packages to one runner's outage. **`release.yml` itself still does not `npm publish` anything** — it only produces artifacts (Release assets for the public five, a workflow artifact for QHexRT) — same "build automated, publish manual" shape as every other platform. See `thoughts/shared/plans/electron_cicd_staging_url_and_npu_ane_pipeline.md` for the full history.

**PROVEN END TO END on v0.20.25 (2026-08-22)** — the first release where this actually ran. Final state: 65 release assets, all 5 public Electron tarballs present with `.sha256` sidecars, zero `qhexrt`-named assets. Verified by downloading the *published* tarballs and running the repo's own gate against them:

```bash
gh release download v<version> --repo RunanywhereAI/runanywhere-sdks -p 'runanywhere-electron*.tgz' -D /tmp/verify
python3 scripts/validation/gates/check_plugin_natives.py --expect-version <version> \
    $(for t in /tmp/verify/*.tgz; do printf -- '--tarball %s ' "$t"; done)
# => All 20 check(s) passed: plugin natives are routable and no staging-URL placeholder was found.
```

That single command asserts all three things you actually care about, per binary: the real `STAGING_BASE_URL` is baked in (no `YOUR_STAGING_BASE_URL`), `rac_commons` embeds the right version, and every backend is genuinely **routable** (`g_llamacpp_ops`, `g_sherpa_stt_ops`, `g_neurt_llm_ops`, `g_onnx_embeddings_ops`, …) rather than a same-sized shell. **Run it before every Electron `npm publish`** — it is the cheapest defense against exactly the class of defect that shipped `electron-sherpa` 0.20.17's NULL-vtable carrier. Expected shipped layout: entry package = `darwin-arm64` + `win32-x64` + `win32-arm64`; llamacpp/onnx/sherpa = `darwin-arm64` + `win32-x64`; neurt = `darwin-arm64` only; qhexrt = `win32-arm64` only.

Where to get the QHexRT tarball for its manual publish (it is deliberately NOT a release asset):

```bash
gh run download <release-run-id> --repo RunanywhereAI/runanywhere-sdks \
    --name sdk-electron-qhexrt-private --dir /tmp/qhexrt
```

If asked to actually publish an Electron package (still a real, separate, manual step — this skill's general discipline in §0/§General verification still applies in full):
- Involve the Windows box for real Windows-native verification before publishing anything Windows-targeted. The team keeps a **Windows ARM64 machine reachable over SSH**; its hostname, user, key, and mesh-VPN node name are operator-specific and deliberately not recorded in this repo — read the Windows/ARM64 host entry out of the operator's `~/.ssh/config` and use that alias. If there is no such entry, the box is not configured for you: say so and ask, rather than guessing at a hostname. Check reachability **first** by asking the mesh-VPN client whether the node is up (e.g. `tailscale status`, matching on the host entry's `HostName`) — if it reports `offline, last seen ...`, the box is asleep, which is not a configuration problem: ask the human to wake it, do not debug it as broken. Only then `ssh -o ConnectTimeout=8 "$WIN_BOX" "whoami"`. That same machine is **also** registered as a GitHub Actions self-hosted runner (labels `[self-hosted, Windows, ARM64, qhexrt]`) running as a Windows service — a queued `native_win_arm64_qhexrt` job on it means the machine is busy; check `gh api repos/RunanywhereAI/runanywhere-sdks/actions/runners` for the matching runner's `busy`/`status` before assuming it's free for manual SSH work, and vice versa.
- **`@runanywhere/electron-qhexrt` being public on npm is a CONFIRMED, settled policy decision** (repo owner, 2026-08-20) — it contains real Hexagon NPU binaries (`libQnnHtpV81Skel.so`, `QnnHtp*.dll`, `rac_commons.dll`, `runanywhere_qhexrt.dll`) on purpose. The QHexRT-stays-private policy enforced everywhere else in this skill is specifically about the **GitHub-Release-side** asset set (Android etc.), a different channel — not a contradiction. Stop treating this as an unresolved item to flag; only re-raise it if you find evidence the policy changed.

## 7. Final sanity pass

After every registry is done, re-view each package's public listing/API and compare against the previous version — a big unexplained drop in file count or package size is a red flag to investigate before calling the release fully published:

```bash
# npm
for p in proto-ts web web-llamacpp web-onnx core llamacpp mlx onnx; do
  npm pack @runanywhere/$p@$VERSION --dry-run 2>&1 | tail -5
done

# Maven — check module metadata / POM sizes are non-trivial, not near-empty
for a in runanywhere-sdk runanywhere-llamacpp runanywhere-onnx; do
  curl -s -o /dev/null -w "%{size_download} bytes  $a\n" \
    "https://repo1.maven.org/maven2/io/github/sanchitmonga22/$a/$VERSION/$a-$VERSION.aar"
done

# pub.dev
for p in runanywhere runanywhere_llamacpp runanywhere_onnx runanywhere_mlx; do
  curl -s "https://pub.dev/api/packages/$p" | python3 -c "import json,sys;d=json.load(sys.stdin);print('$p', d['latest']['version'])"
done
```

Only after this pass — every registry shows `$VERSION`, every artifact's contents check out, and nothing regressed in size/file-count versus the previous release — is the release fully published. Do not skip this step just because each individual publish call reported success; a successful upload is not the same claim as "the right bytes are now live."
