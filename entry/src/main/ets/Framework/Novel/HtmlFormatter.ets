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
    
    let result = HtmlFormatter.format(html, true);
    
    // 处理图片URL，转换为绝对路径
    if (baseUrl) {
      result = result.replace(/<img[^>]*\ssrc\s*=\s*["']([^"']+)["'][^>]*>/gi, 
        (_match: string, src: string): string => {
          const absoluteUrl = HtmlFormatter.resolveUrl(src, baseUrl);
          return `<img src="${absoluteUrl}">`;
        });
    }
    
    return result;
  }

  /**
   * 解析相对URL为绝对URL
   */
  private static resolveUrl(url: string, baseUrl: string): string {
    if (!url) return '';
    
    // 已经是绝对URL
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('//')) {
      if (url.startsWith('//')) {
        return 'https:' + url;
      }
      return url;
    }
    
    // data URL
    if (url.startsWith('data:')) {
      return url;
    }
    
    try {
      // 解析baseUrl
      const baseMatch = baseUrl.match(/^(https?:\/\/[^\/]+)/);
      if (!baseMatch) return url;
      
      const origin = baseMatch[1];
      
      if (url.startsWith('/')) {
        return origin + url;
      } else {
        // 相对路径
        const basePath = baseUrl.replace(/[^\/]*$/, '');
        return basePath + url;
      }
    } catch (e) {
      return url;
    }
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
