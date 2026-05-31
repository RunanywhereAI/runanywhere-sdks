# Convenience Codegen Design — Kotlin / Dart / TypeScript Parity with Swift

PR #494 / T3.3-architect. This document specifies three new post-processors
that consume `rac_options.proto` annotations and emit Swift-equivalent
convenience helpers (`defaults()`, `validate()`, `wireString`,
`from(wireString:)`) for Kotlin (Wire), Dart (`dart-protobuf`/`protoc_plugin`),
and TypeScript (`ts-proto`). The implementation of each generator is owned
by a parallel reviewer agent in T3.3-impl; this doc is the contract those
agents build against.

## Verification stamps

Every assumption in this document was cross-checked against the live
codebase. Reviewer agents implementing T3.3-impl can rely on the
following anchors:

| Assumption                                                          | Source of truth                                                                          |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `rac_*` field numbers 50001–50012                                   | `idl/rac_options.proto:97-135`                                                            |
| Swift generator parses descriptor set via `protoc --include_imports`| `idl/codegen/generate_swift_convenience.py:678-690`                                       |
| Swift generator emits one file (`RAConvenience.swift`)              | `idl/codegen/generate_swift_convenience.py:697-700`                                       |
| Wire stamps `@RacDefaultOption("...")` on annotated fields          | `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/ai/runanywhere/proto/v1/STTOptions.kt:50, :58, :87` |
| Wire emits a `public companion object` on every message             | `sdk/runanywhere-kotlin/.../generated/ai/runanywhere/proto/v1/STTConfiguration.kt:248`    |
| Wire uses snake_case for the constructor parameter names            | `STTOptions.kt:66, :117, :140`; `STTConfiguration.kt:284-302`                             |
| Wire ships annotation classes (`RacWireStringOption.kt`, etc.)      | `sdk/runanywhere-kotlin/.../generated/ai/runanywhere/proto/v1/RacWireStringOption.kt`     |
| Dart `factory` constructor takes nullable camelCase named args      | `sdk/runanywhere-flutter/packages/runanywhere/lib/generated/stt_options.pb.dart:39-91`    |
| Dart represents `int64` via `package:fixnum/fixnum.dart` `Int64`    | `stt_options.pb.dart:15`; existing `stt_options_helpers.dart:8` consumes `Int64(...)`     |
| ts-proto first-char-lower helper rule                               | `sdk/shared/proto-ts/src/model_types.ts:47` (`audioFormatFromJSON`); `stt_options.ts:58` (`sTTLanguageFromJSON`) |
| ts-proto package root has no star re-exports                        | `sdk/shared/proto-ts/src/index.ts:5` (`export {};`)                                       |
| ts-proto uses `Long` from `"long"` for `int64`                      | `sdk/shared/proto-ts/src/stt_options.ts:8`                                                |
| ts-proto interfaces require all non-optional fields in literals     | `stt_options.ts:265-290` (`STTConfiguration`)                                             |
| `generate_ts.sh` passes `useOptionals=messages`                     | `idl/codegen/generate_ts.sh:73`                                                           |
| `generate_dart.sh` strips `ra_convenience.dart` (slot reserved)     | `idl/codegen/generate_dart.sh:119`                                                        |
| `generate_kotlin.sh` strips Wire's gRPC stubs                       | `idl/codegen/generate_kotlin.sh:87-88`                                                    |
| `SDKException.validationFailed(message)` factory (Kotlin)           | `sdk/runanywhere-kotlin/.../foundation/errors/SDKException.kt:128`                        |
| `SDKException.validationFailed(reason)` factory (Dart)              | `sdk/runanywhere-flutter/.../foundation/errors/sdk_exception.dart:260`                    |
| Hand-written Kotlin drift duplicates                                | `RAAudioFormatExtensions.kt:33-65`; `public/configuration/SDKEnvironment.kt:41-74`         |
| Hand-written Dart drift duplicates                                  | `public/extensions/stt/stt_options_helpers.dart:13-78`; `public/configuration/sdk_environment.dart:10-22` |

## 0. Background

### 0.1 The drift problem

`idl/rac_options.proto` declares 9 custom `FieldOptions` / `EnumValueOptions`
extensions (`rac_default`, `rac_required`, `rac_min`, `rac_max`,
`rac_min_float`, `rac_max_float`, `rac_display_name`, `rac_analytics_key`,
`rac_wire_string`). Swift consumes them through
`idl/codegen/generate_swift_convenience.py`, which post-processes the
proto descriptor set and emits `RAConvenience.swift` with:

| Annotation                                  | Emitted accessor                                    |
| ------------------------------------------- | --------------------------------------------------- |
| `rac_wire_string` (per enum value)          | `var wireString: String`                            |
| `rac_wire_string` (per enum value, reverse) | `static func from(wireString: String) -> Self?`     |
| `rac_display_name`                          | `var displayName: String`                           |
| `rac_analytics_key`                         | `var analyticsKey: String`                          |
| `rac_default` (per field)                   | `static func defaults() -> Self`                    |
| `rac_required` / `rac_min` / `rac_max` / `rac_min_float` / `rac_max_float` | `func validate() throws` |

Kotlin / Dart / TypeScript currently hand-write each of these helpers in
the SDK source tree — for example:

- `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/convenience/RAConvenience.kt`
  (generated `wireString` + `audioFormatFromWireString` replacing the prior
  hand-written `RAAudioFormatExtensions.kt`)
- `sdk/runanywhere-kotlin/src/main/.../public/configuration/SDKEnvironment.kt`
  (hand-written `wireString` + `sdkEnvironmentFromWireString`)
- `sdk/runanywhere-flutter/.../public/extensions/stt/stt_options_helpers.dart`
  (hand-written `STTLanguageBcp47.bcp47` + `fromBcp47`)
- `sdk/runanywhere-flutter/.../public/configuration/sdk_environment.dart`
  (hand-written `SDKEnvironmentExtension.description`)

These helpers drift over time relative to the proto annotations
(verified against `idl/model_types.proto`, `idl/stt_options.proto`,
`idl/embeddings_options.proto`). The drift surfaced as a PR #494 review
finding (T3.3): Swift has codegen, no other SDK does.

### 0.2 What Wire already does for free

