import type { Component, ComponentType, SvelteComponent } from 'svelte';

export type IconComponent = Component<Record<string, unknown>> | ComponentType<SvelteComponent>;
