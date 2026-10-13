---
description: Fetch, triage, and act on all comments for a GitHub PR into a single source-of-truth doc.
argument-hint: [pr-number] [optional-repo]
---

You are an assistant that triages GitHub PR comments into a single source-of-truth document and turns larger issues into GitHub issues.

## ⚠️ CRITICAL: Address ALL Comments

**You MUST address EVERY SINGLE COMMENT on the PR. No exceptions.**

- Do NOT skip any comments, regardless of how minor they seem.
- Do NOT assume comments are resolved without verification.
- Do NOT stop fetching until you have retrieved ALL comments (handle pagination!).
- The final document must account for 100% of comments on the PR.

## 🚀 Parallelization Strategy: Use Task Agents

**To maximize efficiency and ensure thorough analysis, use the Task tool extensively:**

1. **For complexity/ranking analysis**: Launch **multiple Task agents in parallel** to analyze different comments simultaneously. Each agent should investigate the code context, assess complexity, and return a ranking score.

2. **For addressing each comment**: Launch a **separate Task agent for EACH comment** to fix or investigate it. This ensures:
   - Each comment gets dedicated attention
   - Fixes are isolated and don't conflict
   - Progress can be tracked independently
   - No comments are accidentally skipped

3. **Batch your Task calls**: When launching multiple agents, send them all in a **single message with multiple Task tool calls** to run them in parallel.

Example pattern:

```text
# In a SINGLE message, launch multiple Task agents:
- Task 1: "Analyze comment #1 - check file X, assess complexity, propose fix"
- Task 2: "Analyze comment #2 - check file Y, assess complexity, propose fix"
- Task 3: "Analyze comment #3 - check file Z, assess complexity, propose fix"
```

## Inputs

- Use the **first argument** `$1` as the PR number (`PR_NUMBER`).
- Use the **second argument** `$2` (if provided) as the repo slug `owner/name`.
  - If `$2` is not provided, infer the repo from the current git remote / workspace.
- All work happens on the **current branch** of the current repo.

## 1. Fetch PR details and ALL comments

### ⚠️ IMPORTANT: Use `gh api` directly – NOT MCP tools

The GitHub MCP tools do NOT support pagination. You MUST use the `gh api` command directly via Bash to ensure you fetch ALL comments.

### Step 1a: Get Total Comment Count First

Before fetching comments, get the total count to know how many you need to retrieve:

```bash
# Get PR details including comment counts
gh api repos/{owner}/{repo}/pulls/{PR_NUMBER} --jq '{
  title: .title,
  author: .user.login,
  state: .state,
  body: .body,
  url: .html_url,
  review_comments: .review_comments,
  comments: .comments
}'
```

### Step 1b: Fetch PR Metadata

```bash
gh pr view {PR_NUMBER} --repo {owner}/{repo} --json title,author,state,body,url,comments,reviewDecision
```

### Step 1c: Fetch ALL Review Comments (with pagination)

Review comments are comments on specific lines of code. **You MUST paginate through ALL pages:**

```bash
# Fetch review comments - paginate until empty results
# Page 1
gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/comments --paginate --jq '.[] | {
  id: .id,
  author: .user.login,
  body: .body,
  path: .path,
  line: .line,
  created_at: .created_at,
  updated_at: .updated_at,
  url: .html_url,
  in_reply_to_id: .in_reply_to_id
}'
```

The `--paginate` flag automatically handles pagination for you, fetching ALL pages.

### Step 1d: Fetch ALL Issue Comments (with pagination)

Issue comments are general PR comments (not on specific lines):

```bash
# Fetch issue comments - paginate until empty results
gh api repos/{owner}/{repo}/issues/{PR_NUMBER}/comments --paginate --jq '.[] | {
  id: .id,
  author: .user.login,
  body: .body,
  created_at: .created_at,
  updated_at: .updated_at,
  url: .html_url
}'
```

### Step 1e: Verify Comment Count

After fetching, **VERIFY** you have ALL comments:

```bash
# Count what you fetched
REVIEW_COMMENTS=$(gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/comments --paginate --jq 'length')
ISSUE_COMMENTS=$(gh api repos/{owner}/{repo}/issues/{PR_NUMBER}/comments --paginate --jq 'length')

echo "Review comments fetched: $REVIEW_COMMENTS"
echo "Issue comments fetched: $ISSUE_COMMENTS"
echo "Total: $((REVIEW_COMMENTS + ISSUE_COMMENTS))"
```

Compare this total against the counts from Step 1a. If they don't match, investigate and re-fetch.

### Step 1f: Count and Document

1. Count the total number of comments (including threaded replies).
2. **Document the count in the output file** – this is your verification that ALL comments were captured.

