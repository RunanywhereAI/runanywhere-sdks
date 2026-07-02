<script lang="ts">
  import { IconBolt, IconBrandGithub, IconCircleCheckFilled, IconInfoCircle, IconPlug } from '@tabler/icons-svelte';
  import AppBar from '../components/AppBar.svelte';
  import Button from '../components/Button.svelte';
  import Icon from '../components/Icon.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import { sdk } from '../stores/sdk.svelte';
  import { settings, type EnvKey } from '../stores/settings.svelte';

  const tone = $derived(
    sdk.ready ? 'ready' : sdk.status === 'error' ? 'error' : sdk.busy ? 'busy' : 'idle',
  );
  const label = $derived(
    sdk.ready ? 'Ready' : sdk.status === 'error' ? 'Error' : sdk.busy ? 'Starting' : 'Offline',
  );

  const ENVS: { key: EnvKey; label: string }[] = [
    { key: 'development', label: 'Development' },
    { key: 'staging', label: 'Staging' },
    { key: 'production', label: 'Production' },
  ];

  // Draft state — applied (and persisted) only on "Save & reload", since the
  // engine initializes once at startup.
  let env = $state<EnvKey>(settings.environment);
  let apiKey = $state(settings.apiKey);
  let baseUrl = $state(settings.baseUrl);

  const dirty = $derived(
    env !== settings.environment || apiKey !== settings.apiKey || baseUrl !== settings.baseUrl,
  );

  const platform = typeof navigator !== 'undefined' ? navigator.userAgent : 'unknown';

  function saveAndReload(): void {
    settings.save({ environment: env, apiKey, baseUrl });
    location.reload();
  }
</script>

