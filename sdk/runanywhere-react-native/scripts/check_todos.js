#!/usr/bin/env node
/**
 * Check that all TODO/FIXME/HACK/XXX/BUG/REFACTOR/OPTIMIZE comments
 * include an issue reference (e.g., #123)
 */

const fs = require('fs');
const path = require('path');
const glob = require('glob');

// Configure patterns and directories
const TODO_PATTERN = /\b(TODO|FIXME|HACK|XXX|BUG|REFACTOR|OPTIMIZE)\b\s*[:(]?\s*/gi;
const ISSUE_PATTERN = /#\d+/;
const SRC_DIR = path.join(__dirname, '..', 'src');

// Directories to skip
const SKIP_DIRS = ['node_modules', '__tests__', '.test.ts'];

function shouldSkip(filePath) {
  return SKIP_DIRS.some(skip => filePath.includes(skip));
}

function checkFile(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const lines = content.split('\n');
  const issues = [];

  lines.forEach((line, index) => {
    // Reset regex lastIndex for global pattern
    TODO_PATTERN.lastIndex = 0;
    let match;

    while ((match = TODO_PATTERN.exec(line)) !== null) {
      const restOfLine = line.slice(match.index);
      if (!ISSUE_PATTERN.test(restOfLine)) {
        issues.push({
          file: filePath,
          line: index + 1,
          type: match[1].toUpperCase(),
          content: line.trim()
        });
      }
    }
  });

  return issues;
}

function main() {
  const files = glob.sync(path.join(SRC_DIR, '**/*.ts'), {
    ignore: ['**/node_modules/**', '**/__tests__/**', '**/*.test.ts']
  });

  let allIssues = [];

  files.forEach(file => {
    if (!shouldSkip(file)) {
      const issues = checkFile(file);
      allIssues = allIssues.concat(issues);
    }
  });

  if (allIssues.length > 0) {
    console.log(`Found ${allIssues.length} TODO comments without issue references:\n`);
    allIssues.forEach(issue => {
      console.log(`${issue.file}:${issue.line}`);
      console.log(`  ${issue.type}: ${issue.content}`);
      console.log('');
    });
    console.log('All TODO/FIXME/HACK/XXX/BUG/REFACTOR/OPTIMIZE comments must include an issue reference (e.g., #123)');
    process.exit(1);
  } else {
    console.log('All TODO comments have issue references.');
    process.exit(0);
  }
}

main();
