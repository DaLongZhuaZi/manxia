/**
 * 图源管理器
 * 统一管理图源的导入、执行、测试等功能
 */

import { logger } from '../../Utils/Logger';
import { DataManager } from '../Data/DataManager';
import { SourceExecutor, ComicInfo, ComicDetailInfo, ChapterInfo, PageInfo } from './SourceExecutor';
import { SourceTester, TestResult } from './SourceTester';
import { JSONSourceParser } from './JSONSourceParser';
import { fileIo } from '@kit.CoreFileKit';
import { SourceRepositoryManager } from './SourceRepositoryManager';
import { WebViewSourceManager } from '../WebView/WebViewSourceManager';
import { CoverCacheManager } from '../Cache/CoverCacheManager';

const TAG = 'SourceManager';

/**
 * 图源类型
 */
export type SourceType = 'manga' | 'ebook' | 'novel' | 'video' | 'audio' | 'image';

/**
 * 图源信息
 */
export interface SourceInfo {
  id: number;
  name: string;
  type: SourceType;  // 图源类型：manga=漫画, novel=小说, video=视频, audio=音频, image=图片
  pkg?: string;  // 图源包名，用于文件管理
  baseUrl: string;
  version: string;
  description: string;
  language: string;
  isEnabled: boolean;
  priority: number;
  createTime: number;
  lastUpdateTime: number;
  iconPath?: string;  // 图源图标路径
  requireProxy?: boolean;  // 是否需要代理访问（对应 metadata.Internet）
}

/**
 * 导入结果
 */
export interface ImportResult {
  success: boolean;
  sourceId?: number;
  sourceName?: string;
  error?: string;
}

/**
 * 图源管理器类
 */
export class SourceManager {
  private static instance: SourceManager | null = null;
  private dataManager: DataManager;
  private executor: SourceExecutor;
  private tester: SourceTester;
  
  private decodeToString(buffer: ArrayBuffer, length: number): string {
    const bytes: Uint8Array = new Uint8Array(buffer, 0, length);
    let out: string = '';
    let i: number = 0;
    const len: number = bytes.length;
    while (i < len) {
      const b0: number = bytes[i++];
      if ((b0 & 0x80) === 0) {
        out += String.fromCharCode(b0);
      } else if ((b0 & 0xe0) === 0xc0 && i < len) {
        const b1: number = bytes[i++];
        const code: number = ((b0 & 0x1f) << 6) | (b1 & 0x3f);
        out += String.fromCharCode(code);
      } else if ((b0 & 0xf0) === 0xe0 && i + 1 < len) {
        const b1: number = bytes[i++];
        const b2: number = bytes[i++];
        const code: number = ((b0 & 0x0f) << 12) | ((b1 & 0x3f) << 6) | (b2 & 0x3f);
        out += String.fromCharCode(code);
      } else if ((b0 & 0xf8) === 0xf0 && i + 2 < len) {
        const b1: number = bytes[i++];
        const b2: number = bytes[i++];
        const b3: number = bytes[i++];
        let codePoint: number = ((b0 & 0x07) << 18) | ((b1 & 0x3f) << 12) | ((b2 & 0x3f) << 6) | (b3 & 0x3f);
        codePoint -= 0x10000;
        out += String.fromCharCode(0xd800 + ((codePoint >> 10) & 0x3ff));
        out += String.fromCharCode(0xdc00 + (codePoint & 0x3ff));
      } else {
        out += '\uFFFD';
      }
    }
    return out;
  }

  private constructor() {
    this.dataManager = DataManager.getInstance();
    this.executor = new SourceExecutor();
    this.tester = new SourceTester();
  }

  /**
   * 获取单例实例
   */
  static getInstance(): SourceManager {
    if (!SourceManager.instance) {
      SourceManager.instance = new SourceManager();
    }
    return SourceManager.instance;
  }

  // ==================== 导入功能 ====================

