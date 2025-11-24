// 文件路径：entry/src/main/ets/Utils/AvifTranscoder.ets
/**
 * 全局 AVIF 转换工具
 * 提供将 AVIF 转码为 WebP 的统一能力，避免在各处重复实现
 */
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { SandboxManager } from '../Framework/Storage/SandboxManager';
import { logger } from './Logger';

const TAG: string = 'AvifTranscoder';

/**
 * 转码结果接口
 */
export interface AvifTranscodeResult {
  success: boolean;
  webpPath?: string;
  name?: string;
  width?: number;
  height?: number;
  fileSize?: number;
  outputFormat?: TranscodeFormat;
  error?: AvifErrorDetails;
}

/**
 * AVIF 文件头诊断信息（ISOBMFF）
 */
interface AvifHeaderInfo {
  isIsobmff: boolean;
  boxType?: string;
  boxSize?: number;
  majorBrand?: string;
  minorVersion?: number;
  compatibleBrands: string[];
}

// 失败阶段枚举
export enum TranscodeFailStage {
  OPEN_FILE = 'OPEN_FILE',
  CREATE_SOURCE = 'CREATE_SOURCE',
  CREATE_PIXELMAP = 'CREATE_PIXELMAP',
  PACK_TO_DATA = 'PACK_TO_DATA',
  WRITE_FILE = 'WRITE_FILE',
  STAT_FILE = 'STAT_FILE',
  UNKNOWN = 'UNKNOWN'
}

// 错误详情结构
export interface AvifErrorDetails {
  name: string;
  message: string;
  stack?: string;
  stage: TranscodeFailStage;
  header?: AvifHeaderInfo;
}

/**
 * 输出格式枚举（与 ImagePacker 的格式字符串一致）
 */
export enum TranscodeFormat {
  WEBP = 'image/webp',
  PNG = 'image/png',
  JPEG = 'image/jpeg',
  HEIF = 'image/heif'
}

/**
 * 转码选项（格式与质量）
 */
interface AvifTranscodeOptions {
  format: TranscodeFormat;
  quality?: number; // 0-100，可选
}

/**
 * AVIF 转码工具单例
 */
export class AvifTranscoder {
  private static instance: AvifTranscoder | null = null;

  private constructor() {}

  public static getInstance(): AvifTranscoder {
    if (!AvifTranscoder.instance) {
      AvifTranscoder.instance = new AvifTranscoder();
    }
    return AvifTranscoder.instance as AvifTranscoder;
  }

  /**
   * 将 AVIF 文件在原目录转码为 WebP
   */
  public async transcodeToSameDirectory(avifPath: string, options?: AvifTranscodeOptions): Promise<AvifTranscodeResult> {
    try {
      const dotIndex: number = avifPath.lastIndexOf('.');
      const basePath: string = dotIndex >= 0 ? avifPath.substring(0, dotIndex) : avifPath;
      const opts: AvifTranscodeOptions = this.normalizeOptions(options);
      const targetExt: string = this.extFromFormat(opts.format);
      const targetOutputPath: string = `${basePath}${targetExt}`;
      return await this.transcodeInternal(avifPath, targetOutputPath, opts);
  } catch (e) {
    const err: Error = e as Error;
    const detail: string = `${String(err.name)}: ${String(err.message)}`;
    logger.warn(TAG, `原目录转码失败: ${avifPath}`, detail);
    if (err.stack) {
      logger.debug(TAG, `异常堆栈: ${String(err.stack)}`);
    }
    const errorDetails: AvifErrorDetails = await this.buildErrorDetails(err, TranscodeFailStage.UNKNOWN, avifPath);
    return { success: false, error: errorDetails } as AvifTranscodeResult;
  }
  }

  /**
   * 将 AVIF 文件转码为 WebP 并写入指定目标目录
   */
  public async transcodeToTargetDirectory(avifPath: string, targetDir: string, options?: AvifTranscodeOptions): Promise<AvifTranscodeResult> {
    try {
      const fileName: string = avifPath.substring(avifPath.lastIndexOf('/') + 1);
      const baseName: string = fileName.substring(0, fileName.lastIndexOf('.'));
      const opts: AvifTranscodeOptions = this.normalizeOptions(options);
      const targetExt: string = this.extFromFormat(opts.format);
      const targetOutputPath: string = `${targetDir}/${baseName}${targetExt}`;
      return await this.transcodeInternal(avifPath, targetOutputPath, opts);
  } catch (e) {
    const err: Error = e as Error;
    const detail: string = `${String(err.name)}: ${String(err.message)}`;
    logger.warn(TAG, `指定目录转码失败: ${avifPath}`, detail);
    if (err.stack) {
      logger.debug(TAG, `异常堆栈: ${String(err.stack)}`);
    }
    const errorDetails: AvifErrorDetails = await this.buildErrorDetails(err, TranscodeFailStage.UNKNOWN, avifPath);
    return { success: false, error: errorDetails } as AvifTranscodeResult;
  }
  }

