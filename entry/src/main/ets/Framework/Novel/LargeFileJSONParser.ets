import { SafeFileUtils } from '../../Utils/SafeFileUtils';
import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * 大文件流式JSON解析器
 * 用于安全导入大型书源JSON文件（50M~100M+）
 * 
 * 核心特性：
 * 1. 分块读取文件，避免一次性加载整个文件到内存
 * 2. 流式解析JSON数组，逐个提取JSON对象
 * 3. 分批处理，每批处理后让出主线程防止ANR
 * 4. 进度回调，实时反馈导入进度
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LargeFileJSONParser.ets
 */

import { logger } from '../../Utils/Logger';
import { fileIo as fs } from '@kit.CoreFileKit';

const TAG = 'LargeFileJSONParser';

/**
 * 解析进度回调
 */
export interface ParseProgressCallback {
  /**
   * 文件读取进度
   * @param bytesRead 已读取字节数
   * @param totalBytes 总字节数
   */
  onFileProgress?: (bytesRead: number, totalBytes: number) => void;
  
  /**
   * 对象解析进度
   * @param parsedCount 已解析对象数
   * @param currentObject 当前解析的对象
   */
  onObjectParsed?: (parsedCount: number, currentObject: object) => void;
  
  /**
   * 批次处理完成
   * @param batchIndex 批次索引
   * @param batchSize 批次大小
   * @param totalParsed 已解析总数
   */
  onBatchComplete?: (batchIndex: number, batchSize: number, totalParsed: number) => void;
  
  /**
   * 解析出错
   * @param error 错误信息
   * @param recoverable 是否可恢复继续
   */
  onError?: (error: string, recoverable: boolean) => void;
}

/**
 * 解析配置
 */
export interface ParseConfig {
  /**
   * 每次读取的块大小（字节），默认 512KB
   */
  chunkSize?: number;
  
  /**
   * 每批处理的对象数量，默认 50
   */
  batchSize?: number;
  
  /**
   * 批次间休眠时间（毫秒），默认 10ms，让出主线程
   */
  batchDelayMs?: number;
  
  /**
   * 单个JSON对象最大大小（字节），超过则跳过，默认 1MB
   */
  maxObjectSize?: number;
}

/**
 * 解析结果
 */
export interface ParseResult<T> {
  success: boolean;
  objects: T[];
  totalParsed: number;
  errors: string[];
  elapsedMs: number;
}

/**
 * 解析器状态
 */
enum ParserState {
  INIT,           // 初始状态
  ARRAY_START,    // 找到数组起始 [
  OBJECT_START,   // 找到对象起始 {
  IN_OBJECT,      // 在对象内部
  IN_STRING,      // 在字符串内部
  ESCAPE,         // 转义字符
  OBJECT_END,     // 对象结束 }
  ARRAY_END,      // 数组结束 ]
  DONE,           // 完成
  ERROR           // 错误
}

/**
 * 大文件流式JSON解析器
 */
export class LargeFileJSONParser<T = object> {
  private config: Required<ParseConfig>;
  private callback: ParseProgressCallback;
  
  // 默认配置
  private static readonly DEFAULT_CONFIG: Required<ParseConfig> = {
    chunkSize: 512 * 1024,      // 512KB
    batchSize: 50,              // 每批50个对象
    batchDelayMs: 10,           // 10ms
    maxObjectSize: 1024 * 1024  // 1MB
  };
  
  constructor(config?: ParseConfig, callback?: ParseProgressCallback) {
    this.config = {
      chunkSize: config?.chunkSize ?? LargeFileJSONParser.DEFAULT_CONFIG.chunkSize,
      batchSize: config?.batchSize ?? LargeFileJSONParser.DEFAULT_CONFIG.batchSize,
      batchDelayMs: config?.batchDelayMs ?? LargeFileJSONParser.DEFAULT_CONFIG.batchDelayMs,
      maxObjectSize: config?.maxObjectSize ?? LargeFileJSONParser.DEFAULT_CONFIG.maxObjectSize
    };
    this.callback = callback || {};
  }
  
