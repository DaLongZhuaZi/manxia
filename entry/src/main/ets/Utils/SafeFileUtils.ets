import fileIo, { ReadOptions, ReadTextOptions, WriteOptions, ListFileOptions } from '@ohos.file.fs';
import { logger } from './Logger';
import { util } from '@kit.ArkTS';

const TAG = 'SafeFileUtils';
const SAFE_FILE_IO_CHUNK_SIZE: number = 1024 * 1024;

export class SafeFileUtils {
  static copyFileSyncStrict(src: string | number, dest: string | number, mode?: number): void {
    if (mode !== undefined) {
      fileIo.copyFileSync(src, dest, mode);
    } else {
      fileIo.copyFileSync(src, dest);
    }
  }

  static mkdirSyncStrict(path: string, recursion?: boolean): void {
    if (recursion !== undefined) {
      fileIo.mkdirSync(path, recursion);
    } else {
      fileIo.mkdirSync(path);
    }
  }

  static openSyncStrict(path: string, mode?: number): fileIo.File {
    if (mode !== undefined) {
      return fileIo.openSync(path, mode);
    }
    return fileIo.openSync(path);
  }

  static readSyncStrict(fd: number, buffer: ArrayBuffer, options?: ReadOptions): number {
    if (fd === -1) {
      throw new Error('Invalid file descriptor');
    }
    if (options !== undefined) {
      return fileIo.readSync(fd, buffer, options);
    }
    return fileIo.readSync(fd, buffer);
  }

  static readExactSync(fd: number, buffer: ArrayBuffer, options?: ReadOptions): void {
    const expectedLength = options?.length !== undefined ? options.length : buffer.byteLength;
    if (expectedLength > buffer.byteLength) {
      throw new Error(`Read buffer too small: expected=${expectedLength}, buffer=${buffer.byteLength}`);
    }
    if (options?.offset !== undefined && options.offset !== 0) {
      fileIo.lseek(fd, options.offset, fileIo.WhenceType.SEEK_CUR);
    }
    const targetView = new Uint8Array(buffer);
    let totalRead = 0;
    while (totalRead < expectedLength) {
      const remaining = expectedLength - totalRead;
      const chunkSize = remaining > SAFE_FILE_IO_CHUNK_SIZE ? SAFE_FILE_IO_CHUNK_SIZE : remaining;
      const chunkBuffer = new ArrayBuffer(chunkSize);
      const readBytes = SafeFileUtils.readSyncStrict(fd, chunkBuffer, { length: chunkSize });
      if (readBytes <= 0) {
        throw new Error(`Incomplete file read: expected=${expectedLength}, actual=${totalRead}`);
      }
      const chunkView = new Uint8Array(chunkBuffer);
      targetView.set(chunkView.subarray(0, readBytes), totalRead);
      totalRead += readBytes;
    }
  }

  static renameSyncStrict(oldPath: string, newPath: string): void {
    fileIo.renameSync(oldPath, newPath);
  }

  static statSyncStrict(file: string | number): fileIo.Stat {
    return fileIo.statSync(file);
  }

  static unlinkSyncStrict(path: string): void {
    fileIo.unlinkSync(path);
  }

  static writeSyncStrict(fd: number, buffer: ArrayBuffer | string, options?: WriteOptions): number {
    if (fd === -1) {
      throw new Error('Invalid file descriptor');
    }
    if (options !== undefined) {
      return fileIo.writeSync(fd, buffer, options);
    }
    return fileIo.writeSync(fd, buffer);
  }

  static writeExactSync(fd: number, buffer: ArrayBuffer | string, options?: WriteOptions): void {
    const expectedLength = options?.length !== undefined
      ? options.length
      : SafeFileUtils.getWriteBufferLength(buffer);
    if (typeof buffer === 'string') {
      const writtenBytes = SafeFileUtils.writeSyncStrict(fd, buffer, options);
      if (writtenBytes !== expectedLength) {
        throw new Error(`Incomplete file write: expected=${expectedLength}, actual=${writtenBytes}`);
      }
      return;
    }

    if (expectedLength > buffer.byteLength) {
      throw new Error(`Write buffer too small: expected=${expectedLength}, buffer=${buffer.byteLength}`);
    }
    if (options?.offset !== undefined && options.offset !== 0) {
      fileIo.lseek(fd, options.offset, fileIo.WhenceType.SEEK_CUR);
    }
    const sourceView = new Uint8Array(buffer);
    let totalWritten = 0;
    while (totalWritten < expectedLength) {
      const remaining = expectedLength - totalWritten;
      const chunkSize = remaining > SAFE_FILE_IO_CHUNK_SIZE ? SAFE_FILE_IO_CHUNK_SIZE : remaining;
      const chunkBuffer = new ArrayBuffer(chunkSize);
      const chunkView = new Uint8Array(chunkBuffer);
      chunkView.set(sourceView.subarray(totalWritten, totalWritten + chunkSize));
      const writtenBytes = SafeFileUtils.writeSyncStrict(fd, chunkBuffer, { length: chunkSize });
      if (writtenBytes <= 0) {
        throw new Error(`Incomplete file write: expected=${expectedLength}, actual=${totalWritten}`);
      }
      totalWritten += writtenBytes;
    }
  }

  static writeStringExactSync(fd: number, content: string, options?: WriteOptions): void {
    const expectedLength = options?.length !== undefined
      ? options.length
      : SafeFileUtils.getWriteBufferLength(content);
    const writtenBytes = SafeFileUtils.writeSyncStrict(fd, content, options);
    if (writtenBytes !== expectedLength) {
      throw new Error(`Incomplete file write: expected=${expectedLength}, actual=${writtenBytes}`);
    }
  }

  private static getWriteBufferLength(buffer: ArrayBuffer | string): number {
    if (typeof buffer !== 'string') {
      return buffer.byteLength;
    }
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(buffer).length;
  }

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
      const stat = fileIo.statSync(path);
      if (!stat.isDirectory()) {
        return [];
      }
    } catch (e) {
      logger.debug(TAG, `listFileSync stat skipped for ${path}`);
      return [];
    }
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