  /**
   * 内部通用转码逻辑：使用文件描述符读取 AVIF，解码为 PixelMap，再打包为 WebP 写入目标路径
   */
  private async transcodeInternal(avifPath: string, targetOutputPath: string, options?: AvifTranscodeOptions): Promise<AvifTranscodeResult> {
    let openedFd: number | null = null;
    let imgSource: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    let imagePacker: image.ImagePacker | null = null;
    let stage: TranscodeFailStage = TranscodeFailStage.OPEN_FILE;
    try {
      const openedFile = await fileIo.open(avifPath, fileIo.OpenMode.READ_ONLY);
      openedFd = openedFile.fd;
      stage = TranscodeFailStage.CREATE_SOURCE;
      imgSource = image.createImageSource(openedFd);

      const decodingOptions: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      } as image.DecodingOptions;
      stage = TranscodeFailStage.CREATE_PIXELMAP;
      pixelMap = await imgSource.createPixelMap(decodingOptions);
      imgSource.release();
      imgSource = null;

      // 获取图像信息
      const info = await pixelMap.getImageInfo();
      const w: number = info.size.width;
      const h: number = info.size.height;

      // 打包为目标格式（PNG/JPEG/WebP/HEIF），官方链路：packToData
      const opts: AvifTranscodeOptions = this.normalizeOptions(options);
      const packOpts: image.PackingOption = {
        format: String(opts.format),
        quality: opts.quality !== undefined ? (opts.quality as number) : 85
      } as image.PackingOption;
      imagePacker = image.createImagePacker();
      stage = TranscodeFailStage.PACK_TO_DATA;
      const outputBuffer: ArrayBuffer = await imagePacker.packToData(pixelMap, packOpts);
      imagePacker.release();
      imagePacker = null;

      // 释放像素图资源
      pixelMap.release();
      pixelMap = null;

      // 写入到目标路径
      const sandbox = SandboxManager.getInstance();
      stage = TranscodeFailStage.WRITE_FILE;
      await sandbox.writeFile(targetOutputPath, outputBuffer);

      stage = TranscodeFailStage.STAT_FILE;
      const statInfo = await fileIo.stat(targetOutputPath);
      const result: AvifTranscodeResult = {
        success: true,
        webpPath: targetOutputPath, // 为兼容旧调用，仍复用该字段承载输出路径
        name: targetOutputPath.substring(targetOutputPath.lastIndexOf('/') + 1),
        width: w,
        height: h,
        fileSize: statInfo.size || 0,
        outputFormat: opts.format
      } as AvifTranscodeResult;
      return result;
    } catch (error) {
    // 解码或打包失败通常意味着设备不支持 AVIF 或文件不合法
    const err: Error = error as Error;
    const detail: string = `${String(err.name)}: ${String(err.message)}`;
    logger.warn(TAG, `AVIF 转码失败或设备不支持: ${avifPath}`, detail);
    if (err.stack) {
      logger.debug(TAG, `异常堆栈: ${String(err.stack)}`);
    }
      // 进行一次文件头诊断，辅助定位是设备能力问题还是源文件格式问题
      try {
        const header = await this.probeAvifHeader(avifPath);
        const brandsSummary: string = header.compatibleBrands.length > 0 ? header.compatibleBrands.join(',') : '无';
        logger.debug(TAG, `AVIF头诊断: isobmff=${String(header.isIsobmff)}, boxType=${String(header.boxType)}, majorBrand=${String(header.majorBrand)}, minor=${String(header.minorVersion)}, compat=[${brandsSummary}]`);
        if (header.isIsobmff && header.majorBrand) {
          const brandLower: string = (header.majorBrand as string).toLowerCase();
          const isAvifBrand: boolean = (brandLower === 'avif') || (brandLower === 'avis');
          const hasMif1: boolean = header.compatibleBrands.includes('mif1');
          const hasMsf1: boolean = header.compatibleBrands.includes('msf1');
          if (!isAvifBrand || !(hasMif1 || hasMsf1)) {
            logger.warn(TAG, `AVIF文件头不符合标准（可能是误标或不完整）：majorBrand=${String(header.majorBrand)}, compat=${brandsSummary}`);
          }
        } else if (header.isIsobmff === false) {
          logger.warn(TAG, '文件头非ISOBMFF结构（可能并非AVIF或已损坏）');
        }
      } catch (probeError) {
        logger.warn(TAG, 'AVIF文件头诊断失败', String(probeError instanceof Error ? probeError.message : probeError));
      }
      const errorDetails: AvifErrorDetails = await this.buildErrorDetails(err, stage, avifPath);
      return { success: false, error: errorDetails } as AvifTranscodeResult;
    } finally {
      // 兜底释放与关闭资源，严格遵守 ArkTS 内存管理
      if (imgSource) {
        imgSource.release();
      }
      if (pixelMap) {
        pixelMap.release();
      }
      if (imagePacker) {
        imagePacker.release();
      }
      if (openedFd !== null) {
        try {
          await fileIo.close(openedFd);
        } catch (closeError) {
          logger.warn(TAG, `文件描述符关闭失败: ${avifPath}`, String(closeError instanceof Error ? closeError.message : closeError));
        }
      }
    }
  }

  private async buildErrorDetails(err: Error, stage: TranscodeFailStage, avifPath: string): Promise<AvifErrorDetails> {
    let headerInfo: AvifHeaderInfo | undefined = undefined;
    try {
      const header = await this.probeAvifHeader(avifPath);
      headerInfo = header as AvifHeaderInfo;
    } catch (_) {
      headerInfo = undefined;
    }
    const details: AvifErrorDetails = {
      name: String(err.name),
      message: String(err.message),
      stack: err.stack ? String(err.stack) : undefined,
      stage: stage,
      header: headerInfo
    } as AvifErrorDetails;
    return details as AvifErrorDetails;
  }

  /**
   * 规范化选项，提供默认格式与质量
   */
  private normalizeOptions(options?: AvifTranscodeOptions): AvifTranscodeOptions {
    const defaultOpts: AvifTranscodeOptions = { format: TranscodeFormat.WEBP, quality: 85 } as AvifTranscodeOptions;
    if (!options) {
      return defaultOpts as AvifTranscodeOptions;
    }
    const format: TranscodeFormat = options.format ? (options.format as TranscodeFormat) : TranscodeFormat.WEBP;
    const quality: number | undefined = options.quality !== undefined ? (options.quality as number) : 85;
    const normalized: AvifTranscodeOptions = { format: format, quality: quality } as AvifTranscodeOptions;
    return normalized as AvifTranscodeOptions;
  }

  /**
   * 根据格式返回文件扩展名
   */
  private extFromFormat(format: TranscodeFormat): string {
    if (format === TranscodeFormat.WEBP) {
      return '.webp';
    }
    if (format === TranscodeFormat.PNG) {
      return '.png';
    }
    if (format === TranscodeFormat.JPEG) {
      return '.jpg';
    }
    if (format === TranscodeFormat.HEIF) {
      return '.heif';
    }
    // 默认回退 webp
    return '.webp';
  }

  /**
   * 读取并解析 AVIF 的 ISOBMFF 头部（ftyp box），用于诊断源文件格式是否正确
   */
  private async probeAvifHeader(avifPath: string): Promise<AvifHeaderInfo> {
    let fd: number | null = null;
    try {
      const file = await fileIo.open(avifPath, fileIo.OpenMode.READ_ONLY);
      fd = file.fd;
      const bufferSize: number = 64;
      const buffer: ArrayBuffer = new ArrayBuffer(bufferSize as number);
      const readLen: number = fileIo.readSync(fd, buffer);
      if (readLen < 16) {
        return { isIsobmff: false, compatibleBrands: [] } as AvifHeaderInfo;
      }
      const view: DataView = new DataView(buffer);
      const boxSize: number = view.getUint32(0, false);
      const boxType: string = this.readAscii(view, 4, 4);
      if (boxType !== 'ftyp') {
        return { isIsobmff: false, boxType: boxType, boxSize: boxSize, compatibleBrands: [] } as AvifHeaderInfo;
      }
      const majorBrand: string = this.readAscii(view, 8, 4);
      const minorVersion: number = view.getUint32(12, false);
      const compatibleBrands: string[] = [] as string[];
      let pos: number = 16;
      while ((pos + 4) <= (readLen as number)) {
        const brand: string = this.readAscii(view, pos, 4);
        compatibleBrands.push(brand);
        pos += 4;
      }
      const info: AvifHeaderInfo = {
        isIsobmff: true,
        boxType: boxType,
        boxSize: boxSize,
        majorBrand: majorBrand,
        minorVersion: minorVersion,
        compatibleBrands: compatibleBrands
      } as AvifHeaderInfo;
      return info;
    } catch (error) {
      throw error as Error;
    } finally {
      if (fd !== null) {
        try {
          await fileIo.close(fd);
        } catch (closeError) {
          logger.warn(TAG, `诊断文件描述符关闭失败: ${avifPath}`, String(closeError instanceof Error ? closeError.message : closeError));
        }
      }
    }
  }

  private readAscii(view: DataView, offset: number, count: number): string {
    let s: string = '';
    for (let i: number = 0; i < count; i++) {
      const code: number = view.getUint8(offset + i);
      s += String.fromCharCode(code);
    }
    return s;
  }
}