import { MinizipCompressNative, MinizipNative } from 'libminizip_ng.so';
import fs from '@ohos.file.fs';

// 定义压缩文件信息接口
interface CompressFileInfo {
  fullPath: string;
  entryName: string;
  size: number;
}

// 压缩进度信息接口
interface CompressProgressInfo {
  overallProgress: number; // 整体进度百分比
  fileProgress: number; // 当前文件进度百分比
  currentFile: string; // 当前正在处理的文件名
  processedFiles: number; // 已处理文件数
  totalFiles: number; // 总文件数
  message: string; // 进度描述信息
}

// 解压进度信息接口
interface DecompressProgressInfo {
  overallProgress: number; // 整体进度百分比
  fileProgress: number; // 当前文件进度百分比
  currentFile: string; // 当前正在处理的文件名
  processedFiles: number; // 已处理文件数
  totalFiles: number; // 总文件数
  message: string; // 进度描述信息
}

// 压缩进度回调类型
export type CompressProgressCallback = (progress: CompressProgressInfo) => void;

// 解压进度回调类型
export type DecompressProgressCallback = (progress: DecompressProgressInfo) => void;

// 使用较大的缓冲区进行流式处理，避免处理大文件时效率低下
const bufferSize: number = 1024 * 1024; // 1024K缓冲区

/**
 * 流式压缩类
 * 提供简洁的API用于文件和文件夹的流式压缩
 */
export class StreamingCompressor {
  private compressEntry: MinizipCompressNative | null = null;
  private progressCallback: CompressProgressCallback | null = null;
  // 进度相关变量
  private totalUncompressedSize: number = 0;
  private processedUncompressedSize: number = 0;
  private totalFiles: number = 0;
  private processedFiles: number = 0;
  private currentFileSize: number = 0;
  private totalReadBytes: number = 0;
  private currentFile: string = '';
  private fileProgressValue: number = 0; // 添加fileProgress属性

  /**
   * 设置进度回调函数
   * @param callback 进度回调函数
   */
  setProgressCallback(callback: CompressProgressCallback): void {
    this.progressCallback = callback;
  }

  /**
   * 获取当前文件进度
   */
  getFileProgress(): number {
    return this.fileProgressValue;
  }

  /**
   * 开始流式压缩
   * @param sourcePath 要压缩的源文件或文件夹路径
   * @param zipFilePath 目标ZIP文件路径
   * @returns Promise<boolean> 压缩是否成功
   */
  async startStreamingCompress(sourcePath: string, zipFilePath: string): Promise<boolean> {
    try {
      // 创建MinizipCompressNative实例
      this.compressEntry = new MinizipCompressNative("", zipFilePath);
      if (this.compressEntry.Create() != 0) {
        throw new Error('创建压缩文件失败');
      }

      // 获取要压缩的文件列表
      const fileList: Array<CompressFileInfo> = await this.collectAllFiles(sourcePath, "");
      if (fileList.length === 0) {
        this.compressEntry.Close();
        this.updateProgress(100, 100, '', 0, 0, '没有文件需要压缩');
        return true;
      }

      // 计算总大小用于整体进度计算
      let totalSize = 0;
      for (let i = 0; i < fileList.length; i++) {
        totalSize += fileList[i].size;
      }

      this.totalUncompressedSize = totalSize;
      this.processedUncompressedSize = 0;
      this.totalFiles = fileList.length;
      this.processedFiles = 0;

      // 处理所有文件
      await this.processNextFileForCompress(0, fileList);
      return true;
    } catch (error) {
      console.error('[StreamingCompressor] 压缩过程出错:', error);
      if (this.compressEntry) {
        this.compressEntry.Close();
      }
      return false;
    }
  }

  // 收集所有需要压缩的文件（扁平化处理）
  private collectAllFiles(dirPath: string, basePath: string): Promise<Array<CompressFileInfo>> {
    return new Promise((resolve: (value: Array<CompressFileInfo>) => void, reject: (reason: Error) => void) => {
      try {
        const result: Array<CompressFileInfo> = [];
        const collect = (currentDirPath: string, currentBasePath: string): void => {
          const files: Array<string> = fs.listFileSync(currentDirPath);

          for (let i = 0; i < files.length; i++) {
            const fileName: string = files[i];
            const fullPath: string = currentDirPath + '/' + fileName;
            const entryName: string = currentBasePath ? currentBasePath + '/' + fileName : fileName;

            const stat = fs.statSync(fullPath);
            if (stat.isDirectory()) {
              // 递归处理目录
              collect(fullPath, entryName);
            } else {
              // 添加文件到列表
              const fileInfo: CompressFileInfo = {
                fullPath: fullPath,
                entryName: entryName,
                size: stat.size
              };
              result.push(fileInfo);
            }
          }
        };

        collect(dirPath, basePath);
        resolve(result);
      } catch (error) {
        reject(error);
      }
    });
  }

