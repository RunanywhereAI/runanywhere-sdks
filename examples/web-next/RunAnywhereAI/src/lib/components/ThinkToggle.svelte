<script lang="ts">
  import { IconBrain } from '@tabler/icons-svelte';
  import Icon from './Icon.svelte';

  interface Props {
    active: boolean;
    onToggle: () => void;
  }

  let { active, onToggle }: Props = $props();
</script>

<button
  class="tt"
  class:active
  onclick={onToggle}
  aria-pressed={active}
  title={active ? 'Thinking on' : 'Thinking off'}
>
  <Icon icon={IconBrain} size={15} stroke={active ? 2.2 : 1.8} />
  <span>Think</span>
</button>

<style>
  .tt {
    display: inline-flex;
    align-items: center;
    gap: 5px;
    height: 34px;
    padding: 0 12px;
    border: 1px solid var(--line-strong);
    border-radius: var(--r-full);
    background: var(--surface);
    color: var(--muted);
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: background 160ms ease, color 160ms ease, border-color 160ms ease;
  }
  .tt:hover { color: var(--ink); }
  .tt.active {
    color: var(--accent);
    background: var(--accent-soft);
    border-color: transparent;
  }
</style>
