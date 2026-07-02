import { VLMGenerationOptions, VLMImage, VLMImageFormat } from '@runanywhere/proto-ts/vlm_options';
import { models } from './models.svelte';

const MAX_DIM = 512;

class VisionStore {
  previewUrl = $state<string | null>(null);
  answer = $state('');
  generating = $state(false);

  private rgb: Uint8Array | null = null;
  private width = 0;
  private height = 0;

  get ready(): boolean {
    return models.loadedVlmId != null;
  }

  get hasImage(): boolean {
    return this.previewUrl != null;
  }

  async setImage(file: File): Promise<void> {
    if (this.previewUrl) URL.revokeObjectURL(this.previewUrl);
    const bitmap = await createImageBitmap(file);
    const scale = Math.min(1, MAX_DIM / Math.max(bitmap.width, bitmap.height));
    const w = Math.max(1, Math.round(bitmap.width * scale));
    const h = Math.max(1, Math.round(bitmap.height * scale));

    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('canvas 2d context unavailable');
    ctx.drawImage(bitmap, 0, 0, w, h);
    bitmap.close?.();

    const rgba = ctx.getImageData(0, 0, w, h).data;
    const rgb = new Uint8Array(w * h * 3);
    for (let i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
      rgb[j] = rgba[i];
      rgb[j + 1] = rgba[i + 1];
      rgb[j + 2] = rgba[i + 2];
    }

    this.rgb = rgb;
    this.width = w;
    this.height = h;
    this.previewUrl = URL.createObjectURL(file);
    this.answer = '';
  }

  clear(): void {
    if (this.generating) return;
    if (this.previewUrl) URL.revokeObjectURL(this.previewUrl);
    this.previewUrl = null;
    this.rgb = null;
    this.answer = '';
  }

  async run(prompt: string): Promise<void> {
    const text = prompt.trim();
    if (!text || !this.rgb || this.generating || !this.ready) return;

    this.generating = true;
    this.answer = '';
    try {
      const { RunAnywhere } = await import('@runanywhere/web');
      const image = VLMImage.fromPartial({
        rawRgb: this.rgb,
        format: VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB,
        width: this.width,
        height: this.height,
        sizeBytes: this.rgb.byteLength,
      });
      const options = VLMGenerationOptions.fromPartial({
        prompt: text,
        maxTokens: 512,
        temperature: 0.4,
        topP: 0.9,
        streamingEnabled: true,
      });
      for await (const event of RunAnywhere.streamImage(image, options)) {
        if (event.token) this.answer += event.token;
        if (event.isFinal) break;
      }
    } catch (err) {
      this.answer = this.answer || `Error: ${err instanceof Error ? err.message : String(err)}`;
    } finally {
      this.generating = false;
    }
  }
}

export const vision = new VisionStore();
