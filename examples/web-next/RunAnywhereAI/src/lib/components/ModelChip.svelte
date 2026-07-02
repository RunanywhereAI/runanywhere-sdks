<script lang="ts">
  import { IconChevronDown } from '@tabler/icons-svelte';
  import Icon from './Icon.svelte';

  interface Props {
    label: string;
    onclick?: () => void;
  }

  let { label, onclick }: Props = $props();
</script>

<button class="chip" {onclick}>
  <span class="dot"></span>
  <span class="txt">{label}</span>
  <Icon icon={IconChevronDown} size={15} stroke={2} />
</button>

<style>
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    height: 34px;
    padding: 0 10px 0 11px;
    border: 1px solid var(--line-strong);
    border-radius: var(--r-full);
    background: var(--surface);
    color: var(--ink);
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    max-width: 52vw;
    transition: border-color 180ms ease, background 180ms ease;
  }
  .chip:hover { background: var(--surface-2); }
  .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--accent); flex: none; }
  .txt { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
</style>
