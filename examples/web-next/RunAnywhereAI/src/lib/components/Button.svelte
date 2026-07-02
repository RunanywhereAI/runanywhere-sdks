<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { IconComponent } from '../icon';
  import Icon from './Icon.svelte';

  interface Props {
    variant?: 'primary' | 'soft' | 'ghost' | 'danger';
    size?: 'sm' | 'md' | 'lg';
    icon?: IconComponent;
    loading?: boolean;
    disabled?: boolean;
    full?: boolean;
    onclick?: () => void;
    children?: Snippet;
  }

  let {
    variant = 'primary',
    size = 'md',
    icon,
    loading = false,
    disabled = false,
    full = false,
    onclick,
    children,
  }: Props = $props();
</script>

<button class="btn {variant} {size}" class:full disabled={disabled || loading} {onclick}>
  {#if loading}
    <span class="spin"></span>
  {:else if icon}
    <Icon {icon} size={size === 'sm' ? 15 : 17} stroke={2} />
  {/if}
  {#if children}<span class="lbl">{@render children()}</span>{/if}
</button>

<style>
  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    border: none;
    border-radius: var(--r-sm);
    font-weight: 600;
    cursor: pointer;
    white-space: nowrap;
    transition: transform 140ms var(--ease), filter 200ms ease, background 200ms ease, opacity 160ms ease;
  }
  .btn:active {
    transform: scale(0.97);
  }
  .btn:disabled {
    cursor: default;
    opacity: 0.55;
  }

  .sm { height: 34px; padding: 0 12px; font-size: 13px; }
  .md { height: 44px; padding: 0 16px; font-size: 14.5px; }
  .lg { height: 52px; padding: 0 20px; font-size: 16px; border-radius: var(--r); }
  .full { width: 100%; }

  .primary {
    background: var(--accent);
    color: var(--on-accent);
  }
  .primary:not(:disabled):hover { filter: brightness(1.04); }

  .soft {
    background: var(--accent-soft);
    color: var(--accent);
  }
  .ghost {
    background: transparent;
    color: var(--ink);
  }
  .ghost:not(:disabled):hover { background: var(--surface-2); }
  .danger {
    background: var(--err-soft);
    color: var(--err);
  }

  .spin {
    width: 16px;
    height: 16px;
    border: 2px solid color-mix(in srgb, currentColor 35%, transparent);
    border-top-color: currentColor;
    border-radius: 50%;
    animation: spin 700ms linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }

  @media (prefers-reduced-motion: reduce) {
    .btn, .spin { transition: none; animation: none; }
  }
</style>
