import type { Component } from 'svelte';

interface SheetState {
  title: string;
  content: Component<any> | null;
  props: Record<string, unknown>;
}

class SheetStore {
  open = $state(false);
  title = $state('');
  content = $state<Component<any> | null>(null);
  props = $state<Record<string, unknown>>({});

  show(title: string, content: Component<any>, props: Record<string, unknown> = {}): void {
    this.title = title;
    this.content = content;
    this.props = props;
    this.open = true;
  }

  close(): void {
    this.open = false;
  }

  snapshot(): SheetState {
    return { title: this.title, content: this.content, props: this.props };
  }
}

export const sheet = new SheetStore();
