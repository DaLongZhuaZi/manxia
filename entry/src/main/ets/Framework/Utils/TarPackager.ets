import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
/**
 * Tar 打包工具
 * 用于将备份数据和媒体文件打包成 .mxbackup 文件
 * 
 * 文件路径: entry/src/main/ets/Framework/Utils/TarPackager.ets
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { zlib } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';

const TAG = 'TarPackager';
const TAR_STREAM_BUFFER_SIZE: number = 1024 * 1024;

/**
 * Tar 文件头结构（512字节）
 */
interface TarHeader {
  name: string;        // 文件名（100字节）
  mode: string;        // 文件权限（8字节）
  uid: string;         // 用户ID（8字节）
  gid: string;         // 组ID（8字节）
  size: string;        // 文件大小（12字节，八进制）
  mtime: string;       // 修改时间（12字节，八进制）
  checksum: string;    // 校验和（8字节）
  typeflag: string;    // 文件类型（1字节）
  linkname: string;    // 链接名（100字节）
  magic: string;       // 魔数"ustar"（6字节）
  version: string;     // 版本"00"（2字节）
  uname: string;       // 用户名（32字节）
  gname: string;       // 组名（32字节）
  devmajor: string;    // 设备主号（8字节）
  devminor: string;    // 设备次号（8字节）
  prefix: string;      // 文件名前缀（155字节）
}

/**
 * Tar 打包器类
 */
export class TarPackager {
  private static instance: TarPackager;

  private constructor() {}

  static getInstance(): TarPackager {
    if (!TarPackager.instance) {
      TarPackager.instance = new TarPackager();
    }
    return TarPackager.instance;
  }