  /**
   * 从文件路径解析JSON数组
   * @param filePath 文件路径
   * @returns 解析结果
   */
  async parseFromFile(filePath: string): Promise<ParseResult<T>> {
    const startTime = Date.now();
    const result: ParseResult<T> = {
      success: false,
      objects: [],
      totalParsed: 0,
      errors: [],
      elapsedMs: 0
    };
    
    let file: fs.File | null = null;
    
    try {
      // 获取文件大小
      const stat = SafeFileUtils.statSync(filePath);
      const totalSize = stat.size;
      
      logger.info(TAG, `开始解析大文件: ${filePath}, 大小: ${this.formatSize(totalSize)}`);
      
      // 打开文件
      file = SafeFileUtils.openSync(filePath, fs.OpenMode.READ_ONLY);
      
      // 流式解析
      await this.parseFileStream(file, totalSize, result);
      
      result.success = true;
      
    } catch (error) {
      const errorMsg = `文件解析失败: ${String(error)}`;
      logger.error(TAG, errorMsg);
      result.errors.push(errorMsg);
      this.callback.onError?.(errorMsg, false);
    } finally {
      if (file) {
        try {
          SafeFileUtils.closeSync(file);
        } catch (e) {
          logger.warn(TAG, `关闭文件失败: ${String(e)}`);
        }
      }
    }
    
    result.elapsedMs = Date.now() - startTime;
    logger.info(TAG, `解析完成: ${result.totalParsed}个对象, 耗时${result.elapsedMs}ms, ` +
      `错误${result.errors.length}个`);
    
    return result;
  }
  
  /**
   * 从文件描述符流式解析
   */
  private async parseFileStream(
    file: fs.File,
    totalSize: number,
    result: ParseResult<T>
  ): Promise<void> {
    const buffer = new ArrayBuffer(this.config.chunkSize);
    let bytesRead = 0;
    let offset = 0;
    
    // 解析状态
    let state = ParserState.INIT;
    let objectBuffer = '';
    let braceDepth = 0;
    let inString = false;
    let escapeNext = false;
    let batchObjects: T[] = [];
    let batchIndex = 0;
    
    // 读取并处理文件
    while (offset < totalSize) {
      // 读取一块数据
      const readLen = SafeFileUtils.readSync(file.fd, buffer, { offset: offset });
      if (readLen <= 0) {
        break;
      }
      
      offset += readLen;
      bytesRead += readLen;
      
      // 回调文件读取进度
      this.callback.onFileProgress?.(bytesRead, totalSize);
      
      // 将缓冲区转换为字符串
      const chunk = this.decodeChunk(buffer, readLen);
      
      // 逐字符解析
      for (let i = 0; i < chunk.length; i++) {
        const char = chunk[i];
        
        // 处理转义
        if (escapeNext) {
          if (state === ParserState.IN_OBJECT) {
            objectBuffer += char;
          }
          escapeNext = false;
          continue;
        }
        
        if (char === '\\' && inString) {
          objectBuffer += char;
          escapeNext = true;
          continue;
        }
        
        // 处理字符串边界
        if (char === '"' && !escapeNext) {
          if (state === ParserState.IN_OBJECT) {
            objectBuffer += char;
            inString = !inString;
          }
          continue;
        }
        
        // 在字符串内部，直接追加
        if (inString) {
          objectBuffer += char;
          continue;
        }
        
        // 根据状态处理字符
        switch (state) {
          case ParserState.INIT:
            if (char === '[') {
              state = ParserState.ARRAY_START;
            } else if (char === '{') {
              // 单个对象，不是数组
              state = ParserState.IN_OBJECT;
              objectBuffer = char;
              braceDepth = 1;
            }
            break;
            
          case ParserState.ARRAY_START:
            if (char === '{') {
              state = ParserState.IN_OBJECT;
              objectBuffer = char;
              braceDepth = 1;
            } else if (char === ']') {
              state = ParserState.DONE;
            }
            break;
            
          case ParserState.IN_OBJECT:
            objectBuffer += char;
            
            if (char === '{') {
              braceDepth++;
            } else if (char === '}') {
              braceDepth--;
              
              if (braceDepth === 0) {
                // 对象结束，尝试解析
                const parsedObj = this.tryParseObject(objectBuffer, result);
                if (parsedObj !== null) {
                  batchObjects.push(parsedObj);
                  result.totalParsed++;
                  
                  this.callback.onObjectParsed?.(result.totalParsed, parsedObj as object);
                  
                  // 检查是否需要处理批次
                  if (batchObjects.length >= this.config.batchSize) {
                    result.objects.push(...batchObjects);
                    this.callback.onBatchComplete?.(batchIndex, batchObjects.length, result.totalParsed);
                    batchObjects = [];
                    batchIndex++;
                    
                    // 让出主线程
                    await this.sleep(this.config.batchDelayMs);
                  }
                }
                
                objectBuffer = '';
                state = ParserState.ARRAY_START;
              }
            }
            
            // 检查对象大小限制
            if (objectBuffer.length > this.config.maxObjectSize) {
              const errorMsg = `对象大小超过限制 (${this.formatSize(objectBuffer.length)})`;
              result.errors.push(errorMsg);
              this.callback.onError?.(errorMsg, true);
              objectBuffer = '';
              braceDepth = 0;
              state = ParserState.ARRAY_START;
            }
            break;
            
          case ParserState.DONE:
            // 已完成，忽略后续字符
            break;
        }
      }
    }
    
    // 处理最后一批
    if (batchObjects.length > 0) {
      result.objects.push(...batchObjects);
      this.callback.onBatchComplete?.(batchIndex, batchObjects.length, result.totalParsed);
    }
    
    // 处理可能的未完成对象
    if (objectBuffer.length > 0 && braceDepth === 0) {
      const parsedObj = this.tryParseObject(objectBuffer, result);
      if (parsedObj !== null) {
        result.objects.push(parsedObj);
        result.totalParsed++;
      }
    }
  }
  
