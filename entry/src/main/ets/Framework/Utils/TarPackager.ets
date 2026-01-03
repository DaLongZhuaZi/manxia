/**
 * Tar 打包工具
 * 用于将备份数据和媒体文件打包成 .mxbackup 文件
 * 
 * 文件路径: entry/src/main/ets/Framework/Utils/TarPackager.ets
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { logger } from '../../Utils/Logger';
import { zlib } from '@kit.BasicServicesKit';

const TAG = 'TarPackager';

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
      logger.info(TAG, `Creating tar archive: ${outputPath}`);
      
      // 获取目录中的所有文件
      const files = await this.getAllFiles(sourceDir);
      logger.info(TAG, `Found ${files.length} files to archive`);
      
      // 创建临时 tar 文件
      const tempTarPath = `${outputPath}.tmp`;
      const tarFile = fs.openSync(tempTarPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      
      try {
        // 写入每个文件
        for (const filePath of files) {
          await this.addFileToTar(tarFile, sourceDir, filePath);
        }
        
        // 写入结束标记（两个512字节的空块）
        const endMarker = new ArrayBuffer(1024);
        fs.writeSync(tarFile.fd, endMarker);
        
        fs.closeSync(tarFile);
        
        // 重命名为最终文件名
        fs.renameSync(tempTarPath, outputPath);
        
        logger.info(TAG, `Tar archive created successfully: ${outputPath}`);
      } catch (error) {
        fs.closeSync(tarFile);
        // 清理临时文件
        if (fs.accessSync(tempTarPath)) {
          fs.unlinkSync(tempTarPath);
        }
        throw new Error(`Tar creation failed: ${error}`);
      }
    } catch (error) {
      logger.error(TAG, `Failed to create tar archive: ${error}`);
      throw new Error(`Failed to create tar archive: ${error}`);
    }
  }

  /**
   * 解压 tar 包
   * @param tarPath tar 文件路径（.mxbackup）
   * @param outputDir 输出目录
   */
  async extractTarArchive(tarPath: string, outputDir: string): Promise<void> {
    try {
      logger.info(TAG, `Extracting tar archive: ${tarPath}`);
      
      // 确保输出目录存在
      if (!fs.accessSync(outputDir)) {
        fs.mkdirSync(outputDir, true);
      }
      
      const tarFile = fs.openSync(tarPath, fs.OpenMode.READ_ONLY);
      
      try {
        let offset = 0;
        
        while (true) {
          // 读取文件头（512字节）
          const headerBuffer = new ArrayBuffer(512);
          const readBytes = fs.readSync(tarFile.fd, headerBuffer, { offset: offset });
          
          if (readBytes < 512) {
            break; // 文件结束
          }
          
          // 解析文件头
          const header = this.parseTarHeader(headerBuffer);
          
          // 检查是否为结束标记（全零块）
          if (header.name === '') {
            break;
          }
          
          offset += 512;
          
          // 读取文件内容
          const fileSize = parseInt(header.size, 8);
          if (fileSize > 0) {
            const fileBuffer = new ArrayBuffer(fileSize);
            fs.readSync(tarFile.fd, fileBuffer, { offset: offset });
            
            // 写入文件
            const outputPath = `${outputDir}/${header.name}`;
            const outputDirPath = outputPath.substring(0, outputPath.lastIndexOf('/'));
            
            if (!fs.accessSync(outputDirPath)) {
              fs.mkdirSync(outputDirPath, true);
            }
            
            const outputFile = fs.openSync(outputPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
            fs.writeSync(outputFile.fd, fileBuffer);
            fs.closeSync(outputFile);
            
            logger.debug(TAG, `Extracted: ${header.name}`);
            
            // 移动到下一个512字节边界
            const paddedSize = Math.ceil(fileSize / 512) * 512;
            offset += paddedSize;
          }
        }
        
        fs.closeSync(tarFile);
        
        logger.info(TAG, `Tar archive extracted successfully to: ${outputDir}`);
      } catch (error) {
        fs.closeSync(tarFile);
        throw new Error(`Tar extraction failed: ${error}`);
      }
    } catch (error) {
      logger.error(TAG, `Failed to extract tar archive: ${error}`);
      throw new Error(`Failed to extract tar archive: ${error}`);
    }
  }

  /**
   * 获取目录中的所有文件（递归）
   */
  private async getAllFiles(dir: string, baseDir?: string): Promise<string[]> {
    const base = baseDir || dir;
    const files: string[] = [];
    
    try {
      if (!fs.accessSync(dir)) {
        logger.warn(TAG, `Directory does not exist: ${dir}`);
        return files;
      }
      
      const entries = fs.listFileSync(dir);
      logger.debug(TAG, `Scanning directory: ${dir}, found ${entries.length} entries`);
      
      for (const entry of entries) {
        const fullPath = `${dir}/${entry}`;
        const stat = fs.statSync(fullPath);
        
        if (stat.isDirectory()) {
          logger.debug(TAG, `Entering subdirectory: ${entry}`);
          const subFiles = await this.getAllFiles(fullPath, base);
          files.push(...subFiles);
        } else {
          // 返回相对路径
          const relativePath = fullPath.substring(base.length + 1);
          files.push(relativePath);
          logger.debug(TAG, `Found file: ${relativePath} (${stat.size} bytes)`);
        }
      }
    } catch (error) {
      logger.error(TAG, `Failed to list files in ${dir}: ${error}`);
    }
    
    logger.info(TAG, `Total files found in ${dir}: ${files.length}`);
    return files;
  }

  /**
   * 添加文件到 tar 包
   */
  private async addFileToTar(tarFile: fs.File, baseDir: string, relativePath: string): Promise<void> {
    const fullPath = `${baseDir}/${relativePath}`;
    const stat = fs.statSync(fullPath);
    
    // 创建文件头
    const header = this.createTarHeader(relativePath, stat.size, stat.mtime);
    
    // 写入文件头
    const headerBuffer = this.serializeTarHeader(header);
    fs.writeSync(tarFile.fd, headerBuffer);
    
    // 写入文件内容
    if (stat.size > 0) {
      const fileContent = new ArrayBuffer(stat.size);
      const sourceFile = fs.openSync(fullPath, fs.OpenMode.READ_ONLY);
      fs.readSync(sourceFile.fd, fileContent);
      fs.closeSync(sourceFile);
      
      fs.writeSync(tarFile.fd, fileContent);
      
      // 填充到512字节边界
      const padding = (512 - (stat.size % 512)) % 512;
      if (padding > 0) {
        const paddingBuffer = new ArrayBuffer(padding);
        fs.writeSync(tarFile.fd, paddingBuffer);
      }
    }
    
    logger.debug(TAG, `Added to tar: ${relativePath} (${stat.size} bytes)`);
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

  /**
   * 写入字符串到 Uint8Array (UTF-8编码)
   */
  private writeString(view: Uint8Array, offset: number, str: string, maxLength: number): void {
    const length = Math.min(str.length, maxLength);
    
    for (let i = 0; i < length; i++) {
      const code = str.charCodeAt(i);
      view[offset + i] = code < 256 ? code : 63; // 使用 '?' 替代非ASCII字符
    }
    
    // 填充剩余空间为0
    for (let i = length; i < maxLength; i++) {
      view[offset + i] = 0;
    }
  }

  /**
   * 从 Uint8Array 读取字符串 (UTF-8解码)
   */
  private readString(view: Uint8Array, offset: number, maxLength: number): string {
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

export function getTarPackager(): TarPackager {
  return TarPackager.getInstance();
}