  private processNextFileForCompress(
    index: number,
    fileList: Array<CompressFileInfo>
  ): Promise<void> {
    return new Promise((resolve, reject) => {
      if (index >= fileList.length) {
        // 所有文件处理完成
        this.compressEntry!.Close();
        this.updateProgress(100, 100, '', this.totalFiles, this.totalFiles, '所有文件已压缩');
        resolve();
        return;
      }

      const fileItem: CompressFileInfo = fileList[index];
      const fullPath: string = fileItem.fullPath;
      const entryName: string = fileItem.entryName;
      const fileSize: number = fileItem.size;

      try {
        // 处理文件
        this.currentFile = entryName;
        this.fileProgressValue = 0;
        this.totalReadBytes = 0;
        this.currentFileSize = fileSize;

        // 打开条目进行流式写入
        const openResult: number = this.compressEntry!.CreateEntryForStream(entryName, "");
        if (openResult !== 0) {
          // 处理下一个文件而不是关闭整个压缩器
          setTimeout(() => {
            this.processNextFileForCompress(index + 1, fileList).then(resolve).catch(reject);
          }, 1);
          return;
        }

        // 打开源文件
        let inputFile: fs.File = fs.openSync(fullPath, fs.OpenMode.READ_ONLY);

        // 开始流式读取和写入
        this.streamFileData(inputFile, entryName, index, fileList, resolve, reject);
      } catch (error) {
        // 处理下一个文件而不是关闭整个压缩器
        setTimeout(() => {
          this.processNextFileForCompress(index + 1, fileList).then(resolve).catch(reject);
        }, 1);
      }
    });
  }

  private streamFileData(
    inputFile: fs.File,
    entryName: string,
    fileIndex: number,
    fileList: Array<CompressFileInfo>,
    resolve: () => void,
    reject: (reason: Error) => void
  ) {


    const readAndWrite = () => {
      try {
        // 为每次读取创建新的缓冲区，避免缓冲区复用问题
        const buffer: ArrayBuffer = new ArrayBuffer(bufferSize);
        // 读取数据
        const bytesRead: number = fs.readSync(inputFile.fd, buffer);

        if (bytesRead < 0) {
          // 读取错误
          fs.closeSync(inputFile);
          this.compressEntry!.CloseEntryStream();
          reject(new Error(`读取源文件数据失败: ${entryName}`));
          return;
        }

        if (bytesRead > 0) {
          // 写入数据到压缩文件
          const bytesWritten: number = this.compressEntry!.WriteEntryStream(buffer, bytesRead);

          if (bytesWritten < 0) {
            fs.closeSync(inputFile);
            this.compressEntry!.CloseEntryStream();
            reject(new Error(`写入压缩文件失败: ${entryName}`));
            return;
          }

          this.totalReadBytes += bytesRead;

          // 更新文件进度
          let fileProgress = 0;
          if (this.currentFileSize > 0) {
            fileProgress = Math.floor((this.totalReadBytes / this.currentFileSize) * 100);
          }

          // 更新整体进度
          let overallProgress = 0;
          if (this.totalUncompressedSize > 0) {
            overallProgress =
              Math.floor(((this.processedUncompressedSize + this.totalReadBytes) / this.totalUncompressedSize) * 100);
          }

          this.fileProgressValue = fileProgress;

          this.updateProgress(overallProgress, fileProgress, entryName, this.processedFiles, this.totalFiles,
            `正在压缩: ${entryName}`);

          // 继续读取更多数据
          setTimeout(readAndWrite, 1); // 短暂延迟以允许UI更新
        } else {
          // 读取完成
          fs.closeSync(inputFile);
          this.compressEntry!.CloseEntryStream();

          // 更新整体进度
          this.processedUncompressedSize += this.currentFileSize;
          this.processedFiles++;

          let overallProgress = 0;
          if (this.totalUncompressedSize > 0) {
            overallProgress = Math.floor((this.processedUncompressedSize / this.totalUncompressedSize) * 100);
          } else {
            overallProgress = Math.floor((this.processedFiles / this.totalFiles) * 100);
          }

          this.fileProgressValue = 100;

          this.updateProgress(overallProgress, 100, entryName, this.processedFiles, this.totalFiles,
            `已压缩完成: ${entryName}`);

          // 处理下一个文件
          setTimeout(() => {
            this.processNextFileForCompress(fileIndex + 1, fileList).then(resolve).catch(reject);
          }, 1);
        }
      } catch (error) {
        fs.closeSync(inputFile);
        if (this.compressEntry) {
          this.compressEntry.CloseEntryStream();
        }
        reject(error);
      }
    };

    // 开始读取和写入循环
    readAndWrite();
  }

