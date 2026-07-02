<script lang="ts">
  import { fly } from 'svelte/transition';
  import { generalSuggestions, toolSuggestions, type PromptSuggestion } from '../prompts';
  import Icon from './Icon.svelte';

  interface Props {
    tools?: boolean;
    onSelect: (prompt: string) => void;
  }

  let { tools = false, onSelect }: Props = $props();

  const items = $derived<PromptSuggestion[]>(tools ? toolSuggestions : generalSuggestions);
</script>

<div class="row">
  {#key tools}
    <div class="track" in:fly={{ x: 24, duration: 200 }}>
      {#each items as s (s.label)}
        <button class="pill" onclick={() => onSelect(s.prompt)}>
          <Icon icon={s.icon} size={15} stroke={1.9} />
          <span>{s.label}</span>
        </button>
      {/each}
    </div>
  {/key}
</div>

<style>
  .row {
    overflow-x: auto;
    scrollbar-width: none;
    -webkit-overflow-scrolling: touch;
    padding: 0 16px 8px;
  }
  .row::-webkit-scrollbar { display: none; }
  .track {
    display: flex;
    gap: 8px;
    width: max-content;
    max-width: 640px;
    margin: 0 auto;
  }
  .pill {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    white-space: nowrap;
    padding: 8px 13px;
    border: 1px solid var(--line);
    border-radius: var(--r-full);
    background: var(--surface-2);
    color: var(--ink);
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: background 160ms ease, border-color 160ms ease, transform 140ms var(--ease);
  }
  .pill :global(svg) { color: var(--accent); }
  .pill:hover { border-color: var(--line-strong); }
  .pill:active { transform: scale(0.96); }
  @media (prefers-reduced-motion: reduce) {
    .pill { transition: none; }
  }
</style>
