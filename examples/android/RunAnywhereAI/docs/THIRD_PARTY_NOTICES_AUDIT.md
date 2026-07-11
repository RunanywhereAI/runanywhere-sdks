# Release SBOM and third-party notices audit

Snapshot date: 2026-07-11

This is a reproducible engineering inventory, not legal approval. A file named
`LICENSE` inside an input archive does not by itself prove that all obligations
are satisfied, and the absence of such a file does not determine the governing
license. The publisher must have counsel or another authorized reviewer approve
the exact release payload and the form and placement of every required notice.

## Reproduce the archive evidence

From this directory, run:

```bash
./scripts/audit-release-notices.sh
./scripts/audit-release-notices.sh --strict --apk app/build/outputs/apk/release/app-release.apk
```

The first command generates:

- `app/build/reports/release-sbom.cdx.json` — CycloneDX 1.5 coordinates and
  SHA-256 hashes for the release runtime classpath and four local SDK AARs.
- `app/build/reports/release-notice-inventory.json` — the same exact components
  and hashes plus every archive path matching `LICENSE`, `NOTICE`, `COPYING`, or
  `COPYRIGHT`, including paths inside an AAR's nested `classes.jar`.

`bundleRelease` generates the SBOM. The audit script generates the matching
notice inventory from the exact SBOM hashes. Archive both reports with the
signed AAB, mapping, native symbols, dependency report, and release test
evidence. Generated reports stay under `build/` and must not be committed.

`--strict` is intentionally only a mechanical gate. It requires the exact APK
and fails while any local RunAnywhere AAR has no notice-like archive entry. A
passing mechanical scan still requires the external approvals below.

## Current result

The 2026-07-11 release classpath contains 110 components: 106 Maven artifacts
and these four local AARs. Sixty Maven artifacts contain at least one
notice-like archive path; 46 do not. None of the four local AARs contains a
license or notice file.

| Local AAR | Native payload relevant to notice review | Packaged notice evidence |
|---|---|---|
| `runanywhere-sdk.aar` | RunAnywhere commons/cloud/JNI, NDK `libc++_shared.so`, and `libomp.so` | None |
| `runanywhere-llamacpp.aar` | RunAnywhere adapters plus statically linked llama.cpp/ggml/mtmd and its vendored code | None |
| `runanywhere-onnx.aar` | ONNX Runtime, the RunAnywhere Sherpa-ONNX fork, and RunAnywhere ONNX/Sherpa adapters | None |
| `runanywhere-qhexrt.aar` | QHexRT/HexagonRT host code, ten QAIRT/QNN host libraries, three HTP skels, and NDK `libc++_shared.so` | None |

The minified release APK present during this audit retained only these five
notice-like entries:

```text
META-INF/androidx/annotation/annotation/LICENSE.txt
META-INF/androidx/collection/collection-ktx/LICENSE.txt
META-INF/androidx/collection/collection/LICENSE.txt
META-INF/androidx/lifecycle/lifecycle-common-java8/LICENSE.txt
META-INF/androidx/lifecycle/lifecycle-common/LICENSE.txt
```

It did not contain a RunAnywhere, QHexRT, HexagonRT, QAIRT/QNN, native runtime,
model, font, Tabler, or brand-logo notices bundle. Re-run the strict command
against the final upload candidate because resource merging and shrinking can
change what survives into the APK/AAB.

The current CycloneDX file is useful artifact evidence, but it has two material
limits: it contains no license declarations, and a local AAR is represented as
one component even when it embeds multiple native projects or proprietary
binaries. Do not use the SBOM alone as the notices list.

## Native payload requiring a reviewed notices bundle

The following entries are grounded in the pinned build inputs and the native
link graph for the staged arm64 AARs. The release archive must preserve the
exact upstream texts and revisions approved by the publisher; do not copy a
current `main`-branch notice into a pinned release.

### RunAnywhere core and llama.cpp

- `librac_commons.so` statically includes or compiles against USearch
  `v2.25.2`, nlohmann/json `3.12.0`, libarchive `3.8.7`, zlib `v1.3.2`, bzip2
  `1.0.8`, Protobuf `35.1`, Protobuf's Abseil/utf8-range dependencies, and
  RunAnywhere code. Their source license files exist in the native build tree,
  but none is copied into `runanywhere-sdk.aar`.
- `runanywhere-llamacpp.aar` is built from llama.cpp tag `b9878` and statically
  includes llama.cpp, ggml, mtmd, and llama.cpp-vendored dependencies such as
  cpp-httplib and nlohmann/json. The pinned llama.cpp license is available at
  <https://github.com/ggml-org/llama.cpp/blob/b9878/LICENSE>; it is not in the
  AAR.
- NDK `27.3.13750724` supplies `libc++_shared.so` and `libomp.so`. The installed
  NDK contains `NOTICE` and `NOTICE.toolchain`; neither is in a local AAR or the
  app's notices surface.

### ONNX and Sherpa

- The Android pins are ONNX Runtime `1.24.4` and
  `Siddhesh2377/sherpa-onnx-rac` `1.13.2`.