  /**
   * 从JSON文件导入图源
   */
  async importFromFile(filePath: string): Promise<ImportResult> {
    try {
      logger.info(TAG, `开始导入图源: ${filePath}`);

      // 读取文件内容
      const file = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const buffer = new ArrayBuffer(1024 * 1024); // 1MB
      const readLen = fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);

      const jsonContent: string = this.decodeToString(buffer, readLen);

      // 导入
      return await this.importFromJSON(jsonContent);
    } catch (error) {
      logger.error(TAG, '从文件导入失败', String(error));
      return {
        success: false,
        error: String(error)
      };
    }
  }

  /**
   * 从JSON字符串导入图源
   */
  async importFromJSON(jsonContent: string): Promise<ImportResult> {
    try {
      // 解析JSON
      const config: ESObject = JSON.parse(jsonContent) as ESObject;
      
      // 检查metadata
      if (!config.metadata) {
        return {
          success: false,
          error: '缺少metadata配置'
        };
      }
      
      const metadata: ESObject = config.metadata as ESObject;
      
      // 通过workflows字段判断是否为WebView格式
      const isWebViewFormat: boolean = !!config.workflows;
      const configType: string = isWebViewFormat ? 'webview' : 'http';
      
      // 根据类型验证配置
      if (isWebViewFormat) {
        // WebView格式验证
        logger.info(TAG, '检测到WebView格式图源（包含workflows字段）');
        
        if (!metadata.baseUrl) {
          return {
            success: false,
            error: 'WebView图源metadata中缺少baseUrl配置'
          };
        }
        
        if (typeof config.workflows !== 'object') {
          return {
            success: false,
            error: 'WebView图源workflows配置格式错误'
          };
        }
      } else {
        // HTTP格式验证（使用旧的解析器）
        logger.info(TAG, '检测到HTTP格式图源');
        
        const parser = JSONSourceParser.fromJSON(jsonContent);
        if (!parser.validate()) {
          return {
            success: false,
            error: 'HTTP图源配置验证失败'
          };
        }
      }

      const sourceName: string = metadata.name as string;
      const pkg: string = metadata.id as string;

      // 检查是否已存在（通过pkg匹配）
      const existingByPkg = await this.dataManager.getComicSourceByPkg(pkg);
      if (existingByPkg) {
        // 图源已存在，执行更新
        logger.info(TAG, `图源已存在，执行更新: ${sourceName} (pkg: ${pkg})`);
        return await this.updateSourceFromJSON(jsonContent, Number(existingByPkg.id));
      }

      // 检查是否已存在（通过名称匹配，向后兼容）
      const existing = await this.findSourceByName(sourceName);
      if (existing) {
        logger.warn(TAG, `图源已存在: ${sourceName}`);
        return {
          success: false,
          error: `图源已存在: ${sourceName}`
        };
      }

      // 导入到数据库
      const importedPkg: string = await this.dataManager.importSourceFromJSON(jsonContent);
      
      // 获取数字 ID
      const sourceRecord = await this.dataManager.getComicSourceByPkg(pkg);
      const sourceId: number = sourceRecord ? Number(sourceRecord.id) : 0;

      logger.info(TAG, `图源导入成功: ${sourceName} (ID: ${sourceId}, pkg: ${pkg}, 类型: ${configType})`);

      // [修复] 图源导入成功后，尝试恢复使用该 pkg 的在线漫画的图源关联
      // 这解决了图源删除后重新导入时，在线漫画无法识别图源的问题
      if (pkg) {
        try {
          const restoredCount = await this.dataManager.restoreOnlineComicSourceByPkg(pkg);
          if (restoredCount > 0) {
            logger.info(TAG, `[修复] 已恢复 ${restoredCount} 部在线漫画的图源关联 (pkg: ${pkg})`);
          }
        } catch (restoreError) {
          logger.warn(TAG, `[修复] 恢复在线漫画图源关联失败: ${restoreError}`);
        }
      }

      return {
        success: true,
        sourceId: sourceId,
        sourceName: sourceName
      };
    } catch (error) {
      logger.error(TAG, '导入图源失败', String(error));
      return {
        success: false,
        error: String(error)
      };
    }
  }

  /**
   * 更新已存在的图源配置
   */
  async updateSourceFromJSON(jsonContent: string, sourceId: number): Promise<ImportResult> {
    try {
      const config: ESObject = JSON.parse(jsonContent) as ESObject;
      const metadata: ESObject = config.metadata as ESObject;
      const sourceName: string = metadata.name as string;
      const baseUrl: string = metadata.baseUrl as string || '';
      const version: string = metadata.version as string || '1.0.0';
      const description: string = metadata.description as string || '';
      const language: string = metadata.language as string || 'zh-CN';
      const sourceType: string = metadata.type as string || 'manga';

      // 更新数据库中的图源配置
      await this.dataManager.updateComicSource(sourceId, {
        name: sourceName,
        baseUrl: baseUrl,
        version: version,
        description: description,
        language: language,
        type: sourceType,
        configJson: jsonContent,
        lastUpdateTime: Date.now()
      });

      logger.info(TAG, `图源更新成功: ${sourceName} (ID: ${sourceId})`);

      return {
        success: true,
        sourceId: sourceId,
        sourceName: sourceName
      };
    } catch (error) {
      logger.error(TAG, '更新图源失败', String(error));
      return {
        success: false,
        error: String(error)
      };
    }
  }

  // ==================== 查询功能 ====================

  /**
   * 获取所有图源
   */
  async getAllSources(): Promise<SourceInfo[]> {
    try {
      const sources = await this.dataManager.getAllComicSources();
      return sources.map((source: ESObject) => this.mapToSourceInfo(source));
    } catch (error) {
      logger.error(TAG, '获取图源列表失败', String(error));
      return [];
    }
  }

  /**
   * 获取启用的图源
   */
  async getEnabledSources(): Promise<SourceInfo[]> {
    try {
      const sources = await this.dataManager.getEnabledComicSources();
      return sources.map((source: ESObject) => this.mapToSourceInfo(source));
    } catch (error) {
      logger.error(TAG, '获取启用的图源失败', String(error));
      return [];
    }
  }

  /**
   * 根据名称查找图源
   */
  private async findSourceByName(name: string): Promise<SourceInfo | null> {
    const sources = await this.getAllSources();
    return sources.find((s: SourceInfo) => s.name === name) || null;
  }

  // ==================== 管理功能 ====================

  /**
   * 启用图源
   */
  async enableSource(sourceId: number): Promise<void> {
    await this.dataManager.updateComicSource(sourceId, { isEnabled: true });
    logger.info(TAG, `图源已启用: ${sourceId}`);
  }

  /**
   * 禁用图源
   */
  async disableSource(sourceId: number): Promise<void> {
    await this.dataManager.updateComicSource(sourceId, { isEnabled: false });
    logger.info(TAG, `图源已禁用: ${sourceId}`);
  }

  /**
   * 删除图源
   * @param sourceId 图源ID
   * @param pkg 图源包名（可选，用于删除文件）
   * @param sourceName 图源名称（可选，用于清理WebView缓存）
   */
  async deleteSource(sourceId: number, pkg?: string, sourceName?: string): Promise<void> {
    // 【关键】获取图源名称（如果未提供），用于清理WebView引擎缓存
    let actualSourceName = sourceName;
    if (!actualSourceName) {
      try {
        const sourceRecord = await this.dataManager.getComicSourceById(sourceId);
        if (sourceRecord) {
          actualSourceName = sourceRecord.name;
        }
      } catch (e) {
        logger.warn(TAG, `获取图源名称失败: ${e}`);
      }
    }
    
    // 如果提供了 pkg，同时删除相关文件
    if (pkg) {
      try {
        const repoManager = SourceRepositoryManager.getInstance();
        repoManager.deleteSourceFiles(pkg);
      } catch (e) {
        logger.warn(TAG, `删除图源文件失败: ${e}`);
      }
    }
    
    // 【关键】清理WebView引擎缓存（必须在删除数据库记录之前）
    try {
      const webViewManager = WebViewSourceManager.getInstance();
      webViewManager.removeSource(String(sourceId), actualSourceName);
      if (actualSourceName) {
        webViewManager.removeEngineByName(actualSourceName);
      }
      logger.info(TAG, `WebView引擎缓存已清理: ${sourceId}${actualSourceName ? ` (${actualSourceName})` : ''}`);
    } catch (e) {
      logger.warn(TAG, `清理WebView引擎缓存失败: ${e}`);
    }
    
    // 【关键】清理封面缓存目录（必须在删除数据库记录之前，因为需要 pkg 信息）
    try {
      const coverCacheManager = CoverCacheManager.getInstance();
      await coverCacheManager.cleanSourceCovers(sourceId);
      logger.info(TAG, `封面缓存已清理: ${sourceId}`);
    } catch (e) {
      logger.warn(TAG, `清理封面缓存失败: ${e}`);
    }
    
    await this.dataManager.deleteComicSource(sourceId);
    this.executor.clearCache(sourceId);
    logger.info(TAG, `图源已删除: ${sourceId}${pkg ? `, pkg: ${pkg}` : ''}`);
  }

  /**
   * 更新图源优先级
   */
  async updatePriority(sourceId: number, priority: number): Promise<void> {
    await this.dataManager.updateComicSource(sourceId, { priority: priority });
    logger.info(TAG, `图源优先级已更新: ${sourceId} -> ${priority}`);
  }

  // ==================== 执行功能 ====================

  /**
   * 获取热门漫画
   */
  async getPopular(sourceId: number, page: number = 1, limit: number = 20): Promise<ComicInfo[]> {
    return await this.executor.getPopular(sourceId, page, limit);
  }

  /**
   * 获取最新更新
   */
  async getLatest(sourceId: number, page: number = 1, limit: number = 20): Promise<ComicInfo[]> {
    return await this.executor.getLatest(sourceId, page, limit);
  }

  /**
   * 搜索漫画
   */
  async search(sourceId: number, keyword: string, page: number = 1, limit: number = 20): Promise<ComicInfo[]> {
    return await this.executor.search(sourceId, keyword, page, limit);
  }

  /**
   * 获取漫画详情
   */
  async getDetail(sourceId: number, comicId: string): Promise<ComicDetailInfo> {
    return await this.executor.getDetail(sourceId, comicId);
  }

  /**
   * 获取章节图片
   */
  async getPages(sourceId: number, chapterId: string): Promise<PageInfo[]> {
    return await this.executor.getPages(sourceId, chapterId);
  }

  // ==================== 测试功能 ====================

  /**
   * 测试图源
   */
  async testSource(sourceId: number): Promise<TestResult> {
    const sources = await this.getAllSources();
    const source = sources.find((s: SourceInfo) => s.id === sourceId);
    
    if (!source) {
      throw new Error(`图源不存在: ${sourceId}`);
    }

    return await this.tester.testSource(sourceId, source.name);
  }

  /**
   * 生成测试报告
   */
  generateTestReport(result: TestResult): string {
    return this.tester.generateReport(result);
  }

  // ==================== 工具方法 ====================

  /**
   * 映射到SourceInfo
   */
  private mapToSourceInfo(source: ESObject): SourceInfo {
    const pkg = source.pkg as string || undefined;
    let iconPath: string | undefined = undefined;
    
    // 尝试获取图标路径
    if (pkg) {
      const repoManager = SourceRepositoryManager.getInstance();
      const foundIconPath = repoManager.getSourceIconPath(pkg);
      if (foundIconPath) {
        iconPath = foundIconPath;
        logger.info(TAG, `图源 ${source.name} 找到图标: ${iconPath}`);
      } else {
        logger.warn(TAG, `图源 ${source.name} 未找到图标, pkg=${pkg}`);
      }
    } else {
      logger.warn(TAG, `图源 ${source.name} 没有 pkg 字段`);
    }
    
    // 获取图源类型，默认为manga
    const sourceType = (source.type as SourceType) || 'manga';
    logger.debug(TAG, `图源 ${source.name} 类型: ${source.type} -> ${sourceType}`);
    
    return {
      id: source.id as number,
      name: source.name as string,
      type: sourceType,
      pkg: pkg,
      baseUrl: source.baseUrl as string,
      version: source.version as string,
      description: source.description as string || '',
      language: source.language as string || 'zh-CN',
      isEnabled: Boolean(source.isEnabled),
      priority: source.priority as number || 0,
      createTime: source.createTime as number,
      lastUpdateTime: source.lastUpdateTime as number,
      iconPath: iconPath,
      requireProxy: Boolean(source.requireProxy)
    };
  }

  /**
   * 清除缓存
   */
  clearCache(): void {
    this.executor.clearCache();
    logger.info(TAG, '缓存已清除');
  }
}

// 导出便捷函数
export function getSourceManager(): SourceManager {
  return SourceManager.getInstance();
}
