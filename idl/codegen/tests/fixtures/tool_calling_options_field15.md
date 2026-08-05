# ToolCallingOptions field 15 schema-skew note

## Status

`ToolCallingOptions.parallel_tool_calls = 15` restores the historical bool
flag that briefly appeared in a reserved list during cleanup. Type and
meaning are unchanged:

| Writer | Reader | Result |
|---|---|---|
| old (bool 15 present) | new | reads parallel_tool_calls |
| new (bool 15 present) | old that knew the flag | reads parallel_tool_calls |
| new | old that reserved 15 | ignores unknown field 15 (safe) |

## Policy

- Field 15 must remain `bool parallel_tool_calls`.
- Never assign a different type to tag 15.
- Confirm any other suspected reclaim (4/5/6/17) against published
  descriptors before asserting a violation; current IDL uses those tags
  for temperature/max_tokens/system_prompt/disable_thinking without a
  confirmed type change.
