/**
 * 文件编辑器服务
 * 提供文件读写、搜索、替换等功能
 * 可作为工具被其他模块调用
 */

import { fileIo } from '@kit.CoreFileKit';
import { logger } from '../../Utils/Logger';
// 导入util模块
import { util } from '@kit.ArkTS';

const TAG = 'FileEditorService';

/**
 * 文件信息
 */
export interface FileInfo {
  path: string;
  name: string;
  extension: string;
  size: number;
  isDirectory: boolean;
  modifiedTime: number;
}

/**
 * 搜索结果
 */
export interface SearchResult {
  line: number;
  column: number;
  text: string;
  match: string;
}

/**
 * 替换结果
 */
export interface ReplaceResult {
  success: boolean;
  replacedCount: number;
  newContent: string;
}

/**
 * 文件编辑器服务类
 */
export class FileEditorService {
  private static instance: FileEditorService;
  
  private constructor() {}
  
  public static getInstance(): FileEditorService {
    if (!FileEditorService.instance) {
      FileEditorService.instance = new FileEditorService();
    }
    return FileEditorService.instance;
  }
  
  /**
   * 读取文件内容
   */
  public async readFile(filePath: string): Promise<string> {
    try {
      logger.info(TAG, `读取文件: ${filePath}`);
      
      const file = await fileIo.open(filePath, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(filePath);
      const buffer = new ArrayBuffer(stat.size);
      await fileIo.read(file.fd, buffer);
      await fileIo.close(file.fd);
      
      const decoder = new util.TextDecoder('utf-8');
      const content = decoder.decodeToString(new Uint8Array(buffer));
      
      logger.info(TAG, `文件读取成功，大小: ${stat.size} bytes`);
      return content;
    } catch (e) {
      logger.error(TAG, `读取文件失败: ${e}`);
      throw new Error(`读取文件失败: ${e}`);
    }
  }
  
  /**
   * 写入文件内容
   */
  public async writeFile(filePath: string, content: string): Promise<boolean> {
    try {
      logger.info(TAG, `写入文件: ${filePath}`);
      
      const encoder = new util.TextEncoder();
      const buffer = encoder.encodeInto(content);
      
      const file = await fileIo.open(filePath, 
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      await fileIo.write(file.fd, buffer.buffer);
      await fileIo.close(file.fd);
      
      logger.info(TAG, `文件写入成功，大小: ${buffer.buffer.byteLength} bytes`);
      return true;
    } catch (e) {
      logger.error(TAG, `写入文件失败: ${e}`);
      throw new Error(`写入文件失败: ${e}`);
    }
  }
  
  /**
   * 获取文件信息
   */
  public async getFileInfo(filePath: string): Promise<FileInfo> {
    try {
      const stat = await fileIo.stat(filePath);
      const name = filePath.split('/').pop() || '';
      const extension = name.includes('.') ? name.split('.').pop() || '' : '';
      
      return {
        path: filePath,
        name: name,
        extension: extension.toLowerCase(),
        size: stat.size,
        isDirectory: stat.isDirectory(),
        modifiedTime: stat.mtime
      };
    } catch (e) {
      logger.error(TAG, `获取文件信息失败: ${e}`);
      throw new Error(`获取文件信息失败: ${e}`);
    }
  }
  
  /**
   * 检查文件是否存在
   */
  public async fileExists(filePath: string): Promise<boolean> {
    try {
      await fileIo.access(filePath);
      return true;
    } catch {
      return false;
    }
  }
  
  /**
   * 创建文件
   */
  public async createFile(filePath: string, content: string = ''): Promise<boolean> {
    try {
      logger.info(TAG, `创建文件: ${filePath}`);
      
      // 确保目录存在
      const dirPath = filePath.substring(0, filePath.lastIndexOf('/'));
      await this.ensureDirectory(dirPath);
      
      return await this.writeFile(filePath, content);
    } catch (e) {
      logger.error(TAG, `创建文件失败: ${e}`);
      throw new Error(`创建文件失败: ${e}`);
    }
  }
  
  /**
   * 删除文件
   */
  public async deleteFile(filePath: string): Promise<boolean> {
    try {
      logger.info(TAG, `删除文件: ${filePath}`);
      await fileIo.unlink(filePath);
      logger.info(TAG, '文件删除成功');
      return true;
    } catch (e) {
      logger.error(TAG, `删除文件失败: ${e}`);
      throw new Error(`删除文件失败: ${e}`);
    }
  }
  
  /**
   * 重命名/移动文件
   */
  public async renameFile(oldPath: string, newPath: string): Promise<boolean> {
    try {
      logger.info(TAG, `重命名文件: ${oldPath} -> ${newPath}`);
      await fileIo.rename(oldPath, newPath);
      logger.info(TAG, '文件重命名成功');
      return true;
    } catch (e) {
      logger.error(TAG, `重命名文件失败: ${e}`);
      throw new Error(`重命名文件失败: ${e}`);
    }
  }
  
  /**
   * 复制文件
   */
  public async copyFile(srcPath: string, destPath: string): Promise<boolean> {
    try {
      logger.info(TAG, `复制文件: ${srcPath} -> ${destPath}`);
      await fileIo.copyFile(srcPath, destPath);
      logger.info(TAG, '文件复制成功');
      return true;
    } catch (e) {
      logger.error(TAG, `复制文件失败: ${e}`);
      throw new Error(`复制文件失败: ${e}`);
    }
  }
  
  /**
   * 确保目录存在
   */
  public async ensureDirectory(dirPath: string): Promise<void> {
    try {
      await fileIo.access(dirPath);
    } catch {
      await fileIo.mkdir(dirPath, true);
      logger.info(TAG, `创建目录: ${dirPath}`);
    }
  }
  
  /**
   * 列出目录内容
   */
  public async listDirectory(dirPath: string): Promise<FileInfo[]> {
    try {
      const entries = await fileIo.listFile(dirPath);
      const files: FileInfo[] = [];
      
      for (const entry of entries) {
        const fullPath = `${dirPath}/${entry}`;
        try {
          const info = await this.getFileInfo(fullPath);
          files.push(info);
        } catch {
          // 忽略无法访问的文件
        }
      }
      
      // 排序：目录在前，文件在后，按名称排序
      files.sort((a, b) => {
        if (a.isDirectory !== b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return a.name.localeCompare(b.name);
      });
      
      return files;
    } catch (e) {
      logger.error(TAG, `列出目录失败: ${e}`);
      throw new Error(`列出目录失败: ${e}`);
    }
  }
  
  /**
   * 在文件内容中搜索
   */
  public searchInContent(content: string, searchText: string, caseSensitive: boolean = false, useRegex: boolean = false): SearchResult[] {
    const results: SearchResult[] = [];
    const lines = content.split('\n');
    
    let pattern: RegExp;
    if (useRegex) {
      try {
        pattern = new RegExp(searchText, caseSensitive ? 'g' : 'gi');
      } catch {
        logger.error(TAG, '无效的正则表达式');
        return results;
      }
    } else {
      const escaped = searchText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      pattern = new RegExp(escaped, caseSensitive ? 'g' : 'gi');
    }
    
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      let match: RegExpExecArray | null;
      
      while ((match = pattern.exec(line)) !== null) {
        results.push({
          line: i + 1,
          column: match.index + 1,
          text: line,
          match: match[0]
        });
        
        // 防止无限循环（对于空匹配）
        if (match.index === pattern.lastIndex) {
          pattern.lastIndex++;
        }
      }
    }
    
    logger.info(TAG, `搜索完成，找到 ${results.length} 个结果`);
    return results;
  }
  
  /**
   * 替换文件内容
   */
  public replaceInContent(content: string, searchText: string, replaceText: string, 
    caseSensitive: boolean = false, useRegex: boolean = false, replaceAll: boolean = true): ReplaceResult {
    
    let pattern: RegExp;
    if (useRegex) {
      try {
        pattern = new RegExp(searchText, caseSensitive ? (replaceAll ? 'g' : '') : (replaceAll ? 'gi' : 'i'));
      } catch {
        logger.error(TAG, '无效的正则表达式');
        return { success: false, replacedCount: 0, newContent: content };
      }
    } else {
      const escaped = searchText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      pattern = new RegExp(escaped, caseSensitive ? (replaceAll ? 'g' : '') : (replaceAll ? 'gi' : 'i'));
    }
    
    let replacedCount = 0;
    const newContent = content.replace(pattern, (match) => {
      replacedCount++;
      return replaceText;
    });
    
    logger.info(TAG, `替换完成，替换了 ${replacedCount} 处`);
    return {
      success: replacedCount > 0,
      replacedCount: replacedCount,
      newContent: newContent
    };
  }
  
  /**
   * 根据文件扩展名获取语言类型
   */
  public getLanguageByExtension(extension: string): string {
    const languageMap: Record<string, string> = {
      'js': 'javascript',
      'ts': 'typescript',
      'jsx': 'javascript',
      'tsx': 'typescript',
      'json': 'json',
      'xml': 'xml',
      'html': 'html',
      'htm': 'html',
      'css': 'css',
      'scss': 'scss',
      'less': 'less',
      'md': 'markdown',
      'markdown': 'markdown',
      'py': 'python',
      'java': 'java',
      'kt': 'kotlin',
      'c': 'c',
      'cpp': 'cpp',
      'h': 'c',
      'hpp': 'cpp',
      'cs': 'csharp',
      'go': 'go',
      'rs': 'rust',
      'swift': 'swift',
      'rb': 'ruby',
      'php': 'php',
      'sql': 'sql',
      'sh': 'shell',
      'bash': 'shell',
      'yaml': 'yaml',
      'yml': 'yaml',
      'toml': 'ini',
      'ini': 'ini',
      'conf': 'ini',
      'txt': 'plaintext',
      'log': 'plaintext',
      'ets': 'typescript',
      'ark': 'typescript'
    };
    
    return languageMap[extension.toLowerCase()] || 'plaintext';
  }
  
  /**
   * 检查是否为文本文件
   */
  public isTextFile(extension: string): boolean {
    const textExtensions = [
      'txt', 'md', 'markdown', 'json', 'xml', 'html', 'htm', 'css', 'scss', 'less',
      'js', 'ts', 'jsx', 'tsx', 'py', 'java', 'kt', 'c', 'cpp', 'h', 'hpp', 'cs',
      'go', 'rs', 'swift', 'rb', 'php', 'sql', 'sh', 'bash', 'yaml', 'yml', 'toml',
      'ini', 'conf', 'log', 'ets', 'ark', 'vue', 'svelte', 'astro'
    ];
    return textExtensions.includes(extension.toLowerCase());
  }
}



// 导出单例
export const fileEditorService = FileEditorService.getInstance();
