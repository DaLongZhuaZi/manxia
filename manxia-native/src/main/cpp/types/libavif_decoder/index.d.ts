/**
 * AVIF解码器Native模块类型声明
 */

export interface AvifDecodeResult {
  width: number;
  height: number;
  pixels: Uint8Array;
}

export interface AvifImageInfo {
  width: number;
  height: number;
}

export const isAvifFormat: (data: ArrayBuffer) => boolean;
export const isLibavifAvailable: () => boolean;
export const decodeAvifToRgba: (data: ArrayBuffer) => AvifDecodeResult | null;
export const decodeAvifAsync: (data: ArrayBuffer) => Promise<AvifDecodeResult | null>;
export const getAvifInfo: (data: ArrayBuffer) => AvifImageInfo | null;