## 2. Create / update the comments document

1. In the repo root (or appropriate parent directory), ensure there is a `comments/` folder.
2. Create or overwrite a single markdown file:
   - Path: `comments/PR_${1}_comments.md`
3. At the top of the file, write a header like:

   ```md
   # PR #$1 – Comment Triage

   - Repo: <owner/name>
   - PR Title: <title>
   - PR URL: <url>
   - Total comments (including replies): <N>

   ## PR Description

   <PR body/description here>

   ---


This file must be treated as the single source of truth for this PR’s comments and resolutions.

Every time you do work for this command, keep updating this same file instead of creating new ones.

3. Normalize and analyze each comment

For each PR comment (including review comments and replies):

Extract:

Author

Created/updated timestamps

The full comment text

The file + line / code context if available

A permalink to the comment in GitHub

Detect whether the comment:

Is a true issue (bug, correctness, performance, security, missing tests, UX problem, etc.)

Is a nit / style / minor suggestion

Is a question or pure discussion

If the comment includes an AI prompt for the fix, capture that exactly (do not rewrite) and keep it attached to that comment.

4. Gut scoring and prioritization

### ⚠️ Use Parallel Task Agents for Analysis

**Launch multiple Task agents in parallel** to analyze comments simultaneously. For each batch of comments:

1. Send a **single message with multiple Task tool calls** (one per comment)
2. Each Task agent should:
   - Read the relevant file(s) mentioned in the comment
   - Understand the code context
   - Assess the legitimacy and complexity
   - Return a structured analysis with scores

Example prompt for each Task agent:

```text
Analyze PR comment for scoring:
- Comment: "<comment text>"
- File: <path>:<line>
- Task: Read the file, understand context, and return:
  1. LUS (Legitimacy & Urgency Score): 1-5
  2. CS (Complexity Score): 1-5
  3. Category: bug | nit | style | docs | question | other
  4. Brief explanation of your scoring
```

### Scoring Criteria

For each comment that represents an actionable issue, assign two gut scores (simple 1–5 scale):

Legitimacy & Urgency Score (LUS) – 1 (not legit / very low urgency) to 5 (definitely legit / very urgent).

Complexity Score (CS) – 1 (trivial / one-liner change) to 5 (large refactor / multi-file / needs design).

Then:

Compute a rough priority rank:

Sort primarily by LUS (descending).

Ties can be broken by CS (descending) or your judgment.

Use this ranking to decide if an item goes into:

Section 1: Quick & Easy Fixes (LUS high, CS low–medium)

Section 2: Larger / Structural Issues (LUS medium–high, CS medium–high)

5. Document structure inside PR_${1}_comments.md

Inside the markdown file, after the PR description, create these sections:

## Section 1 – Quick & Easy Fixes

(Short, low-complexity items we should fix directly in this PR.)

## Section 2 – Larger / Structural Issues (Create GitHub Issues)

(Items that are too big or risky to fully fix in this PR and should be tracked as issues.)

## Summary & Status

(High-level summary of what was addressed, what remains, and links to created issues.)

Section 1 – Quick & Easy Fixes

For each quick/easy item, add an entry like:

### QEF-<index> – <short title>

- Source comment: <GitHub permalink>
- Author: <name>
- File / location: `<path>:<line>` (if available)
- LUS (Legitimacy & Urgency): <1–5>
- CS (Complexity): <1–5>
- Type: bug | nit | style | docs | question | other

**Original Comment:**
> <comment text>

**AI Prompt (from comment, if present):**
```text
<prompt or "N/A">


Plan / Notes:

<your brief plan for how to fix, or what needs to be done>

Status:

TODO | In progress | Fixed (include commit hash / PR link if known)


### Section 2 – Larger / Structural Issues

For each larger item that should become a GitHub issue, add:

```md
### ISSUE-CANDIDATE-<index> – <short title>

- Source comment: <GitHub permalink>
- Author: <name>
- File / location: `<path>:<line>` (if available)
- LUS (Legitimacy & Urgency): <1–5>
- CS (Complexity): <1–5>

**Original Comment:**
> <comment text>

**Why this should be an issue:**
- <brief explanation>

**Draft Issue Title:**
- <proposed GitHub issue title>

**Draft Issue Overview:**
- <1–3 sentence overview: what, impact, priority>

**Status:**
- TODO (not created) | Created as <issue link>

6. Verifying each issue against the code

Once you’ve populated the doc:

For each actionable item (both quick fixes and larger issues):

Make sure you are on the current branch.

Use code navigation (file reads, searches, git tools, etc.) to verify:

The problem truly exists.

The comment is still relevant (the code may have changed).

If a comment is no longer valid, mark it clearly in the doc:

Example: Status: INVALID – Code has changed and this comment no longer applies (explain why).

Update the LUS score if verification changes your confidence.

7. Quick & easy fixes: execution guidance

### ⚠️ CRITICAL: Launch a Separate Task Agent for EACH Comment

**For EVERY quick fix, launch a dedicated Task agent.** Do NOT try to fix multiple comments in a single agent.

Why separate agents per comment:
- Ensures each comment gets **full, dedicated attention**
- Prevents fixes from conflicting with each other
- Makes it easy to track which comments are done
- Guarantees no comment is accidentally skipped

### Execution Pattern

1. **Batch launch Task agents** - Send multiple Task tool calls in a single message:

```text
# Launch these in PARALLEL (single message, multiple Task calls):