<AppBar title="Settings">
  {#snippet actions()}<StatusPill {tone} {label} />{/snippet}
</AppBar>

<div class="wrap">
  <section class="card">
    <div class="head"><span class="ic"><Icon icon={IconPlug} size={18} stroke={1.8} /></span><h2>Connection</h2></div>

    <div class="field">
      <span class="lbl">Environment</span>
      <div class="seg">
        {#each ENVS as e (e.key)}
          <button class="segbtn" class:active={env === e.key} onclick={() => (env = e.key)}>{e.label}</button>
        {/each}
      </div>
    </div>

    <label class="field">
      <span class="lbl">API key</span>
      <input type="password" bind:value={apiKey} placeholder="For cloud auth & telemetry" autocomplete="off" spellcheck="false" />
    </label>

    <label class="field">
      <span class="lbl">Base URL</span>
      <input type="text" bind:value={baseUrl} placeholder="RunAnywhere API base URL" autocomplete="off" spellcheck="false" />
    </label>

    <p class="hint">Used for auth, device registration, and telemetry. The engine initializes once at startup — saving reloads to apply.</p>
    <Button full variant={dirty ? 'primary' : 'soft'} disabled={!dirty} onclick={saveAndReload}>
      {dirty ? 'Save & reload' : 'Saved'}
    </Button>
  </section>

  <section class="card">
    <div class="head"><span class="ic"><Icon icon={IconBolt} size={18} stroke={1.8} /></span><h2>On-device engine</h2></div>
    <p class="msg">{sdk.message}</p>

    <div class="backends">
      {#each sdk.backends as b (b.id)}
        <div class="b" class:on={b.ready}>
          <span class="dot"></span>
          <div class="meta">
            <span class="bn">{b.label}</span>
            <span class="bs">{b.sub}</span>
          </div>
          {#if b.ready}<span class="tick"><Icon icon={IconCircleCheckFilled} size={20} /></span>{/if}
        </div>
      {/each}
    </div>

    <Button
      full
      variant={sdk.ready ? 'soft' : 'primary'}
      icon={IconBolt}
      loading={sdk.busy}
      disabled={sdk.ready}
      onclick={() => sdk.boot()}
    >
      {sdk.ready ? 'Online' : sdk.busy ? 'Starting…' : 'Bring it online'}
    </Button>
  </section>

  <section class="card">
    <div class="head"><span class="ic"><Icon icon={IconInfoCircle} size={18} stroke={1.8} /></span><h2>About</h2></div>
    <div class="rows">
      <div class="row"><span class="k">Environment</span><span class="v">{ENVS.find((e) => e.key === settings.environment)?.label}</span></div>
      <div class="row"><span class="k">Backends</span><span class="v">{sdk.backends.length}</span></div>
      <div class="row"><span class="k">Platform</span><span class="v mono">{platform}</span></div>
      <a class="row link" href="https://github.com/RunanywhereAI/runanywhere-sdks" target="_blank" rel="noopener noreferrer">
        <span class="k"><Icon icon={IconBrandGithub} size={16} stroke={1.8} /> Source</span>
        <span class="v">github.com/RunanywhereAI</span>
      </a>
    </div>
  </section>

  <p class="foot">RunAnywhere Web · worker-first · fully on-device</p>
</div>

<style>
  .wrap { padding: 18px; max-width: 560px; margin: 0 auto; display: flex; flex-direction: column; gap: 16px; }
  .card {
    background: var(--surface);
    border: 1px solid var(--line);
    border-radius: var(--r-lg);
    box-shadow: var(--shadow-sm);
    padding: 20px;
  }
  .head { display: flex; align-items: center; gap: 8px; margin-bottom: 6px; }
  .ic { color: var(--accent); display: flex; }
  h2 { font-size: 16px; font-weight: 700; }
  .msg { color: var(--muted); font-size: 14px; margin-top: 2px; min-height: 20px; }

  .field { display: flex; flex-direction: column; gap: 6px; margin-top: 14px; }
  .lbl { font-size: 12px; font-weight: 600; color: var(--muted); }
  input {
    border: 1px solid var(--line-strong);
    border-radius: var(--r-sm);
    background: var(--bg);
    color: var(--ink);
    font: inherit;
    font-size: 14px;
    padding: 10px 12px;
    outline: none;
  }
  input:focus { border-color: var(--accent); }
  input::placeholder { color: var(--muted-2); }

  .seg { display: flex; gap: 4px; padding: 4px; border-radius: var(--r-sm); background: var(--surface-2); }
  .segbtn {
    flex: 1;
    border: none;
    background: none;
    color: var(--muted);
    font: inherit;
    font-size: 13px;
    font-weight: 600;
    padding: 8px 6px;
    border-radius: var(--r-xs);
    cursor: pointer;
    transition: background 160ms ease, color 160ms ease;
  }
  .segbtn.active { background: var(--surface); color: var(--accent); box-shadow: var(--shadow-sm); }

  .hint { font-size: 12px; color: var(--muted-2); margin: 12px 0 14px; }

  .backends { display: flex; flex-direction: column; gap: 8px; margin: 14px 0; }
  .b {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 14px;
    border: 1px solid var(--line);
    border-radius: var(--r-sm);
    transition: border-color 300ms ease;
  }
  .b.on { border-color: color-mix(in srgb, var(--ok) 45%, var(--line)); }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--line-strong); transition: background 300ms ease, box-shadow 300ms ease; flex: none; }
  .b.on .dot { background: var(--ok); box-shadow: 0 0 0 4px var(--ok-soft); }
  .meta { display: flex; flex-direction: column; flex: 1; }
  .bn { font-size: 14px; font-weight: 600; }
  .bs { font-size: 12px; color: var(--muted-2); }
  .tick { color: var(--ok); display: flex; }

  .rows { display: flex; flex-direction: column; margin-top: 8px; }
  .row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 11px 0;
    border-top: 1px solid var(--line);
    font-size: 14px;
  }
  .row:first-child { border-top: none; }
  .k { color: var(--muted); display: inline-flex; align-items: center; gap: 6px; }
  .v { color: var(--ink); text-align: right; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 60%; }
  .v.mono { font-family: var(--font-mono); font-size: 12px; color: var(--muted-2); }
  .link { text-decoration: none; cursor: pointer; }
  .link .v { color: var(--accent); }

  .foot { text-align: center; font-size: 12px; color: var(--muted-2); font-family: var(--font-mono); }
</style>
