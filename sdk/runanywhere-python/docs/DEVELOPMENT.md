# Python SDK — Development

Contributor guide for building and testing the `runanywhere` Python package from source.

## Prerequisites

- Python 3.9+
- A C++20 toolchain and CMake (for the native `_core` extension)
- Built or co-located `runanywhere-commons` sources (scikit-build-core drives CMake)

## Editable install

The SDK builds via [scikit-build-core](https://scikit-build-core.readthedocs.io), which compiles the native `_core` extension from `runanywhere-commons`.

```bash
cd sdk/runanywhere-python
pip install -e ".[test]"
```

## Tests

```bash
pytest tests
```

The suite includes pure-Python tests that fake the native core, so you can run many tests without a full native build.

## Architecture notes

- The compiled native runtime loads lazily on the first `initialize()`, so importing `runanywhere` is side-effect-free.
- Multiple `RunAnywhere` clients share one reference-counted underlying runtime.
- See `AGENTS.md` in this directory for the full architecture, build details, and lazy-load design.
