## Workflow rules
- [No commit or push without approval](no-commit-without-approval.md) — wait for an explicit go-ahead before git commit/push.
- [One-line commit messages](one-line-commit-messages.md) — single meaningful subject line, no body.
- [No AI-slop comments](no-ai-slop-comments.md) — comment only what code can't say itself.
- [Use humanizer for writing](use-humanizer-for-writing.md) — run the humanizer skill on all non-code prose.
- [Use gh for GitHub](use-gh-for-github.md) — gh CLI for PRs, issues, CI, and API lookups.
- [Short responses](short-responses.md) — always answer short, humanized, and clean; no long dumps.
- [Edit tool for file changes](use-edit-tool-for-file-changes.md) — no sed/python heredocs for edits.

## Hands off
- [Maven group is admin-managed](maven-group-is-admin-managed.md) — never change publishing coordinates or package ids.

## Engineering judgment
- [No hardcoded model names](no-hardcoded-model-names.md) — derive capability from the artifact, not the model id.
- [Verify before claiming an API is absent](verify-before-claiming-api-absent.md) — search extensions and spreads, not just the facade file.

## Project context
- [Backend monorepo location](backend-monorepo-location.md) — server/frontend code lives in a separate repo.
- [Kotlin is source SDK for API shaping](kotlin-source-sdk-for-api-shaping.md) — task-22 workstream overrides iOS-as-source-of-truth for facade shape
