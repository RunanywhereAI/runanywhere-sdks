<script lang="ts">
  interface Props {
    tone?: 'idle' | 'busy' | 'ready' | 'error';
    label: string;
  }

  let { tone = 'idle', label }: Props = $props();
</script>

<span class="pill {tone}">
  <i></i>{label}
</span>

<style>
  .pill {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.01em;
    padding: 5px 11px 5px 9px;
    border-radius: var(--r-full);
    background: var(--surface-2);
    color: var(--muted);
    border: 1px solid var(--line);
  }
  i {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: currentColor;
  }
  .busy { color: var(--accent); background: var(--accent-soft); border-color: transparent; }
  .ready { color: var(--ok); background: var(--ok-soft); border-color: transparent; }
  .error { color: var(--err); background: var(--err-soft); border-color: transparent; }
  .busy i { animation: blink 1s ease-in-out infinite; }
  @keyframes blink { 50% { opacity: 0.3; } }
  @media (prefers-reduced-motion: reduce) { .busy i { animation: none; } }
</style>
