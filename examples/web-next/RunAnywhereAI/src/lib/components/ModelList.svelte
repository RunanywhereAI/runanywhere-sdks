<script lang="ts">
  import type { ModelItem } from '../types';
  import ModelRow from './ModelRow.svelte';

  interface Props {
    items?: ModelItem[];
    loadable?: boolean;
    onDownload?: (id: string) => void;
    onLoad?: (id: string) => void;
  }

  let { items = [], loadable = false, onDownload, onLoad }: Props = $props();
</script>

<div class="list">
  {#each items as m (m.id)}
    <ModelRow
      name={m.name}
      meta={m.meta}
      state={m.state}
      progress={m.progress ?? 0}
      {loadable}
      onDownload={() => onDownload?.(m.id)}
      onLoad={() => onLoad?.(m.id)}
    />
  {/each}
</div>

<style>
  .list {
    display: flex;
    flex-direction: column;
  }
</style>
