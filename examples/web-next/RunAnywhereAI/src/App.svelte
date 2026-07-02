<script lang="ts">
  import { onMount } from 'svelte';
  import { fade } from 'svelte/transition';
  import type { Component } from 'svelte';
  import BottomBar from './lib/components/BottomBar.svelte';
  import Sheet from './lib/components/Sheet.svelte';
  import { router } from './lib/stores/router.svelte';
  import { sdk } from './lib/stores/sdk.svelte';
  import Chat from './lib/screens/Chat.svelte';
  import Voice from './lib/screens/Voice.svelte';
  import More from './lib/screens/More.svelte';
  import Settings from './lib/screens/Settings.svelte';
  import Vision from './lib/screens/Vision.svelte';
  import Rag from './lib/screens/Rag.svelte';
  import Tts from './lib/screens/Tts.svelte';
  import Stt from './lib/screens/Stt.svelte';

  onMount(() => {
    void sdk.boot();
  });

  const screens: Record<string, Component<any>> = {
    chat: Chat,
    voice: Voice,
    more: More,
    settings: Settings,
    vision: Vision,
    rag: Rag,
    tts: Tts,
    stt: Stt,
  };
</script>

<div class="shell">
  <main class="content" class:flush={router.active === 'chat' || router.active === 'vision' || router.active === 'rag'}>
    {#key router.active}
      {@const Screen = screens[router.active]}
      <div class="page" in:fade={{ duration: 180 }}>
        <Screen />
      </div>
    {/key}
  </main>
  <BottomBar />
  <Sheet />
</div>

<style>
  .shell { min-height: 100dvh; }
  .content {
    min-height: 100dvh;
    padding-bottom: calc(var(--nav) + env(safe-area-inset-bottom) + 28px);
  }
  .content.flush { padding-bottom: 0; }
</style>
