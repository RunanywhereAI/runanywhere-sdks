<script lang="ts">
  import { IconBolt, IconCheck, IconDownload } from '@tabler/icons-svelte';
  import Button from './Button.svelte';
  import Icon from './Icon.svelte';
  import ProgressBar from './ProgressBar.svelte';
  import type { ModelState } from '../types';

  interface Props {
    name: string;
    meta?: string;
    state?: ModelState;
    loadable?: boolean;
    progress?: number;
    onDownload?: () => void;
    onLoad?: () => void;
  }

  let { name, meta = '', state = 'available', loadable = true, progress = 0, onDownload, onLoad }: Props = $props();

  const determinate = $derived(progress > 0 && progress < 1);
</script>

<div class="row" class:loaded={state === 'loaded'}>
  <div class="info">
    <span class="name">{name}</span>
    {#if meta}<span class="meta">{meta}</span>{/if}
    {#if state === 'downloading'}
      <div class="prog">
        <ProgressBar indeterminate={!determinate} value={progress} />
        <span class="lbl">{determinate ? `${Math.round(progress * 100)}%` : 'Working…'}</span>
      </div>
    {/if}
  </div>

  <div class="action">
    {#if state === 'loaded'}
      <span class="badge"><Icon icon={IconCheck} size={14} stroke={2.6} />Loaded</span>
    {:else if state === 'downloading'}
      <Button size="sm" variant="ghost" loading>…</Button>
    {:else if !loadable}
      <span class="soon">Soon</span>
    {:else if state === 'downloaded'}
      <Button size="sm" icon={IconBolt} onclick={onLoad}>Load</Button>
    {:else}
      <Button size="sm" variant="soft" icon={IconDownload} onclick={onDownload}>Download</Button>
    {/if}
  </div>
</div>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 13px 4px;
    border-bottom: 1px solid var(--line);
  }
  .row:last-child { border-bottom: none; }
  .info { flex: 1; min-width: 0; }
  .name { display: block; font-size: 14.5px; font-weight: 600; letter-spacing: -0.01em; }
  .meta { display: block; font-size: 12px; color: var(--muted-2); font-family: var(--font-mono); margin-top: 1px; }
  .prog { display: flex; align-items: center; gap: 8px; margin-top: 9px; }
  .prog :global(.track) { flex: 1; }
  .lbl { font-size: 11px; font-weight: 600; color: var(--accent); white-space: nowrap; }
  .action { flex: none; }
  .badge { display: inline-flex; align-items: center; gap: 4px; font-size: 12.5px; font-weight: 600; color: var(--ok); }
  .soon { font-size: 12px; font-weight: 600; color: var(--muted-2); padding: 6px 10px; border-radius: var(--r-full); background: var(--surface-2); }
</style>