Square Wire (Kotlin generator) propagates the option-extension definitions
into Kotlin source as runtime annotations
(`sdk/runanywhere-kotlin/src/main/.../v1/RacWireStringOption.kt`,
`RacDefaultOption.kt`, `RacRequiredOption.kt`, `RacMinOption.kt`, …),
and stamps every annotated field / enum constant with the corresponding
annotation:

```kotlin
@RacWireStringOption("pcm")
AUDIO_FORMAT_PCM(1),

@RacDefaultOption("STT_LANGUAGE_EN")
@field:WireField(tag = 1, …)
public val language: STTLanguage = STTLanguage.STT_LANGUAGE_UNSPECIFIED,
```

Kotlin therefore has the option payloads available at runtime via
reflection. This is **not** true for Dart (`dart-protobuf` discards
unknown FieldOptions / EnumValueOptions; the `.pb.dart` output contains
no trace of `rac_*` annotations) or for TypeScript (`ts-proto` likewise
elides them). The two non-Kotlin generators must therefore go through
the same descriptor-set path the Swift generator uses.

### 0.3 Why three new files (not one templated generator)

Each target language has fundamentally different idioms:

- Kotlin: extension functions on the message type's `Companion` and
  on enum types directly; throws subclass of `SDKException`.
- Dart: top-level functions + `extension` on the message type; throws
  `SDKException` from `foundation/errors/sdk_exception.dart`.
- TypeScript: namespaced free-function exports (no static methods on
  `interface`-shaped messages); throws an `Error` subclass.

