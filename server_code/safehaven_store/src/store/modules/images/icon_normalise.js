import { decodePixels, bilinearResize, u32be, pngChunk, compressZlib } from "./png_utils.js";

const CANVAS = 192;
const INNER  = 154;
const OFFSET = (CANVAS - INNER) / 2;

const sampleBackgroundColour = (rgba, w, h) => {
  const sampleSize = Math.min(5, Math.floor(Math.min(w, h) * 0.08) || 1);
  const samples = [];

  const addSamples = (startX, startY) => {
    for (let dy = 0; dy < sampleSize; dy++) {
      for (let dx = 0; dx < sampleSize; dx++) {
        const x = Math.min(startX + dx, w - 1);
        const y = Math.min(startY + dy, h - 1);
        const i = (y * w + x) * 4;
        if (rgba[i + 3] > 200) {
          samples.push([rgba[i], rgba[i+1], rgba[i+2]]);
        }
      }
    }
  };

  addSamples(0, 0);
  addSamples(w - sampleSize, 0);
  addSamples(0, h - sampleSize);
  addSamples(w - sampleSize, h - sampleSize);
  addSamples(Math.floor(w / 2) - Math.floor(sampleSize / 2), 0);
  addSamples(Math.floor(w / 2) - Math.floor(sampleSize / 2), h - sampleSize);
  addSamples(0, Math.floor(h / 2) - Math.floor(sampleSize / 2));
  addSamples(w - sampleSize, Math.floor(h / 2) - Math.floor(sampleSize / 2));

  if (samples.length === 0) {
    const borderSamples = [];
    const borderW = Math.max(1, Math.floor(w * 0.1));
    const borderH = Math.max(1, Math.floor(h * 0.1));
    for (let y = borderH; y < h - borderH; y += Math.max(1, Math.floor(h / 20))) {
      for (let x = borderW; x < w - borderW; x += Math.max(1, Math.floor(w / 20))) {
        const i = (y * w + x) * 4;
        if (rgba[i + 3] > 128) {
          borderSamples.push([rgba[i], rgba[i+1], rgba[i+2]]);
        }
      }
    }
    if (borderSamples.length > 0) {
      borderSamples.sort((a, b) => (a[0] + a[1] + a[2]) - (b[0] + b[1] + b[2]));
      const mid = borderSamples[Math.floor(borderSamples.length / 2)];
      return { r: mid[0], g: mid[1], b: mid[2] };
    }
    return { r: 255, g: 255, b: 255 };
  }

  samples.sort((a, b) => (a[0] + a[1] + a[2]) - (b[0] + b[1] + b[2]));
  const mid = samples[Math.floor(samples.length / 2)];
  return { r: mid[0], g: mid[1], b: mid[2] };
};

const buildSquircleMask = () => {
  const mask = new Uint8Array(CANVAS * CANVAS);
  const cx   = CANVAS / 2;
  const cy   = CANVAS / 2;
  const rx   = CANVAS / 2 - 1;
  const ry   = CANVAS / 2 - 1;
  const n    = 4;

  for (let y = 0; y < CANVAS; y++) {
    for (let x = 0; x < CANVAS; x++) {
      const dx = Math.abs((x - cx) / rx);
      const dy = Math.abs((y - cy) / ry);
      const v  = Math.pow(dx, n) + Math.pow(dy, n);
      const edge = 1.5 / rx;
      const inside = 1 - Math.min(1, Math.max(0, (v - (1 - edge)) / edge));
      mask[y * CANVAS + x] = Math.round(inside * 255);
    }
  }
  return mask;
};

const squircleMask = buildSquircleMask();

const compositeOntoSquircle = (srcRgba, srcW, srcH) => {
  const bg     = sampleBackgroundColour(srcRgba, srcW, srcH);
  const scale  = Math.min(INNER / srcW, INNER / srcH);
  const dstW   = Math.round(srcW * scale);
  const dstH   = Math.round(srcH * scale);
  const scaled = bilinearResize(srcRgba, srcW, srcH, dstW, dstH);

  const canvas = new Uint8Array(CANVAS * CANVAS * 4);
  for (let i = 0; i < CANVAS * CANVAS; i++) {
    canvas[i * 4]     = bg.r;
    canvas[i * 4 + 1] = bg.g;
    canvas[i * 4 + 2] = bg.b;
    canvas[i * 4 + 3] = 255;
  }

  const ox = Math.round(OFFSET + (INNER - dstW) / 2);
  const oy = Math.round(OFFSET + (INNER - dstH) / 2);

  for (let y = 0; y < dstH; y++) {
    for (let x = 0; x < dstW; x++) {
      const si = (y * dstW + x) * 4;
      const di = ((oy + y) * CANVAS + (ox + x)) * 4;
      const a  = scaled[si + 3] / 255;
      canvas[di]   = Math.round(scaled[si]   * a + bg.r * (1 - a));
      canvas[di+1] = Math.round(scaled[si+1] * a + bg.g * (1 - a));
      canvas[di+2] = Math.round(scaled[si+2] * a + bg.b * (1 - a));
      canvas[di+3] = 255;
    }
  }

  for (let i = 0; i < CANVAS * CANVAS; i++) {
    canvas[i * 4 + 3] = squircleMask[i];
  }

  return canvas;
};

const encodePng = async (rgba, w, h) => {
  const stride   = w * 4;
  const filtered = new Uint8Array(h * (stride + 1));

  for (let y = 0; y < h; y++) {
    filtered[y * (stride + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const si = (y * w + x) * 4;
      const di = y * (stride + 1) + 1 + x * 4;
      filtered[di]   = rgba[si];
      filtered[di+1] = rgba[si+1];
      filtered[di+2] = rgba[si+2];
      filtered[di+3] = rgba[si+3];
    }
  }

  const compressed = await compressZlib(filtered);
  const ihdr = new Uint8Array([...u32be(w), ...u32be(h), 8, 6, 0, 0, 0]);
  const sig   = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
  const parts = [sig, pngChunk("IHDR", ihdr), pngChunk("IDAT", compressed), pngChunk("IEND", new Uint8Array(0))];
  const total = parts.reduce((s, p) => s + p.length, 0);
  const out   = new Uint8Array(total);
  let off     = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
};

export const normaliseIcon = async (bytes) => {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const { width, height, rgba } = decodePixels(u8);
  const composited = compositeOntoSquircle(rgba, width, height);
  return encodePng(composited, CANVAS, CANVAS);
};
