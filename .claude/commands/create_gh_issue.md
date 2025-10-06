Create a GitHub issue with the following structure:

## Required Information:
1. **Title**: Clear, concise description of the issue (50-80 chars)
2. **Labels**: Add relevant labels (e.g., ios-sdk, android-sdk, ios-sample, P1/P2/P3, bug, enhancement, etc.)
3. **Overview Section**:
   - Brief summary of the issue
   - Impact level (Low/Medium/High)
   - Priority (P0/P1/P2)
   - Effort estimate (Small/Medium/Large)

## Issue Body Structure:

### 1. Problem Statement
- What's the issue?
- Why does it matter?
- What's broken or needs improvement?

### 2. Current State
- What exists today?
- Specific file paths and line numbers
- Code examples showing the problem

### 3. Proposed Solution
- How to fix it?
- Code examples showing the solution
- File structure if creating new files

### 4. Implementation Plan
- Step-by-step checklist
- Phased approach if applicable
- Files that need changes

### 5. Success Criteria
- Clear checklist of what "done" means
- Measurable outcomes

## Guidelines:
- Be specific: Include file paths, line numbers, and code snippets
- Use code blocks with syntax highlighting
- Add ⚠️ or 🔵 for priority indicators
- Include "Related Issues" section if applicable
- Keep it scannable with headers and lists
- Use the `gh issue create` command with `--title`, `--label`, and `--body` flags

## labels to choose from:
bug	Something isn't working	#d73a4a
documentation	Improvements or additions to documentation	#0075ca
duplicate	This issue or pull request already exists	#cfd3d7
enhancement	New feature or request	#a2eeef
good first issue	Good for newcomers	#7057ff
help wanted	Extra attention is needed	#008672
question	Further information is requested	#d876e3
ios-sample		#03a750
ios-sdk		#54156f
kotlin-sample		#0c06b3
kotlin-sdk		#74148a
web-sdk	Web sdk	#7a34bf
web-sample		#7cb13f
P0		#939fc8
P1		#77b201
P2		#d94b35
