# iOS SDK Release Guide

This guide explains how to create a new release of the RunAnywhere iOS SDK.

## Prerequisites

- Clean git working directory (no uncommitted changes)
- On `main` branch (or your release branch)
- GitHub CLI (`gh`) installed and authenticated
- All changes for the release already committed

## Quick Release (Automated)

The easiest way to create a release is using the automated script:

```bash
# From repository root
./scripts/release_ios_sdk.sh
```

The script will:
1. ✅ Validate preconditions (clean git, correct branch, gh CLI)
2. ✅ Prompt you for version bump type (patch/minor/major)
3. ✅ Update VERSION file
4. ✅ Update CHANGELOG.md with release date
5. ✅ Update version references in README files
6. ✅ Run tests to ensure package builds
7. ✅ Create git commit and tag
8. ✅ Push to GitHub
9. ✅ Create GitHub release with notes

### Example

```bash
$ ./scripts/release_ios_sdk.sh

=== RunAnywhere iOS SDK Release ===

ℹ Current version: 0.15.0

Select version bump type:
  1) patch (bug fixes)           - 0.15.0 -> 0.15.1
  2) minor (new features)        - 0.15.0 -> 0.16.0
  3) major (breaking changes)    - 0.15.0 -> 1.0.0

Enter choice (1-3): 2

⚠ About to release v0.16.0 (was 0.15.0)
Continue? (y/N): y

✓ Updated sdk/runanywhere-swift/VERSION
✓ Updated README.md
✓ Updated sdk/runanywhere-swift/README.md
✓ Updated sdk/runanywhere-swift/CHANGELOG.md
✓ Package builds successfully
✓ Created release commit
✓ Created tag v0.16.0
✓ Pushed commit and tag to GitHub
✓ GitHub release created

=== Release Complete! ===
✓ Released v0.16.0 successfully
```

## Manual Release (Step-by-Step)

If you prefer to create a release manually:

### 1. Update CHANGELOG.md

Edit `sdk/runanywhere-swift/CHANGELOG.md`:

```markdown
## [Unreleased]

### Added
- New feature X
- New feature Y

### Fixed
- Bug fix Z
```

Make sure all changes for this release are documented under `[Unreleased]`.

### 2. Determine Version Number

Follow [Semantic Versioning](https://semver.org/):

- **MAJOR** (1.0.0): Breaking API changes
- **MINOR** (0.X.0): New features, backwards compatible
- **PATCH** (0.0.X): Bug fixes, backwards compatible

### 3. Update Version References

Update the following files with the new version:

**`sdk/runanywhere-swift/VERSION`:**
```
0.16.0
```

**`sdk/runanywhere-swift/CHANGELOG.md`:**
Move `[Unreleased]` content to new version section:
```markdown
## [Unreleased]

## [0.16.0] - 2025-10-17
### Added
- Feature X
```

**`README.md` (root):**
Update all version references:
```swift
.package(url: "https://github.com/RunanywhereAI/sdks", from: "0.16.0")
```

**`sdk/runanywhere-swift/README.md`:**
Update all version references (same as above).

### 4. Test the Package

```bash
# From repository root
swift package resolve
swift build --target RunAnywhere

# Run tests (when available)
# swift test
```

### 5. Commit Changes

```bash
git add sdk/runanywhere-swift/VERSION \
        sdk/runanywhere-swift/CHANGELOG.md \
        README.md \
        sdk/runanywhere-swift/README.md

git commit -m "Release v0.16.0

- Updated version to 0.16.0
- Updated documentation
- See CHANGELOG.md for details"
```

### 6. Create Git Tag

```bash
git tag -a v0.16.0 -m "Release v0.16.0"
```

### 7. Push to GitHub

```bash
git push origin main
git push origin v0.16.0
```

### 8. Create GitHub Release

```bash
gh release create v0.16.0 \
    --title "RunAnywhere iOS SDK v0.16.0" \
    --notes "See [CHANGELOG.md](sdk/runanywhere-swift/CHANGELOG.md) for details" \
    --latest
```

Or create manually via GitHub web UI:
1. Go to https://github.com/RunanywhereAI/sdks/releases/new
2. Select tag `v0.16.0`
3. Title: `RunAnywhere iOS SDK v0.16.0`
4. Copy release notes from CHANGELOG.md
5. Mark as "Latest release"
6. Click "Publish release"

## After Release

### Verify Installation

Test that users can install the new version:

```swift
// Create a test Package.swift
dependencies: [
    .package(url: "https://github.com/RunanywhereAI/sdks", from: "0.16.0")
]
```

### Announce Release

- Post on Discord: https://discord.gg/pxRkYmWh
- Tweet from @RunanywhereAI
- Update documentation site (if applicable)

### Monitor for Issues

- Watch GitHub issues for installation problems
- Check Discord for user feedback
- Monitor SPM resolution issues

## Versioning Strategy

### Current (0.x.x series)

While in 0.x.x, we follow these conventions:
- **0.X.0**: New features, may include minor breaking changes
- **0.x.X**: Bug fixes and small improvements

### Future (1.0.0 and beyond)

When we reach 1.0.0, we'll strictly follow semantic versioning:
- **MAJOR**: Breaking changes
- **MINOR**: New features, backwards compatible
- **PATCH**: Bug fixes only

## Troubleshooting

### Script fails: "Git working directory is not clean"

Commit or stash your changes:
```bash
git status
git add .
git commit -m "Your changes"
```

### Script fails: "GitHub CLI not installed"

Install GitHub CLI:
```bash
brew install gh
gh auth login
```

### Script fails: "Not on main branch"

Switch to main branch:
```bash
git checkout main
git pull
```

### Package build fails

Fix build errors before releasing:
```bash
swift build --target RunAnywhere
# Fix any errors
```

### Tag already exists

Delete the tag and try again:
```bash
git tag -d v0.16.0
git push origin :refs/tags/v0.16.0
```

## Files Structure

```
sdks/
├── Package.swift                              # Root package manifest (required for SPM)
├── README.md                                  # Root documentation (update versions)
├── scripts/
│   └── release_ios_sdk.sh                    # Automated release script
└── sdk/runanywhere-swift/
    ├── Package.swift                          # Local development manifest
    ├── VERSION                                # Single source of truth for version
    ├── CHANGELOG.md                           # Release notes
    ├── RELEASING.md                           # This file
    └── README.md                              # SDK documentation (update versions)
```

## Questions?

- **Discord**: https://discord.gg/pxRkYmWh
- **Email**: founders@runanywhere.ai
- **GitHub Issues**: https://github.com/RunanywhereAI/sdks/issues

---

**Happy releasing! 🚀**
