# TODO Comment Policy

## Overview

To maintain code quality and ensure proper tracking of technical debt, all TODO-style comments in this codebase must reference a GitHub issue number.

## Supported Keywords

The following keywords trigger the TODO policy:
- `TODO`
- `FIXME`
- `HACK`
- `XXX`
- `BUG`
- `REFACTOR`
- `OPTIMIZE`

## Required Format

All TODO comments must include a GitHub issue number in the format `#123`:

### ✅ Correct Examples

```swift
// TODO: #123 - Implement proper error handling for network failures
```

```kotlin
// FIXME: #456 - Memory leak when loading large models
/* TODO: #789 - Refactor this to use coroutines */
```

```java
// BUG: #101 - Race condition in concurrent model loading
```

### ❌ Incorrect Examples

```swift
// TODO: Implement this later
// FIXME: This is broken
// TODO - Add validation
```

## Enforcement

### Swift (iOS SDK)
- SwiftLint custom rules check for TODOs without issue references
- Build will fail if non-compliant TODOs are found

### Kotlin/Java (Android SDK)
- Android Lint checks via `lint.xml` configuration
- Detekt rules for Kotlin-specific checks
- Build will fail if non-compliant TODOs are found

### Pre-commit Hooks
- Universal check across all file types
- Prevents commits with non-compliant TODOs

## Creating Issues for TODOs

When you need to add a TODO:

1. **Create a GitHub Issue First**
   - Go to the repository's Issues tab
   - Click "New Issue"
   - Choose appropriate labels (e.g., `technical-debt`, `enhancement`, `bug`)
   - Describe the task in detail

2. **Reference the Issue in Code**
   ```swift
   // TODO: #123 - Brief description of what needs to be done
   ```

3. **Link Back to Code** (Optional)
   - In the issue description, mention the file and line number
   - Example: "See `RunAnywhereSDK.swift:45`"

## Benefits

1. **Traceability**: Every TODO is tracked in the issue tracker
2. **Accountability**: Issues can be assigned to team members
3. **Visibility**: Project managers can see technical debt
4. **Discussion**: Issues provide a place for discussion
5. **Cleanup**: Easy to find and address all TODOs

## Exceptions

In rare cases where a TODO doesn't warrant an issue:
- Consider if it's really needed
- Use regular comments instead
- Or create a bulk issue for minor TODOs

## Tools

### Finding TODOs

```bash
# Find all properly formatted TODOs
grep -rn "TODO: #[0-9]" .

# Find TODOs missing issue numbers (will fail in CI)
grep -rEn "(TODO|FIXME|HACK)(?!.*#[0-9]+)" .
```

### IDE Integration

Most IDEs highlight TODO comments. Configure them to use our format:
- **Xcode**: Preferences → Text Editing → TODO highlighting
- **Android Studio**: Settings → Editor → TODO patterns

## Migration

For existing TODOs without issue numbers:

1. Run the finder script to identify them
2. Create appropriate GitHub issues
3. Update the TODOs with issue numbers
4. Commit the changes

## Questions?

If you have questions about this policy:
- Check existing issues for examples
- Ask in the team chat
- Create a discussion issue