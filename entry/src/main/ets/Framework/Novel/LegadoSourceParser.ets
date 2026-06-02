import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * Legado书源解析器
 * 解析和验证Legado书源JSON配置
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/LegadoSourceParser.ets
 */

import { logger } from '../../Utils/Logger';
import {
  LegadoBookSource,
  LegadoBookSourceType,
  LegadoSearchRule,
  LegadoBookInfoRule,
  LegadoTocRule,
  LegadoContentRule,
  LegadoExploreRule,
  LegadoExploreKind,
  LegadoSourceImportResult
} from './LegadoSourceTypes';

const TAG = 'LegadoSourceParser';

/**
 * Legado书源解析器类
 */
export class LegadoSourceParser {
  private source: LegadoBookSource | null = null;

  constructor() {}

  /**
   * 从JSON字符串解析书源
   */
  parseFromJSON(jsonStr: string): LegadoBookSource | null {
    try {
      const parsed: Object = SafeUtils.parseObj(jsonStr);
      
      // 检查是否为数组（批量导入）
      if (Array.isArray(parsed)) {
        const arr = parsed as Object[];
        if (arr.length > 0) {
          return this.parseSourceObject(arr[0] as Record<string, Object>);
        }
        return null;
      }
      
      return this.parseSourceObject(parsed as Record<string, Object>);
    } catch (error) {
      logger.error(TAG, `解析书源JSON失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 从JSON字符串解析多个书源
   */
  parseMultipleFromJSON(jsonStr: string): LegadoBookSource[] {
    try {
      const parsed: Object = SafeUtils.parseObj(jsonStr);
      
      if (Array.isArray(parsed)) {
        const sources: LegadoBookSource[] = [];
        const parsedArray = parsed as Object[];
        for (let i = 0; i < parsedArray.length; i++) {
          const source = this.parseSourceObject(parsedArray[i] as Record<string, Object>);
          if (source) {
            sources.push(source);
          }
        }
        return sources;
      }
      
      const single = this.parseSourceObject(parsed as Record<string, Object>);
      return single ? [single] : [];
    } catch (error) {
      logger.error(TAG, `解析书源JSON失败: ${String(error)}`);
      return [];
    }
  }

  /**
   * 解析单个书源对象
   */
  private parseSourceObject(obj: ESObject): LegadoBookSource | null {
    if (!obj) {
      return null;
    }

    // 必填字段检查
    if (!obj.bookSourceUrl || !obj.bookSourceName) {
      logger.warn(TAG, '书源缺少必填字段: bookSourceUrl 或 bookSourceName');
      return null;
    }

    const source: LegadoBookSource = {
      bookSourceUrl: String(obj.bookSourceUrl),
      bookSourceName: String(obj.bookSourceName),
      bookSourceType: this.parseBookSourceType(obj.bookSourceType),
      bookSourceGroup: obj.bookSourceGroup ? String(obj.bookSourceGroup) : undefined,
      bookUrlPattern: obj.bookUrlPattern ? String(obj.bookUrlPattern) : undefined,
      customOrder: typeof obj.customOrder === 'number' ? obj.customOrder : 0,
      enabled: obj.enabled !== false,
      enabledExplore: obj.enabledExplore !== false,
      jsLib: obj.jsLib ? String(obj.jsLib) : undefined,
      enabledCookieJar: obj.enabledCookieJar === true,
      concurrentRate: obj.concurrentRate ? String(obj.concurrentRate) : undefined,
      header: obj.header ? String(obj.header) : undefined,
      loginUrl: obj.loginUrl ? String(obj.loginUrl) : undefined,
      loginUi: obj.loginUi ? String(obj.loginUi) : undefined,
      loginCheckJs: obj.loginCheckJs ? String(obj.loginCheckJs) : undefined,
      coverDecodeJs: obj.coverDecodeJs ? String(obj.coverDecodeJs) : undefined,
      bookSourceComment: obj.bookSourceComment ? String(obj.bookSourceComment) : undefined,
      variableComment: obj.variableComment ? String(obj.variableComment) : undefined,
      lastUpdateTime: typeof obj.lastUpdateTime === 'number' ? obj.lastUpdateTime : Date.now(),
      respondTime: typeof obj.respondTime === 'number' ? obj.respondTime : 180000,
      weight: 0, // 导入的书源默认不置顶，忽略原始weight值
      exploreUrl: obj.exploreUrl ? String(obj.exploreUrl) : undefined,
      exploreScreen: obj.exploreScreen ? String(obj.exploreScreen) : undefined,
      searchUrl: obj.searchUrl ? String(obj.searchUrl) : undefined,
      ruleExplore: this.parseExploreRule(obj.ruleExplore as ESObject),
      ruleSearch: this.parseSearchRule(obj.ruleSearch as ESObject),
      ruleBookInfo: this.parseBookInfoRule(obj.ruleBookInfo as ESObject),
      ruleToc: this.parseTocRule(obj.ruleToc as ESObject),
      ruleContent: this.parseContentRule(obj.ruleContent as ESObject)
    };

    this.source = source;
    return source;
  }

  /**
   * 解析书源类型
   */
  private parseBookSourceType(type: ESObject): LegadoBookSourceType {
    if (typeof type === 'number') {
      switch (type) {
        case 0: return LegadoBookSourceType.TEXT;
        case 1: return LegadoBookSourceType.AUDIO;
        case 2: return LegadoBookSourceType.IMAGE;
        case 3: return LegadoBookSourceType.FILE;
        default: return LegadoBookSourceType.TEXT;
      }
    }
    return LegadoBookSourceType.TEXT;
  }

  /**
   * 解析搜索规则
   */
  private parseSearchRule(obj: ESObject): LegadoSearchRule | undefined {
    if (!obj) {
      return undefined;
    }

    return {
      checkKeyWord: obj.checkKeyWord ? String(obj.checkKeyWord) : undefined,
      bookList: obj.bookList ? String(obj.bookList) : undefined,
      name: obj.name ? String(obj.name) : undefined,
      author: obj.author ? String(obj.author) : undefined,
      intro: obj.intro ? String(obj.intro) : undefined,
      kind: obj.kind ? String(obj.kind) : undefined,
      lastChapter: obj.lastChapter ? String(obj.lastChapter) : undefined,
      updateTime: obj.updateTime ? String(obj.updateTime) : undefined,
      bookUrl: obj.bookUrl ? String(obj.bookUrl) : undefined,
      coverUrl: obj.coverUrl ? String(obj.coverUrl) : undefined,
      wordCount: obj.wordCount ? String(obj.wordCount) : undefined
    };
  }

  /**
   * 解析发现规则
   */
  private parseExploreRule(obj: ESObject): LegadoExploreRule | undefined {
    if (!obj) {
      return undefined;
    }

    return {
      bookList: obj.bookList ? String(obj.bookList) : undefined,
      name: obj.name ? String(obj.name) : undefined,
      author: obj.author ? String(obj.author) : undefined,
      intro: obj.intro ? String(obj.intro) : undefined,
      kind: obj.kind ? String(obj.kind) : undefined,
      lastChapter: obj.lastChapter ? String(obj.lastChapter) : undefined,
      updateTime: obj.updateTime ? String(obj.updateTime) : undefined,
      bookUrl: obj.bookUrl ? String(obj.bookUrl) : undefined,
      coverUrl: obj.coverUrl ? String(obj.coverUrl) : undefined,
      wordCount: obj.wordCount ? String(obj.wordCount) : undefined
    };
  }

  /**
   * 解析书籍详情规则
   */
  private parseBookInfoRule(obj: ESObject): LegadoBookInfoRule | undefined {
    if (!obj) {
      return undefined;
    }

    return {
      init: obj.init ? String(obj.init) : undefined,
      name: obj.name ? String(obj.name) : undefined,
      author: obj.author ? String(obj.author) : undefined,
      intro: obj.intro ? String(obj.intro) : undefined,
      kind: obj.kind ? String(obj.kind) : undefined,
      lastChapter: obj.lastChapter ? String(obj.lastChapter) : undefined,
      updateTime: obj.updateTime ? String(obj.updateTime) : undefined,
      coverUrl: obj.coverUrl ? String(obj.coverUrl) : undefined,
      tocUrl: obj.tocUrl ? String(obj.tocUrl) : undefined,
      wordCount: obj.wordCount ? String(obj.wordCount) : undefined,
      canReName: obj.canReName ? String(obj.canReName) : undefined,
      downloadUrls: obj.downloadUrls ? String(obj.downloadUrls) : undefined
    };
  }

  /**
   * 解析目录规则
   */
  private parseTocRule(obj: ESObject): LegadoTocRule | undefined {
    if (!obj) {
      return undefined;
    }

    return {
      preUpdateJs: obj.preUpdateJs ? String(obj.preUpdateJs) : undefined,
      chapterList: obj.chapterList ? String(obj.chapterList) : undefined,
      chapterName: obj.chapterName ? String(obj.chapterName) : undefined,
      chapterUrl: obj.chapterUrl ? String(obj.chapterUrl) : undefined,
      formatJs: obj.formatJs ? String(obj.formatJs) : undefined,
      isVolume: obj.isVolume ? String(obj.isVolume) : undefined,
      isVip: obj.isVip ? String(obj.isVip) : undefined,
      isPay: obj.isPay ? String(obj.isPay) : undefined,
      updateTime: obj.updateTime ? String(obj.updateTime) : undefined,
      nextTocUrl: obj.nextTocUrl ? String(obj.nextTocUrl) : undefined
    };
  }

  /**
   * 解析正文规则
   */
  private parseContentRule(obj: ESObject): LegadoContentRule | undefined {
    if (!obj) {
      return undefined;
    }

    return {
      content: obj.content ? String(obj.content) : undefined,
      title: obj.title ? String(obj.title) : undefined,
      nextContentUrl: obj.nextContentUrl ? String(obj.nextContentUrl) : undefined,
      webJs: obj.webJs ? String(obj.webJs) : undefined,
      sourceRegex: obj.sourceRegex ? String(obj.sourceRegex) : undefined,
      replaceRegex: obj.replaceRegex ? String(obj.replaceRegex) : undefined,
      imageStyle: obj.imageStyle ? String(obj.imageStyle) : undefined,
      imageDecode: obj.imageDecode ? String(obj.imageDecode) : undefined,
      payAction: obj.payAction ? String(obj.payAction) : undefined
    };
  }

  /**
   * 解析发现分类URL
   */
  parseExploreKinds(exploreUrl: string | undefined): LegadoExploreKind[] {
    if (!exploreUrl) {
      return [];
    }

    const kinds: LegadoExploreKind[] = [];

    // 检查是否为JSON格式
    if (exploreUrl.trim().startsWith('[')) {
      try {
        const parsed: Object = SafeUtils.parseObj(exploreUrl);
        const parsedArray = parsed as Record<string, Object>[];
        for (let i = 0; i < parsedArray.length; i++) {
          const item = parsedArray[i];
          if (item['title'] && item['url']) {
            const kind: LegadoExploreKind = {
              title: String(item['title']),
              url: String(item['url'])
            };
            if (item['style']) {
              kind.style = item['style'] as Record<string, Object>;
            }
            kinds.push(kind);
          }
        }
        return kinds;
      } catch (e) {
        // 不是JSON，继续按文本格式解析
      }
    }

    // 按换行分割
    const lines = exploreUrl.split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) {
        continue;
      }

      // 格式: 分类名::URL
      const parts = trimmed.split('::');
      if (parts.length >= 2) {
        kinds.push({
          title: parts[0].trim(),
          url: parts.slice(1).join('::').trim()
        });
      }
    }

    return kinds;
  }

  /**
   * 验证书源配置
   */
  validate(source?: LegadoBookSource): boolean {
    const s = source || this.source;
    if (!s) {
      return false;
    }

    // 必须有书源URL和名称
    if (!s.bookSourceUrl || !s.bookSourceName) {
      logger.warn(TAG, '书源验证失败: 缺少bookSourceUrl或bookSourceName');
      return false;
    }

    // 必须有搜索URL或发现URL
    if (!s.searchUrl && !s.exploreUrl) {
      logger.warn(TAG, '书源验证失败: 缺少searchUrl和exploreUrl');
      return false;
    }

    // 搜索规则验证
    if (s.searchUrl && s.ruleSearch) {
      if (!s.ruleSearch.bookList) {
        logger.warn(TAG, '书源验证警告: 搜索规则缺少bookList');
      }
    }

    return true;
  }

  /**
   * 获取当前解析的书源
   */
  getSource(): LegadoBookSource | null {
    return this.source;
  }

  /**
   * 将书源转换为JSON字符串
   */
  static toJSON(source: LegadoBookSource): string {
    return JSON.stringify(source, null, 2);
  }

  /**
   * 检查书源是否为小说类型
   */
  static isNovelSource(source: LegadoBookSource): boolean {
    return source.bookSourceType === LegadoBookSourceType.TEXT;
  }

  /**
   * 检查书源是否为漫画类型
   */
  static isMangaSource(source: LegadoBookSource): boolean {
    return source.bookSourceType === LegadoBookSourceType.IMAGE;
  }

  /**
   * 获取书源的基础URL
   */
  static getBaseUrl(source: LegadoBookSource): string {
    try {
      const url = LegadoSourceParser.normalizeSourceUrl(source.bookSourceUrl);
      const match = url.match(/^(https?:\/\/[^\/]+)/i);
      return match ? match[1] : url;
    } catch (e) {
      return source.bookSourceUrl;
    }
  }

  /**
   * 归一化书源URL，去除附加标识（如 ##@xxx）和无效片段
   */
  private static normalizeSourceUrl(rawUrl: string): string {
    let result = rawUrl.trim();
    const extensionSeparator = result.indexOf('##');
    if (extensionSeparator >= 0) {
      result = result.substring(0, extensionSeparator).trim();
    }

    const fragmentIndex = result.indexOf('#');
    if (fragmentIndex >= 0) {
      result = result.substring(0, fragmentIndex).trim();
    }

    return result;
  }
}
