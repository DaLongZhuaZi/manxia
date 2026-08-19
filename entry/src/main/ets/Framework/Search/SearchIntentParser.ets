/**
 * 搜索意图解析器
 * 将用户输入解析为结构化的搜索意图，支持ID直达、URL直达等增强功能
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  SearchIntent,
  SearchIntentType,
  UrlParsedInfo,
  SourceUrlPattern
} from './SearchIntentTypes';

const TAG = 'SearchIntentParser';

/**
 * ID前缀配置
 */
interface IdPrefixConfig {
  prefix: string;
  type: SearchIntentType;
}

/**
 * 搜索意图解析器
 * 将用户输入解析为结构化的搜索意图
 */
export class SearchIntentParser {

  /** ID前缀映射列表 */
  private static readonly ID_PREFIXES: IdPrefixConfig[] = [
    { prefix: 'id:', type: SearchIntentType.MANGA_ID },
    { prefix: 'aid:', type: SearchIntentType.MANGA_ID },
    { prefix: 'manga:', type: SearchIntentType.MANGA_ID },
    { prefix: 'illust:', type: SearchIntentType.MANGA_ID },
    { prefix: 'uid:', type: SearchIntentType.AUTHOR_ID },
    { prefix: 'user:', type: SearchIntentType.AUTHOR_ID },
    { prefix: 'author:', type: SearchIntentType.AUTHOR_ID },
    { prefix: 'sid:', type: SearchIntentType.SERIES_ID },
    { prefix: 'series:', type: SearchIntentType.SERIES_ID },
    { prefix: 'cid:', type: SearchIntentType.CHAPTER_ID },
    { prefix: 'chapter:', type: SearchIntentType.CHAPTER_ID },
  ];

  /**
   * 解析用户输入的搜索查询
   * @param rawQuery 原始输入
   * @param sourceUrlPattern 图源URL模式配置（可选）
   * @returns 解析后的搜索意图
   */
  static parse(rawQuery: string, sourceUrlPattern?: SourceUrlPattern): SearchIntent {
    const trimmed = rawQuery.trim();

    if (!trimmed) {
      const result: SearchIntent = {
        type: SearchIntentType.KEYWORD,
        rawQuery: rawQuery
      };
      return result;
    }

    // 1. 优先检测URL
    if (SearchIntentParser.isUrl(trimmed)) {
      return SearchIntentParser.parseUrl(trimmed, sourceUrlPattern);
    }

    // 2. 检测显式ID前缀
    const prefixResult = SearchIntentParser.parsePrefixedId(trimmed);
    if (prefixResult) {
      return prefixResult;
    }

    // 3. 检测纯数字（需要用户选择）
    if (SearchIntentParser.isPureNumber(trimmed)) {
      const result: SearchIntent = {
        type: SearchIntentType.AMBIGUOUS,
        id: trimmed,
        rawQuery: rawQuery
      };
      return result;
    }

    // 4. 默认为关键词搜索
    const result: SearchIntent = {
      type: SearchIntentType.KEYWORD,
      rawQuery: rawQuery
    };
    return result;
  }

  /**
   * 检测是否为URL
   */
  private static isUrl(text: string): boolean {
    return text.startsWith('http://') || text.startsWith('https://');
  }

