# Segmentation confidence and ABI 14

Confidence is optional: the SDK's existing `includeConfidence` / `include_confidence`
option requests one byte per source pixel in row-major order. Each byte is the
winning class's softmax probability after logit resizing, rounded to 0–255.
The default path skips confidence allocation and probability calculations.

The plugin API remains 14. The original segmentation options, results, service
struct, operation table, result cleanup function, engine manifest and engine
vtable retain their original layouts. The private-engine pins and receipt checks
are unchanged. Existing ABI-14 engines continue to serve their existing operations.

## Optional engine interface

`rac/features/segmentation/rac_segmentation_confidence.h` declares a separate
V1 confidence output, operation table and manifest wrapper. Engine capability
bit 40 (`RAC_ENGINE_CAP_SEGMENTATION_CONFIDENCE_V1`) reserves this wrapper contract:
both the legacy manifest and the engine metadata advertise the bit, and the
unchanged manifest is the wrapper's first member. Unknown flags are ignored by
older hosts. Engines must keep their original segmentation callback and must
not import newly added host symbols in order to support older ABI-14 hosts.

A new host checks the flag before reading the wrapper, then checks its size,
version and optional operation table. Missing support returns
`RAC_ERROR_NOT_SUPPORTED`; malformed advertised interfaces return
`RAC_ERROR_INVALID_PARAMETER`. Neither case silently retries on another engine.

`rac_segmentation_segment_with_confidence` accepts the original image/options
and result plus an independently initialized `rac_segmentation_confidence_mask_v1_t`.
Release the two outputs separately with `rac_segmentation_result_free` and
`rac_segmentation_confidence_mask_free`. The confidence buffer must be empty on
entry. Inference errors and invalid payloads release and reset both outputs.
Legacy result cleanup never reads any additional fields.

The new host pins the exact selected engine while a segmentation model exists,
including on the registry lifecycle path. Unregister, unload or replacement of
that engine returns `RAC_ERROR_PLUGIN_BUSY` until its models are destroyed; the
library mapping and its callbacks remain valid. Inference never discovers a
different provider after the model has been created.

## Build and validation scope

Core, ONNX and SDK native bridges must be built to expose the new operation.
Existing unrelated ABI-14 private-engine archives do not require an ABI rebuild
for this extension. Their normal platform integration and receipt checks still
apply. An old host can use the new ONNX engine's original segmentation operation;
an old ONNX engine on a new host supports ordinary segmentation and explicitly
rejects confidence requests.

Cross-version binaries, direct and lifecycle inference, malformed headers and
payloads, cleanup, engine unload/replacement and static/dynamic linking all need
validation. Platform builds and private archive integration remain separate
from source-layout or local bridge checks.
