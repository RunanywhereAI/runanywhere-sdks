---
description: Detect, run, report, and fix ALL lint errors in a project using parallel agents.
argument-hint: [project-path]
---

You are an assistant that detects, runs, reports, and **fixes ALL lint errors** in a project using a multi-agent approach.

## Critical Requirements

**You MUST fix EVERY SINGLE lint error. No exceptions.**

- Do NOT stop until ALL lint errors are fixed.
- Do NOT skip any error, regardless of how minor it seems.
- Do NOT claim an error cannot be fixed without exhausting all options.
- PRESERVE all business logic - fixes must not change functionality.
- The final result must be a project with ZERO lint errors.

---

## Multi-Agent Workflow Overview

This command uses a **4-phase multi-agent approach**:

```
Phase 1: DETECTION AGENT
    └── Identify project type(s) and lint tooling

Phase 2: EXECUTION AGENT
    └── Run all lint checks and capture outputs

Phase 3: REPORT AGENT
    └── Parse results and create structured report

Phase 4: FIX AGENTS (PARALLEL)
    └── Launch N agents to fix errors (one per file or error group)
    └── Repeat until zero errors remain
```

---

## Phase 1: Detection Agent

**Launch a Task agent** to identify project types and lint tooling.

### Agent Prompt Template

```text
Analyze the project at [PROJECT_PATH] and identify:

1. PROJECT TYPES - Detect by scanning for canonical files:
   - Swift/iOS: Package.swift, *.xcodeproj, *.xcworkspace, Podfile, **/*.swift
   - Kotlin/Android: gradlew, settings.gradle(.kts), build.gradle(.kts), AndroidManifest.xml
   - React Native/Node/TypeScript: package.json, tsconfig.json, node_modules
   - Flutter/Dart: pubspec.yaml, lib/, analysis_options.yaml

2. LINT TOOLING - For each project type, check:
   - Swift: .swiftlint.yml, .swiftformat, .periphery.yml, Mintfile
   - Kotlin: detekt.yml, ktlint config, Gradle lint tasks
   - Node/TS: .eslintrc*, tsconfig.json, .prettierrc*, package.json scripts
   - Dart: analysis_options.yaml

3. TOOL RUNNERS - Detect available runners:
   - Mint, Bundler, Gradle wrapper, npm/yarn/pnpm

Return a structured report with:
- Detected project types and evidence (files found)
- Detected lint tools and their config paths
- Recommended lint commands to run
- Any missing tools or setup issues
```

### Expected Output from Detection Agent

Document the findings before proceeding:
- List of project types
- List of configured lint tools
- Exact commands to run for each tool

---

## Phase 2: Execution Agent

**Launch a Task agent** to run all detected lint checks.

### Agent Prompt Template

```text
Run lint checks for the project at [PROJECT_PATH].

Based on the detection results:
[INSERT DETECTION RESULTS HERE]

Execute these lint commands in order, capturing ALL output:

For Swift/iOS:
- SwiftLint: mint run swiftlint swiftlint lint --reporter json (or swiftlint lint --reporter json)
- SwiftFormat: swiftformat . --lint (if configured)
- Periphery: periphery scan (if configured)

For Kotlin/Android:
- ./gradlew ktlintCheck --no-daemon (if ktlint configured)
- ./gradlew detekt --no-daemon (if detekt configured)
- ./gradlew lint --no-daemon (Android lint)

For Node/TypeScript:
- [package-manager] run lint (if lint script exists)
- [package-manager] exec eslint . (if eslint configured)
- [package-manager] exec tsc --noEmit (if tsconfig exists)

For Flutter/Dart:
- flutter analyze
- dart format . --set-exit-if-changed

CRITICAL RULES:
- Capture stdout AND stderr for each tool
- Record exit code for each tool
- Continue even if a tool fails
- Save raw outputs to comments/.lint_tmp/

Return:
- Commands executed with exit codes
- Path to each raw output file
- Initial count of errors/warnings per tool
```

---

## Phase 3: Report Agent

**Launch a Task agent** to parse results and create a structured report.

### Agent Prompt Template