  /**
   * 创建 tar 包
   * @param sourceDir 源目录
   * @param outputPath 输出文件路径（.mxbackup）
   */
  async createTarArchive(sourceDir: string, outputPath: string): Promise<void> {
    try {
      logger.info(TAG, `正在创建tar归档: ${outputPath}`);
      
      // 获取目录中的所有文件
      const files = await this.getAllFiles(sourceDir);
      logger.info(TAG, `找到 ${files.length} 个文件待归档`);
      
      // 创建临时 tar 文件
      const tempTarPath = `${outputPath}.tmp`;
      const tarFile = SafeFileUtils.openSyncStrict(tempTarPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      
      try {
        // 写入每个文件
        for (const filePath of files) {
          await this.addFileToTar(tarFile, sourceDir, filePath);
        }
        
        // 写入结束标记（两个512字节的空块）
        const endMarker = new ArrayBuffer(1024);
        SafeFileUtils.writeExactSync(tarFile.fd, endMarker);
        
        SafeFileUtils.closeSync(tarFile);
        
        // 重命名为最终文件名
        SafeFileUtils.renameSyncStrict(tempTarPath, outputPath);
        
        logger.info(TAG, `tar归档创建成功: ${outputPath}`);
      } catch (error) {
        SafeFileUtils.closeSync(tarFile);
        // 清理临时文件
        if (SafeFileUtils.accessSync(tempTarPath)) {
          SafeFileUtils.unlinkSyncStrict(tempTarPath);
        }
        throw new Error(`tar创建失败: ${error}`);
      }
    } catch (error) {
      logger.error(TAG, `创建tar归档失败: ${error}`);
      throw new Error(`创建tar归档失败: ${error}`);
    }
  }

  /**
   * 解压 tar 包
   * @param tarPath tar 文件路径（.mxbackup）
   * @param outputDir 输出目录
   * [修复] 正确处理文件和目录条目，添加详细日志
   */
  async extractTarArchive(tarPath: string, outputDir: string): Promise<void> {
    try {
      logger.info(TAG, `正在解压tar归档: ${tarPath}`);
      
      // 确保输出目录存在
      if (!SafeFileUtils.accessSync(outputDir)) {
        SafeFileUtils.mkdirSyncStrict(outputDir, true);
      }
      
      const tarFile = SafeFileUtils.openSyncStrict(tarPath, fs.OpenMode.READ_ONLY);
      let extractedCount = 0;
      let dirCount = 0;

      try {
        let offset = 0;

        while (true) {
          // 读取文件头（512字节）
          const headerBuffer = new ArrayBuffer(512);
          const readBytes = SafeFileUtils.readSyncStrict(tarFile.fd, headerBuffer);

          if (readBytes < 512) {
            if (readBytes === 0) {
              break;
            }
            throw new Error(`tar头读取不完整: offset=${offset}, readBytes=${readBytes}`);
          }

          if (this.isZeroBlock(headerBuffer)) {
            logger.debug(TAG, `遇到tar结束块，结束解压`);
            break;
          }
          
          // 解析文件头
          const header = this.parseTarHeader(headerBuffer);
          this.validateTarHeader(headerBuffer, header);
          const entryName = this.getTarEntryName(header);
          
          // 检查是否为结束标记（全零块）
          if (entryName === '') {
            logger.debug(TAG, `遇到空名称条目，结束解压`);
            break;
          }
          
          offset += 512;
          
          // 获取文件大小和类型
          const fileSize = this.parseOctal(header.size, 'size');
          const typeFlag = header.typeflag;
          
          // [修复] 处理目录条目 (typeflag='5') 或以/结尾的路径
          const isDirectory = typeFlag === '5' || entryName.endsWith('/');
          const isRegularFile = typeFlag === '' || typeFlag === '0';
          const outputPath = this.resolveTarEntryPath(outputDir, entryName);
          
          if (isDirectory) {
            // 创建目录
            if (!SafeFileUtils.accessSync(outputPath)) {
              SafeFileUtils.mkdirSyncStrict(outputPath, true);
            }
            dirCount++;
            logger.debug(TAG, `已创建目录: ${entryName}`);
            if (fileSize > 0) {
              const paddedSize = Math.ceil(fileSize / 512) * 512;
              this.skipTarBytes(tarFile.fd, paddedSize);
              offset += paddedSize;
            }
          } else if (!isRegularFile) {
            throw new Error(`不支持的tar条目类型: entry=${entryName}, type=${typeFlag}`);
          } else if (fileSize > 0) {
            // 确保父目录存在
            const outputDirPath = outputPath.substring(0, outputPath.lastIndexOf('/'));
            if (outputDirPath && outputDirPath !== outputDir) {
              if (!SafeFileUtils.accessSync(outputDirPath)) {
                SafeFileUtils.mkdirSyncStrict(outputDirPath, true);
              }
            }

            this.extractRegularFileFromTar(tarFile.fd, outputPath, fileSize);
            extractedCount++;
            logger.debug(TAG, `已解压文件: ${entryName} (${fileSize}字节)`);

            // 移动到下一个512字节边界
            const padding = (512 - (fileSize % 512)) % 512;
            if (padding > 0) {
              this.skipTarBytes(tarFile.fd, padding);
            }
            offset += fileSize + padding;
          } else {
            const outputDirPath = outputPath.substring(0, outputPath.lastIndexOf('/'));
            if (outputDirPath && outputDirPath !== outputDir && !SafeFileUtils.accessSync(outputDirPath)) {
              SafeFileUtils.mkdirSyncStrict(outputDirPath, true);
            }
            const outputFile = SafeFileUtils.openSyncStrict(outputPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
            SafeFileUtils.closeSync(outputFile);
            extractedCount++;
            logger.debug(TAG, `已解压空文件: ${entryName}`);
          }
        }
        
        SafeFileUtils.closeSync(tarFile);
        
        logger.info(TAG, `tar归档解压成功: ${outputDir}, 文件=${extractedCount}, 目录=${dirCount}`);
        
        // [修复] 验证解压结果
        try {
          const extractedContents = SafeFileUtils.listFileSync(outputDir);
          logger.info(TAG, `解压后目录内容: ${extractedContents.join(', ')}`);
        } catch (listError) {
          logger.warn(TAG, `无法列出解压目录: ${listError}`);
        }
      } catch (error) {
        SafeFileUtils.closeSync(tarFile);
        throw new Error(`tar解压失败: ${error}`);
      }
    } catch (error) {
      logger.error(TAG, `解压tar归档失败: ${error}`);
      throw new Error(`解压tar归档失败: ${error}`);
    }
  }

  /**
   * 获取目录中的所有文件（递归）
   * [修复] 为每个条目添加单独的错误处理，防止单个条目失败导致整个目录被跳过
   */
  private async getAllFiles(dir: string, baseDir?: string): Promise<string[]> {
    const base = baseDir || dir;
    const files: string[] = [];
    
    try {
      if (!SafeFileUtils.accessSync(dir)) {
        logger.warn(TAG, `目录不存在: ${dir}`);
        return files;
      }
      
      const entries = SafeFileUtils.listFileSync(dir);
      logger.debug(TAG, `扫描目录: ${dir}, 找到 ${entries.length} 个条目`);
      
      // [修复] 在根目录级别记录所有条目名称，便于调试
      if (dir === base) {
        logger.info(TAG, `根目录条目列表: ${entries.join(', ')}`);
      }
      
      for (const entry of entries) {
        const fullPath = `${dir}/${entry}`;
        
        // [修复] 为每个条目单独捕获异常，避免一个条目失败导致整个循环中断
        try {
          const stat = SafeFileUtils.statSyncStrict(fullPath);
          
          if (stat.isDirectory()) {
            logger.debug(TAG, `进入子目录: ${entry}`);
            const subFiles = await this.getAllFiles(fullPath, base);
            files.push(...subFiles);
          } else {
            // 返回相对路径
            const relativePath = fullPath.substring(base.length + 1);
            files.push(relativePath);
            logger.debug(TAG, `找到文件: ${relativePath} (${stat.size} 字节)`);
          }
        } catch (entryError) {
          logger.error(TAG, `处理条目失败: ${entry}, 路径: ${fullPath}, 错误: ${entryError}`);
          throw new Error(`处理tar源目录条目失败: ${fullPath}, ${entryError}`);
        }
      }
    } catch (error) {
      logger.error(TAG, `列出目录文件失败 ${dir}: ${error}`);
      throw new Error(`列出目录文件失败 ${dir}: ${error}`);
    }
    
    logger.info(TAG, `目录 ${dir} 共找到 ${files.length} 个文件`);
    return files;
  }

  private skipTarBytes(fd: number, byteCount: number): void {
    let remaining = byteCount;
    while (remaining > 0) {
      const chunkSize = remaining > TAR_STREAM_BUFFER_SIZE ? TAR_STREAM_BUFFER_SIZE : remaining;
      const skipBuffer = new ArrayBuffer(chunkSize);
      SafeFileUtils.readExactSync(fd, skipBuffer, { length: chunkSize });
      remaining -= chunkSize;
    }
  }

  private extractRegularFileFromTar(tarFd: number, outputPath: string, fileSize: number): void {
    const outputFile = SafeFileUtils.openSyncStrict(outputPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      let remaining = fileSize;
      while (remaining > 0) {
        const chunkSize = remaining > TAR_STREAM_BUFFER_SIZE ? TAR_STREAM_BUFFER_SIZE : remaining;
        const buffer = new ArrayBuffer(chunkSize);
        SafeFileUtils.readExactSync(tarFd, buffer, { length: chunkSize });
        SafeFileUtils.writeExactSync(outputFile.fd, buffer, { length: chunkSize });
        remaining -= chunkSize;
      }
    } finally {
      SafeFileUtils.closeSync(outputFile);
    }
  }

  /**
   * 添加文件到 tar 包
   */
  private async addFileToTar(tarFile: fs.File, baseDir: string, relativePath: string): Promise<void> {
    const fullPath = `${baseDir}/${relativePath}`;
    const stat = SafeFileUtils.statSyncStrict(fullPath);
    
    // 创建文件头
    const header = this.createTarHeader(relativePath, stat.size, stat.mtime);
    
    // 写入文件头
    const headerBuffer = this.serializeTarHeader(header);
    SafeFileUtils.writeExactSync(tarFile.fd, headerBuffer);
    
    // 写入文件内容
    if (stat.size > 0) {
      this.writeFileContentToTar(tarFile.fd, fullPath, stat.size);

      // 填充到512字节边界
      const padding = (512 - (stat.size % 512)) % 512;
      if (padding > 0) {
        const paddingBuffer = new ArrayBuffer(padding);
        SafeFileUtils.writeExactSync(tarFile.fd, paddingBuffer);
      }
    }
    
    logger.debug(TAG, `已添加到tar: ${relativePath} (${stat.size} 字节)`);
  }

  private writeFileContentToTar(tarFd: number, sourcePath: string, fileSize: number): void {
    const sourceFile = SafeFileUtils.openSyncStrict(sourcePath, fs.OpenMode.READ_ONLY);
    try {
      let remaining = fileSize;
      while (remaining > 0) {
        const chunkSize = remaining > TAR_STREAM_BUFFER_SIZE ? TAR_STREAM_BUFFER_SIZE : remaining;
        const buffer = new ArrayBuffer(chunkSize);
        SafeFileUtils.readExactSync(sourceFile.fd, buffer, { length: chunkSize });
        SafeFileUtils.writeExactSync(tarFd, buffer, { length: chunkSize });
        remaining -= chunkSize;
      }
    } finally {
      SafeFileUtils.closeSync(sourceFile);
    }
  }

  /**
   * 创建 tar 文件头
   */
  private createTarHeader(name: string, size: number, mtime: number): TarHeader {
    return {
      name: name,
      mode: '0000644',
      uid: '0000000',
      gid: '0000000',
      size: size.toString(8).padStart(11, '0'),
      mtime: Math.floor(mtime / 1000).toString(8).padStart(11, '0'),
      checksum: '        ', // 临时值，稍后计算
      typeflag: '0', // 普通文件
      linkname: '',
      magic: 'ustar',
      version: '00',
      uname: 'manxia',
      gname: 'manxia',
      devmajor: '0000000',
      devminor: '0000000',
      prefix: ''
    };
  }

  /**
   * 序列化 tar 文件头为 512 字节的 ArrayBuffer
   */
  private serializeTarHeader(header: TarHeader): ArrayBuffer {
    const buffer = new ArrayBuffer(512);
    const view = new Uint8Array(buffer);
    
    // 填充字段
    this.writeString(view, 0, header.name, 100);
    this.writeString(view, 100, header.mode, 8);
    this.writeString(view, 108, header.uid, 8);
    this.writeString(view, 116, header.gid, 8);
    this.writeString(view, 124, header.size, 12);
    this.writeString(view, 136, header.mtime, 12);
    
    // 计算校验和（先填充空格）
    this.writeString(view, 148, '        ', 8);
    
    this.writeString(view, 156, header.typeflag, 1);
    this.writeString(view, 157, header.linkname, 100);
    this.writeString(view, 257, header.magic, 6);
    this.writeString(view, 263, header.version, 2);
    this.writeString(view, 265, header.uname, 32);
    this.writeString(view, 297, header.gname, 32);
    this.writeString(view, 329, header.devmajor, 8);
    this.writeString(view, 337, header.devminor, 8);
    this.writeString(view, 345, header.prefix, 155);
    
    // 计算并填充校验和
    let checksum = 0;
    for (let i = 0; i < 512; i++) {
      checksum += view[i];
    }
    const checksumStr = checksum.toString(8).padStart(6, '0') + '\0 ';
    this.writeString(view, 148, checksumStr, 8);
    
    return buffer;
  }

  /**
   * 解析 tar 文件头
   */
  private parseTarHeader(buffer: ArrayBuffer): TarHeader {
    const view = new Uint8Array(buffer);
    
    return {
      name: this.readString(view, 0, 100),
      mode: this.readString(view, 100, 8),
      uid: this.readString(view, 108, 8),
      gid: this.readString(view, 116, 8),
      size: this.readString(view, 124, 12),
      mtime: this.readString(view, 136, 12),
      checksum: this.readString(view, 148, 8),
      typeflag: this.readString(view, 156, 1),
      linkname: this.readString(view, 157, 100),
      magic: this.readString(view, 257, 6),
      version: this.readString(view, 263, 2),
      uname: this.readString(view, 265, 32),
      gname: this.readString(view, 297, 32),
      devmajor: this.readString(view, 329, 8),
      devminor: this.readString(view, 337, 8),
      prefix: this.readString(view, 345, 155)
    };
  }

  private isZeroBlock(buffer: ArrayBuffer): boolean {
    const view = new Uint8Array(buffer);
    for (let i = 0; i < view.length; i++) {
      if (view[i] !== 0) {
        return false;
      }
    }
    return true;
  }

  private validateTarHeader(buffer: ArrayBuffer, header: TarHeader): void {
    const magic = header.magic.trim();
    if (magic.length > 0 && magic !== 'ustar') {
      throw new Error(`不支持的tar格式: magic=${header.magic}`);
    }

    const expectedChecksum = this.parseOctal(header.checksum, 'checksum');
    const actualChecksum = this.calculateHeaderChecksum(buffer);
    if (expectedChecksum !== actualChecksum) {
      throw new Error(`tar头校验失败: entry=${this.getTarEntryName(header)}, expected=${expectedChecksum}, actual=${actualChecksum}`);
    }

    this.parseOctal(header.size, 'size');
  }

  private calculateHeaderChecksum(buffer: ArrayBuffer): number {
    const view = new Uint8Array(buffer);
    let checksum = 0;
    for (let i = 0; i < view.length; i++) {
      if (i >= 148 && i < 156) {
        checksum += 32;
      } else {
        checksum += view[i];
      }
    }
    return checksum;
  }

  private parseOctal(value: string, fieldName: string): number {
    const normalized = value.trim();
    if (normalized.length === 0) {
      return 0;
    }
    for (let i = 0; i < normalized.length; i++) {
      const code = normalized.charCodeAt(i);
      if (code < 48 || code > 55) {
        throw new Error(`tar ${fieldName}字段不是八进制: ${value}`);
      }
    }
    return parseInt(normalized, 8);
  }

  private getTarEntryName(header: TarHeader): string {
    if (header.prefix.length > 0) {
      return `${header.prefix}/${header.name}`;
    }
    return header.name;
  }

  private resolveTarEntryPath(outputDir: string, entryName: string): string {
    const normalizedEntry = entryName.replace(/\\/g, '/');
    if (
      normalizedEntry.length === 0 ||
      normalizedEntry.startsWith('/') ||
      normalizedEntry.startsWith('./') ||
      normalizedEntry.includes('/../') ||
      normalizedEntry === '..' ||
      normalizedEntry.startsWith('../') ||
      normalizedEntry.includes('\0') ||
      normalizedEntry.includes(':')
    ) {
      throw new Error(`非法tar路径: ${entryName}`);
    }

    return `${outputDir}/${normalizedEntry}`;
  }

  /**
   * 写入字符串到 Uint8Array (UTF-8编码)
   * [修复] 正确处理UTF-8编码，支持中文等多字节字符
   */
  private writeString(view: Uint8Array, offset: number, str: string, maxLength: number): void {
    try {
      // 使用TextEncoder将字符串转换为UTF-8字节数组
      const encoder = new util.TextEncoder();
      const encoded: Uint8Array = encoder.encodeInto(str);
      
      if (!encoded || encoded.length === 0) {
        // 如果编码失败，使用简单的ASCII编码
        const length = Math.min(str.length, maxLength);
        for (let i = 0; i < length; i++) {
          const code = str.charCodeAt(i);
          view[offset + i] = code < 256 ? code : 63; // 使用 '?' 替代非ASCII字符
        }
        for (let i = length; i < maxLength; i++) {
          view[offset + i] = 0;
        }
        return;
      }
      
      const length = Math.min(encoded.length, maxLength);
      
      for (let i = 0; i < length; i++) {
        view[offset + i] = encoded[i];
      }
      
      // 填充剩余空间为0
      for (let i = length; i < maxLength; i++) {
        view[offset + i] = 0;
      }
    } catch (error) {
      // 编码失败时使用简单的ASCII编码
      logger.warn(TAG, `UTF-8编码失败，使用ASCII编码: ${error}`);
      const length = Math.min(str.length, maxLength);
      for (let i = 0; i < length; i++) {
        const code = str.charCodeAt(i);
        view[offset + i] = code < 256 ? code : 63;
      }
      for (let i = length; i < maxLength; i++) {
        view[offset + i] = 0;
      }
    }
  }

  /**
   * 从 Uint8Array 读取字符串 (UTF-8解码)
   * [修复] 正确处理UTF-8编码，支持中文等多字节字符
   */
  private readString(view: Uint8Array, offset: number, maxLength: number): string {
    try {
      // 找到字符串结束位置（null终止符）
      let endIndex = offset;
      for (let i = 0; i < maxLength; i++) {
        if (view[offset + i] === 0) {
          break;
        }
        endIndex = offset + i + 1;
      }
      
      // 提取字节数组
      const bytes = view.slice(offset, endIndex);
      
      if (bytes.length === 0) {
        return '';
      }
      
      // 使用TextDecoder将UTF-8字节数组转换为字符串
      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(bytes);
    } catch (error) {
      // 解码失败时使用简单的ASCII解码
      logger.warn(TAG, `UTF-8解码失败，使用ASCII解码: ${error}`);
      const bytes: number[] = [];
      for (let i = 0; i < maxLength; i++) {
        const byte = view[offset + i];
        if (byte === 0) {
          break;
        }
        bytes.push(byte);
      }
      return String.fromCharCode(...bytes);
    }
  }
}

export function getTarPackager(): TarPackager {
  return TarPackager.getInstance();
}
