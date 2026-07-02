<script lang="ts">
  import { IconBrain, IconChevronRight } from '@tabler/icons-svelte';
  import Icon from './Icon.svelte';

  interface Props {
    text: string;
    live?: boolean;
  }

  let { text, live = false }: Props = $props();
  let open = $state(false);

  $effect(() => {
    open = live;
  });
</script>

<div class="think" class:live>
  <button class="head" onclick={() => (open = !open)}>
    <Icon icon={IconBrain} size={14} stroke={1.9} />
    <span class="lbl">{live ? 'Thinking…' : 'Thoughts'}</span>
    <span class="chev" class:open><Icon icon={IconChevronRight} size={14} stroke={2} /></span>
  </button>
  {#if open}
    <div class="body">{text.trim()}</div>
  {/if}
</div>

<style>
  .think {
    align-self: flex-start;
    max-width: 100%;
    border-left: 2px solid var(--accent-soft);
    padding-left: 10px;
  }
  .think.live { border-left-color: var(--accent); }
  .head {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    border: none;
    background: none;
    padding: 2px 0;
    color: var(--muted);
    font-size: 12.5px;
    font-weight: 600;
    cursor: pointer;
  }
  .think.live .head { color: var(--accent); }
  .head:hover { color: var(--ink); }
  .chev { display: inline-flex; transition: transform 160ms var(--ease); }
  .chev.open { transform: rotate(90deg); }
  .body {
    margin-top: 4px;
    font-size: 13px;
    line-height: 1.55;
    color: var(--muted-2);
    white-space: pre-wrap;
    word-break: break-word;
  }
  @media (prefers-reduced-motion: reduce) {
    .chev { transition: none; }
  }
</style>
