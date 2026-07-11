# Shared QHexRT Android model catalog

QHexRT owns Qualcomm-specific SoC detection, the v75/v79/v81 support policy,
and per-model chip selection. `runanywhere-commons` remains backend-neutral and
provides the registry, HTTP, Hugging Face folder resolver, download, extraction,
validation, and local-path primitives used after QHexRT selects a definition.

## Ownership boundary

| Concern | Owner |
|---|---|
| Model id, display metadata, remote URL, validated architecture list | Example app |
| Snapdragon/Hexagon probe and v75/v79/v81 support set | QHexRT engine |
| Definition eligibility and logical URL -> device folder | QHexRT engine |
| Bundle manifest predicate and QNN context format | QHexRT bundle policy |
| Registry, HF tree enumeration, sizes/checksums, executable rejection | Commons |
| Download/resume/extract/expected-file validation | Commons |
| Canonical local primary/companion path resolution | Commons lifecycle |

The public header is `include/rac/qhexrt/rac_qhexrt.h`. The catalog facade
reuses serialized `runanywhere.v1.RegisterModelFromUrlRequest` bytes; it does
not introduce another schema or embed product URLs in native code.

```c
const rac_qhexrt_hexagon_arch_t arches[] = {
    RAC_QHEXRT_HEXAGON_ARCH_V75,
    RAC_QHEXRT_HEXAGON_ARCH_V81,
};

rac_proto_buffer_t saved;
rac_proto_buffer_init(&saved);
rac_bool_t registered = RAC_FALSE;
rac_result_t rc = rac_qhexrt_register_model_for_device_proto(
    request_bytes, request_size, arches, 2, &registered, &saved);
rac_proto_buffer_free(&saved);
```

Malformed definitions fail closed. A definition requires a stable id, the
QHEXRT framework, a URL, and a non-empty subset of v75/v79/v81. An unsupported
or ineligible device is a normal skip: `RAC_SUCCESS`, `registered=false`, and
an empty success buffer.

For a logical HNPU ref, QHexRT inserts the detected architecture before calling
commons:

- `.../org/repo` -> `.../org/repo/v81`
- `.../org/repo/model.json` -> `.../org/repo/v81/model.json`

Already pinned refs must match the detected device. Concrete `/resolve/` and
`/blob/` refs remain explicit.

Once a definition is registered, the normal lifecycle API owns the rest. A
`ModelLoadRequest` with `validate_availability=true` drives the existing native
plan -> download -> extract -> validate -> registry update -> local-path
resolution sequence.

## Binding migration checklist

- [x] Kotlin QHexRT JNI/facade passes generated request bytes and generated
  `HexagonArch` values to the engine API.
- [x] Flutter QHexRT FFI/facade exposes the same catalog operation.
- [x] React Native QHexRT Nitro facade exposes the same catalog operation.
- [x] Stage this public header with QHexRT Android packages.
- [x] Add Kotlin, Flutter, and React Native wire-contract tests for the shared
  enum numbers and serialized registration request.
- [ ] Kotlin example: retain rows/URLs only; call the QHexRT facade for NPU rows
  and remove app-side probe/filter logic.
- [ ] Flutter Android example: sync the authoritative model definitions and
  validated generated `HexagonArch` sets, call `registerModelForDevice`, and
  expose only rows the native facade registers.
- [ ] React Native Android example: perform the same catalog sync and facade
  migration; its current `NpuBundle` rows do not yet carry architecture sets.
- [x] Add a hardware-free Flutter FFI integration smoke that crosses the SDK
  wrapper into the exported native registration symbol. Keep an Android-device
  smoke in the release workflow for packaged-library validation.

Native evidence:

- `test_qhexrt_model_catalog`: support matrix, intersection semantics,
  ineligible no-mutation, app metadata round-trip, and logical V81 HF selection.
- Flutter `qhexrt_catalog_wire_test`: real host dylib wrapper-to-C-ABI
  registration, including the normal unsupported-host skip mapping.
- Commons `test_register_model_from_url` and `test_hf_resolver_folder`: normalized
  registration, full folder enumeration, checksums, and executable-code denial.
- Commons download/extraction/model-path/lifecycle tests: shared downstream
  orchestration and path validation.