Task Agent for QEF-1:
"Fix PR comment QEF-1:
- Comment: '<comment text>'
- File: <path>:<line>
- Apply the fix, verify it compiles, report what you changed"

Task Agent for QEF-2:
"Fix PR comment QEF-2:
- Comment: '<comment text>'
- File: <path>:<line>
- Apply the fix, verify it compiles, report what you changed"

Task Agent for QEF-3:
...
```

2. **Each Task agent should**:
   - Read the file and understand context
   - Apply the fix
   - Verify the code still compiles (if practical)
   - Report back what was changed

3. **After agents complete**, update the document with results

### Additional Guidelines

Where the comment already includes an AI prompt for the fix, reuse it:

Reference that prompt in your own reasoning.

Optionally use it to generate concrete code changes.

When you apply a fix:

Modify the code in the appropriate files.

Make sure the project still compiles / tests still pass (where practical).

Update the corresponding entry in PR_${1}_comments.md:

Status: Fixed

Include commit hash or link to the PR update.

8. Larger issues: creating GitHub issues

For each item in Section 2 that truly deserves a separate issue:

Create a GitHub issue in RunanywhereAI/runanywhere-sdks using `gh issue create` (prefer `gh` CLI over MCP for reliability):

```bash
gh issue create --repo RunanywhereAI/runanywhere-sdks
```

Fill out the issue content:

Required Information

Title – Clear, concise description of the issue (≈50–80 chars).

Labels – Choose from:

ios-sdk, android-sdk, ios-sample, kotlin-sample, kotlin-sdk, web-sdk, web-sample

bug, enhancement, documentation, question

Priority labels: P0, P1, P2

Others as appropriate: good first issue, help wanted, etc.

Overview Section

Brief summary of the issue

Impact level (Low / Medium / High)

Priority (P0 / P1 / P2)

Effort estimate (Small / Medium / Large)

Issue Body Structure

Problem Statement

What’s the issue?

Why does it matter?

What’s broken or needs improvement?

Current State

What exists today?

Specific file paths and line numbers

Code examples showing the problem

Proposed Solution

How to fix it?

Code examples / pseudocode

File structure if creating new files

Implementation Plan

Step-by-step checklist

Files that need changes

Phased approach if applicable

Success Criteria

Clear checklist of what “done” means

Measurable outcomes

Guidelines

Be specific: include file paths, line numbers, and snippets.

Use markdown headings and lists.

Use code blocks with syntax highlighting where appropriate.

Add ⚠️ / 🔵 emojis or similar to highlight priority if useful.

Add a “Related Issues” section if applicable.

Use `gh issue create` with `--title`, `--label`, and `--body` flags.

After creating each issue:

Add the issue URL back into PR_${1}_comments.md under the corresponding ISSUE-CANDIDATE entry.

Update Status to Created as <link>.

9. Final summary and status update

At the end of the command:

Update the Summary & Status section at the bottom of PR_${1}_comments.md with:

Number of comments triaged.

Number of quick & easy fixes identified and how many are already fixed.

Number of larger issues identified and how many have GitHub issues created (with links).

Any remaining TODOs or things that still require human input / clarification.

Make sure the doc reads as a single, up-to-date overview of the PR's review state:

Someone new to the PR should be able to open this one file and understand:

What reviewers asked for,

What has been addressed,

What remains, and

Where to track the remaining work.

## ⚠️ Final Verification Checklist

Before considering this command complete, verify:

- [ ] **ALL comments fetched**: Compare fetched count against PR metadata counts
- [ ] **ALL comments documented**: Every comment appears in the markdown file
- [ ] **ALL comments triaged**: Each comment has a status (QEF, ISSUE-CANDIDATE, or marked INVALID)
- [ ] **ALL quick fixes addressed**: Either fixed or documented why not
- [ ] **ALL larger issues tracked**: GitHub issues created with links in the doc

**If any comment is missing from the final document, you have NOT completed this command.**
