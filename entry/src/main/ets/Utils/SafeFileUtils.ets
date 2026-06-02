import fileIo, { ReadOptions, ReadTextOptions, WriteOptions, ListFileOptions } from '@ohos.file.fs';
import { logger } from './Logger';

const TAG = 'SafeFileUtils';

export class SafeFileUtils {
  static accessSync(path: string, mode?: number, flag?: number): boolean {
    try {
      if (flag !== undefined) {
        return fileIo.accessSync(path, mode, flag as number);
      } else if (mode !== undefined) {
        return fileIo.accessSync(path, mode as number);
      } else {
        return fileIo.accessSync(path);
      }
    } catch (e) {
      logger.debug(TAG, `accessSync skipped for ${path}`);
      return false;
    }
  }

  static closeSync(file: number | fileIo.File): void {
    let fd = typeof file === 'number' ? file : file.fd;
    if (fd === -1) return;
    try {
      fileIo.closeSync(file);
    } catch (e) {
      logger.debug(TAG, `closeSync error for fd ${fd}`);
    }
  }

  static copyFileSync(src: string | number, dest: string | number, mode?: number): void {
    if (src === -1 || dest === -1) return;
    try {
      if (mode !== undefined) {
        fileIo.copyFileSync(src, dest, mode);
      } else {
        fileIo.copyFileSync(src, dest);
      }
    } catch (e) {
      logger.error(TAG, `copyFileSync error: ${String(e)}`);
    }
  }

  static listFileSync(path: string, options?: ListFileOptions): string[] {
    try {
      if (options !== undefined) {
        return fileIo.listFileSync(path, options);
      } else {
        return fileIo.listFileSync(path);
      }
    } catch (e) {
      logger.debug(TAG, `listFileSync error for ${path}`);
      return [];
    }
  }

  static mkdirSync(path: string, recursion?: boolean): void {
    try {
      if (recursion !== undefined) {
        fileIo.mkdirSync(path, recursion);
      } else {
        fileIo.mkdirSync(path);
      }
    } catch (e) {
      logger.debug(TAG, `mkdirSync error for ${path}`);
    }
  }

  static openSync(path: string, mode?: number): fileIo.File {
    try {
      if (mode !== undefined) {
        return fileIo.openSync(path, mode);
      } else {
        return fileIo.openSync(path);
      }
    } catch (e) {
      logger.debug(TAG, `openSync error for ${path}, returning dummy fd`);
      let dummy: Record<string, Object> = {};
      return dummy as Object as fileIo.File;
    }
  }

  static readSync(fd: number, buffer: ArrayBuffer, options?: ReadOptions): number {
    if (fd === -1) return 0;
    try {
      if (options !== undefined) {
        return fileIo.readSync(fd, buffer, options);
      } else {
        return fileIo.readSync(fd, buffer);
      }
    } catch (e) {
      logger.debug(TAG, `readSync error for fd ${fd}`);
      return 0;
    }
  }

  static readTextSync(filePath: string, options?: ReadTextOptions): string {
    try {
      if (options !== undefined) {
        return fileIo.readTextSync(filePath, options);
      } else {
        return fileIo.readTextSync(filePath);
      }
    } catch (e) {
      logger.error(TAG, `readTextSync error for ${filePath}`);
      return "";
    }
  }

  static renameSync(oldPath: string, newPath: string): void {
    try {
      fileIo.renameSync(oldPath, newPath);
    } catch (e) {
      logger.error(TAG, `renameSync error from ${oldPath} to ${newPath}`);
    }
  }

  static rmdirSync(path: string): void {
    try {
      fileIo.rmdirSync(path);
    } catch (e) {
      logger.debug(TAG, `rmdirSync error for ${path}`);
    }
  }

  static statSync(file: string | number): fileIo.Stat {
    try {
      return fileIo.statSync(file);
    } catch (e) {
      logger.debug(TAG, `statSync error for ${file}`);
      let dummyStat: Record<string, Object> = {};
      return dummyStat as Object as fileIo.Stat;
    }
  }

  static unlinkSync(path: string): void {
    try {
      fileIo.unlinkSync(path);
    } catch (e) {
      logger.debug(TAG, `unlinkSync error for ${path}`);
    }
  }

  static writeSync(fd: number, buffer: ArrayBuffer | string, options?: WriteOptions): number {
    if (fd === -1) return 0;
    try {
      if (options !== undefined) {
        return fileIo.writeSync(fd, buffer, options);
      } else {
        return fileIo.writeSync(fd, buffer);
      }
    } catch (e) {
      logger.error(TAG, `writeSync error for fd ${fd}`);
      return 0;
    }
  }
}
