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

Deploy from `examples/web/RunAnywhereAI`, not from `dist` alone. The `api`
directory contains the Node function and must be included in the deployment.

## Required Vercel WAF Limit

The public marker is not authentication. Before promoting a deployment, create
and publish this [Vercel WAF rate-limit rule](https://vercel.com/docs/vercel-firewall/vercel-waf/rate-limiting)
for the project:

- Condition: **Raw Path** starts with `/api/runanywhere/`.
- Action: **Rate Limit** with a fixed 60-second window.
- Request limit: **120**.
- Counting key: **IP**.
- Exceeded action: the default **429** response.

This globally deployed WAF rule is the production abuse boundary; Vercel counts
rate-limit state per region, while an in-memory function counter would reset
across serverless instances and is not a substitute. The function additionally
requires a matching `Origin` or same-origin `Sec-Fetch-Site` browser context,
but custom clients can spoof headers, so that check does not replace the WAF
limit.

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
