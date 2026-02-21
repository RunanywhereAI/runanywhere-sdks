/**
 * @runanywhere/web-kittentts
 *
 * KittenTTS backend for the RunAnywhere Web SDK.
 * Provides high-quality text-to-speech using KittenTTS (StyleTTS 2)
 * models with onnxruntime-web inference.
 *
 * 8 built-in voices: Bella, Jasper, Luna, Bruno, Rosie, Hugo, Kiki, Leo
 * Sample rate: 24000 Hz
 *
 * Usage:
 *   import { KittenTTSProvider } from '@runanywhere/web-kittentts';
 *   KittenTTSProvider.register();
 */

export { KittenTTSProvider } from './KittenTTSProvider';
export type { KittenTTSConfig, KittenTTSVoice } from './Foundation/KittenTTSEngine';
