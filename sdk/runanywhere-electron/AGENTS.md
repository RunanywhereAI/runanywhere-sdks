# AGENTS.md

This package is the Electron/Node binding for RunAnywhere. `CLAUDE.md` is a symlink to
this file.

## Ownership

- **C++ commons owns AI truth** (inference, lifecycle, registry, RAG, cancel, error
  categories). The TypeScript facade and N-API addon are thin bridges.
- Align `native/addon.cpp` with the Python `module.cpp` when the surfaces intentionally
  mirror each other (handle maps, leases, secure store, streaming).
- Swift remains the cross-SDK product-semantics reference when behavior is ambiguous.

## Best practices (Electron)

Adapted from `thoughts/shared/plans/BEST_PRACTISES.md` for this package:

### Typed contracts

- Prefer typed `SDKException` / `ErrorCode` / `ErrorCategory` on every JS-facing path.
- Map native `rac_result_t` through structured errors — never collapse failures to a
  plain `Error` string if a typed path exists.
- Keep utility-process RPC **allowlisted** (`ALLOWED_RPC_METHODS`); do not proxy arbitrary
  addon methods.

### Honesty and readiness

- Document what is true today. Do not claim encryption, remote Phase-2 auth, or Windows
  QHexRT/NPU unless packaging and runtime are wired end-to-end.
- Win32 secure store is DPAPI; do not label it "plaintext M0" in headers/docs.
- Phase-2 `completeServicesInitialization` is a local lifecycle seam unless real auth
  lands.

### Native safety

- Unload paths use `take_handle_when_idle`; in-flight generate/embed/transcribe paths take
  `begin_op` leases so unload-during-generate cannot UAF.
- Win32 file/secure paths use wide UTF-16 (`_wfopen`); validate secure keys against
  traversal (`secure_key_ok`).
- Optional backends link via the CMake `foreach` / `RAC_HAVE_BACKEND_*` loop — no
  hard-coded "always link QHexRT" claims on desktop.

### Testing and CI

- Unit tests (`npm test`) are the primary gate for this package today.
- Prefer hermetic fakes over real models for unit coverage.
- Do not add mock public APIs for unfinished capabilities — document and defer.

### Anti-patterns

- Bare `throw new Error(String(racCode))` on the native→JS path.
- Unallowlisted RPC `api[method](...args)`.
- Hardcoded chat templates that ignore model chat formats (Llama-3 / Qwen) when a
  commons/chat-template path exists.
- Claiming parity with Python/Swift for features that are still host-side stubs.
