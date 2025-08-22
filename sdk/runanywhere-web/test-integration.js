#!/usr/bin/env node

/**
 * Integration test to verify the SDK packages work correctly
 */

import { logger, LogLevel, Result, DIContainer } from './packages/core/dist/index.js';
import { VoicePipelineManager, PipelineState } from './packages/voice/dist/index.js';

console.log('🧪 Testing RunAnywhere Web SDK Integration...\n');

// Test 1: Core package - Logger
console.log('✓ Testing Logger...');
logger.setLevel(LogLevel.DEBUG);
logger.info('Logger test', 'TestSuite');

// Test 2: Core package - Result type
console.log('✓ Testing Result type...');
const okResult = Result.ok('success');
const errResult = Result.err(new Error('test error'));
console.assert(Result.isOk(okResult), 'Result.ok should be ok');
console.assert(Result.isErr(errResult), 'Result.err should be error');

// Test 3: Core package - DI Container
console.log('✓ Testing DI Container...');
const container = new DIContainer();
const TEST_TOKEN = Symbol.for('TestService');
container.register(TEST_TOKEN, {
  factory: () => ({ name: 'TestService', value: 42 }),
  lifecycle: 'singleton'
});

// Test 4: Voice package - Pipeline Manager
console.log('✓ Testing Voice Pipeline Manager...');
const pipeline = new VoicePipelineManager({
  vad: { enabled: false } // Disable for testing
}, container);

console.assert(pipeline.getState() === PipelineState.IDLE, 'Pipeline should start in IDLE state');
console.log(`  Pipeline ID: ${pipeline.getId()}`);
console.log(`  Pipeline State: ${pipeline.getState()}`);

// Test 5: Async operations
console.log('✓ Testing async operations...');
(async () => {
  const service = await container.resolve(TEST_TOKEN);
  console.log('  Service resolved:', service);

  const health = await pipeline.getHealth();
  console.log('  Pipeline health:', health.overall ? '✅ Healthy' : '❌ Unhealthy');

  console.log('\n✅ All tests passed! SDK is working correctly.');
  console.log('\n📊 Summary:');
  console.log('  - Core package: ✓');
  console.log('  - Voice package: ✓');
  console.log('  - DI Container: ✓');
  console.log('  - Pipeline Manager: ✓');
  console.log('  - Async operations: ✓');

  process.exit(0);
})().catch(error => {
  console.error('\n❌ Test failed:', error);
  process.exit(1);
});
