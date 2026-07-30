# Global rules

## Git
- Never `git commit` or `git push` until I explicitly ask. Do the work, summarize the diff, then stop. Approval of the code is not approval to commit.
- Commit messages are one line and must name the real change (scope prefix + concrete change). No body, no bullet summaries. If it won't fit on one line, split the commit.
- Use the `gh` CLI for all GitHub access — PRs, issues, reviews, releases, CI runs, `gh api` lookups.

## Code
- No AI-slop comments. Don't restate the line below, don't add section banners or `// Step 1:` scaffolding, don't narrate the edit. Comment only where a reader would otherwise be misled: a non-obvious invariant, a workaround and its reason, an ABI or wire constraint. Match the comment density of the surrounding file.

## Writing
- For any non-code writing — docs, READMEs, plans, PR descriptions, issue text, release notes — invoke the `humanizer` skill (installed at `~/.claude/skills/humanizer`) and apply it before finalizing.
