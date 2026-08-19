/**
 * 文件路径: entry/src/main/ets/Framework/Utils/ImageCropper.ets
 * 职责: 提供基于设备屏幕分辨率比例的中心裁剪工具，使用HarmonyOS官方PixelMap读写API实现
 * 注意: 禁止使用any/unknown与解构语法，严格类型与显式空值检查
 */
import { image } from '@kit.ImageKit';
import { display } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'ImageCropper';

/** 目标比例接口（名义类型） */
export interface AspectRatio {
  width: number;
  height: number;
}

/** 裁剪矩形接口（名义类型） */
export interface CropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** 裁剪对齐枚举（名义类型） */
export enum CropAlignment {
  CENTER = 0,
  TOP = 1,
  BOTTOM = 2,
  LEFT = 3,
  RIGHT = 4,
  TOP_LEFT = 5,
  TOP_RIGHT = 6,
  CENTER_LEFT = 7,
  CENTER_RIGHT = 8,
  BOTTOM_LEFT = 9,
  BOTTOM_RIGHT = 10
}

/** 裁剪选项接口（名义类型） */
export interface CropOptions {
  targetRatio: AspectRatio;
  alignment: CropAlignment;
  zoom: number; // 缩放系数（>=1.0），值越大裁剪区域越小
}

/** 返回当前设备屏幕比例（以px的宽高计算） */
export function getDisplayAspectRatio(): AspectRatio {
  const disp = display.getDefaultDisplaySync();
  const w = disp.width;
  const h = disp.height;
  return { width: w, height: h } as AspectRatio;
}

/**
 * 根据目标比例计算中心裁剪矩形
 */
function computeCenterCropRect(srcWidth: number, srcHeight: number, targetRatio: AspectRatio): CropRect {
  const targetW = targetRatio.width;
  const targetH = targetRatio.height;
  const srcRatio = srcWidth / srcHeight;
  const tgtRatio = targetW / targetH;

  let cropWidth = srcWidth;
  let cropHeight = srcHeight;

  if (srcRatio > tgtRatio) {
    // 过宽，按目标比例减少宽度
    cropWidth = Math.floor(srcHeight * tgtRatio);
    cropHeight = srcHeight;
  } else if (srcRatio < tgtRatio) {
    // 过高，按目标比例减少高度
    cropWidth = srcWidth;
    cropHeight = Math.floor(srcWidth / tgtRatio);
  } else {
    cropWidth = srcWidth;
    cropHeight = srcHeight;
  }

  const startX = Math.max(0, Math.floor((srcWidth - cropWidth) / 2));
  const startY = Math.max(0, Math.floor((srcHeight - cropHeight) / 2));

  return { x: startX, y: startY, width: cropWidth, height: cropHeight } as CropRect;
}

/**
 * 根据对齐与缩放选项计算裁剪矩形
 */
function computeCropRectWithOptions(srcWidth: number, srcHeight: number, options: CropOptions): CropRect {
  const baseRect = computeCenterCropRect(srcWidth, srcHeight, options.targetRatio);
  const zoomFactor = options.zoom <= 1.0 ? 1.0 : options.zoom;

  // 按缩放系数缩小裁剪区域，保持比例不变
  const targetWidth = Math.max(1, Math.floor(baseRect.width / zoomFactor));
  const targetHeight = Math.max(1, Math.floor(baseRect.height / zoomFactor));

  // 计算起始坐标（对齐）
  let startX = baseRect.x + Math.floor((baseRect.width - targetWidth) / 2);
  let startY = baseRect.y + Math.floor((baseRect.height - targetHeight) / 2);

  // 组合对齐处理（九宫格）
  switch (options.alignment) {
    case CropAlignment.LEFT:
      startX = baseRect.x;
      break;
    case CropAlignment.RIGHT:
      startX = baseRect.x + (baseRect.width - targetWidth);
      break;
    case CropAlignment.TOP:
      startY = baseRect.y;
      break;
    case CropAlignment.BOTTOM:
      startY = baseRect.y + (baseRect.height - targetHeight);
      break;
    case CropAlignment.TOP_LEFT:
      startX = baseRect.x;
      startY = baseRect.y;
      break;
    case CropAlignment.TOP_RIGHT:
      startX = baseRect.x + (baseRect.width - targetWidth);
      startY = baseRect.y;
      break;
    case CropAlignment.CENTER_LEFT:
      startX = baseRect.x;
      // startY 保持居中
      break;
    case CropAlignment.CENTER_RIGHT:
      startX = baseRect.x + (baseRect.width - targetWidth);
      // startY 保持居中
      break;
    case CropAlignment.BOTTOM_LEFT:
      startX = baseRect.x;
      startY = baseRect.y + (baseRect.height - targetHeight);
      break;
    case CropAlignment.BOTTOM_RIGHT:
      startX = baseRect.x + (baseRect.width - targetWidth);
      startY = baseRect.y + (baseRect.height - targetHeight);
      break;
    case CropAlignment.CENTER:
    default:
      // 居中已是默认
      break;
  }

  // 边界保护
  if (startX < 0) { startX = 0; }
  if (startY < 0) { startY = 0; }
  const maxX = Math.max(0, srcWidth - targetWidth);
  const maxY = Math.max(0, srcHeight - targetHeight);
  if (startX > maxX) { startX = maxX; }
  if (startY > maxY) { startY = maxY; }

  const rect: CropRect = { x: startX, y: startY, width: targetWidth, height: targetHeight } as CropRect;
  return rect;
}

