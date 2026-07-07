/**
 * @runanywhere/mlx - Apple MLX backend for RunAnywhere React Native SDK.
 *
 * The MLX runtime itself lives in the Swift `RunAnywhereMLX` product. This
 * package exposes the React Native registration call and delegates to the core
 * Nitro bridge, which discovers the Swift runtime C symbols at runtime.
 */

export { MLX } from './MLX';
