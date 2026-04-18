# Starter Apps Tracking

External example repositories that consume the RunAnywhere SDKs.
Cloned into `external_examples/` locally (gitignored). Used by
`release.yml`'s consumer-validation jobs to verify every release
actually installs and builds in a downstream app.

**Unified version going forward: all SDKs will publish at the same
semver (e.g., `v0.19.8`, `v0.20.0`). Starter apps can pin to any tag.**

| SDK | Repo | HEAD commit | HEAD date | Currently pins |
|---|---|---|---|---|
| Swift | `RunanywhereAI/swift-starter-example` | `fe98b78` | 2026-03-19 | ? |
| Kotlin | `RunanywhereAI/kotlin-starter-example` | `56423ad` | 2026-02-16 | ? |
| Web | `RunanywhereAI/web-starter-app` | `bc6347a` | 2026-02-27 | @runanywhere/web@0.1.0-beta.10 |
| Flutter | `RunanywhereAI/flutter-starter-example` | `6587079` | 2026-02-14 | 0.16.0 |
| React Native | `RunanywhereAI/react-native-starter-app` | `8068d0b` | 2026-02-14 | @runanywhere/core@^0.18.1 |

## How to update these locally

```bash
for repo in swift-starter-example kotlin-starter-example web-starter-app flutter-starter-example react-native-starter-app; do
  if [ -d "external_examples/$repo" ]; then
    (cd "external_examples/$repo" && git pull --ff-only)
  else
    gh repo clone "RunanywhereAI/$repo" "external_examples/$repo"
  fi
done
```

## After cutting a release

1. `release.yml` builds artifacts and creates a draft GitHub Release.
2. `release.yml`'s consumer-validation jobs clone each starter repo and try
   to build it against the freshly-produced artifacts (`continue-on-error: true`).
3. If a starter fails to build, it's a signal the public API broke — either
   update the starter (post-release) or patch the SDK (post-release).
4. Publish the draft release once starters are green.
