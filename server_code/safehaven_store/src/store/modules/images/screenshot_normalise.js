import { decodePixels, bilinearResize, u32be, pngChunk, compressZlib } from "./png_utils.js";

const MAX_W = 1080;
const MAX_H = 1920;

const flattenAlpha = (rgba, w, h) => {
  const out = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    const a    = rgba[i*4+3] / 255;
    out[i*4]   = Math.round(rgba[i*4]   * a + 255 * (1 - a));
    out[i*4+1] = Math.round(rgba[i*4+1] * a + 255 * (1 - a));
    out[i*4+2] = Math.round(rgba[i*4+2] * a + 255 * (1 - a));
    out[i*4+3] = 255;
  }
  return out;
};

const encodePng = async (rgba, w, h) => {
  const stride   = w * 3;
  const filtered = new Uint8Array(h * (stride + 1));

  for (let y = 0; y < h; y++) {
    filtered[y * (stride + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const si = (y * w + x) * 4;
      const di = y * (stride + 1) + 1 + x * 3;
      filtered[di]   = rgba[si];
      filtered[di+1] = rgba[si+1];
      filtered[di+2] = rgba[si+2];
    }
  }

  const compressed = await compressZlib(filtered);
  const ihdr = new Uint8Array([...u32be(w), ...u32be(h), 8, 2, 0, 0, 0]);
  const sig   = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
  const parts = [sig, pngChunk("IHDR", ihdr), pngChunk("IDAT", compressed), pngChunk("IEND", new Uint8Array(0))];
  const total = parts.reduce((s, p) => s + p.length, 0);
  const out   = new Uint8Array(total);
  let off     = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
};

export const normaliseScreenshot = async (bytes) => {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);

  const { width, height, rgba } = decodePixels(u8);

  if (width <= MAX_W && height <= MAX_H) {
    const flat = flattenAlpha(rgba, width, height);
    return encodePng(flat, width, height);
  }

  const scale   = Math.min(MAX_W / width, MAX_H / height);
  const dw      = Math.round(width  * scale);
  const dh      = Math.round(height * scale);
  const resized = bilinearResize(rgba, width, height, dw, dh);
  const flat    = flattenAlpha(resized, dw, dh);
  return encodePng(flat, dw, dh);
};
