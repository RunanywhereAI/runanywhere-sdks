<script lang="ts">
  import type { IconComponent } from '../icon';
  import Icon from './Icon.svelte';

  interface Props {
    icon: IconComponent;
    label: string;
    size?: number;
    active?: boolean;
    disabled?: boolean;
    variant?: 'default' | 'accent';
    onclick?: () => void;
  }

  let { icon, label, size = 40, active = false, disabled = false, variant = 'default', onclick }: Props = $props();
</script>

<button
  class="ib {variant}"
  class:active
  style="--sz: {size}px"
  aria-label={label}
  title={label}
  {disabled}
  {onclick}
>
  <Icon {icon} size={size * 0.5} stroke={1.9} />
</button>

<style>
  .ib {
    width: var(--sz);
    height: var(--sz);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border: none;
    border-radius: var(--r-full);
    background: transparent;
    color: var(--muted);
    cursor: pointer;
    transition: background 180ms ease, color 180ms ease, transform 140ms var(--ease);
  }
  .ib:hover:not(:disabled) { background: var(--surface-2); color: var(--ink); }
  .ib:active:not(:disabled) { transform: scale(0.92); }
  .active { color: var(--accent); background: var(--accent-soft); }
  .accent { background: var(--accent); color: var(--on-accent); }
  .accent:hover:not(:disabled) { background: var(--accent); color: var(--on-accent); filter: brightness(1.05); }
  .ib:disabled { opacity: 0.4; cursor: not-allowed; }
  @media (prefers-reduced-motion: reduce) { .ib { transition: none; } }
</style>
