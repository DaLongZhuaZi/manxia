/**
 * HTML格式化工具
 * 参考Kotlin原版Legado的HtmlFormatter实现
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/HtmlFormatter.ets
 */

/**
 * HTML格式化器
 * 用于将HTML内容转换为纯文本，保留必要的格式
 */
interface LegadoImageUrlOptionSplit {
  url: string;
  optionSuffix: string;
}

export class HtmlFormatter {
  // &nbsp; 空格
  private static readonly nbspRegex = /(&nbsp;)+/gi;
  // &ensp; &emsp; 空格
  private static readonly espRegex = /(&ensp;|&emsp;)/gi;
  // 不可打印字符
  private static readonly noPrintRegex = /(&thinsp;|&zwnj;|&zwj;|\u2009|\u200C|\u200D)/g;
  // 换行HTML标签
  private static readonly wrapHtmlRegex = /<\/?(?:div|p|br|hr|h[1-6]|article|dd|dl)[^>]*>/gi;
  // HTML注释
  private static readonly commentRegex = /<!--[\s\S]*?-->/g;
  // 非img的HTML标签
  private static readonly notImgHtmlRegex = /<\/?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>/gi;
  // 所有HTML标签
  private static readonly otherHtmlRegex = /<\/?[a-zA-Z]+(?=[ >])[^<>]*>/gi;
  // script标签及内容
  private static readonly scriptRegex = /<script[^>]*>[\s\S]*?<\/script>/gi;
  // style标签及内容
  private static readonly styleRegex = /<style[^>]*>[\s\S]*?<\/style>/gi;
  // 多个换行合并
  private static readonly indent1Regex = /\s*\n+\s*/g;
  // 开头空白
  private static readonly indent2Regex = /^[\n\s]+/;
  // 结尾空白
  private static readonly lastRegex = /[\n\s]+$/;
  // Legado原版图片标签格式：src、data-src、任意data-*，并兼容带参数占位的src
  private static readonly formatImageRegex: RegExp =
    /<img[^>]*\ssrc\s*=\s*(?:"([^"{>]*\{(?:[^{}]|\{[^}>]+\})+\})"|'([^'{>]*\{(?:[^{}]|\{[^}>]+\})+\})'|([^'"\s>]*\{(?:[^{}]|\{[^}>]+\})+\}))[^>]*>|<img[^>]*\s(?:data-src|src)\s*=\s*(?:"([^'">]+)"|'([^'">]+)'|([^\s"'<>]+))[^>]*>|<img[^>]*\sdata-[^=>]*=\s*(?:"([^'">]*)"|'([^'">]*)'|([^\s"'<>]*))[^>]*>/gi;
  private static readonly legadoUrlOptionSeparatorRegex: RegExp = /\s*,\s*(?=\{)/;

  /**
   * 格式化HTML为纯文本
   * @param html HTML内容
   * @param keepImg 是否保留图片标签
   * @returns 格式化后的纯文本
   */
  static format(html: string | null | undefined, keepImg: boolean = false): string {
    if (!html) return '';
    
    let result = html;
    
    // 1. 移除script标签及内容
    result = result.replace(HtmlFormatter.scriptRegex, '');
    
    // 2. 移除style标签及内容
    result = result.replace(HtmlFormatter.styleRegex, '');
    
    // 3. 处理空格实体
    result = result.replace(HtmlFormatter.nbspRegex, ' ');
    result = result.replace(HtmlFormatter.espRegex, ' ');
    result = result.replace(HtmlFormatter.noPrintRegex, '');
    
    // 4. 将换行标签转换为换行符
    result = result.replace(HtmlFormatter.wrapHtmlRegex, '\n');
    
    // 5. 移除HTML注释
    result = result.replace(HtmlFormatter.commentRegex, '');
    
    // 6. 移除HTML标签（可选保留img）
    if (keepImg) {
      result = result.replace(HtmlFormatter.notImgHtmlRegex, '');
    } else {
      result = result.replace(HtmlFormatter.otherHtmlRegex, '');
    }
    
    // 7. 处理换行（不添加缩进，缩进由后续处理统一添加）
    // 注意：之前这里添加了'　　'缩进，但会导致与NovelContentProcessor和TextReaderComponent的缩进重复
    result = result.replace(HtmlFormatter.indent1Regex, '\n');
    result = result.replace(HtmlFormatter.indent2Regex, '');
    result = result.replace(HtmlFormatter.lastRegex, '');
    
    return result;
  }

  /**
   * 格式化HTML并保留图片标签
   * @param html HTML内容
   * @param baseUrl 基础URL，用于解析相对路径
   * @returns 格式化后的内容（保留img标签）
   */
  static formatKeepImg(html: string | null | undefined, baseUrl?: string): string {
    if (!html) return '';
    
    const keepImgHtml = HtmlFormatter.format(html, true);
    let appendPos = 0;
    let result = '';
    HtmlFormatter.formatImageRegex.lastIndex = 0;
    let match = HtmlFormatter.formatImageRegex.exec(keepImgHtml);
    while (match) {
      result += keepImgHtml.substring(appendPos, match.index);
      const rawSrc = HtmlFormatter.readFirstRegexGroup(match, 1, 9);
      const separatedUrl = HtmlFormatter.separateLegadoImageUrlOption(rawSrc);
      const absoluteUrl = HtmlFormatter.resolveUrl(separatedUrl.url, baseUrl || '');
      result += `<img src="${absoluteUrl}${separatedUrl.optionSuffix}">`;
      appendPos = match.index + match[0].length;
      match = HtmlFormatter.formatImageRegex.exec(keepImgHtml);
    }

    if (appendPos < keepImgHtml.length) {
      result += keepImgHtml.substring(appendPos);
    }
    
    return result;
  }

  private static readFirstRegexGroup(match: RegExpExecArray, startIndex: number, endIndex: number): string {
    for (let i = startIndex; i <= endIndex && i < match.length; i++) {
      const value = match[i];
      if (value && value.length > 0) {
        return value;
      }
    }
    return '';
  }

  static resolveUrlForImage(url: string, baseUrl: string): string {
    const separatedUrl = HtmlFormatter.separateLegadoImageUrlOption(url);
    return HtmlFormatter.resolveUrl(separatedUrl.url, baseUrl) + separatedUrl.optionSuffix;
  }

  static getUrlWithoutLegadoOption(url: string): string {
    return HtmlFormatter.separateLegadoImageUrlOption(url).url;
  }

  static getLegadoUrlOptionSuffix(url: string): string {
    return HtmlFormatter.separateLegadoImageUrlOption(url).optionSuffix;
  }

  private static separateLegadoImageUrlOption(url: string): LegadoImageUrlOptionSplit {
    const trimmed = url ? HtmlFormatter.unescapeHtml(url.trim()) : '';
    if (trimmed.length <= 0) {
      return { url: '', optionSuffix: '' };
    }
    const match = HtmlFormatter.legadoUrlOptionSeparatorRegex.exec(trimmed);
    if (!match || match.index <= 0) {
      return { url: trimmed, optionSuffix: '' };
    }
    const imageUrl = trimmed.substring(0, match.index).trim();
    const optionSuffix = ',' + trimmed.substring(match.index + match[0].length).trim();
    return { url: imageUrl, optionSuffix: optionSuffix };
  }

  /**
   * 解析相对URL为绝对URL
   */
  private static resolveUrl(url: string, baseUrl: string): string {
    if (!url) return '';
    const trimmedUrl = url.trim();
    
    // 已经是绝对URL
    if (trimmedUrl.startsWith('http://') || trimmedUrl.startsWith('https://') || trimmedUrl.startsWith('//')) {
      if (trimmedUrl.startsWith('//')) {
        return 'https:' + trimmedUrl;
      }
      return trimmedUrl;
    }
    
    // data URL
    if (trimmedUrl.startsWith('data:')) {
      return trimmedUrl;
    }
    
    try {
      // 解析baseUrl
      const baseMatch = baseUrl.match(/^(https?:\/\/[^\/?#]+)([^?#]*)?([?#].*)?$/);
      if (!baseMatch) return trimmedUrl;
      
      const origin = baseMatch[1];
      const basePath = baseMatch[2] && baseMatch[2].length > 0 ? baseMatch[2] : '/';
      const baseWithoutSuffix = origin + basePath;
      if (trimmedUrl.startsWith('?') || trimmedUrl.startsWith('#')) {
        return baseWithoutSuffix.replace(/[?#].*$/, '') + trimmedUrl;
      }
      
      let pathWithSuffix = '';
      if (trimmedUrl.startsWith('/')) {
        pathWithSuffix = trimmedUrl;
      } else if (basePath.endsWith('/')) {
        pathWithSuffix = basePath + trimmedUrl;
      } else {
        const lastSlash = basePath.lastIndexOf('/');
        const parentPath = lastSlash >= 0 ? basePath.substring(0, lastSlash + 1) : '/';
        pathWithSuffix = parentPath + trimmedUrl;
      }
      return origin + HtmlFormatter.normalizeUrlPath(pathWithSuffix);
    } catch (e) {
      return trimmedUrl;
    }
  }

  private static normalizeUrlPath(pathWithSuffix: string): string {
    const suffixMatch = pathWithSuffix.match(/([?#].*)$/);
    const suffix = suffixMatch ? suffixMatch[1] : '';
    const path = suffixMatch ? pathWithSuffix.substring(0, pathWithSuffix.length - suffix.length) : pathWithSuffix;
    const segments = path.split('/');
    const normalizedSegments: string[] = [];
    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i];
      if (segment.length === 0 || segment === '.') {
        continue;
      }
      if (segment === '..') {
        if (normalizedSegments.length > 0) {
          normalizedSegments.pop();
        }
        continue;
      }
      normalizedSegments.push(segment);
    }
    return '/' + normalizedSegments.join('/') + suffix;
  }

  /**
   * 处理HTML实体
   * 参考Apache Commons Text的StringEscapeUtils.unescapeHtml4
   */
  static unescapeHtml(html: string): string {
    if (!html || html.indexOf('&') === -1) return html;
    
    let result = html;
    
    // 常见HTML实体
    const entities: Record<string, string> = {
      '&nbsp;': ' ',
      '&lt;': '<',
      '&gt;': '>',
      '&amp;': '&',
      '&quot;': '"',
      '&apos;': "'",
      '&#39;': "'",
      '&ldquo;': '"',
      '&rdquo;': '"',
      '&lsquo;': "'",
      '&rsquo;': "'",
      '&mdash;': '—',
      '&ndash;': '–',
      '&hellip;': '…',
      '&copy;': '©',
      '&reg;': '®',
      '&trade;': '™',
      '&times;': '×',
      '&divide;': '÷',
      '&plusmn;': '±',
      '&deg;': '°',
      '&cent;': '¢',
      '&pound;': '£',
      '&euro;': '€',
      '&yen;': '¥',
      '&sect;': '§',
      '&para;': '¶',
      '&bull;': '•',
      '&middot;': '·',
      '&ensp;': ' ',
      '&emsp;': ' ',
      '&thinsp;': ' ',
      '&zwnj;': '',
      '&zwj;': ''
    };
    
    // 替换命名实体
    for (const entity of Object.keys(entities)) {
      result = result.replace(new RegExp(entity, 'gi'), entities[entity]);
    }
    
    // 替换数字实体 &#123;
    result = result.replace(/&#(\d+);/g, (_match: string, dec: string): string => {
      const code = parseInt(dec, 10);
      if (code > 0 && code < 65536) {
        return String.fromCharCode(code);
      }
      return _match;
    });
    
    // 替换十六进制实体 &#x1F4A9;
    result = result.replace(/&#x([0-9a-fA-F]+);/g, (_match: string, hex: string): string => {
      const code = parseInt(hex, 16);
      if (code > 0 && code < 65536) {
        return String.fromCharCode(code);
      }
      return _match;
    });
    
    return result;
  }

  /**
   * 清理正文内容
   * 移除广告、无关内容等
   */
  static cleanContent(content: string): string {
    if (!content) return '';
    
    let result = content;
    
    // 移除常见广告文本模式
    const adPatterns = [
      /本章未完.*?点击下一页继续阅读/gi,
      /手机用户请浏览.*?阅读/gi,
      /请记住本书.*?网址/gi,
      /最新章节.*?请访问/gi,
      /天才一秒记住.*?地址/gi,
      /一秒记住.*?免费阅读/gi
    ];
    
    for (const pattern of adPatterns) {
      result = result.replace(pattern, '');
    }
    
    return result.trim();
  }
}
