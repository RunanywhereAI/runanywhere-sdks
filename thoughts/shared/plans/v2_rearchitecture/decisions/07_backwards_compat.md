# Decision 07 — Backwards compatibility

## Question

Do we keep any old API shim / alias / shell during this refactor?

## Choice

**No.** Every `rac_*` symbol is either renamed, reshaped, or deleted.
No compatibility layer, no transitional aliases, no `[[deprecated]]`
headers that forward to the new name.

## Reasoning

Explicit user directive: "do not think about backwards compatibility."

The only current consumers of the commons C ABI are the SDK frontends
in this same monorepo. They're on our side of the fence and will
migrate in their own follow-up plan. No external consumer is locked
in against the current ABI.

Keeping shims indefinitely makes the codebase harder to reason about
and slower to evolve; we'd be defending contract surfaces that no
customer relies on. One clean break now is cheaper than a long decay.

## Alternatives considered

| Option | Why rejected |
| --- | --- |
| Keep `rac_*` as `[[deprecated]]` wrappers around `ra_*` | Doubles the symbol count; every mistake now lives in two places |
| Ship v1 commons alongside v2 in the same build | Massive build complexity; two proto schemas to maintain |
| Bump SONAME, support both for one release | Extra CI burden; we're not a library on an OS distribution's release train |

## Implications

- Phase 1: `rac_service_*` deleted, not deprecated.
- Phase 2: callback-based service functions deleted; no wrapper
  emits tokens into a callback anymore.
- Phase 5: struct-based C ABI types deleted; no shim serialises a
  struct to proto.
- Phase 8: `rac_` prefix renamed to `ra_` across the remaining
  surface area.
- The frontend SDKs need to migrate as part of their own plans;
  until they do, they need to link against the version of commons
  they last built against. Our git tagging scheme (`commons-vX.Y.Z`)
  supports that.
- **What a frontend developer sees:** the moment they pull new
  commons, compile errors tell them every API that changed. Fix list
  is mechanical and finite.

No carve-outs. No exceptions. If a team wants to hold back on
migrating, they pin commons to an older tag.
