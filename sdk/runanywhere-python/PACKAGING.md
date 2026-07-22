# Packaging & PyPI release checklist

`runanywhere` ships as a **pybind11 native wheel** (the `_core` extension over the `rac_*` C ABI)
plus a pure-Python facade. Because the wheel carries a compiled extension + vendored sidecar libs
(onnxruntime/sherpa), there is **one wheel per platform + Python version** — there is no universal
wheel. The sdist is source-only.

## What gets published

| Artifact | Built by | Repaired by | Sidecar location |
|---|---|---|---|
| `runanywhere-*-win_amd64.whl` | scikit-build-core | `delvewheel` | `runanywhere.libs/` |
| `runanywhere-*-manylinux_2_35_x86_64.whl` | scikit-build-core | `auditwheel` | `runanywhere.libs/` |
| `runanywhere-*-macosx_*_arm64.whl` | scikit-build-core | `delocate` | `runanywhere/.dylibs/` |
| `runanywhere-*.tar.gz` (sdist) | scikit-build-core | — | source only (no binaries) |

CI (`.github/workflows/pr-build.yml`) already builds + repairs + validates + hermetic-tests the
wheel on `python-windows`, `python-linux`, and `python-macos`. The release just collects those
artifacts.

## Dry-run checklist (before `twine upload`)

1. **Version** — bump `sdk/runanywhere-commons/VERSION`; `scripts/release/sync-versions.sh` propagates
   it into `pyproject.toml`. Confirm `pip show`/`__version__` match.
2. **Build sdist** — `python -m build --sdist -o dist`.
3. **Build + repair each wheel** on its platform (Win/Linux/macOS) via the CI recipe (build →
   delvewheel/auditwheel/delocate).
4. **Validate the release boundary** — `python scripts/validate_public_packages.py --dist dist
   --expected-version <VERSION>` (asserts: `_core` + sidecar libs present in the right dir per
   platform, no host-path leaks in binaries, the sdist has sources only, version matches).
5. **`twine check dist/*`** — long-description + metadata render.
6. **Fresh-venv install of each wheel** and smoke it:
   - base: `pip install <wheel>` → `import runanywhere` (no fastapi/protobuf), `runanywhere version`,
     `runanywhere models`.
   - server: `pip install "<wheel>[server]"` → `runanywhere serve` boots; `import runanywhere` still
     pulls in no fastapi.
   - rag: `pip install "<wheel>[rag]"` → `from runanywhere.rag import RagSession` imports.
7. **TestPyPI first** — `twine upload --repository testpypi dist/*`, then
   `pip install -i https://test.pypi.org/simple/ runanywhere` in a clean venv and re-run the smoke.
8. **Upload** — `twine upload dist/*`.

## Notes
- The base install is intentionally lean (`numpy` + stdlib only). `fastapi`/`uvicorn` live under the
  `[server]` extra; `protobuf` under `[rag]`.
- `sdist.include` scopes the sdist to `runanywhere/` + `native/` so it stays a few MB (not the whole
  monorepo).
- CUDA / QHexRT are build-flag opt-ins (`-C cmake.define.RAC_GPU_CUDA=ON`, etc.) producing separate
  distributions — not part of the default PyPI wheel.
