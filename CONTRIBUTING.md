# Contributing to RunAnywhere SDKs

Thank you for your interest in contributing! RunAnywhere SDKs are maintained by
RunAnywhere, Inc. We welcome contributions from the community and are grateful
for your help in making the SDKs better.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Building & Running](#building--running)
- [Making Changes](#making-changes)
- [Submitting Changes](#submitting-changes)
- [Code Style](#code-style)
- [Reporting Issues](#reporting-issues)

## 🤝 Code of Conduct

By participating in this project you agree to uphold our
[Code of Conduct](CODE_OF_CONDUCT.md). Please be respectful and constructive in
all interactions.

## 🚀 Getting Started

1. **Fork the repository** on GitHub.
2. **Clone your fork** and add the upstream remote:
   ```bash
   git clone https://github.com/<your-username>/runanywhere-sdks.git
   cd runanywhere-sdks
   git remote add upstream https://github.com/RunanywhereAI/runanywhere-sdks.git
   ```
3. **Set up your environment** (see [Development Setup](#development-setup)).
4. **Create a branch** for your change:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## 🛠️ Development Setup

This is a monorepo: a single C++ core (`sdk/runanywhere-commons`) behind the
`rac_*` C ABI, with five thin platform SDKs — **Swift, Kotlin, Flutter, React
Native, and Web** — plus an example app per platform. See [`AGENTS.md`](AGENTS.md)
for the full architecture and per-SDK build details.

Everything is driven through the **`./run`** task runner at the repo root
(`run.bat` is the Windows wrapper). Start here:

```bash
./run doctor          # Scan your host toolchains and show what can be built
./run setup           # Provision build files + dependencies for buildable targets
```

`./run doctor` tells you which toolchains are present (Android SDK/NDK, Xcode,
Flutter, Node/Yarn, Emscripten) and what is missing, so you only install what you
need for the SDK you are touching.

**Install the pre-commit hooks** (runs gitleaks secret-scanning + SwiftLint on
commit, and keeps the `CLAUDE.md` → `AGENTS.md` symlinks in place):

```bash
pip install pre-commit
pre-commit install
```

Each `CLAUDE.md` is a symlink to its sibling `AGENTS.md` (edit either — it's the
same file), committed to the repo, so a fresh clone recreates them automatically
on macOS/Linux. `pre-commit install` also wires post-checkout/post-merge hooks
that re-create any missing link (e.g. on a Windows checkout); `scripts/setup/setup.sh`
does the same on demand.

## 🧱 Building & Running

All build, lint, and run actions go through `./run`. Run `./run help` for the
full list. Common commands:

```bash
# Native C++ commons core
./run sdk commons build-android     # All Android ABIs
./run sdk commons build-ios         # XCFramework (macOS only)
./run sdk commons build-wasm        # WebAssembly

# Per-SDK build / lint
./run sdk kotlin build              # Debug AAR
./run sdk kotlin lint               # ktlint + detekt
./run sdk ios build                 # swift build (macOS only)
./run sdk flutter build
./run sdk rn build
./run sdk web build

# Example apps
./run example android install       # Build + install + launch on a device
./run example ios build             # (macOS only)
./run example web dev

# Repo-wide helpers
./run lint                          # Linters across SDKs
./run format                        # Formatters across SDKs
./run codegen                       # Regenerate bindings from idl/
```

## 🔧 Making Changes

### Branch naming

- `feature/description` — new features
- `bugfix/description` — bug fixes
- `docs/description` — documentation
- `refactor/description` — refactoring

### Commit messages

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

**Examples:**
```
feat(android): add cost tracking to generation results
fix(ios): resolve memory leak in model loading
docs: update README with new API examples
```

### Architecture rule

When fixing something, prefer the **lowest layer that serves all consumers** —
a fix in C++ commons benefits all five SDKs, a per-SDK fix helps one. When
behavior is ambiguous across platforms, the **iOS Swift SDK is the source of
truth**. See [`AGENTS.md`](AGENTS.md) and the per-SDK `AGENTS.md` files.

## 📤 Submitting Changes

1. **Lint your change** before pushing:
   ```bash
   ./run lint
   ```
2. **Commit** with a clear Conventional Commit message.
3. **Push** to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```
4. **Open a Pull Request** against `main` with a clear title, a description of
   what and why, references to related issues, and screenshots/examples if
   relevant.

### Pull Request guidelines

- **Keep PRs focused** — one feature or fix per PR.
- **Explain what and why**, not just how.
- **Update documentation** when you change public API.
- **Ensure CI passes** — all required checks must be green.

## 🎨 Code Style

Linting and formatting are wired into `./run` and enforced by CI and the
pre-commit hooks:

- **Kotlin** — `./run sdk kotlin format` (ktlint), `./run sdk kotlin lint`
- **Swift** — SwiftLint (run via pre-commit) + Periphery for unused code
- **TypeScript / RN / Web** — ESLint + Prettier via each package's scripts
- **Dart / Flutter** — `dart format` + `flutter analyze`

General guidance: meaningful names, self-documenting code, early returns over
deep nesting, and small single-responsibility functions. Do not add unit tests
unless the change specifically calls for them — this repo validates behavior
end-to-end through the example apps rather than through broad unit-test suites.

## 🐛 Reporting Issues

Before filing: search existing issues, try the latest version, and check the
docs for known limitations.

**Bug reports** should include a clear description, reproduction steps, expected
vs. actual behavior, environment details (OS, SDK version), and logs/code
samples if applicable.

**Feature requests** should describe the desired functionality, the use case,
and any implementation ideas you have.

## ❓ Questions?

- **General questions** — open a GitHub Discussion
- **Bug reports / feature requests** — open an issue using the templates
- **Security issues** — email **founders@runanywhere.ai** (do not open a public
  issue; see [SECURITY.md](SECURITY.md))

Thank you for contributing to RunAnywhere SDKs! 🚀
