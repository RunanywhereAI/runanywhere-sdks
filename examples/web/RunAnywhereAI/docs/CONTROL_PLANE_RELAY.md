# First-Party Control-Plane Relay

The Web app authenticates to the maintained RunAnywhere control plane through
the same-origin `/api/runanywhere/*` relay. The production API key is never a
browser build variable.

## Environment

Configure both deployment values in Vercel for every intended environment:

- `VITE_RUNANYWHERE_RELAY_ENABLED=true` is a public build flag.
- `RUNANYWHERE_API_KEY` is a server-only secret read by the Vercel Function.

For local Vite development, place the same names in an uncommitted `.env.local`.
Never create `VITE_RUNANYWHERE_API_KEY`; every `VITE_*` value is embedded in
the client bundle.

## Reproducible Prebuilt Deployment

Deploy from `examples/web/RunAnywhereAI`, not from `dist` alone. The ignored
WASM binaries must be built from the SDK workspace, while the `api` directory
must remain part of the Vercel project. A Git deployment from a clean checkout
does not contain the WASM binaries and is therefore intentionally rejected by
the Vite production build instead of publishing an incomplete app.

The release host must satisfy the example's Node engine (Node 20 from `20.19`,
or Node `22.12+`) and the Web SDK's Emscripten/CMake prerequisites. Starting
from a clean clone:

```bash
npm ci
vercel link
npm run release:deploy
```

`release:deploy` installs or activates the repository-pinned Emscripten SDK
when needed, then runs the SDK's provenance-checking vendor scripts (which
reuse current archives and build missing or stale ones), builds all four
canonical SDK WASM variants, and verifies the browser bundle. It then creates
an ignored `.vercel-stage` containing the prebuilt static files, the minimal
relay source tree, and the Vercel project link; runs `vercel build --prod` in
that staging directory; verifies the Vercel static output and relay function;
and finally runs `vercel deploy --prebuilt --prod` from the same directory. The
stage intentionally contains only `package-lock.json`, so the function and
frontend packaging cannot select the unrelated Yarn lockfile.

The checked-in source Vercel build command is deliberately non-empty so Git
deployments fail with the missing-artifact diagnostic rather than reusing a
stale or absent `dist` directory. Vercel is also pinned to `npm ci`, ensuring
the checked-in npm lockfile controls dependency installation.

The public relay build flag is set by `build:deployment`. Keep
`RUNANYWHERE_API_KEY` exclusively in the Vercel project's encrypted runtime
environment. Re-run the post-deployment checks below before promotion.

## Required Vercel WAF Limit

The public marker is not authentication: it is bundled into the browser and a
custom client can copy it and forge same-origin request headers. The relay is a
public, route-limited capability backed by the server API key; it must not be
treated as proof of caller identity. Only use an API key whose permissions and
billing exposure are acceptable for that public capability.

Before promoting a deployment, create and publish this
[Vercel WAF rate-limit rule](https://vercel.com/docs/vercel-firewall/vercel-waf/rate-limiting)
for the project:

- Condition: **Raw Path** starts with `/api/runanywhere/`.
- Action: **Rate Limit** with a fixed 60-second window.
- Request limit: **120**.
- Counting key: **IP**.
- Exceeded action: the default **429** response.

This globally deployed WAF rule is the production abuse boundary; Vercel counts
rate-limit state per region and IP, while an in-memory function counter would
reset across serverless instances and is not a substitute. It limits neither a
distributed client's aggregate traffic nor access by an identified user. The
function additionally requires a matching `Origin` or same-origin
`Sec-Fetch-Site` browser context, but custom clients can spoof headers, so that
check does not replace the WAF limit. If the key grants privileged or
tenant-billed operations, add real caller authentication and authorization
before exposing the relay.

## Fixed Contract

The relay accepts only these production requests, with no query string or
trailing-slash variant:

| Method | Upstream path |
| --- | --- |
| `POST` | `/api/v1/auth/sdk/authenticate` |
| `POST` | `/api/v1/auth/sdk/refresh` |
| `POST` | `/api/v1/devices/register` |
| `GET` | `/api/v1/model-assignments/for-sdk` |

The upstream origin is a compile-time constant. The relay rebuilds request
headers, replaces the public client marker in the authenticate header and JSON
body, rejects cross-origin requests and redirects, bounds JSON bodies and
timeouts, strips unsafe response headers, and always returns `private,
no-store` responses. It intentionally logs no request or response data.

User-entered Settings credentials and custom base URLs do not use this relay.
They remain a direct browser connection and therefore require their own CORS
policy.

## Verification

Run the focused static gates from this directory:

```bash
npm run typecheck
npm run lint
npm test
VITE_RUNANYWHERE_RELAY_ENABLED=true npm run build
```

After deployment, verify an unknown path returns `404`, a wrong method returns
`405`, any query returns `400`, and a bare request without browser context
headers returns `403`. Confirm the published WAF rule returns `429` after its
per-IP threshold. Function responses must be JSON with
`Cache-Control: private, no-store` and must not include `Set-Cookie`,
`Location`, or permissive CORS headers.
