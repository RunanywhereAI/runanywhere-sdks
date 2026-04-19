# Sanitizer suppressions

These files are loaded via `ASAN_OPTIONS=suppressions=…`,
`TSAN_OPTIONS=suppressions=…`, and `UBSAN_OPTIONS=suppressions=…` in
the `commons-sanitizers` CI workflow.

Every entry must carry a `#`-prefixed comment citing:

1. **Which third-party dep** raises the warning.
2. **Why it is safe to suppress** (usually: upstream-known, or local
   guarantee stronger than what the tool can see).
3. **Link to upstream tracker** if available.

A new entry without the above rationale blocks the PR.

Anything in our own source code that TSan / ASan / UBSan flags must be
**fixed, not suppressed.**
