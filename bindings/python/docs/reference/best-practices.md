# Python SDK — best practices checklist

Adapted from `thoughts/shared/plans/BEST_PRACTISES.md` for this package. This is the bar for
review on every change; `../../AGENTS.md` states the handful of invariants that apply to
almost every task, this file is the fuller checklist.

### Ownership and layering

(See the repo-root `AGENTS.md` "Business logic layering rules" for the cross-SDK version of
this — commons owns truth, the SDK layer owns platform I/O and composition. Python-specific
applications of it:)

- The Python layer owns: platform adapter I/O, pybind11 bridging, host download/catalog,
  streaming fan-out (`_streaming.py`), the composition the spec puts behind one verb
  (messages, grammar, the tool loop), the CLI/server, and honesty in docs/API surface.
- Keep routers/handlers thin. `runanywhere/server/` and `runanywhere/cli/` are adaptation
  over the namespaces — no new AI business logic in a FastAPI route or a CLI handler. If a
  command needs multi-step orchestration, push it into the namespace or into commons.
- One verb per job. `llm.generate` loads and downloads what it needs; never make a caller
  assemble register → download → load themselves.

### Typed contracts at every boundary

- Public options/results are dataclasses or IntEnums — never raw string status codes.
- Native error codes come from `idl/errors.proto` / `rac_error.h`. Keep `ErrorCode` /
  `ErrorCategory` exhaustive relative to the IDL and map categories with
  `category_for_code` as a faithful port of commons `rac_result_to_proto_category`
  (AUTH is only 320–329; unmapped failures → INTERNAL, not UNSPECIFIED).
- Registry framework/category ints are **C ABI enums** (`RAC_FRAMEWORK_*`,
  `RAC_MODEL_CATEGORY_*`), not proto wire values. Name them and pin them in tests.
- Generated RAG protos live in `runanywhere/_proto/`; regenerate via
  `idl/codegen/generate_python.sh` (wired into `generate_all.sh`). Never hand-edit
  `_pb2.py`.
- Keep `_native/_core.pyi` in lockstep with `native/module.cpp` bindings.

### Honesty and readiness

- Document what is actually true today. Do not claim encryption, remote auth, or NPU
  support that is not wired.
  - Secure store: DPAPI on Windows; **plaintext mode-0600 files on POSIX**.
  - `initialize` runs the control plane only with credentials: authenticate + telemetry flush
    over a stdlib-`urllib` transport (no libcurl). Keyless, it does no network work;
    `api_key`/`base_url` map to that handshake. The HTTP server's optional Bearer `api_key`
    is a separate thing, configured on `serve()` / the CLI.
  - Desktop wheels report CPU backends (llamacpp/onnx/sherpa). QHexRT/Windows Snapdragon
    HNPU is not available until packaging and runtime exist.
- A verb the bridge cannot serve raises `not_implemented` naming the exact missing `rac_*`
  symbols. Never return a plausible empty result instead.
- If a capability cannot be done properly (missing HTTP transport, lifecycle migration),
  document it as deferred — do not stub or mock it into the public surface.

### Concurrency and native safety

- Every modality unload that can race an in-flight op uses `take_handle_when_idle`
  (including VAD). Blocking ops take `begin_op` / `OpScope` leases.
- Stream teardown must set the stop `Event` **and** call component cancel
  (`cancel_generate` / `cancel_generate_vlm`) via `_streaming.on_stop` so decode stops
  promptly, not only on the next token callback.
- One in-flight generation per model handle (`_GenerationGuard`); a second concurrent
  generate is a programming error → `invalid_state`, not a silent queue.
- Win32 file sizing uses `_fseeki64` / `_ftelli64` (plain `ftell`/`long` truncates >2GB).
- Secure-store keys must reject path separators / `..` / absolute paths (`secure_key_ok`
  + Python `_validate_secure_key`).

### Errors and observability

- Raise `SDKException` only on the public surface; map I/O/download failures to
  `STORAGE_ERROR` (or the correct category), not `GENERATION_FAILED`.
- Prefer factories (`storage_error`, `model_load_failed`, …) so code/category stay
  consistent.
- Never log secrets, secure-store values, or signed URLs alongside destination paths.
- EventBus listeners must not break emit — failures are swallowed/logged, not re-raised
  into the lifecycle path.

### Testing

- Hermetic by default: `FakeCore` / no network / no real keys / no models required for
  the unit suite.
- Pin ABI and category tables with tests so silent drift fails CI.
- CI builds a wheel, repairs it, installs into a clean env, and runs pytest from a
  relocated `tests/` dir — local verification should match that shape when touching
  packaging.
- Support the claimed Python range (3.9+); Linux CI matrices both 3.9 and 3.12.

### Security basics

- Validate all external inputs (URLs, archive members, secure keys, model ids).
- SSRF: connect-by-IP, no open redirects on host download paths.
- Do not require cloud credentials to initialize or run unit tests.
- Treat AI output as untrusted: structured/tool paths parse and validate before use.

### Anti-patterns (do not)

- Re-implement commons business logic in Python "for convenience".
- Hand-write error codes or framework ints that diverge from IDL/C ABI.
- Leave dead constructor knobs that imply remote auth.
- Claim "encrypted secure store" on POSIX.
- Use `generation_failed` for disk/tar/HTTP I/O.
- Unload with plain `take_handle` while another thread may still be inside `rac_*`.
- Add mock/stub public APIs for unfinished capabilities.
- Mount server admin/eval shortcuts without an explicit, documented opt-in.
