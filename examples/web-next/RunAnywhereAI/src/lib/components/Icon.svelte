<script lang="ts">
  import type { IconComponent } from '../icon';

  interface Props {
    icon: IconComponent;
    size?: number;
    stroke?: number;
  }

  let { icon, size = 20, stroke = 1.8 }: Props = $props();
</script>

{#if icon}
  {@const C = icon}
  <C {size} {stroke} />
{/if}
