/**
 * Turning a picked image into the pixels a vision model reads — once.
 *
 * WHY THIS EXISTS. The Vision tab and the chat composer's image attachment both
 * need the same thing: an aspect-preserving downscale of whatever the user
 * picked, alpha stripped, in the packed `RGBRGB…` layout
 * `RunAnywhere.ImageInput.rawRgb` takes. Both had their own byte-identical copy
 * of the canvas dance, the RGBA→RGB loop and the "could not decode" error, which
 * is two places for the size limit to drift apart and two places to fix a decode
 * bug in.
 *
 * The downscale is not a nicety. `ImageInput.blob` would hand the encoded file
 * straight to the WASM decoder, and a 12 MB photo decodes to ~200 MB of RGB —
 * enough to exhaust a wasm32 heap that also holds the model. Fitting the longest
 * side to `maxDim` first is what keeps a phone photo from ending the session,
 * and the vision encoder resizes to its own fixed input anyway, so nothing is
 * lost by doing it here.
 */

/** Packed 3-bytes-per-pixel RGB samples, as `ImageInput.rawRgb` expects. */
export interface RgbFrame {
  rgbPixels: Uint8Array;
  width: number;
  height: number;
}

/** A decoded frame plus a data URL of exactly those pixels, for the preview. */
export interface DecodedImageFrame extends RgbFrame {
  previewUrl: string;
}

/**
 * The ceiling on a picked image, in bytes.
 *
 * A limit rather than a silent downscale-and-hope: decoding happens before any
 * resize can, so an arbitrarily large file is a browser-tab risk no matter what
 * this module does with it afterwards. 12 MB clears every phone camera JPEG.
 */
export const MAX_IMAGE_BYTES = 12 * 1024 * 1024;

/**
 * Why this file cannot be used as an image, or `null` when it can.
 *
 * Type is checked as well as size because an `accept` attribute only filters a
 * *picker* — a drop and a paste never consult it, and a user can switch any
 * picker to "All Files".
 */
export function validateImageFile(file: File): string | null {
  if (file.size === 0) return 'That file is empty.';
  if (!file.type.startsWith('image/')) {
    return 'That is not an image. Attach a PNG, JPEG, WebP, or GIF.';
  }
  if (file.size > MAX_IMAGE_BYTES) {
    return `Images must be ${formatMegabytes(MAX_IMAGE_BYTES)} or smaller.`;
  }
  return null;
}

/**
 * Decode a picked image file into raw RGB, downscaled so its longest side is at
 * most `maxDim`, together with a data URL of the same pixels.
 *
 * @throws Error when the browser cannot decode the file or 2D canvas is absent.
 */
export async function decodeImageFileToRgbFrame(
  file: File,
  maxDim: number,
): Promise<DecodedImageFrame> {
  const objectUrl = URL.createObjectURL(file);
  try {
    const img = await loadImageElement(objectUrl);
    const longest = Math.max(img.naturalWidth, img.naturalHeight) || 1;
    const scale = Math.min(1, maxDim / longest);
    const width = Math.max(1, Math.round(img.naturalWidth * scale));
    const height = Math.max(1, Math.round(img.naturalHeight * scale));

    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    if (!ctx) throw new Error('2D canvas context unavailable');
    ctx.drawImage(img, 0, 0, width, height);

    return {
      ...extractRgb(ctx, width, height),
      previewUrl: canvas.toDataURL('image/jpeg', 0.82),
    };
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}

/**
 * A data URL for pixels that are already in hand.
 *
 * The camera hands over RGB bytes and no image, so a captured still had nothing
 * to show once the camera was released — this is what lets the frame the model
 * is about to read stay on screen after the stream stops.
 */
export function rgbFrameToDataUrl(frame: RgbFrame): string | null {
  const canvas = document.createElement('canvas');
  canvas.width = frame.width;
  canvas.height = frame.height;
  const ctx = canvas.getContext('2d');
  if (!ctx) return null;
  const image = ctx.createImageData(frame.width, frame.height);
  for (let src = 0, dst = 0; src < frame.rgbPixels.length; src += 3, dst += 4) {
    image.data[dst] = frame.rgbPixels[src];
    image.data[dst + 1] = frame.rgbPixels[src + 1];
    image.data[dst + 2] = frame.rgbPixels[src + 2];
    image.data[dst + 3] = 255;
  }
  ctx.putImageData(image, 0, 0);
  return canvas.toDataURL('image/jpeg', 0.82);
}

/**
 * A small JPEG data URL for a decoded frame, cheap enough to persist.
 *
 * Chat keeps its turns in IndexedDB, so a full-size preview per image message
 * would grow the database without bound; a thumbnail at `maxDim` costs a few
 * kilobytes and is all a 44 px attachment card can show.
 */
export function rgbFrameToThumbnailDataUrl(frame: RgbFrame, maxDim: number): string | null {
  const source = document.createElement('canvas');
  source.width = frame.width;
  source.height = frame.height;
  const sourceCtx = source.getContext('2d');
  if (!sourceCtx) return null;
  const image = sourceCtx.createImageData(frame.width, frame.height);
  for (let src = 0, dst = 0; src < frame.rgbPixels.length; src += 3, dst += 4) {
    image.data[dst] = frame.rgbPixels[src];
    image.data[dst + 1] = frame.rgbPixels[src + 1];
    image.data[dst + 2] = frame.rgbPixels[src + 2];
    image.data[dst + 3] = 255;
  }
  sourceCtx.putImageData(image, 0, 0);

  const scale = Math.min(1, maxDim / (Math.max(frame.width, frame.height) || 1));
  const width = Math.max(1, Math.round(frame.width * scale));
  const height = Math.max(1, Math.round(frame.height * scale));
  const thumb = document.createElement('canvas');
  thumb.width = width;
  thumb.height = height;
  const thumbCtx = thumb.getContext('2d');
  if (!thumbCtx) return null;
  thumbCtx.drawImage(source, 0, 0, width, height);
  return thumb.toDataURL('image/jpeg', 0.7);
}

function extractRgb(ctx: CanvasRenderingContext2D, width: number, height: number): RgbFrame {
  const { data } = ctx.getImageData(0, 0, width, height); // RGBA
  const rgbPixels = new Uint8Array(width * height * 3);
  for (let src = 0, dst = 0; src < data.length; src += 4, dst += 3) {
    rgbPixels[dst] = data[src];
    rgbPixels[dst + 1] = data[src + 1];
    rgbPixels[dst + 2] = data[src + 2];
  }
  return { rgbPixels, width, height };
}

function loadImageElement(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('Could not decode the selected image'));
    img.src = src;
  });
}

function formatMegabytes(bytes: number): string {
  return `${Math.round(bytes / (1024 * 1024))} MB`;
}