```text
Create a comprehensive lint report from the execution results.

Execution results:
[INSERT EXECUTION RESULTS HERE]

Tasks:
1. Create report directory: comments/
2. Create report file: comments/LINT_[PROJECT_NAME]_[TIMESTAMP].md

3. Parse each tool's output into severity buckets:
   - ERRORS: Must be fixed (blocks CI, breaks builds)
   - WARNINGS: Should be fixed (code quality issues)
   - STYLE/INFO: Nice to fix (formatting, conventions)

4. For each error/warning, extract:
   - File path and line number
   - Error code/rule name
   - Error message
   - Suggested fix (if provided by tool)

5. Create the report with these sections:

## Report Structure

### Header
- Project path
- Timestamp
- Branch and commit
- Tools executed

### Summary Table
| Tool | Exit Code | Errors | Warnings | Style |
|------|-----------|--------|----------|-------|
| ...  | ...       | ...    | ...      | ...   |

### Errors by File
Group errors by file path for efficient fixing:

#### File: path/to/File1.swift
- Line 42: [E001] Error description
- Line 87: [E002] Error description

#### File: path/to/File2.kt
- Line 15: [E003] Error description

### Warnings by File
(Same structure as errors)

### Style Issues by File
(Same structure as errors)

### Raw Outputs
<details>
<summary>Tool Name - Raw Output</summary>
(raw output here)
</details>

Return the full report and a summary:
- Total errors: N
- Total warnings: N
- Total style issues: N
- Files affected: N
```

---

## Phase 4: Fix Agents (Parallel)

**This is the most critical phase. You MUST fix ALL errors.**

### Strategy: Parallel Agents per File

Launch **multiple Task agents in parallel**, one for each file with errors.

**Why separate agents per file:**
- Ensures each file gets dedicated attention
- Prevents conflicting edits
- Makes progress trackable
- Guarantees no error is skipped

### Agent Launch Pattern

In a **single message**, launch multiple Task tool calls:

```text
# Launch these in PARALLEL (single message, multiple Task calls):

Task Agent for File 1:
"Fix ALL lint errors in [path/to/File1.swift]:
Errors to fix:
- Line 42: [E001] Description
- Line 87: [E002] Description

RULES:
- Fix EVERY error listed
- PRESERVE all business logic
- Maintain code formatting consistency
- Report what you changed
- Verify the file still compiles"

Task Agent for File 2:
"Fix ALL lint errors in [path/to/File2.kt]:
Errors to fix:
- Line 15: [E003] Description
...

Task Agent for File 3:
...
```

### Fix Agent Detailed Prompt

For each file, the fix agent must:

```text
Fix ALL lint errors in [FILE_PATH].

Errors to fix:
[LIST ALL ERRORS WITH LINE NUMBERS AND DESCRIPTIONS]

## Critical Rules

1. FIX EVERY ERROR - Do not skip any
2. PRESERVE BUSINESS LOGIC - Changes must not alter functionality
3. MAINTAIN STYLE - Keep consistent with surrounding code
4. VERIFY COMPILATION - Ensure code still compiles after fixes

## Common Fix Patterns

### Swift/SwiftLint
- trailing_whitespace: Remove trailing whitespace
- line_length: Break long lines or refactor
- force_unwrapping: Use optional binding or guard
- unused_import: Remove unused imports
- identifier_name: Rename to follow conventions

### Kotlin/Detekt/Ktlint
- max-line-length: Break long lines
- no-wildcard-imports: Use specific imports
- unused-imports: Remove unused imports
- naming conventions: Rename to follow conventions

### TypeScript/ESLint
- no-unused-vars: Remove or use the variable
- prefer-const: Change let to const
- @typescript-eslint rules: Follow type safety recommendations

## Response Format

Report back:
1. List of errors fixed (with before/after snippets)
2. Any errors that could NOT be fixed and why
3. Confirmation that file still compiles
4. Any concerns about business logic preservation
```

### Iteration Until Zero Errors

After the fix agents complete:

1. **Re-run lint checks** to verify fixes
2. **Count remaining errors**
3. **If errors remain**, launch another round of fix agents
4. **Repeat until zero errors**

```text
VERIFICATION LOOP:

while (lint_errors > 0) {
    1. Re-run lint checks
    2. Parse new errors
    3. Launch fix agents for remaining errors
    4. Collect results
}

STOP only when: lint_errors == 0
```

---

## Execution Flow

### Step 1: Setup

```bash
PROJECT_PATH="${1:?Usage: run_and_fix_lints <project-path>}"

# Get repo root
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git rev-parse --show-toplevel)"
else
  REPO_ROOT="$(cd "$PROJECT_PATH" && pwd)"
fi

cd "$REPO_ROOT"
mkdir -p comments/.lint_tmp

SAFE_PROJECT_NAME="$(basename "$PROJECT_PATH" | tr -cd 'A-Za-z0-9_-')"
TS="$(date +%Y%m%d_%H%M%S)"
REPORT="comments/LINT_${SAFE_PROJECT_NAME}_${TS}.md"
```

### Step 2: Launch Detection Agent

```text
Task: Analyze [PROJECT_PATH] for project types and lint tooling
Agent: Explore or general-purpose
Return: Detection results
```

