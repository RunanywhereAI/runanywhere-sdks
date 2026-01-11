# Flutter SDK Quality Tools

This directory contains scripts for maintaining code quality in the Flutter SDK.

## Quick Start

```bash
cd sdk/runanywhere-flutter

# Run full quality check
./tool/quality/flutter_quality.sh

# Individual checks
dart format lib/                    # Format code
flutter analyze lib/                # Static analysis
dart fix --apply lib/               # Apply safe auto-fixes
./tool/quality/todo_check.sh        # Check TODO comments
```

## Scripts

### `flutter_quality.sh`
Main quality check script that runs all checks in sequence:
1. Code formatting check
2. Static analysis (`flutter analyze`)
3. Available dart fixes (dry run)
4. TODO/FIXME comment validation
5. Tests (if present)

### `todo_check.sh`
Ensures all TODO/FIXME/HACK/XXX comments reference an issue number.

**Valid:**
```dart
// TODO(#123): Implement this feature
// FIXME #456: Fix this bug
```

**Invalid:**
```dart
// TODO: Do something later
// FIXME: This is broken
```

## Analysis Configuration

The `analysis_options.yaml` at the SDK root configures:
- Strict unused code detection (errors for dead code)
- Strong typing rules (avoid_dynamic_calls)
- API hygiene (return types, const usage)
- Reliability (cancel subscriptions, close sinks)

## CI Integration

For GitHub Actions, add to `.github/workflows/quality.yml`:

```yaml
name: Quality Check
on: [pull_request]
jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: cd sdk/runanywhere-flutter && ./tool/quality/flutter_quality.sh
```

## Common Issues

### Unused imports
```bash
# Find and remove unused imports
dart fix --apply lib/
```

### Formatting issues
```bash
# Auto-format all code
dart format lib/
```

### Missing issue references in TODOs
Update comments to include issue numbers:
```dart
// Before: // TODO: Fix this
// After:  // TODO(#123): Fix this
```