/**
 * 对PixelMap进行中心裁剪，裁剪后的PixelMap与目标比例一致
 */
export async function cropToAspect(pixelMap: image.PixelMap, targetRatio: AspectRatio): Promise<image.PixelMap> {
  const info = await pixelMap.getImageInfo();
  const srcWidth = info.size.width;
  const srcHeight = info.size.height;

  const rect = computeCenterCropRect(srcWidth, srcHeight, targetRatio);
  const bufferSize = rect.width * rect.height * 4; // RGBA8888
  const buffer = new ArrayBuffer(bufferSize);

  const readArea: image.PositionArea = {
    pixels: buffer,
    offset: 0,
    stride: rect.width * 4,
    region: {
      size: { width: rect.width, height: rect.height },
      x: rect.x,
      y: rect.y
    }
  };

  await pixelMap.readPixels(readArea);

  const initOptions: image.InitializationOptions = {
    size: { width: rect.width, height: rect.height },
    pixelFormat: 3, // RGBA_8888
    alphaType: 0,
    editable: true
  };

  const cropped = await image.createPixelMap(buffer, initOptions);
  return cropped;
}

/**
 * 按选项裁剪
 */
export async function cropToAspectWithOptions(pixelMap: image.PixelMap, options: CropOptions): Promise<image.PixelMap> {
  const info = await pixelMap.getImageInfo();
  const srcWidth = info.size.width;
  const srcHeight = info.size.height;

  const rect = computeCropRectWithOptions(srcWidth, srcHeight, options);
  const bufferSize = rect.width * rect.height * 4;
  const buffer = new ArrayBuffer(bufferSize);

  const readArea: image.PositionArea = {
    pixels: buffer,
    offset: 0,
    stride: rect.width * 4,
    region: {
      size: { width: rect.width, height: rect.height },
      x: rect.x,
      y: rect.y
    }
  };
  await pixelMap.readPixels(readArea);

  const initOptions: image.InitializationOptions = {
    size: { width: rect.width, height: rect.height },
    pixelFormat: 3,
    alphaType: 0,
    editable: true
  };
  const cropped = await image.createPixelMap(buffer, initOptions);
  return cropped;
}

/**
 * 基于当前设备屏幕比例进行中心裁剪（便捷方法）
 */
export async function cropToDisplayAspect(pixelMap: image.PixelMap): Promise<image.PixelMap> {
  try {
    const ratio = getDisplayAspectRatio();
    const out = await cropToAspect(pixelMap, ratio);
    return out;
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(TAG, `裁剪失败: ${msg}`);
    throw new Error(`裁剪失败: ${msg}`);
  }
}

/**
 * 基于设备比例的裁剪（对齐+缩放）
 */
export async function cropToDisplayAspectWithOptions(pixelMap: image.PixelMap, alignment: CropAlignment, zoom: number): Promise<image.PixelMap> {
  try {
    const ratio = getDisplayAspectRatio();
    const opts: CropOptions = { targetRatio: ratio, alignment: alignment, zoom: zoom } as CropOptions;
    const out = await cropToAspectWithOptions(pixelMap, opts);
    return out;
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    logger.error(TAG, `裁剪失败: ${msg}`);
    throw new Error(`裁剪失败: ${msg}`);
  }
}