### Step 3: Launch Execution Agent

```text
Task: Run all detected lint tools on [PROJECT_PATH]
Agent: general-purpose
Input: Detection results from Step 2
Return: Raw outputs and initial error counts
```

### Step 4: Launch Report Agent

```text
Task: Parse lint outputs and create structured report
Agent: general-purpose
Input: Execution results from Step 3
Return: Structured report with errors grouped by file
```

### Step 5: Launch Fix Agents (Parallel)

```text
For each file with errors:
  Launch Task agent to fix ALL errors in that file

Run all fix agents in PARALLEL (single message, multiple Task calls)
```

### Step 6: Verification Loop

```text
while lint_errors > 0:
    1. Re-run lint (same commands as Step 3)
    2. Parse new errors
    3. If errors remain:
       - Update report with progress
       - Launch new fix agents for remaining errors
    4. If max_iterations reached:
       - Document unfixable errors
       - Provide manual fix guidance
```

### Step 7: Final Report Update

Update the report with final status:
- All errors that were fixed
- Before/after error counts
- Any warnings about business logic changes
- Final lint status (should be PASS)

---

## Output Requirements

### Report Location
- Path: `comments/LINT_${PROJECT_NAME}_${TIMESTAMP}.md`

### Report Must Include
1. Detection results (project types, tools found)
2. Commands executed with exit codes
3. Initial error/warning/style counts
4. Errors grouped by file
5. Fix summary (what was changed)
6. Final verification results
7. Status: PASS (all errors fixed) or FAIL (with remaining issues)

### Console Output
At the end, print:
```
Lint Fix Complete!
- Initial errors: X
- Errors fixed: Y
- Remaining errors: 0
- Report: comments/LINT_[name]_[timestamp].md
```

---

## Verification Checklist

Before considering this command complete, verify:

- [ ] **Detection complete**: All project types and lint tools identified
- [ ] **Lint executed**: All configured lint tools were run
- [ ] **Report created**: Structured report exists in comments/
- [ ] **Errors grouped**: All errors organized by file
- [ ] **Fix agents launched**: Parallel agents for each affected file
- [ ] **All errors fixed**: Zero lint errors remaining
- [ ] **Business logic preserved**: No functional changes
- [ ] **Code compiles**: Project still builds successfully
- [ ] **Final verification**: Re-ran lint to confirm zero errors

**If ANY lint errors remain unfixed, you have NOT completed this command.**

---

## Edge Cases and Handling

### Tool Not Found
If a configured lint tool is not installed:
- Document the missing tool in the report
- Attempt to install (e.g., `brew install swiftlint`, `mint bootstrap`)
- If install fails, note in report and continue with other tools

### Unfixable Errors
If an error genuinely cannot be auto-fixed:
- Document why (e.g., requires architectural change)
- Provide manual fix guidance
- Mark as "MANUAL_FIX_REQUIRED" in report

### Conflicting Rules
If lint rules conflict with each other:
- Document the conflict
- Prefer the stricter/safer rule
- Add note about potential config adjustment

### Large Error Counts
If a file has >20 errors:
- Still create a fix agent for it
- The agent should batch related fixes
- May require multiple iterations

---

## Example Execution

```text
User: /run_and_fix_lints examples/ios/RunAnywhereAI

Agent Actions:
1. Launch Detection Agent for examples/ios/RunAnywhereAI
   Result: iOS project, SwiftLint configured, Mint available

2. Launch Execution Agent
   Commands: mint run swiftlint swiftlint lint --reporter json
   Result: 47 errors, 23 warnings across 12 files

3. Launch Report Agent
   Result: Structured report with errors grouped by file

4. Launch Fix Agents (12 parallel agents, one per file)
   - Agent 1: Fix 8 errors in AppDelegate.swift
   - Agent 2: Fix 5 errors in ContentView.swift
   - Agent 3: Fix 4 errors in VoiceService.swift
   ...

5. Re-run lint verification
   Result: 3 remaining errors in 2 files

6. Launch Fix Agents Round 2 (2 agents)
   - Agent 1: Fix 2 errors in ContentView.swift
   - Agent 2: Fix 1 error in VoiceService.swift

7. Re-run lint verification
   Result: 0 errors - SUCCESS!

8. Final report update
   Status: PASS - All 47 errors fixed
```

---

## Summary

This command ensures **comprehensive lint coverage** through:

1. **Automated detection** of project types and lint tools
2. **Systematic execution** of all configured linters
3. **Structured reporting** with errors grouped by file
4. **Parallel fix agents** that address each file independently
5. **Iterative verification** until zero errors remain

**The goal is simple: zero lint errors, preserved business logic.**