- The pinned ONNX Runtime tree has both a
  [project license](https://github.com/microsoft/onnxruntime/blob/v1.24.4/LICENSE)
  and a much larger
  [third-party notices file](https://github.com/microsoft/onnxruntime/blob/v1.24.4/ThirdPartyNotices.txt).
  Neither is in `runanywhere-onnx.aar`.
- The pinned Sherpa fork has an
  [upstream license file](https://github.com/Siddhesh2377/sherpa-onnx-rac/blob/v1.13.2/LICENSE),
  but the downloaded Android prebuilt directory contains no license, notice, or
  third-party-notices file. The publisher must review the fork changes and the
  transitive native payload, not only the upstream project license.

### QHexRT and Qualcomm

- `runanywhere-qhexrt.aar` contains QAIRT/QNN `2.47.0.260601` host binaries
  (`libQnnHtp*`, `libQnnSystem.so`) plus V75, V79, and V81 HTP skels. The local
  QAIRT distribution contains `LICENSE.pdf` and `NOTICE.txt`; neither is in the
  AAR.
- The publisher must confirm that its Qualcomm agreement permits Play Store
  redistribution of every included host binary and skel and must determine the
  required placement and wording of the Qualcomm license and notice materials.
  This repository cannot establish that authority.
- The QHexRT repository at the audited revision has no top-level license or
  notice file. Its compiled host library includes code identified in source as
  coming from HexagonRT, llama.cpp-derived tokenizer code, nlohmann/json `3.12.0`,
  and stb image code. QHexRT/HexagonRT ownership and redistribution authority,
  exact upstream revisions, modifications, and the selected license/attribution
  records must be documented before release.

## Models, fonts, and icons

[`MODEL_LICENSE_REVIEW.md`](MODEL_LICENSE_REVIEW.md) remains the exact model
ledger. Its current state is:

- 68 Hugging Face repositories: 21 blocked for missing/`other` license
  inspection and 47 still pending publisher review. Twenty-five are private.
- Five non-Hugging-Face downloads, all blocked until archive/model/voice terms
  and immutable SHA-256 values are recorded.
- No model weights are bundled in the APK, but the app advertises and downloads
  these entries. The publisher must approve the distribution/download flow,
  model-card terms, required attribution, gated access, and reviewer access for
  every catalog entry retained in the release.

The three bundled font files contain SIL OFL 1.1 metadata, but no full OFL text
is packaged:

| File | Embedded metadata | SHA-256 |
|---|---|---|
| `figtree.ttf` | Figtree 2.002, Figtree Project Authors | `1851150b35645dab3a4ef935a349a2d1f5373221c0d5b6993d145210766c54de` |
| `figtree_italic.ttf` | Figtree 2.002, Figtree Project Authors | `94bda60cfc0df1ae1142b01c813ef900fdc8cde11ca5bd62082dfb22ef8b2816` |
| `maple_mono.ttf` | Maple Mono 7.900, Maple Mono Project Authors | `55c21f6733c7fa93403c7acccb9d15d87c98fec20723b875e4fdd6db1619388c` |

Record the exact font source revisions and archive the matching OFL text.
`RACIcons.kt` attributes its general icon paths to Tabler, but records no exact
Tabler revision and packages no MIT notice. Pin the source revision and archive
its matching license rather than using the mutable
<https://github.com/tabler/tabler-icons/blob/main/LICENSE>.

Seven embedded brand paths—Meta, Mistral, Qwen, Hugging Face, Whisper, Liquid,
and Foundation—have no recorded source revision or license. The publisher must
approve both copyright/license provenance and trademark use, or replace/remove
the paths before publishing.

## Exact remaining external approvals

- [ ] Qualcomm/QAIRT redistribution authority and the required treatment of
  `LICENSE.pdf`, `NOTICE.txt`, the ten QNN host binaries, and three HTP skels.
- [ ] QHexRT and HexagonRT ownership/redistribution authority plus the exact
  notices for copied or modified llama.cpp, nlohmann/json, and stb code.
- [ ] A reviewed native notices bundle for RunAnywhere, llama.cpp/ggml/mtmd,
  ONNX Runtime and its third-party notices, the Sherpa fork and its transitive
  payload, USearch, libarchive, zlib, bzip2, Protobuf/Abseil/utf8-range,
  nlohmann/json, NDK libc++/OpenMP, and any additional component found by the
  final native link/SBOM review.
- [ ] Coordinate-by-coordinate review of all 106 resolved Maven runtime
  artifacts and confirmation that the final app notices surface retains every
  required text after shrinking.
- [ ] Publisher decisions for all 68 Hugging Face repositories (21 license
  inspection blockers and 47 pending reviews) and all five blocked non-Hugging-
  Face artifacts.
- [ ] Exact source/revision and OFL packaging for Figtree and Maple Mono; exact
  Tabler revision and MIT notice; copyright/license and trademark approval for
  all seven embedded brand paths.
- [ ] Final counsel/publisher sign-off on the generated SBOM, notice bundle,
  in-app/legal-page presentation, and the exact upload candidate. No item in
  this document constitutes that sign-off.
