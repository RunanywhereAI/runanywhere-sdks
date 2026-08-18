# HTTP contract (generated — do not hand-edit)

`sdk-openapi.json` is the device-facing subset of the RunAnywhere control-plane
API: the endpoint families an SDK build actually calls, plus exactly the schemas
they reference. It is generated in the backend repo by
`scripts/export_sdk_openapi.py` and copied here.

It exists because the backend repo is private and this repo is public. Rather
than the two sides maintaining parallel hand-written notions of the wire format
— which is how four spellings of `llama.cpp` and both `ios` and `iOS` ended up
in the stored telemetry — the device-facing slice is published once and both
sides generate from it.

## What it pins

The telemetry event schemas carry **closed enums** for the free-text dimensions
that used to drift:

| Field | Schema |
|---|---|
| `framework` | `TelemetryFramework` |
| `platform` | `TelemetryPlatform` |
| `sdk_binding` | `TelemetrySdkBinding` |
| `battery_state` | `TelemetryBatteryState` |

`idl/codegen/generate_telemetry_vocabulary.py` turns those into
`core/include/rac/infrastructure/telemetry/rac_telemetry_vocabulary.h`, so a
value outside the vocabulary fails here rather than being discovered at ingest.

## Updating

1. Backend repo: `cd backend && uv run python scripts/export_sdk_openapi.py`
2. Copy `backend/sdk-openapi.json` to `idl/http/sdk-openapi.json` here.
3. Regenerate: `python3 idl/codegen/generate_telemetry_vocabulary.py`
4. Commit both. CI fails if the generated header does not match the contract.