  /**
   * 解析URL
   */
  private static parseUrl(url: string, sourceUrlPattern?: SourceUrlPattern): SearchIntent {
    logger.info(TAG, `解析URL: ${url}`);

    try {
      // 手动解析URL（ArkTS不支持URL构造函数）
      const domainMatch = url.match(/^https?:\/\/([^\/]+)/);
      const domain = domainMatch ? domainMatch[1] : '';
      const pathMatch = url.match(/^https?:\/\/[^\/]+(\/[^?#]*)?/);
      const path = pathMatch && pathMatch[1] ? pathMatch[1] : '/';

      // 通用Pixiv URL解析
      if (domain.includes('pixiv')) {
        return SearchIntentParser.parsePixivUrl(url, path);
      }

      // 通用Komiic URL解析
      if (domain.includes('komiic')) {
        return SearchIntentParser.parseKomiicUrl(url, path);
      }

      // 使用图源自定义模式解析
      if (sourceUrlPattern) {
        const customResult = SearchIntentParser.parseWithCustomPattern(url, path, sourceUrlPattern);
        if (customResult) {
          return customResult;
        }
      }

      // 无法解析，返回URL类型让图源自行处理
      const result: SearchIntent = {
        type: SearchIntentType.URL,
        url: url,
        rawQuery: url,
        urlParsedInfo: {
          domain: domain,
          pathType: 'unknown'
        } as UrlParsedInfo
      };
      return result;
    } catch (e) {
      logger.warn(TAG, `URL解析失败: ${e}`);
      const result: SearchIntent = {
        type: SearchIntentType.KEYWORD,
        rawQuery: url
      };
      return result;
    }
  }

  /**
   * 解析Pixiv URL
   */
  private static parsePixivUrl(url: string, path: string): SearchIntent {
    // /artworks/12345 或 /i/12345
    const artworkMatch = path.match(/\/(artworks|i)\/(\d+)/);
    if (artworkMatch) {
      const result: SearchIntent = {
        type: SearchIntentType.MANGA_ID,
        id: artworkMatch[2],
        url: url,
        rawQuery: url,
        urlParsedInfo: {
          domain: 'pixiv.net',
          pathType: 'artwork',
          extractedId: artworkMatch[2]
        } as UrlParsedInfo
      };
      return result;
    }

    // /users/67890
    const userMatch = path.match(/\/users\/(\d+)/);
    if (userMatch) {
      const result: SearchIntent = {
        type: SearchIntentType.AUTHOR_ID,
        id: userMatch[1],
        url: url,
        rawQuery: url,
        urlParsedInfo: {
          domain: 'pixiv.net',
          pathType: 'user',
          extractedId: userMatch[1]
        } as UrlParsedInfo
      };
      return result;
    }

    // member.php?id=67890
    const memberMatch = url.match(/member\.php\?id=(\d+)/);
    if (memberMatch) {
      const result: SearchIntent = {
        type: SearchIntentType.AUTHOR_ID,
        id: memberMatch[1],
        url: url,
        rawQuery: url,
        urlParsedInfo: {
          domain: 'pixiv.net',
          pathType: 'user',
          extractedId: memberMatch[1]
        } as UrlParsedInfo
      };
      return result;
    }

    // /user/67890/series/111
    const seriesMatch = path.match(/\/user\/(\d+)\/series\/(\d+)/);
    if (seriesMatch) {
      const result: SearchIntent = {
        type: SearchIntentType.SERIES_ID,
        id: `${seriesMatch[1]}-${seriesMatch[2]}`, // userId-seriesId
        url: url,
        rawQuery: url,
        urlParsedInfo: {
          domain: 'pixiv.net',
          pathType: 'series',
          extractedId: seriesMatch[2]
        } as UrlParsedInfo
      };
      return result;
    }

    const result: SearchIntent = {
      type: SearchIntentType.URL,
      url: url,
      rawQuery: url,
      urlParsedInfo: {
        domain: 'pixiv.net',
        pathType: 'unknown'
      } as UrlParsedInfo
    };
    return result;
  }

  /**
   * 解析Komiic URL
   */
  private static parseKomiicUrl(url: string, path: string): SearchIntent {
    // /comic/12345 或 /comic/12345/chapter/xxx
    const comicMatch = path.match(/\/comic\/(\d+)/);
    if (comicMatch) {
      const result: SearchIntent = {
        type: SearchIntentType.MANGA_ID,
        id: comicMatch[1],
        url: url,
        rawQuery: url,
        urlParsedInfo: {
          domain: 'komiic.com',
          pathType: 'artwork',
          extractedId: comicMatch[1]
        } as UrlParsedInfo
      };
      return result;
    }

    // /author/xxx
    const authorMatch = path.match(/\/author\/([^\/]+)/);
    if (authorMatch) {
      const result: SearchIntent = {
        type: SearchIntentType.AUTHOR_ID,
        id: authorMatch[1],
        url: url,
        rawQuery: url,
        urlParsedInfo: {
          domain: 'komiic.com',
          pathType: 'user',
          extractedId: authorMatch[1]
        } as UrlParsedInfo
      };
      return result;
    }

    const result: SearchIntent = {
      type: SearchIntentType.URL,
      url: url,
      rawQuery: url,
      urlParsedInfo: {
        domain: 'komiic.com',
        pathType: 'unknown'
      } as UrlParsedInfo
    };
    return result;
  }

  /**
   * 使用自定义模式解析URL
   */
  private static parseWithCustomPattern(
    url: string,
    path: string,
    pattern: SourceUrlPattern
  ): SearchIntent | null {
    if (pattern.artworkPattern) {
      const regex = new RegExp(pattern.artworkPattern);
      const match = path.match(regex);
      if (match && match[1]) {
        const result: SearchIntent = {
          type: SearchIntentType.MANGA_ID,
          id: match[1],
          url: url,
          rawQuery: url
        };
        return result;
      }
    }

    if (pattern.authorPattern) {
      const regex = new RegExp(pattern.authorPattern);
      const match = path.match(regex);
      if (match && match[1]) {
        const result: SearchIntent = {
          type: SearchIntentType.AUTHOR_ID,
          id: match[1],
          url: url,
          rawQuery: url
        };
        return result;
      }
    }

    if (pattern.seriesPattern) {
      const regex = new RegExp(pattern.seriesPattern);
      const match = path.match(regex);
      if (match && match[1]) {
        const result: SearchIntent = {
          type: SearchIntentType.SERIES_ID,
          id: match[1],
          url: url,
          rawQuery: url
        };
        return result;
      }
    }

    return null;
  }

  /**
   * 解析带前缀的ID
   */
  private static parsePrefixedId(text: string): SearchIntent | null {
    const lowerText = text.toLowerCase();

    for (let i = 0; i < SearchIntentParser.ID_PREFIXES.length; i++) {
      const config = SearchIntentParser.ID_PREFIXES[i];
      if (lowerText.startsWith(config.prefix)) {
        const id = text.substring(config.prefix.length).trim();
        if (id) {
          const result: SearchIntent = {
            type: config.type,
            id: id,
            rawQuery: text
          };
          return result;
        }
      }
    }

    return null;
  }

  /**
   * 检测是否为纯数字
   */
  private static isPureNumber(text: string): boolean {
    return /^\d+$/.test(text);
  }

  /**
   * 获取支持的前缀列表（用于UI提示）
   */
  static getSupportedPrefixes(): string[] {
    const prefixes: string[] = [];
    for (let i = 0; i < SearchIntentParser.ID_PREFIXES.length; i++) {
      prefixes.push(SearchIntentParser.ID_PREFIXES[i].prefix);
    }
    return prefixes;
  }

  /**
   * 获取搜索语法帮助文本
   */
  static getHelpText(): string {
    return `支持的搜索语法：
• 关键词：直接输入漫画名称
• 作品ID：id:12345 或 aid:12345
• 作者ID：uid:67890 或 user:67890
• 系列ID：sid:111 或 series:111
• URL：直接粘贴作品/作者页面链接`;
  }
}
