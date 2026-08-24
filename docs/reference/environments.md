# SDK environments and base-URL resolution

How `RunAnywhere.initialize(environment:apiKey:baseUrl:)` decides **where your telemetry and
control-plane calls go** — and the traps that silently send them nowhere.

> **Public-repo note.** This file deliberately names only the public production control-plane
> endpoint. The staging origin is a build-time secret (`STAGING_BASE_URL`) and must never be
> written into tracked source or docs; `.gitleaks.toml` fails the build on a staging Railway URL,
> any `*.supabase.co` URL, and any Supabase key.

## There are exactly two environments

`core/include/rac/infrastructure/network/rac_environment.h`:

| enum | value | meaning |
|---|---|---|
| `RAC_ENV_DEVELOPMENT` | `0` | keyless, anonymous telemetry |
| ~~`RAC_ENV_STAGING`~~ | `1` | **retired.** `rac_env_normalize()` folds it into `PRODUCTION` |
| `RAC_ENV_PRODUCTION` | `2` | API key required, HTTPS required |

Slot `1` stays permanently reserved so an old binary that names staging degrades to production
instead of failing. **Do not reintroduce a third environment value.**

## Resolution rules — the whole truth

`rac_validate_base_url()` and `rac_state_initialize()`
(`core/src/infrastructure/network/environment.cpp:221-250, 418-425`):

| environment | you pass `base_url` | what happens |
|---|---|---|
| `DEVELOPMENT` | omitted | the **baked staging origin** is substituted (`rac_dev_config_get_staging_base_url()`) |
| `DEVELOPMENT` | omitted, and nothing was baked | init still returns `RAC_VALIDATION_OK` — the SDK is fully usable **offline**, but telemetry has nowhere to go and is dropped silently |
| `DEVELOPMENT` | `http://…` or `https://…` | used verbatim. This is the localhost / self-hosted-backend override |
| `PRODUCTION` | omitted | `RAC_VALIDATION_URL_REQUIRED` — init fails |
| `PRODUCTION` | `http://…` | `RAC_VALIDATION_URL_HTTPS_REQUIRED` — no localhost escape hatch |
| `PRODUCTION` | `https://…` | used verbatim; API key also required (min 10 chars, no placeholder) |

The public production control plane is `https://runanywhere-backend-production.up.railway.app`.

### The silent-failure mode to know about

`DEVELOPMENT` + no baked URL + no explicit URL = **valid init, zero telemetry**. This is
intentional (an open-source clone must build and run offline without credentials), but it means
"my events never arrived" is usually this, not a server problem. `core/tests/test_development_keyless_live.cpp`
exists to catch it and is excluded from the default ctest suite because it needs a real origin.

## How the staging origin gets into a build

```
GitHub Actions secret STAGING_BASE_URL
  └─ core/CMakeLists.txt:686-687  string(REPLACE "YOUR_STAGING_BASE_URL" …)
       └─ core/src/infrastructure/network/development_config.cpp   (gitignored)
            └─ rac_dev_config_get_staging_base_url()
```

Only `development_config.cpp.template` is tracked, carrying the literal placeholder
`YOUR_STAGING_BASE_URL`. To build a staging-capable binary locally, copy the template next to
itself, fill in the origin, and use `./run --env-staging` (which reads it back out; see `run:110-127`).

**This is an origin, not a credential.** Older SDK releases baked a Supabase URL + anon key and
wrote to the database directly; that path was removed in `0.20.0`. Nothing in a current build
carries database credentials.

## Per-binding defaults — one of these is wrong

The C++ core's rules above are the contract. A binding that substitutes its own default overrides
them, and one does so incorrectly:

| binding | default when no `base_url` is given | status |
|---|---|---|
| Swift / Kotlin / Flutter | none — the core rules apply | ✅ correct |
| **Electron** | `if (!baseUrl && !isProd) baseUrl = await backend.devStagingBaseUrl()` (`bindings/electron/src/api/facade.ts:450-451`) | ✅ correct — mirrors the core |
| **React Native** | `options.baseUrl?.trim() \|\| DEFAULT_BASE_URL`, applied **in every environment** (`bindings/react-native/packages/core/src/Public/RunAnywhere.ts:245`) | ⚠ **bug** |

React Native's `DEFAULT_BASE_URL` resolves through
`services/Network/NetworkConfiguration.ts:14` → `environmentDefaults.productionBaseUrl` →
`idl/sdk_defaults.proto:309` = **`https://api.runanywhere.ai`, which does not resolve (NXDOMAIN)**.
So on RN, forgetting `baseUrl` in production turns the core's clean `URL_REQUIRED` failure into
requests against a dead domain.

### Dead hostnames still present in the IDL

`idl/sdk_defaults.proto:309-321` defines three hostnames that are emitted into
`core/include/rac/rac_defaults_generated.h:120-122`:

| macro | value | resolves? |
|---|---|---|
| `RAC_DEFAULT_ENVIRONMENT_PRODUCTION_BASE_URL` | `https://api.runanywhere.ai` | **no — NXDOMAIN** |
| `RAC_DEFAULT_ENVIRONMENT_DEVELOPMENT_BASE_URL` | `https://dev-api.runanywhere.ai` | **no — NXDOMAIN** |
| `RAC_DEFAULT_ENVIRONMENT_DEVELOPMENT_PLACEHOLDER_URL` | `https://dev.runanywhere.local` | **no — reserved mDNS TLD** |

**The C++ init path never reads these macros** (zero references anywhere in `core/src`,
`core/include`, or `engines/` outside the definitions). They are inert in the core and reachable
only via a binding or a doc that copies them — as RN does above. Docs and quickstarts that print
them are giving readers an unreachable host.

## What the server side does with `environment`

The SDK's `environment` does **not** select a database. It only decides whether an API key is
required and which origin is used when you omit one. Server-side, one backend image is deployed
several times and each deployment points at its own database — so the origin you send to is what
determines where the row lands. Keyless `DEVELOPMENT` traffic is attributed to a fixed
anonymous organization rather than rejected.

## Verifying which origin a build will actually use

```bash
grep -n 'STAGING_BASE_URL' core/src/infrastructure/network/development_config.cpp
                                     # gitignored; in a clean clone this file does not exist
python3 scripts/release/prepublish_check.py
                                     # asserts the artifact has a REAL staging URL baked in
```

`prepublish_check.py:153-163` is the check that matters, and it runs the direction you might not
expect — it **requires** the staging origin to be present in a release artifact:

- placeholder `YOUR_STAGING_BASE_URL` found → **fail**, "NO TELEMETRY"
- a real staging origin found → pass
- no marker at all → "NOT verified" note

Because when the placeholder survives into a build, `rac_dev_config_is_usable_http_url()` rejects
it, keyless `DEVELOPMENT` resolves no origin, and the SDK ships reporting **nothing** — while
passing every other check (right size, right symbols). The 0.20.19 Electron packages shipped
exactly that way before this check existed.
