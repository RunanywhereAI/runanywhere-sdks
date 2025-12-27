#!/usr/bin/env node
/**
 * Run full static analysis pipeline and output results to lint-reports/
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPORT_DIR = path.join(__dirname, '..', 'lint-reports');
const ITERATION = process.argv[2] || 'current';
const ITERATION_DIR = path.join(REPORT_DIR, `iteration-${ITERATION}`);

// Ensure directories exist
if (!fs.existsSync(REPORT_DIR)) {
  fs.mkdirSync(REPORT_DIR, { recursive: true });
}
if (!fs.existsSync(ITERATION_DIR)) {
  fs.mkdirSync(ITERATION_DIR, { recursive: true });
}

function runCommand(cmd, outputFile, failOnError = false) {
  console.log(`\nRunning: ${cmd}`);
  console.log(`Output: ${outputFile}`);
  try {
    const result = execSync(cmd, {
      encoding: 'utf8',
      maxBuffer: 10 * 1024 * 1024,
      cwd: path.join(__dirname, '..')
    });
    fs.writeFileSync(outputFile, result);
    console.log('  Success');
    return { success: true, output: result };
  } catch (error) {
    const output = error.stdout || error.message;
    fs.writeFileSync(outputFile, output);
    console.log(`  Completed with issues (exit code: ${error.status})`);
    if (failOnError) {
      throw error;
    }
    return { success: false, output };
  }
}

function main() {
  console.log('='.repeat(60));
  console.log(`Running Static Analysis - Iteration ${ITERATION}`);
  console.log('='.repeat(60));

  const results = {};

  // 1. TypeScript Type Check
  console.log('\n[1/4] TypeScript Type Check');
  results.tsc = runCommand(
    'yarn tsc --noEmit 2>&1',
    path.join(ITERATION_DIR, 'tsc.txt')
  );

  // 2. ESLint
  console.log('\n[2/4] ESLint');
  results.eslint = runCommand(
    'yarn eslint "src/**/*.ts" --format json 2>&1 || true',
    path.join(ITERATION_DIR, 'eslint.json')
  );

  // 3. Knip (unused code detection)
  console.log('\n[3/4] Knip (Unused Code Detection)');
  results.knip = runCommand(
    'yarn knip --reporter json 2>&1 || true',
    path.join(ITERATION_DIR, 'knip.json')
  );

  // Also get human-readable knip output
  runCommand(
    'yarn knip 2>&1 || true',
    path.join(ITERATION_DIR, 'knip.txt')
  );

  // 4. TODO Check
  console.log('\n[4/4] TODO Comment Check');
  results.todos = runCommand(
    'node scripts/check_todos.js 2>&1 || true',
    path.join(ITERATION_DIR, 'todos.txt')
  );

  // Generate summary
  console.log('\n' + '='.repeat(60));
  console.log('Analysis Summary');
  console.log('='.repeat(60));

  const summary = {
    iteration: ITERATION,
    timestamp: new Date().toISOString(),
    results: {
      tsc: results.tsc.success ? 'PASS' : 'ISSUES',
      eslint: results.eslint.success ? 'PASS' : 'ISSUES',
      knip: results.knip.success ? 'PASS' : 'ISSUES',
      todos: results.todos.success ? 'PASS' : 'ISSUES'
    },
    reportDir: ITERATION_DIR
  };

  fs.writeFileSync(
    path.join(ITERATION_DIR, 'summary.json'),
    JSON.stringify(summary, null, 2)
  );

  console.log(`\nReports written to: ${ITERATION_DIR}/`);
  console.log('  - tsc.txt');
  console.log('  - eslint.json');
  console.log('  - knip.json / knip.txt');
  console.log('  - todos.txt');
  console.log('  - summary.json');

  // Exit with error if any check failed
  const hasFailures = Object.values(results).some(r => !r.success);
  if (hasFailures) {
    console.log('\nSome checks have issues. Review reports for details.');
    process.exit(1);
  }
}

main();
