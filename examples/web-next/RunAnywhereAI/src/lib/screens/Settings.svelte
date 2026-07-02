<script lang="ts">
  import { IconBolt, IconCircleCheckFilled } from '@tabler/icons-svelte';
  import AppBar from '../components/AppBar.svelte';
  import Button from '../components/Button.svelte';
  import Icon from '../components/Icon.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import { sdk } from '../stores/sdk.svelte';

  const tone = $derived(
    sdk.ready ? 'ready' : sdk.status === 'error' ? 'error' : sdk.busy ? 'busy' : 'idle',
  );
  const label = $derived(
    sdk.ready ? 'Ready' : sdk.status === 'error' ? 'Error' : sdk.busy ? 'Starting' : 'Offline',
  );
</script>

<AppBar title="Settings">
  {#snippet actions()}<StatusPill {tone} {label} />{/snippet}
</AppBar>

<div class="wrap">
  <section class="card">
    <h2>On-device engine</h2>
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
      size="lg"
      variant={sdk.ready ? 'soft' : 'primary'}
      icon={IconBolt}
      loading={sdk.busy}
      disabled={sdk.ready}
      onclick={() => sdk.boot()}
    >
      {sdk.ready ? 'Online' : sdk.busy ? 'Starting…' : 'Bring it online'}
    </Button>
  </section>

  <p class="foot">RunAnywhere Web · worker-first · {sdk.backends.length} backends</p>
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
  h2 { font-size: 16px; font-weight: 700; }
  .msg { color: var(--muted); font-size: 14px; margin-top: 4px; min-height: 20px; }
  .backends { display: flex; flex-direction: column; gap: 8px; margin: 16px 0; }
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
  .foot { text-align: center; font-size: 12px; color: var(--muted-2); font-family: var(--font-mono); }
</style>
