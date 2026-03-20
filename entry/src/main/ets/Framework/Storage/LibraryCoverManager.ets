import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import fs from '@ohos.file.fs';
import { logger } from '../../Utils/Logger';

const TAG = 'LibraryCoverManager';
const LIBRARY_COVER_DIR = 'library_covers';

export enum LibraryCoverType {
  MANGA = 'manga',
  NOVEL = 'novel',
  EBOOK = 'ebook'
}

export class LibraryCoverManager {
  public static getLibraryCoverBaseDir(filesDir: string): string {
    return `${filesDir}/${LIBRARY_COVER_DIR}`;
  }

  public static getLibraryCoverTypeDir(filesDir: string, type: LibraryCoverType): string {
    return `${LibraryCoverManager.getLibraryCoverBaseDir(filesDir)}/${type}`;
  }

  public static async persistCoverByFilesDir(
    filesDir: string,
    type: LibraryCoverType,
    uniqueId: string,
    sourceCoverPath: string
  ): Promise<string | null> {
    try {
      const source = sourceCoverPath.trim();
      if (!source) {
        return null;
      }

      const normalizedSource = LibraryCoverManager.normalizeLocalPath(source);
      const typeDir = LibraryCoverManager.getLibraryCoverTypeDir(filesDir, type);
      LibraryCoverManager.ensureDir(typeDir);

      if (LibraryCoverManager.isManagedCoverPathByFilesDir(normalizedSource, filesDir) &&
          fs.accessSync(normalizedSource)) {
        return normalizedSource;
      }

      const safeName = LibraryCoverManager.sanitizeFileName(uniqueId || `${Date.now()}`);
      const ext = LibraryCoverManager.getFileExtension(source);
      const targetPath = `${typeDir}/${safeName}${ext}`;
      const normalizedTargetPath = `${typeDir}/${safeName}.webp`;

      if (LibraryCoverManager.isNetworkUrl(source)) {
        const downloaded = await LibraryCoverManager.downloadCoverToPath(source, targetPath);
        if (downloaded) {
          return targetPath;
        }
        return null;
      }

      if (!fs.accessSync(normalizedSource)) {
        logger.warn(TAG, `封面源文件不存在: ${normalizedSource}`);
        return null;
      }

      const normalizedPersistedPath = await LibraryCoverManager.normalizeLocalCoverToManagedPath(
        normalizedSource,
        normalizedTargetPath
      );
      if (normalizedPersistedPath) {
        return normalizedPersistedPath;
      }

      if (LibraryCoverManager.samePath(normalizedSource, targetPath)) {
        return targetPath;
      }

      if (fs.accessSync(targetPath)) {
        fs.unlinkSync(targetPath);
      }
      fs.copyFileSync(normalizedSource, targetPath);
      return targetPath;
    } catch (error) {
      logger.error(TAG, `持久化封面失败: ${String(error)}`);
      return null;
    }
  }

  public static isManagedCoverPathByFilesDir(path: string, filesDir: string): boolean {
    if (!path || !filesDir) {
      return false;
    }
    const normalizedPath = LibraryCoverManager.normalizeComparePath(path);
    const normalizedFilesDir = LibraryCoverManager.normalizeComparePath(filesDir);
    const allowedPrefixes = [
      `${normalizedFilesDir}/covers/`,
      `${normalizedFilesDir}/manga_covers/`,
      `${normalizedFilesDir}/novel_covers/`,
      `${normalizedFilesDir}/${LIBRARY_COVER_DIR}/`
    ];
    return allowedPrefixes.some((prefix: string) => normalizedPath.startsWith(prefix));
  }

  public static deleteManagedCoverIfExists(path: string, filesDir: string): boolean {
    try {
      const normalizedPath = LibraryCoverManager.normalizeLocalPath(path);
      if (!normalizedPath || !LibraryCoverManager.isManagedCoverPathByFilesDir(normalizedPath, filesDir)) {
        return false;
      }
      if (!fs.accessSync(normalizedPath)) {
        return false;
      }
      fs.unlinkSync(normalizedPath);
      return true;
    } catch (error) {
      logger.warn(TAG, `删除封面失败: ${String(error)}`);
      return false;
    }
  }

