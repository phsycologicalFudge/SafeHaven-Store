import { PhotonImage } from "@cf-wasm/photon";

const MAX_W = 1080;
const MAX_H = 1920;

const decodePixels = (bytes) => {
  const u8  = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const img = PhotonImage.new_from_byteslice(u8);
  const width  = img.get_width();
  const height = img.get_height();
  const rgba   = img.get_raw_pixels();
  img.free();
  return { width, height, rgba };
};

const bilinearResize = (src, sw, sh, dw, dh) => {
  const dst  = new Uint8Array(dw * dh * 4);
  const xRat = sw / dw;
  const yRat = sh / dh;

  for (let dy = 0; dy < dh; dy++) {
    for (let dx = 0; dx < dw; dx++) {
      const sx  = dx * xRat;
      const sy  = dy * yRat;
      const x0  = Math.floor(sx);
      const y0  = Math.floor(sy);
      const x1  = Math.min(x0 + 1, sw - 1);
      const y1  = Math.min(y0 + 1, sh - 1);
      const xf  = sx - x0;
      const yf  = sy - y0;

      const i00 = (y0 * sw + x0) * 4;
      const i10 = (y0 * sw + x1) * 4;
      const i01 = (y1 * sw + x0) * 4;
      const i11 = (y1 * sw + x1) * 4;

      const di = (dy * dw + dx) * 4;
      for (let c = 0; c < 4; c++) {
        dst[di + c] = Math.round(
          src[i00+c] * (1-xf) * (1-yf) +
          src[i10+c] * xf     * (1-yf) +
          src[i01+c] * (1-xf) * yf     +
          src[i11+c] * xf     * yf
        );
      }
    }
  }

  return dst;
};

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

const crc32Table = (() => {
  const t = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let j = 0; j < 8; j++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    t[i] = c;
  }
  return t;
})();

const crc32 = (data) => {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < data.length; i++) c = crc32Table[(c ^ data[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
};

const u32be = (n) => [(n >>> 24) & 0xFF, (n >>> 16) & 0xFF, (n >>> 8) & 0xFF, n & 0xFF];

const pngChunk = (type, data) => {
  const typeBytes = type.split("").map((c) => c.charCodeAt(0));
  const crc       = crc32(new Uint8Array([...typeBytes, ...data]));
  return new Uint8Array([...u32be(data.length), ...typeBytes, ...data, ...u32be(crc)]);
};

const compressZlib = async (data) => {
  const cs     = new CompressionStream("deflate");
  const writer = cs.writable.getWriter();
  const reader = cs.readable.getReader();

  writer.write(data);
  writer.close();

  const chunks = [];
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
  }

  const raw = new Uint8Array(chunks.reduce((s, c) => s + c.length, 0));
  let off   = 0;
  for (const c of chunks) { raw.set(c, off); off += c.length; }
  return raw;
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