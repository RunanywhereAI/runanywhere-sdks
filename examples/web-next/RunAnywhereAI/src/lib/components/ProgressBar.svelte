<script lang="ts">
  interface Props {
    value?: number;
    indeterminate?: boolean;
  }

  let { value = 0, indeterminate = false }: Props = $props();
  const pct = $derived(Math.max(0, Math.min(1, value)) * 100);
</script>

<div class="track" class:indeterminate role="progressbar" aria-valuenow={indeterminate ? undefined : Math.round(pct)}>
  {#if indeterminate}
    <div class="ind"></div>
  {:else}
    <div class="fill" style="width: {pct}%"></div>
  {/if}
</div>

<style>
  .track {
    position: relative;
    height: 6px;
    border-radius: var(--r-full);
    background: var(--surface-3);
    overflow: hidden;
  }
  .fill {
    height: 100%;
    border-radius: inherit;
    background: var(--accent);
    transition: width 320ms var(--ease);
  }
  .ind {
    position: absolute;
    inset: 0 auto 0 0;
    width: 38%;
    border-radius: inherit;
    background: var(--accent);
    animation: slide 1.1s ease-in-out infinite;
  }
  @keyframes slide {
    0% { transform: translateX(-100%); }
    100% { transform: translateX(320%); }
  }
  @media (prefers-reduced-motion: reduce) { .ind { animation: none; } }
</style>
