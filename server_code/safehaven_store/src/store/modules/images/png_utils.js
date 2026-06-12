import { PhotonImage } from "@cf-wasm/photon";

export const decodePixels = (bytes) => {
  const u8     = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const img    = PhotonImage.new_from_byteslice(u8);
  const width  = img.get_width();
  const height = img.get_height();
  const rgba   = img.get_raw_pixels();
  img.free();
  return { width, height, rgba };
};

export const bilinearResize = (src, sw, sh, dw, dh) => {
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

export const crc32Table = (() => {
  const t = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let j = 0; j < 8; j++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    t[i] = c;
  }
  return t;
})();

export const crc32 = (data) => {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < data.length; i++) c = crc32Table[(c ^ data[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
};

export const u32be = (n) => [(n >>> 24) & 0xFF, (n >>> 16) & 0xFF, (n >>> 8) & 0xFF, n & 0xFF];

export const pngChunk = (type, data) => {
  const len = data.length;
  const out = new Uint8Array(12 + len);
  out[0] = (len >>> 24) & 0xFF;
  out[1] = (len >>> 16) & 0xFF;
  out[2] = (len >>> 8)  & 0xFF;
  out[3] = len & 0xFF;
  out[4] = type.charCodeAt(0);
  out[5] = type.charCodeAt(1);
  out[6] = type.charCodeAt(2);
  out[7] = type.charCodeAt(3);
  out.set(data, 8);
  const crc = crc32(out.subarray(4, 8 + len));
  out[8 + len]     = (crc >>> 24) & 0xFF;
  out[8 + len + 1] = (crc >>> 16) & 0xFF;
  out[8 + len + 2] = (crc >>> 8)  & 0xFF;
  out[8 + len + 3] = crc & 0xFF;
  return out;
};

export const compressZlib = async (data) => {
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