  /**
   * 解码数据块为字符串
   */
  private decodeChunk(buffer: ArrayBuffer, length: number): string {
    try {
      // 使用 TextDecoder 或手动解码
      const uint8Array = new Uint8Array(buffer, 0, length);
      let result = '';
      
      // 分批解码，避免栈溢出
      const chunkSize = 8192;
      for (let i = 0; i < uint8Array.length; i += chunkSize) {
        const end = Math.min(i + chunkSize, uint8Array.length);
        const slice = uint8Array.slice(i, end);
        result += String.fromCharCode(...slice);
      }
      
      return result;
    } catch (error) {
      logger.error(TAG, `解码数据块失败: ${String(error)}`);
      return '';
    }
  }
  
  /**
   * 尝试解析JSON对象
   */
  private tryParseObject(jsonStr: string, result: ParseResult<T>): T | null {
    try {
      const trimmed = jsonStr.trim();
      if (!trimmed || !trimmed.startsWith('{') || !trimmed.endsWith('}')) {
        return null;
      }
      
      return SafeUtils.parseObj(trimmed) as T;
    } catch (error) {
      const errorMsg = `JSON解析失败: ${String(error).substring(0, 100)}`;
      result.errors.push(errorMsg);
      this.callback.onError?.(errorMsg, true);
      return null;
    }
  }
  
  /**
   * 休眠指定毫秒
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
  
  /**
   * 格式化文件大小
   */
  private formatSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes}B`;
    } else if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)}KB`;
    } else if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / 1024 / 1024).toFixed(1)}MB`;
    } else {
      return `${(bytes / 1024 / 1024 / 1024).toFixed(2)}GB`;
    }
  }
  
  /**
   * 静态方法：快速解析大文件
   */
  static async parseFile<T = object>(
    filePath: string,
    config?: ParseConfig,
    callback?: ParseProgressCallback
  ): Promise<ParseResult<T>> {
    const parser = new LargeFileJSONParser<T>(config, callback);
    return parser.parseFromFile(filePath);
  }
  
  /**
   * 估算文件中的JSON对象数量（快速扫描）
   */
  static async estimateObjectCount(filePath: string): Promise<number> {
    try {
      const stat = SafeFileUtils.statSync(filePath);
      const totalSize = stat.size;
      
      // 采样前1MB来估算
      const sampleSize = Math.min(1024 * 1024, totalSize);
      const file = SafeFileUtils.openSync(filePath, fs.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(sampleSize);
      const readLen = SafeFileUtils.readSync(file.fd, buffer);
      SafeFileUtils.closeSync(file);
      
      // 计算采样中的 { 数量
      const uint8Array = new Uint8Array(buffer, 0, readLen);
      let braceCount = 0;
      let depth = 0;
      
      for (let i = 0; i < uint8Array.length; i++) {
        if (uint8Array[i] === 123) { // '{'
          if (depth === 0) {
            braceCount++;
          }
          depth++;
        } else if (uint8Array[i] === 125) { // '}'
          depth--;
        }
      }
      
      // 根据采样估算总数
      const ratio = totalSize / sampleSize;
      return Math.round(braceCount * ratio);
    } catch (error) {
      logger.warn(TAG, `估算对象数量失败: ${String(error)}`);
      return 0;
    }
  }
}
