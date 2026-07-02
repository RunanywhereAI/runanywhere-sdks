import '@fontsource-variable/figtree';
import '@fontsource/maple-mono';
import { mount } from 'svelte';
import './app.css';
import App from './App.svelte';

export default mount(App, { target: document.getElementById('app')! });