  private updateProgress(
    overallProgress: number,
    fileProgress: number,
    currentFile: string,
    processedFiles: number,
    totalFiles: number,
    message: string
  ): void {
    if (this.progressCallback) {
      const progressInfo: CompressProgressInfo = {
        overallProgress: overallProgress,
        fileProgress: fileProgress,
        currentFile: currentFile,
        processedFiles: processedFiles,
        totalFiles: totalFiles,
        message: message
      };
      this.progressCallback(progressInfo);
    }
  }
}

/**
 * 流式解压缩类
 * 提供简洁的API用于ZIP文件的流式解压
 */
export class StreamingDecompressor {
  private progressCallback: DecompressProgressCallback | null = null;
  // 进度相关变量
  private entryNames: Array<string> = [];
  private totalFiles: number = 0;
  private processedFiles: number = 0;
  private currentFileSize: number = 0;
  private totalReadBytes: number = 0;
  private totalUncompressedSize: number = 0;
  private processedUncompressedSize: number = 0;
  private currentFile: string = '';
  private fileProgressValue: number = 0;

  /**
   * 设置进度回调函数
   * @param callback 进度回调函数
   */
  setProgressCallback(callback: DecompressProgressCallback): void {
    this.progressCallback = callback;
  }

  /**
   * 获取当前文件进度
   */
  getFileProgress(): number {
    return this.fileProgressValue;
  }

  /**
   * 开始流式解压
   * @param zipFilePath ZIP文件路径
   * @param targetPath 目标解压路径
   * @returns Promise<boolean> 解压是否成功
   */
  async startStreamingDecompress(zipFilePath: string, targetPath: string): Promise<boolean> {
    try {
      let minizipEntry = new MinizipNative(zipFilePath);
      // 先打开ZIP文件
      if (minizipEntry.Open() == 0) {
        // 自动检测字符编码
        const detectedEncoding: number = minizipEntry.DetectCharEncoding();
        if (detectedEncoding > 0) {
          // 使用检测到的编码
          minizipEntry.SetCharEncoding(detectedEncoding);
        }

        // 获取文件列表
        this.entryNames = minizipEntry.GetEntryNames();
        this.totalFiles = this.entryNames.filter(name => !name.endsWith('/')).length; // 只计算文件，不计算文件夹

        // 获取ZIP文件总大小
        this.totalUncompressedSize = minizipEntry.GetTotalUncompressedSize();

        // 逐个解压文件
        await this.processEntriesStreaming(minizipEntry, targetPath, '');
        return true;
      } else {
        throw new Error('打开ZIP文件失败');
      }
    } catch (error) {
      console.error('[StreamingDecompressor] 解压过程出错:', error);
      return false;
    }
  }

