<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    title: string;
    actions?: Snippet;
    leading?: Snippet;
  }

  let { title, actions, leading }: Props = $props();
</script>

<header class="bar">
  <div class="lead">
    {#if leading}{@render leading()}{/if}
    <h1>{title}</h1>
  </div>
  {#if actions}<div class="actions">{@render actions()}</div>{/if}
</header>

<style>
  .bar {
    position: sticky;
    top: 0;
    z-index: 20;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: max(14px, env(safe-area-inset-top)) 18px 12px;
    background: color-mix(in srgb, var(--bg) 82%, transparent);
    backdrop-filter: blur(16px);
    border-bottom: 1px solid var(--line);
  }
  .lead {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
  }
  h1 {
    font-size: 21px;
    font-weight: 700;
    letter-spacing: -0.02em;
  }
  .actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }
</style>
