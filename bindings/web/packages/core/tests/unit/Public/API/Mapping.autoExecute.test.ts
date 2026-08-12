/**
 * PR #605 review issue #7 — `llm.generate`/`llm.generateStream` with inline
 * `tools` hardcoded `autoExecute: true` when building the `toolCalling`
 * submessage (`toProtoLlmOptions` in `Mapping.ts`), so an explicit
 * `LlmOptions.autoExecute = false` never reached
 * `toolCalling.generateWithTools` -- the direct tool-calling API already
 * forwarded its own `autoExecute` override correctly
 * (`RunAnywhere+ToolCalling.test.ts`); this pins the `llm.generate(...,
 * tools, autoExecute: false)` hop that fed it a hardcoded value instead.
 */

import { describe, expect, it } from 'vitest';
import { toProtoLlmOptions } from '../../../../src/Public/API/Mapping';

describe('toProtoLlmOptions autoExecute forwarding', () => {
  it('defaults to auto-executing tools when unset', () => {
    const proto = toProtoLlmOptions({ toolChoice: { kind: 'auto' } });
    expect(proto.toolCalling?.autoExecute).toBe(true);
  });

  it('forwards an explicit autoExecute = false to the toolCalling submessage', () => {
    const proto = toProtoLlmOptions({ toolChoice: { kind: 'auto' }, autoExecute: false });
    expect(proto.toolCalling?.autoExecute).toBe(false);
  });

  it('forwards an explicit autoExecute = true unchanged', () => {
    const proto = toProtoLlmOptions({ toolChoice: { kind: 'auto' }, autoExecute: true });
    expect(proto.toolCalling?.autoExecute).toBe(true);
  });

  it('autoExecute = false still builds a toolCalling submessage from toolChoice alone', () => {
    const proto = toProtoLlmOptions({ toolChoice: { kind: 'required' }, autoExecute: false });
    expect(proto.toolCalling).toBeDefined();
    expect(proto.toolCalling?.autoExecute).toBe(false);
  });

  it('no tools/toolChoice/maxToolCalls means no toolCalling submessage at all', () => {
    const proto = toProtoLlmOptions({ autoExecute: false });
    expect(proto.toolCalling).toBeUndefined();
  });
});
