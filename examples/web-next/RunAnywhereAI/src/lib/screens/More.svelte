<script lang="ts">
  import { IconDatabase, IconMicrophone, IconPhoto, IconSparkles, IconVectorTriangle, IconVolume } from '@tabler/icons-svelte';
  import type { IconComponent } from '../icon';
  import AppBar from '../components/AppBar.svelte';
  import Icon from '../components/Icon.svelte';
  import ModelList from '../components/ModelList.svelte';
  import { displayItems } from '../catalog';
  import { router } from '../stores/router.svelte';
  import { sheet } from '../stores/sheet.svelte';

  const tiles: { id: string; label: string; sub: string; icon: IconComponent; open: () => void }[] = [
    { id: 'vision', label: 'Vision', sub: 'Describe & reason over images', icon: IconPhoto, open: () => router.go('vision') },
    { id: 'rag', label: 'RAG', sub: 'Chat over your documents', icon: IconDatabase, open: () => router.go('rag') },
    { id: 'tts', label: 'Text to Speech', sub: 'Synthesize speech on-device', icon: IconVolume, open: () => router.go('tts') },
    { id: 'stt', label: 'Speech to Text', sub: 'Transcribe your voice on-device', icon: IconMicrophone, open: () => router.go('stt') },
    { id: 'embed', label: 'Embeddings', sub: 'Vectorize text on-device', icon: IconVectorTriangle, open: () => sheet.show('Embedding models', ModelList, { items: displayItems('embedding') }) },
    { id: 'diffusion', label: 'Diffusion', sub: 'Image generation', icon: IconSparkles, open: () => sheet.show('Diffusion models', ModelList, { items: [] }) },
  ];
</script>

<div class="screen">
  <AppBar title="More" />
  <div class="grid">
    {#each tiles as t (t.id)}
      <button class="tile" onclick={t.open}>
        <span class="ic"><Icon icon={t.icon} size={24} stroke={1.7} /></span>
        <span class="label">{t.label}</span>
        <span class="sub">{t.sub}</span>
      </button>
    {/each}
  </div>
</div>

<style>
  .screen { min-height: 100dvh; }
  .grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 12px;
    padding: 18px;
    max-width: 560px;
    margin: 0 auto;
  }
  .tile {
    display: flex;
    flex-direction: column;
    gap: 4px;
    text-align: left;
    padding: 18px 16px;
    border: 1px solid var(--line);
    border-radius: var(--r);
    background: var(--surface);
    cursor: pointer;
    transition: transform 160ms var(--ease), border-color 200ms ease, box-shadow 200ms ease;
  }
  .tile:hover { border-color: var(--line-strong); box-shadow: var(--shadow-sm); }
  .tile:active { transform: scale(0.98); }
  .ic {
    width: 44px;
    height: 44px;
    display: grid;
    place-items: center;
    border-radius: var(--r-sm);
    background: var(--accent-soft);
    color: var(--accent);
    margin-bottom: 6px;
  }
  .label { font-size: 15px; font-weight: 700; }
  .sub { font-size: 12.5px; color: var(--muted-2); }
  @media (prefers-reduced-motion: reduce) { .tile { transition: none; } }
</style>
