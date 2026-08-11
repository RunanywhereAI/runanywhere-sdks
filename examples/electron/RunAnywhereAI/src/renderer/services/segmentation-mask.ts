/**
 * Presentation helpers for the Segmentation screen.
 *
 * Commons has no image decoder — `rac_segmentation_image_t` takes decoded pixels —
 * so the chosen file is decoded here and handed over as raw RGB. The mask painter
 * is likewise pure presentation until the SDK grows `image.fromFile`.
 */

/** A distinct colour per class id, spaced by the golden angle. */
export function classRgb(id: number): readonly [number, number, number] {
  const h = ((id * 137.508) % 360) / 60;
  const c = 0.62;
  const x = c * (1 - Math.abs((h % 2) - 1));
  const m = 0.24;
  const [r, g, b] =
    h < 1
      ? [c, x, 0]
      : h < 2
        ? [x, c, 0]
        : h < 3
          ? [0, c, x]
          : h < 4
            ? [0, x, c]
            : h < 5
              ? [x, 0, c]
              : [c, 0, x];
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}

export interface RawRgbImage {
  readonly rgb: Uint8Array;
  readonly width: number;
  readonly height: number;
}

/** Decode a browser `File` to packed 8-bit RGB, capped on the long edge. */
export async function decodeRawRgb(file: File, maxEdge = 512): Promise<RawRgbImage> {
  const bitmap = await createImageBitmap(file);
  try {
    const scale = Math.min(1, maxEdge / Math.max(bitmap.width, bitmap.height));
    const width = Math.max(1, Math.round(bitmap.width * scale));
    const height = Math.max(1, Math.round(bitmap.height * scale));
    const off = document.createElement('canvas');
    off.width = width;
    off.height = height;
    const ctx = off.getContext('2d');
    if (ctx === null) throw new Error('2D canvas context unavailable');
    ctx.drawImage(bitmap, 0, 0, width, height);
    const rgba = ctx.getImageData(0, 0, width, height).data;
    const rgb = new Uint8Array(width * height * 3);
    for (let i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
      rgb[j] = rgba[i] ?? 0;
      rgb[j + 1] = rgba[i + 1] ?? 0;
      rgb[j + 2] = rgba[i + 2] ?? 0;
    }
    return { rgb, width, height };
  } finally {
    bitmap.close();
  }
}

export interface ClassMaskResult {
  readonly classMask: Uint8Array | Uint16Array | Int32Array | number[];
  readonly width: number;
  readonly height: number;
}

/** Paint a class-id mask onto a canvas for display. */
export function paintClassMask(canvas: HTMLCanvasElement, result: ClassMaskResult): boolean {
  const { classMask, width, height } = result;
  if (classMask.length < width * height) {
    canvas.style.display = 'none';
    return false;
  }
  const pixels = new Uint8ClampedArray(width * height * 4);
  const palette = new Map<number, readonly [number, number, number]>();
  for (let i = 0; i < width * height; i += 1) {
    const id = Number(classMask[i] ?? 0);
    let rgb = palette.get(id);
    if (rgb === undefined) {
      rgb = classRgb(id);
      palette.set(id, rgb);
    }
    pixels[i * 4] = rgb[0];
    pixels[i * 4 + 1] = rgb[1];
    pixels[i * 4 + 2] = rgb[2];
    pixels[i * 4 + 3] = 255;
  }
  canvas.width = width;
  canvas.height = height;
  canvas.style.display = 'block';
  const ctx = canvas.getContext('2d');
  if (ctx === null) return false;
  ctx.putImageData(new ImageData(pixels, width, height), 0, 0);
  return true;
}