Sharing a single generator across all three would require an opinionated
template DSL that hides the per-language quirks behind macros. The
language-specific shape is small enough (~300-500 LOC each, in line with
the Swift generator's 811 LOC) that triplicating the descriptor walk is
cheaper than building a templating layer.

The descriptor parsing, wire-format helpers, name-casing utilities, and
field-default-literal translation are however identical. Section 6
extracts them into `idl/codegen/_convenience_common.py` (a sibling
module imported by all four generators including the existing Swift one).

## 1. Generator: `generate_kotlin_convenience.py`

### 1.1 Input

1. The committed `rac_options.proto` annotations on every `.proto` file
   under `idl/`. Parsed via `protoc --descriptor_set_out=… --include_imports`
   into a `FileDescriptorSet`, identical to the Swift generator's input
   strategy. **Rationale:** even though Wire already stamps the
   annotations onto the generated Kotlin source, that path requires
   parsing `.kt` files — far slower and far more brittle than
   re-reading the descriptor set. The descriptor approach also means
   the four generators (Swift / Kotlin / Dart / TS) share the same
   descriptor-set build step (cached behind a single `protoc`
   invocation in Section 5).

2. The Wire-generated Kotlin output at
   `sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/ai/runanywhere/proto/v1/`
   for naming conformance verification only (not for parsing).
   The generator emits references to the Wire types; it does not
   import or read them at codegen time.

### 1.2 Output

Single file:
`sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/generated/convenience/RAConvenience.kt`

Single-file output (not one file per message) matches the Swift output
shape, keeps the `generated/convenience/` subtree free of `*Client.kt`
collisions with Wire's stub-stripping logic in `generate_kotlin.sh:87`,
and lets `idl-drift-check` diff exactly one file per language.

### 1.3 Output shape — per annotation

#### `rac_wire_string` on enum value

```kotlin
package com.runanywhere.sdk.generated.convenience

import ai.runanywhere.proto.v1.AudioFormat

public val AudioFormat.wireString: String
    get() = when (this) {
        AudioFormat.AUDIO_FORMAT_UNSPECIFIED -> "unspecified"
        AudioFormat.AUDIO_FORMAT_PCM -> "pcm"
        AudioFormat.AUDIO_FORMAT_WAV -> "wav"
        // …
    }

public fun AudioFormat.Companion.fromWireString(value: String): AudioFormat? =
    when (value.lowercase()) {
        "unspecified" -> AudioFormat.AUDIO_FORMAT_UNSPECIFIED
        "pcm" -> AudioFormat.AUDIO_FORMAT_PCM
        "wav" -> AudioFormat.AUDIO_FORMAT_WAV
        // …
        else -> null
    }
```

Naming choices:

- `wireString` (camelCase, matches Swift's `wireString`).
- `fromWireString` (Kotlin convention for static-style factories;
  `from(wireString:)` is Swift's argument-label idiom but doesn't
  carry over — Kotlin's call shape is `AudioFormat.fromWireString("pcm")`).
- Companion-object extension function (not a top-level `fun`) so the
  call shape exactly mirrors the proto type, not a free helper. Wire
  emits `public companion object { ... }` on every message and enum,
  so the extension binds cleanly (verified at
  `STTConfiguration.kt:248`).
- Return type is **nullable** `AudioFormat?` — matches Swift's
  `static func from(wireString:) -> Self?`. **Migration impact**: the
  existing hand-written `audioFormatFromWireString(value: String): AudioFormat`
  in `RAAudioFormatExtensions.kt:53-65` returns a non-nullable
  `AudioFormat` with `AUDIO_FORMAT_UNSPECIFIED` as the unknown-input
  fallback. T3.3-impl's per-language follow-up MUST update the two
  known callers (search `audioFormatFromWireString` under
  `sdk/runanywhere-kotlin/`) to handle the new nullable contract —
  typically `audioFormatFromWireString(s) ?: AudioFormat.AUDIO_FORMAT_UNSPECIFIED`
  to preserve the pre-IDL behavior. The same pattern applies to
  `sdkEnvironmentFromWireString` (which already returns nullable, so
  no caller change is needed for that one).

Drift retired: `RAAudioFormatExtensions.kt:33-65`, the
`sdkEnvironmentFromWireString` body in `SDKEnvironment.kt:68-74`,
and the corresponding `wireString` switches in those files.

#### `rac_display_name` / `rac_analytics_key`

Same shape as `wireString` but property-only (no reverse factory),
matching Swift's `displayName` / `analyticsKey` extensions.

#### `rac_default` on message field — `defaults()` factory

```kotlin
public fun STTConfiguration.Companion.defaults(): STTConfiguration =
    STTConfiguration(
        language = STTLanguage.STT_LANGUAGE_EN,
        sample_rate = 16000,
        enable_punctuation = true,
        enable_word_timestamps = true,
    )
```

Notes:

- Wire generates `STTConfiguration` as a `public class` with a primary
  constructor taking every field as a named parameter with a
  default value (verified in `STTOptions.kt`). The generator emits
  named-argument calls so adding a new field upstream doesn't break
  the call site.
- Wire uses `snake_case` field names in the constructor
  (`enable_punctuation`, not `enablePunctuation`). The generator
  uses the proto field name verbatim — **NOT** the camelCase form,
  which is the inverse of the Swift rule. The descriptor walk
  reuses `field.name` directly without `_proto_field_to_swift_name`.
- Companion-object extension function (Kotlin idiom). The Wire-
  generated message classes already declare a `companion object`
  block; the convenience helper extends it.

#### `rac_required` / `rac_min` / `rac_max` / `rac_min_float` / `rac_max_float` — `validate()`

```kotlin
public fun STTConfiguration.validate() {
    if (sample_rate < 8000 || sample_rate > 48000) {
        throw SDKException.validationFailed(
            "sample_rate must be in 8000...48000 (got $sample_rate)"
        )
    }
}
```

Notes:

- Extension function on the message type, not on the companion.
  Mirrors Swift's `public func validate() throws` (instance method).
- Throws `com.runanywhere.sdk.foundation.errors.SDKException` using
  the existing `validationFailed(message)` factory
  (`sdk/runanywhere-kotlin/.../foundation/errors/SDKException.kt`).
  This is the same hand-written exception the Wire-generated message
  classes ship for hand-rolled validators today.
- Kotlin does not need `throws` declarations; the generator emits a
  non-throwing function signature and lets `SDKException` propagate.
- Required-field zero check uses Kotlin's idiomatic `.isEmpty()` for
  strings; `== 0` for ints / floats; same field names as the
  proto definition.

### 1.4 Naming convention

| Construct                    | Form                                                                |
| ---------------------------- | ------------------------------------------------------------------- |
| Package                      | `com.runanywhere.sdk.generated.convenience`                         |
| File header                  | `// Code generated by idl/codegen/generate_kotlin_convenience.py.`  |
| Enum import                  | `import ai.runanywhere.proto.v1.<EnumName>`                         |
| Message import               | `import ai.runanywhere.proto.v1.<MessageName>`                      |
| Wire-string accessor         | `val <Enum>.wireString: String`                                     |
| Wire-string reverse factory  | `fun <Enum>.Companion.fromWireString(value: String): <Enum>?`       |
| `displayName` accessor       | `val <Enum>.displayName: String`                                    |
| `analyticsKey` accessor      | `val <Enum>.analyticsKey: String`                                   |
| Defaults factory             | `fun <Msg>.Companion.defaults(): <Msg>`                             |
| Validate                     | `fun <Msg>.validate()`                                              |
| `@Suppress` directives       | `@file:Suppress("FunctionName", "VariableNaming")`                  |

### 1.5 Key algorithm

```text
def main():
    fds = run_protoc_to_descriptor_set(idl/*.proto)
    blocks: list[str] = []

    for file_desc in fds.file:
        if file_desc.package != "runanywhere.v1":
            continue

        for enum_desc in file_desc.enum_type:
            for accessor in ("wireString", "displayName", "analyticsKey"):
                emit_enum_property(enum_desc, accessor)
            emit_enum_reverse_factory(enum_desc, "fromWireString",
                                      RAC_WIRE_STRING_FIELD_NUM)

        for msg_desc in file_desc.message_type:
            emit_message_defaults(msg_desc)     # rac_default
            emit_message_validate(msg_desc)     # rac_required + numeric ranges

    write_kt_file(HEADER, blocks)
```

Reuses `_convenience_common.py` (Section 6) for descriptor parsing,
wire-format readers, and default-literal translation.

## 2. Generator: `generate_dart_convenience.py`

### 2.1 Input

Same descriptor-set strategy as Kotlin. Dart's `protoc_plugin` discards
custom FieldOptions / EnumValueOptions extensions, so the generator
MUST go through the proto descriptor set — there is no in-source
annotation path to fall back on (verified by inspecting
`stt_options.pb.dart`: the `..e<STTLanguage>(2, …)` builder calls
contain no `rac_*` metadata).

### 2.2 Output

Single file:
`sdk/runanywhere-flutter/packages/runanywhere/lib/generated/convenience/ra_convenience.dart`

The path lives under `lib/generated/` so it sits alongside the
`.pb.dart` outputs. The pre-existing `rm -f "${OUT_DIR}/ra_convenience.dart"`
guard in `generate_dart.sh:119` (which strips out a now-absent legacy
file) tells us the slot is reserved exactly for this purpose. The
guard should be **removed** in T3.3-impl once the new generator emits
the canonical file — see Section 5.2.

### 2.3 Output shape — per annotation

#### `rac_wire_string` on enum value

Dart's `extension` cannot declare static methods on the underlying
type (`extension X on T { static M(...) }` puts the static on `X`,
not on `T`). The standard Dart idiom is therefore a top-level
function for the reverse factory, plus an instance extension getter
for the forward accessor:

```dart
import 'package:runanywhere/generated/model_types.pbenum.dart';

extension AudioFormatWireString on AudioFormat {
  String get wireString {
    switch (this) {
      case AudioFormat.AUDIO_FORMAT_UNSPECIFIED:
        return 'unspecified';
      case AudioFormat.AUDIO_FORMAT_PCM:
        return 'pcm';
      // …
    }
    return '';
  }
}

AudioFormat? audioFormatFromWireString(String value) {
  switch (value.toLowerCase()) {
    case 'unspecified':
      return AudioFormat.AUDIO_FORMAT_UNSPECIFIED;
    case 'pcm':
      return AudioFormat.AUDIO_FORMAT_PCM;
    // …
  }
  return null;
}
```

Naming choices:

- `<enumName>FromWireString` (camelCase top-level fn). Dart style
  guide: lowerCamelCase for top-level functions; the leading
  segment is the enum-name without prefixing.
- `extension <EnumName>WireString on <EnumName>` for the getter:
  the extension name disambiguates against the existing
  hand-written `STTLanguageBcp47` extension (which lives in a
  separate file and stays as a domain-specific helper).
- Drift retired: the hand-written
  `sdk_environment.dart:SDKEnvironmentExtension.description` switch
  (lines 11-22) becomes superfluous once `rac_display_name` is
  adopted on `SDKEnvironment` and the generated `displayName` getter
  ships. The legacy file stays for the `isProduction` /
  `defaultLogLevel` behaviour helpers, which are out of scope for
  IDL annotations.

#### `rac_default` — `defaults()` factory

```dart
extension STTConfigurationConvenience on STTConfiguration {
  static STTConfiguration defaults() {
    final r = STTConfiguration();
    r.language = STTLanguage.STT_LANGUAGE_EN;
    r.sampleRate = 16000;
    r.enablePunctuation = true;
    r.enableWordTimestamps = true;
    return r;
  }
}
```

Dart `extension` DOES allow `static` methods on the extension itself
(but not on the target type's namespace); the call shape is
`STTConfigurationConvenience.defaults()`, NOT `STTConfiguration.defaults()`.
This is a known Dart constraint with no clean workaround.

Alternative considered and rejected: top-level function
`STTConfiguration sttConfigurationDefaults()`. Rejected because the
call shape is less discoverable from `STTConfiguration` autocomplete,
and ts-proto already uses the namespaced free-function shape in
TypeScript — same shape in Dart would be too divergent.

The Dart `dart-protobuf` generator stores field accessors in **camelCase**
(`sampleRate`, not `sample_rate`), the inverse of Wire's convention.
The descriptor-walk reuses the existing
`_proto_field_to_swift_name` helper from the Swift generator (which
does proto-snake-case to lowerCamelCase) — but **without** the `Id` →
`ID` upper-case rule (Dart keeps `modelId`, `Id` stays `Id`). The
shared `_convenience_common.py` exposes both variants:
`to_camel_case(name, *, special_id_uppercase: bool = False)`.

#### `rac_required` / `rac_min` / `rac_max` — `validate()` extension

```dart
extension STTConfigurationValidate on STTConfiguration {
  void validate() {
    if (sampleRate < 8000 || sampleRate > 48000) {
      throw SDKException.validationFailed(
        'sample_rate must be in 8000...48000 (got $sampleRate)',
      );
    }
  }
}
```

Notes:

- Instance method on a dedicated `<Msg>Validate` extension. Dart
  permits multiple extensions on the same type as long as their
  names differ; the generator uses `<Msg>Convenience` for
  `defaults()` and `<Msg>Validate` for `validate()` to keep imports
  minimal (`show STTConfigurationValidate` lets a caller opt into
  just one).
- Throws `SDKException` from
  `package:runanywhere/foundation/errors/sdk_exception.dart`
  via the existing `.validationFailed(message)` factory.
- Repeated fields (`vocabulary_list: List<String>`) skip required
  checks (Dart proto-plugin returns the empty list, never null;
  required semantics are ill-defined for list/map fields and
  Swift's generator likewise skips them).

### 2.4 Naming convention

| Construct                    | Form                                                                  |
| ---------------------------- | --------------------------------------------------------------------- |
| File name                    | `ra_convenience.dart`                                                 |
| Package import               | `import 'package:runanywhere/generated/<file>.pb.dart';`              |
| Enum import                  | `import 'package:runanywhere/generated/<file>.pbenum.dart';`          |
| File header                  | `// GENERATED by idl/codegen/generate_dart_convenience.py — DO NOT EDIT.` |
| Wire-string getter           | `extension <EnumName>WireString on <EnumName> { String get wireString }` |
| Wire-string reverse factory  | `<EnumName>? <enumName>FromWireString(String value)`                  |
| Display-name getter          | `extension <EnumName>DisplayName on <EnumName> { String get displayName }` |
| Analytics-key getter         | `extension <EnumName>AnalyticsKey on <EnumName> { String get analyticsKey }` |
| Defaults factory             | `extension <Msg>Convenience on <Msg> { static <Msg> defaults() }`     |
| Validate                     | `extension <Msg>Validate on <Msg> { void validate() }`                |
| Lint suppression             | `// ignore_for_file: prefer_const_constructors, unnecessary_this`     |

### 2.5 Key constraint — Int64 / fixnum

Dart represents `int64` proto fields as `package:fixnum/fixnum.dart`
`Int64`. The `rac_default` annotation values are strings; the
default-literal translator MUST emit `Int64(16000)` for an int64
field whose `rac_default = "16000"`, not bare `16000`. The shared
`_convenience_common.py` `to_default_literal` function exposes a
`int64_wrapper: str | None` argument:

- Swift: `int64_wrapper = None` → emits `16000`.
- Kotlin: `int64_wrapper = None` → emits `16000L`.
- Dart: `int64_wrapper = "Int64"` → emits `Int64(16000)` (and adds
  `import 'package:fixnum/fixnum.dart';` to the output preamble when
  any int64 default is found).
- TypeScript: `int64_wrapper = None` → emits `Long.fromNumber(16000)`
  when ts-proto's `long` import is in play, OR `16000n` for BigInt
  mode. Section 4 picks `Long.fromNumber` because the existing
  ts-proto output uses `Long` (verified in `stt_options.ts:8`).

## 3. Generator: `generate_ts_convenience.py`

### 3.1 Input

Same descriptor-set strategy as Kotlin / Dart. ts-proto discards
`rac_*` extensions; the generator MUST go through `protoc`.

### 3.2 Output

One file per `.proto` module — NOT a single mega-file:

`sdk/shared/proto-ts/src/convenience/<base>_convenience.ts`

Rationale: ts-proto already emits one `.ts` file per `.proto` module,
and `sdk/shared/proto-ts/src/index.ts` deliberately does NOT
star-re-export anything (verified at `index.ts:5`: `export {};`) to
avoid duplicate-type ambiguity across files. A single convenience
mega-file would force every convenience helper to live in one
namespace; one file per source proto matches the existing import
shape (`import { STTConfiguration } from '@runanywhere/proto-ts/stt_options'`
pairs naturally with `import { sttConfigurationDefaults } from
'@runanywhere/proto-ts/convenience/stt_options_convenience'`).

The generator emits `convenience/<base>_convenience.ts` only when
the source proto carries at least one rac_* annotation; empty files
are skipped (no need for placeholder files because ts-proto's
no-star-export rule means a missing module is just a missing
import path, not a compile error).

### 3.3 Output shape — per annotation

ts-proto messages are TypeScript `interface`s (not classes), so static
methods aren't an option. The generator emits **namespaced free
functions** with predictable names. Verified shape of an existing
message in `stt_options.ts:265`:

```ts
export interface STTConfiguration {
  modelId: string;
  language: STTLanguage;
  sampleRate: number;
  // …
}
```

#### `rac_wire_string` on enum value

```ts
import { AudioFormat } from '../model_types';

export const audioFormatWireString = (e: AudioFormat): string => {
  switch (e) {
    case AudioFormat.AUDIO_FORMAT_UNSPECIFIED:
      return 'unspecified';
    case AudioFormat.AUDIO_FORMAT_PCM:
      return 'pcm';
    // …
    default:
      return '';
  }
};

export const audioFormatFromWireString = (s: string): AudioFormat | undefined => {
  switch (s.toLowerCase()) {
    case 'unspecified':
      return AudioFormat.AUDIO_FORMAT_UNSPECIFIED;
    case 'pcm':
      return AudioFormat.AUDIO_FORMAT_PCM;
    // …
    default:
      return undefined;
  }
};
```

Naming choices:

- `<enumName>WireString(e)` — pure function, no `this` ceremony.
  Matches ts-proto's existing `audioFormatToJSON(object)` / `audioFormatFromJSON(object)`
  shape exactly (verified `model_types.ts:86`, `:47`). The generator
  uses the same lowerCamelCase form ts-proto picks for the enum name
  ts-proto's choice of `audioFormat` from `AudioFormat` is deterministic;
  see Section 6.3 for the helper that mirrors the rule (first
  character lowercased, rest preserved).
- `<enumName>FromWireString(s)` — returns `undefined` (not `null`)
  to match ts-proto's idiomatic optional return.
- Drift retired: any hand-written wireString switches in
  `sdk/runanywhere-web/` and `sdk/runanywhere-react-native/` (none
  found at audit time — see Section 7).

#### `rac_default` — defaults factory

```ts
import { STTConfiguration } from '../stt_options';
import { STTLanguage } from '../stt_options';

export const sttConfigurationDefaults = (): STTConfiguration => ({
  modelId: '',
  language: STTLanguage.STT_LANGUAGE_EN,
  sampleRate: 16000,
  enableVad: false,
  audioFormat: AudioFormat.AUDIO_FORMAT_UNSPECIFIED,
  enablePunctuation: true,
  enableDiarization: false,
  vocabularyList: [],
  maxAlternatives: 0,
  enableWordTimestamps: true,
  // … all fields present so the literal satisfies the interface
});
```

Notes:

- TS-interface literals require EVERY non-optional field to be present
  (verified `stt_options.ts:265-290` — only `preferredFramework` and
  `languageCode` are `?`-optional). The generator therefore initialises
  unspecified fields to their proto3 zero values (`""` for string,
  `0` for number, `false` for bool, `[]` for repeated, the enum's
  `_UNSPECIFIED = 0` constant for enums) — same default-zero rule the
  Swift generator's `var r = RAEmbeddingsConfiguration()` initialiser
  applies under the hood via `swift-protobuf`'s synthesized init.
- The `useOptionals=messages` flag (passed at `generate_ts.sh:73`)
  makes **nested message-typed** fields `?`-optional; scalars
  (string / number / bool), repeateds, and enums remain required in
  the interface. The defaults factory must therefore initialise every
  scalar / repeated / enum field (zero values) and may omit nested
  message fields (TypeScript treats absent `?` properties as
  `undefined`). Proto `optional` scalars (e.g. `language_code`) are
  also `?` and follow the same omit rule.
- `int64` fields use `Long.fromNumber(N)` to match ts-proto's
  `Long` import. The generator emits `import Long from 'long';` when
  any int64 default appears (verified `stt_options.ts:8`).
- Optional fields (`?`) are emitted only if `rac_default` is set on
  them; otherwise omitted (TypeScript treats absent properties as
  the same as `undefined` for `?`-typed slots).

#### `rac_required` / `rac_min` / `rac_max` — `validate`

```ts
export const validateSTTConfiguration = (m: STTConfiguration): void => {
  if (m.sampleRate < 8000 || m.sampleRate > 48000) {
    throw new ValidationError(
      `sample_rate must be in 8000...48000 (got ${m.sampleRate})`,
    );
  }
};
```

Notes:

- Function name `validate<MessageName>` (PascalCase suffix); matches
  the existing TS naming idiom in `audioFormatFromJSON` / similar
  generated helpers.
- Returns `void`; throws `ValidationError` from
  `@runanywhere/proto-ts/convenience/_errors` (a small new file
  shipped alongside the first convenience module; see Section 6.4).
  Both Web and RN SDKs already catch generic `Error` subclasses for
  validation failures.
- For required string/number fields, the zero-check uses the
  TypeScript-idiomatic `m.<field> === '' || m.<field> === 0` form
  (same semantics as Swift's `.isEmpty` / `== 0`).

### 3.4 Naming convention

| Construct                       | Form                                                                |
| ------------------------------- | ------------------------------------------------------------------- |
| File name                       | `<base>_convenience.ts` (one per source proto with annotations)     |
| File header                     | `// GENERATED by idl/codegen/generate_ts_convenience.py — DO NOT EDIT.` |
| Re-import message               | `import { <Msg> } from '../<base>';`                                |
| Re-import enum                  | `import { <Enum> } from '../<base>';`                               |
| Wire-string accessor (function) | `export const <enumName>WireString = (e: <Enum>): string => { … };` |
| Wire-string reverse factory     | `export const <enumName>FromWireString = (s: string): <Enum> \| undefined => { … };` |
| Display-name accessor           | `export const <enumName>DisplayName = (e: <Enum>): string => { … };` |
| Analytics-key accessor          | `export const <enumName>AnalyticsKey = (e: <Enum>): string => { … };` |
| Defaults factory                | `export const <msgName>Defaults = (): <Msg> => ({ … });`            |
| Validate                        | `export const validate<Msg> = (m: <Msg>): void => { … };`           |
| Lint suppression                | `/* eslint-disable */` (matches ts-proto's own output)              |
| Shared `ValidationError`        | `convenience/_errors.ts` — `export class ValidationError extends Error {}` |

### 3.5 ts-proto naming subtleties

ts-proto's first-character-lowercased rule:

| Proto type                | ts-proto symbol           | Helper exported              |
| ------------------------- | ------------------------- | ---------------------------- |
| `enum AudioFormat`        | `AudioFormat`             | `audioFormatWireString`      |
| `enum SDKEnvironment`     | `SDKEnvironment`          | `sDKEnvironmentWireString`   |
| `enum STTLanguage`        | `STTLanguage`             | `sTTLanguageWireString`      |
| `message STTConfiguration`| `STTConfiguration`        | `sTTConfigurationDefaults`   |
| `message RAGConfiguration`| `RAGConfiguration`        | `rAGConfigurationDefaults`   |

Verified against the existing `sTTLanguageFromJSON` / `sTTLanguageToJSON`
emitted by ts-proto for `STTLanguage` (`stt_options.ts:58, :109`). The
ALL-CAPS prefix is preserved verbatim; only the very first character
flips. The shared `_convenience_common.py` exposes
`ts_proto_function_prefix(name)` implementing exactly this rule.

## 4. Field-type → default-literal translation

`_convenience_common.py.to_default_literal(field, default_str, lang)`
translates a proto field's `rac_default` string into a language-native
literal. Reuses the Swift generator's existing logic with one switch
arm per language.

| Proto type                         | Swift                    | Kotlin                            | Dart                                          | TypeScript                                  |
| ---------------------------------- | ------------------------ | --------------------------------- | --------------------------------------------- | ------------------------------------------- |
| `string "auto"`                    | `"auto"`                 | `"auto"`                          | `'auto'`                                      | `'auto'`                                    |
| `bool "true"`                      | `true`                   | `true`                            | `true`                                        | `true`                                      |
| `int32 "3"`                        | `3`                      | `3`                               | `3`                                           | `3`                                         |
| `int64 "16000"`                    | `16000`                  | `16000L`                          | `Int64(16000)`                                | `Long.fromNumber(16000)`                    |
| `float "0.7"`                      | `0.7`                    | `0.7f`                            | `0.7`                                         | `0.7`                                       |
| `double "0.7"`                     | `0.7`                    | `0.7`                             | `0.7`                                         | `0.7`                                       |
| `enum STT_LANGUAGE_EN`             | `.en`                    | `STTLanguage.STT_LANGUAGE_EN`     | `STTLanguage.STT_LANGUAGE_EN`                 | `STTLanguage.STT_LANGUAGE_EN`               |
| `enum unknown`                     | skip                     | skip                              | skip                                          | skip                                        |

Implementation note: the existing
`_build_enum_swift_case_map(fds)` in `generate_swift_convenience.py`
becomes `_build_enum_case_map(fds, lang)` in the shared module, with
per-language case translation (Swift uses `.<camelCase>`; Kotlin,
Dart, TS all keep the proto SCREAMING_SNAKE name as the source-of-truth
case identifier on the generated enum).

## 5. Integration with `generate_all.sh`

### 5.1 New invocation lines

After each language's existing message-codegen step:

```bash
# generate_all.sh — additions at the bottom of each block

echo "▶ Kotlin proto codegen"
"${SCRIPT_DIR}/generate_kotlin.sh"
if command -v python3 >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/generate_kotlin_convenience.py"
fi

if [ "${SKIP_DART}" -eq 1 ]; then
    echo "▶ Dart proto codegen (skipped via --skip-dart)"
else
    echo "▶ Dart proto codegen"
    "${SCRIPT_DIR}/generate_dart.sh"
    if command -v python3 >/dev/null 2>&1; then
        python3 "${SCRIPT_DIR}/generate_dart_convenience.py"
    fi
fi

echo "▶ TypeScript proto codegen (RN + Web)"
"${SCRIPT_DIR}/generate_ts.sh"
if command -v python3 >/dev/null 2>&1; then
    python3 "${SCRIPT_DIR}/generate_ts_convenience.py"
fi
```

The post-processor is invoked AFTER the language's primary codegen so
that the message / enum type names referenced by the convenience file
are already on disk and provably exist (mirrors the Swift pattern in
`generate_swift.sh:91-96`).

Each post-processor exits 0 (warning to stderr) when `python3` is
missing OR when `protoc` cannot build a descriptor set, so a Dart-only
or Kotlin-only developer environment that omits Python still completes
the upstream codegen successfully — same tolerance the existing
Swift generator already implements.

### 5.2 Cleanup actions for `generate_dart.sh`

`generate_dart.sh:119` currently runs `rm -f "${OUT_DIR}"/ra_convenience.dart`
to strip a phantom legacy artifact. T3.3-impl MUST DELETE that line
when `generate_dart_convenience.py` lands; the new generator owns
the slot and the file should NOT be stripped after emission.

### 5.3 Drift CI gate (`ci-drift-check.sh`)

No change needed. `ci-drift-check.sh` re-runs `generate_all.sh` and
then `git diff --exit-code`. Adding new generated files to the tree
automatically participates in the drift gate; the first time the
convenience files land, they are committed once, and any subsequent
out-of-sync state in those files breaks CI exactly as it does for the
Swift convenience file today.

### 5.4 Setup-toolchain note

`scripts/setup/setup-toolchain.sh` already installs Python 3 + the
`protobuf` Python package (required by `generate_swift_convenience.py`
and `generate_swift_modality_abi.py`). No new toolchain dependency is
introduced by the three new generators — they reuse the same
`google.protobuf.descriptor_pb2` import.

## 6. Shared module — `idl/codegen/_convenience_common.py`

Centralizes the descriptor-walk + wire-format helpers currently
duplicated inside `generate_swift_convenience.py`. T3.3-impl extracts
these so all four generators (existing Swift + three new) consume
them, eliminating divergence drift in the codegen itself.

### 6.1 Surface

```python
# _convenience_common.py — public API

# --- Annotation field numbers (mirror idl/rac_options.proto) ------------
RAC_DEFAULT_FIELD_NUM       = 50001
RAC_REQUIRED_FIELD_NUM      = 50002
RAC_MIN_FIELD_NUM           = 50004
RAC_MAX_FIELD_NUM           = 50005
RAC_MIN_FLOAT_FIELD_NUM     = 50006
RAC_MAX_FLOAT_FIELD_NUM     = 50007
RAC_DISPLAY_NAME_FIELD_NUM  = 50010
RAC_ANALYTICS_KEY_FIELD_NUM = 50011
RAC_WIRE_STRING_FIELD_NUM   = 50012

# --- Proto wire-format type enums (used by callers building defaults) ---
TYPE_DOUBLE   = 1
TYPE_FLOAT    = 2
TYPE_INT64    = 3
# … all 18 proto wire-types as in the Swift generator today

_INTEGER_TYPES = frozenset(...)
_FLOAT_TYPES   = frozenset(...)

# --- Descriptor build (one protoc invocation per CI run) ----------------
def build_descriptor_set(idl_dir: Path) -> FileDescriptorSet: ...

# --- Annotation extraction (works without compiled extension registry) --
def get_string_option(opts, field_num: int) -> str | None: ...
def get_bool_option(opts, field_num: int) -> bool | None: ...
def get_int32_option(opts, field_num: int) -> int | None: ...
def get_double_option(opts, field_num: int) -> float | None: ...

# --- Annotation walks ---------------------------------------------------
def iter_runanywhere_files(fds): ...
def iter_top_level_enums(file_desc): ...
def iter_top_level_messages(file_desc): ...

# --- Default-literal translation ----------------------------------------
class LangProfile(TypedDict):
    int64_wrapper: str | None     # None | "Int64" | "Long.fromNumber"
    int32_suffix:  str            # "" | "" | "" | ""
    int64_suffix:  str            # "" | "L"
    float_suffix:  str            # "" | "f"
    enum_form: Literal["swift_dot", "kotlin_dot", "dart_dot", "ts_dot"]

def to_default_literal(field, default_str, enum_case_map, profile) -> str | None: ...

# --- Naming utilities ---------------------------------------------------
def proto_field_to_camel(name: str, *, id_uppercase: bool = False) -> str: ...
def ts_proto_function_prefix(symbol: str) -> str:
    """First char lowercased, rest preserved (`STTLanguage` → `sTTLanguage`)."""
def swift_enum_case(enum_name: str, value_name: str) -> str: ...
```

### 6.2 Migration plan

T3.3-impl extracts the helpers in this order, in ONE migration commit:

1. Move the body of `generate_swift_convenience.py`'s helpers
   (`_camel_case_from_snake`, `_swift_case_name`, `_get_uninterpreted_*`,
   `_read_varint`, `_scan_fields`, `_decode_*_field`,
   `_build_enum_swift_case_map`, `_build_descriptor_set`) into
   `_convenience_common.py`.
2. Replace the moved helpers in `generate_swift_convenience.py` with
   `from _convenience_common import …`.
3. Verify the Swift convenience output is **byte-identical**
   pre- vs post-extraction via `ci-drift-check.sh`.
4. Add `generate_kotlin_convenience.py` / `generate_dart_convenience.py` /
   `generate_ts_convenience.py` consuming the shared module.

This sequencing ensures the Swift generator never has a window where
it produces different output than today (the CI drift gate is the
contract that keeps the migration honest).

### 6.3 ts-proto first-char-lowercased rule

```python
def ts_proto_function_prefix(symbol: str) -> str:
    if not symbol:
        return symbol
    return symbol[0].lower() + symbol[1:]
```

Verification: `STTLanguage` → `sTTLanguage` (matches
`stt_options.ts:58`), `AudioFormat` → `audioFormat` (matches
`model_types.ts:47`), `RAGConfiguration` → `rAGConfiguration`.

### 6.4 Shared TS `ValidationError`

```ts
// sdk/shared/proto-ts/src/convenience/_errors.ts
export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ValidationError';
  }
}
```

Hand-checked-in (not generated). T3.3-impl creates this once; the
generators emit `import { ValidationError } from './_errors';`
relative to each `<base>_convenience.ts`.

## 7. Drift inventory — what gets retired per generator

T3.3-impl SHOULD NOT delete hand-written helpers in the same PR as
the generator landings. The land-then-migrate flow keeps blast
radius small: the generator lands first, the new generated helpers
are validated against the hand-written ones for parity, then the
duplicate hand-written helpers are deleted in a follow-up.

### 7.1 Kotlin — confirmed duplicates

| Hand-written file                                                                                      | Helper        | Annotation backing  |
| ------------------------------------------------------------------------------------------------------ | ------------- | ------------------- |
| `sdk/runanywhere-kotlin/src/main/.../RAAudioFormatExtensions.kt` (retired; superseded by generated `RAConvenience.kt`) | `wireString`, `audioFormatFromWireString` | `rac_wire_string` on `AudioFormat`     |
| `sdk/runanywhere-kotlin/src/main/.../public/configuration/SDKEnvironment.kt:41-74`                     | `wireString`, `sdkEnvironmentFromWireString` | `rac_wire_string` on `SDKEnvironment` |

### 7.2 Dart — confirmed duplicates

| Hand-written file                                                              | Helper                                           | Annotation backing                            |
| ------------------------------------------------------------------------------ | ------------------------------------------------ | --------------------------------------------- |
| `sdk/runanywhere-flutter/.../public/extensions/stt/stt_options_helpers.dart:13-78` | `STTLanguageBcp47.bcp47` / `fromBcp47`           | `rac_wire_string` on `STTLanguage` (the BCP-47 codes ARE the wire strings) |
| `sdk/runanywhere-flutter/.../public/configuration/sdk_environment.dart:11-22`  | `SDKEnvironmentExtension.description`            | `rac_display_name` on `SDKEnvironment` (TODO: add to proto) |

### 7.3 TypeScript — none found at audit time

No hand-written `wireString` / `defaults()` / `validate()` shims
located in `sdk/runanywhere-web/` or `sdk/runanywhere-react-native/`
during the audit (Grep across `case AudioFormat.AUDIO_FORMAT_*` and
`case SDKEnvironment.SDK_ENVIRONMENT_*` returned 0 SDK-side hits).
The TypeScript drift target is forward-looking: once the generator
lands, new RN / Web facades can rely on the generated helpers
instead of hand-rolling them.

## 8. Build-sequence checklist (T3.3-impl)

Execute in this order. Each step is a single commit; do NOT
combine multiple steps.

- [ ] **Step 1**: Extract `_convenience_common.py` from
      `generate_swift_convenience.py`. Confirm `RAConvenience.swift`
      is byte-identical before and after via `ci-drift-check.sh`.
- [ ] **Step 2**: Add `generate_kotlin_convenience.py`. Wire into
      `generate_all.sh`. Commit the first emitted
      `RAConvenience.kt` so subsequent runs no-op.
- [ ] **Step 3**: Add `generate_dart_convenience.py`. Wire into
      `generate_all.sh`. **Delete** the
      `rm -f "${OUT_DIR}"/ra_convenience.dart` line from
      `generate_dart.sh`. Commit the first emitted
      `ra_convenience.dart`.
- [ ] **Step 4**: Add `convenience/_errors.ts` (hand-written) and
      `generate_ts_convenience.py`. Wire into `generate_all.sh`.
      Commit the first emitted `<base>_convenience.ts` files.
- [ ] **Step 5**: Validate each generated convenience helper produces
      the same string mappings / default values / validation errors as
      the hand-written equivalent in Section 7. Use unit tests in
      `sdk/<lang>/.../convenience-parity-test/`.
- [ ] **Step 6**: Land per-language follow-up PRs that DELETE the
      hand-written drift duplicates from Section 7 and reroute call
      sites onto the generated helpers.

## 9. Critical considerations

### 9.1 Error handling

**Canonical shape (cross-SDK contract)**:

```
{
  code:      'invalid_argument',
  category:  'validation',
  fieldPath: '<MessageName>.<field_name>',   // e.g. 'STTOptions.sampleRate'
  message:   '<human-readable description>'
}
```

All four convenience generators emit this shape. The four exception types
are byte-isomorphic via the proto `SDKError`:

* `code` ↔ `SDKError.code` (`ERROR_CODE_INVALID_ARGUMENT` / the TS string
  discriminant `'invalid_argument'`)
* `category` ↔ `SDKError.category` (`ERROR_CATEGORY_VALIDATION` / the TS
  string discriminant `'validation'`)
* `fieldPath` ↔ `SDKError.context.metadata["field_path"]` (Swift /
  Kotlin / Dart) or top-level property (TS)
* `message` ↔ `SDKError.message`

Cross-platform consumer code (the React Native ↔ shared validation
layer, streaming-perf parity tests) can rely on the same discriminants
on every platform:

```ts
if (e instanceof ValidationError && e.code === 'invalid_argument') {
  console.error('Validation failed for', e.fieldPath, ':', e.message);
}
```
```kotlin
if (e is SDKException && e.fieldPath != null) { ... }
```

| Language   | Exception type / shape                                                                                   | Origin                                                                |
| ---------- | -------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Swift      | `SDKException.validationFailed(fieldPath:message:)` → exposes `.code`, `.category`, `.fieldPath`, `.message` | `sdk/runanywhere-swift/.../SDKException.swift`                        |
| Kotlin     | `SDKException.validationFailed(fieldPath, message)` → exposes `.code`, `.category`, `.fieldPath`, `.message` | `sdk/runanywhere-kotlin/.../foundation/errors/SDKException.kt`        |
| Dart       | `SDKException.validationFailed(message, fieldPath: ...)` → exposes `.code`, `.category`, `.fieldPath`, `.message` | `sdk/runanywhere-flutter/.../foundation/errors/sdk_exception.dart`    |
| TypeScript | `new ValidationError({fieldPath, message})` → exposes `.code`, `.category`, `.fieldPath`, `.message`     | `sdk/shared/proto-ts/src/convenience/_errors.ts` (hand-written)       |

### 9.2 Wire-format / runtime constraints

- **Kotlin / Wire**: messages have `Companion` objects; companion-object
  extension functions are first-class. No reflection needed at runtime.
- **Dart / dart-protobuf**: messages extend `$pb.GeneratedMessage`; the
  `factory STTConfiguration({...})` constructor accepts named args
  with `null` defaults. `defaults()` uses the no-arg `create()` factory
  and mutates fields one at a time (mirrors Swift's `var r = ...; r.x = ...`).
- **TypeScript / ts-proto**: messages are TS `interface`s; defaults
  are constructed via object-literal expressions. Every non-optional
  field must be initialised in the literal.

### 9.3 Codegen testability

The generators are unit-testable in isolation by feeding them
synthesized `FileDescriptorSet` protos. T3.3-impl SHOULD add
Python unit tests at `idl/codegen/tests/test_convenience_kotlin.py`,
`test_convenience_dart.py`, `test_convenience_ts.py` exercising:

- Empty proto file (no annotations) → empty output.
- One enum with three `rac_wire_string` values → 3-case switch.
- One message with a mix of `rac_default` + `rac_min` + `rac_max` →
  defaults factory + validate fn with the expected literals / range checks.
- Edge cases: int64 default (Int64 wrapper / Long), enum default,
  required string + required int field, message with annotated +
  non-annotated fields (annotated subset only in defaults).

The Swift generator currently has zero unit tests (the drift gate is
its only test); landing tests as part of T3.3-impl ALSO gives us the
first regression net for `generate_swift_convenience.py` via the
shared module.

### 9.4 Performance

Each generator runs in <2s on the current 30-file IDL set. `protoc`
spawn dominates; the descriptor walk is O(annotations) ≈ 200 today.
No optimisation needed.

### 9.5 Security

Generated files are pure code (no eval, no dynamic imports), readable
by humans, committed to git, gated by drift CI. The descriptor-set
input is the committed `.proto` files only. No additional security
surface.

## 10. Out-of-scope (deferred)

- Nested enums / nested messages (Swift generator currently emits
  top-level only; the three new generators mirror that choice — see
  `_collect_top_level_enums` comment in `generate_swift_convenience.py:341`).
  Promoting nested types is a follow-up tracked separately.
- `rac_pattern` / `rac_alias` annotations (reserved field numbers in
  `rac_options.proto:42` but not yet declared). Generators ignore
  unknown field numbers as today.
- Cross-message field references (e.g. `STTOptions.language` inheriting
  the default from `STTConfiguration.language`). Each message stands alone.
- Auto-routing the deleted hand-written helpers' call sites. T3.3-impl
  ships the generators; SDK migration to consume them is per-language
  follow-up work.

---

**Owner**: T3.3-impl (3 parallel reviewer agents — one per language).
**Reviewer**: codegen owner. **Gate**: `idl/codegen/ci-drift-check.sh`
must pass after generators land and after the first committed
generated output ships.
