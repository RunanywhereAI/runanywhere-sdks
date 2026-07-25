# AGENTS.md

This package is the Electron/Node binding for RunAnywhere.

- Keep the TypeScript facade thin and house-uniform with the other SDKs.
- Keep native behavior in `native/addon.cpp` aligned with the Python binding when they intentionally mirror each other.
- Prefer typed `SDKException` errors on every JS-facing path; do not collapse native `rac_result_t` failures to plain strings.
- Keep utility-process RPC allowlisted and minimal.
- Do not claim Windows QHexRT/NPU support unless packaging and runtime support are actually wired end-to-end.