  public static normalizeLocalPath(path: string): string {
    if (!path) {
      return '';
    }
    return path.startsWith('file://') ? path.substring(7) : path;
  }

  public static isNetworkUrl(path: string): boolean {
    return path.startsWith('http://') || path.startsWith('https://');
  }

  private static async downloadCoverToPath(url: string, targetPath: string): Promise<boolean> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 10000
      });

      if (response.responseCode !== 200 || !response.result) {
        logger.warn(TAG, `下载封面失败: code=${response.responseCode}, url=${url}`);
        return false;
      }

      const file = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try {
        fs.writeSync(file.fd, response.result as ArrayBuffer);
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (error) {
      logger.warn(TAG, `下载封面异常: ${String(error)}`);
      return false;
    } finally {
      request.destroy();
    }
  }

  private static async normalizeLocalCoverToManagedPath(
    sourcePath: string,
    targetPath: string
  ): Promise<string | null> {
    let file: fs.File | null = null;
    let pixelMap: image.PixelMap | null = null;
    try {
      if (LibraryCoverManager.samePath(sourcePath, targetPath) && fs.accessSync(sourcePath)) {
        return sourcePath;
      }

      file = fs.openSync(sourcePath, fs.OpenMode.READ_ONLY);
      const imageSource = image.createImageSource(file.fd);
      pixelMap = await imageSource.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });

      const imagePacker = image.createImagePacker();
      const packedBuffer = await imagePacker.packing(pixelMap, {
        format: 'image/webp',
        quality: 90
      });
      imagePacker.release();
      imageSource.release();

      if (fs.accessSync(targetPath)) {
        fs.unlinkSync(targetPath);
      }
      const outputFile = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      try {
        fs.writeSync(outputFile.fd, packedBuffer);
      } finally {
        fs.closeSync(outputFile);
      }

      logger.info(TAG, `灏侀潰宸叉爣鍑嗗寲涓?WebP: source='${sourcePath}', target='${targetPath}'`);
      return targetPath;
    } catch (error) {
      logger.warn(TAG, `灏侀潰鏍囧噯鍖栧け璐ワ紝灏嗗洖閫€鍒板師鏂囦欢澶嶅埗: source='${sourcePath}', error=${String(error)}`);
      return null;
    } finally {
      try {
        pixelMap?.release();
      } catch (_error) {
      }
      try {
        if (file) {
          fs.closeSync(file);
        }
      } catch (_error) {
      }
    }
  }

  private static getFileExtension(pathOrUrl: string): string {
    const cleaned = pathOrUrl.split('?')[0].split('#')[0].toLowerCase();
    if (cleaned.endsWith('.jpeg')) return '.jpeg';
    if (cleaned.endsWith('.jpg')) return '.jpg';
    if (cleaned.endsWith('.png')) return '.png';
    if (cleaned.endsWith('.webp')) return '.webp';
    if (cleaned.endsWith('.avif')) return '.avif';
    if (cleaned.endsWith('.gif')) return '.gif';
    if (cleaned.endsWith('.bmp')) return '.bmp';
    return '.jpg';
  }

  private static sanitizeFileName(value: string): string {
    const sanitized = value.replace(/[<>:"/\\|?*\x00-\x1F]/g, '_').replace(/\s+/g, '_');
    if (!sanitized) {
      return `cover_${Date.now()}`;
    }
    if (sanitized.length > 120) {
      return sanitized.substring(0, 120);
    }
    return sanitized;
  }

  private static ensureDir(path: string): void {
    if (!fs.accessSync(path)) {
      fs.mkdirSync(path, true);
    }
  }

  private static samePath(pathA: string, pathB: string): boolean {
    return LibraryCoverManager.normalizeComparePath(pathA) === LibraryCoverManager.normalizeComparePath(pathB);
  }

  private static normalizeComparePath(path: string): string {
    return LibraryCoverManager.normalizeLocalPath(path).replace(/\\/g, '/');
  }
}