  private processEntriesStreaming(minizipEntry: MinizipNative, targetPath: string, password: string): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.entryNames.length === 0) {
        this.updateProgress(100, 100, '', 0, 0, '没有文件需要解压');
        resolve();
        return;
      }

      // 使用递归处理每个条目，以便能够正确处理进度
      this.processNextEntryStreaming(0, minizipEntry, targetPath, password, resolve, reject);
    });
  }

  private processNextEntryStreaming(
    index: number,
    minizipEntry: MinizipNative,
    targetPath: string,
    password: string,
    resolve: () => void,
    reject: (reason: Error) => void
  ): void {
    if (index >= this.entryNames.length) {
      this.updateProgress(100, 100, '', this.totalFiles, this.totalFiles, '所有文件已解压');
      resolve();
      return;
    }

    const entryName = this.entryNames[index];
    const path = targetPath + "/" + entryName;

    if (entryName.endsWith("/")) {
      // 创建文件夹
      if (!fs.accessSync(path)) {
        fs.mkdirSync(path, true);
      }
      // 处理下一个条目
      this.processNextEntryStreaming(index + 1, minizipEntry, targetPath, password, resolve, reject);
    } else {
      // 更新当前处理的文件
      this.currentFile = entryName;
      this.fileProgressValue = 0;
      this.totalReadBytes = 0;

      // 创建文件夹（如果不存在）
      this.createFolders(path);

      try {
        // 打开条目进行流式读取
        const openResult = minizipEntry.OpenEntryForStream(entryName, password);
        if (openResult !== 0) {
          this.updateProgress(0, 0, entryName, this.processedFiles, this.totalFiles,
            `无法打开条目进行流式读取: ${entryName}`);
          // 继续处理下一个文件
          setTimeout(() => {
            this.processNextEntryStreaming(index + 1, minizipEntry, targetPath, password, resolve, reject);
          }, 1);
          return;
        }

        // 获取文件大小用于进度计算
        this.currentFileSize = this.getFileSizeFromEntry(minizipEntry, entryName);

        // 创建输出文件
        let file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);

        // 开始流式读取和写入
        this.streamEntryData(minizipEntry, file, entryName, index, targetPath, password, resolve, reject);
      } catch (error) {
        this.updateProgress(0, 0, entryName, this.processedFiles, this.totalFiles,
          `处理文件时出错: ${entryName}, 错误: ${error}`);
        // 继续处理下一个文件
        setTimeout(() => {
          this.processNextEntryStreaming(index + 1, minizipEntry, targetPath, password, resolve, reject);
        }, 1);
      }
    }
  }

  private streamEntryData(
    minizipEntry: MinizipNative,
    outputFile: fs.File,
    entryName: string,
    entryIndex: number,
    targetPath: string,
    password: string,
    resolve: () => void,
    reject: (reason: Error) => void
  ): void {
    const readAndWrite = () => {
      // 为每次读取创建新的缓冲区，避免缓冲区复用问题
      const buffer: ArrayBuffer = new ArrayBuffer(bufferSize);
      // 读取数据
      const bytesRead: number = minizipEntry.ReadEntryStream(buffer, bufferSize);

      if (bytesRead < 0) {
        // 读取错误
        fs.closeSync(outputFile);
        minizipEntry.CloseEntryStream();
        reject(new Error(`读取文件数据失败: ${entryName}`));
        return;
      }

      if (bytesRead > 0) {
        // 写入数据到文件
        try {
          fs.writeSync(outputFile.fd, buffer, { length: bytesRead });
          this.totalReadBytes += bytesRead;

          // 更新进度
          let fileProgress = 0;
          if (this.currentFileSize > 0) {
            fileProgress = Math.floor((this.totalReadBytes / this.currentFileSize) * 100);
          }

          // 更新整体进度
          let overallProgress = 0;
          if (this.totalUncompressedSize > 0) {
            overallProgress =
              Math.floor(((this.processedUncompressedSize + this.totalReadBytes) / this.totalUncompressedSize) * 100);
          }

          this.fileProgressValue = fileProgress;

          this.updateProgress(overallProgress, fileProgress, entryName, this.processedFiles, this.totalFiles,
            `正在解压: ${entryName}`);

          // 继续读取更多数据
          setTimeout(readAndWrite, 1); // 短暂延迟以允许UI更新
        } catch (writeError) {
          fs.closeSync(outputFile);
          minizipEntry.CloseEntryStream();
          reject(new Error(`写入文件失败: ${entryName}`));
          return;
        }
      } else {
        // 读取完成
        try {
          fs.closeSync(outputFile);
          minizipEntry.CloseEntryStream();

          // 更新整体进度
          this.processedUncompressedSize += this.currentFileSize;
          this.processedFiles++;
          let overallProgress = 0;
          if (this.totalUncompressedSize > 0) {
            overallProgress = Math.floor((this.processedUncompressedSize / this.totalUncompressedSize) * 100);
          } else {
            overallProgress = Math.floor((this.processedFiles / this.totalFiles) * 100);
          }

          this.fileProgressValue = 100;

          this.updateProgress(overallProgress, 100, entryName, this.processedFiles, this.totalFiles,
            `已解压完成: ${entryName}`);

          // 处理下一个条目
          setTimeout(() => {
            this.processNextEntryStreaming(entryIndex + 1, minizipEntry, targetPath, password, resolve, reject);
          }, 1);
        } catch (error) {
          reject(new Error(`关闭文件时出错: ${entryName}, 错误: ${error}`));
        }
      }
    };

    // 开始读取和写入循环
    readAndWrite();
  }

  private getFileSizeFromEntry(minizipEntry: MinizipNative, entryName: string): number {
    // 从ZIP条目中获取实际未压缩文件大小
    try {
      return minizipEntry.GetEntryUncompressedSize(entryName);
    } catch (error) {
      console.warn(`无法获取文件大小信息: ${entryName}, 使用默认值`);
      return 1024 * 1024; // 默认1MB
    }
  }

  private createFolders(path: string): void {
    const parts = path.split('/');
    if (parts.length <= 1) {
      return;
    }
    const folders = parts.slice(0, -1).join('/');
    if (!fs.accessSync(folders)) {
      fs.mkdirSync(folders, true);
    }
  }

  private updateProgress(
    overallProgress: number,
    fileProgress: number,
    currentFile: string,
    processedFiles: number,
    totalFiles: number,
    message: string
  ): void {
    if (this.progressCallback) {
      const progressInfo: DecompressProgressInfo = {
        overallProgress: overallProgress,
        fileProgress: fileProgress,
        currentFile: currentFile,
        processedFiles: processedFiles,
        totalFiles: totalFiles,
        message: message
      };
      this.progressCallback(progressInfo);
    }
  }
}