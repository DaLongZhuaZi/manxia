/**
 * HTML 实体编解码模块
 * 提供完整的 HTML 实体编码和解码功能
 * 
 * 基于 he 库设计，完全使用 ArkTS 实现
 */

/**
 * HTML 实体工具类
 */
export class HtmlEntities {
  private static _namedEntities: Map<string, string> | null = null;
  private static _reverseEntities: Map<string, string> | null = null;

  /**
   * 获取命名实体映射表（懒加载）
   */
  private static getNamedEntities(): Map<string, string> {
    if (HtmlEntities._namedEntities === null) {
      HtmlEntities._namedEntities = new Map<string, string>();
      const m = HtmlEntities._namedEntities;
      
      // 常用符号
      m.set('amp', '&');
      m.set('lt', '<');
      m.set('gt', '>');
      m.set('quot', '"');
      m.set('apos', "'");
      m.set('nbsp', '\u00A0');
      
      // 版权和商标
      m.set('copy', '©');
      m.set('reg', '®');
      m.set('trade', '™');
      
      // 货币符号
      m.set('cent', '¢');
      m.set('pound', '£');
      m.set('yen', '¥');
      m.set('euro', '€');
      
      // 数学符号
      m.set('plusmn', '±');
      m.set('times', '×');
      m.set('divide', '÷');
      m.set('frac14', '¼');
      m.set('frac12', '½');
      m.set('frac34', '¾');
      m.set('deg', '°');
      m.set('sup2', '²');
      m.set('sup3', '³');
      
      // 箭头
      m.set('larr', '←');
      m.set('uarr', '↑');
      m.set('rarr', '→');
      m.set('darr', '↓');
      m.set('harr', '↔');
      
      // 希腊字母
      m.set('alpha', 'α');
      m.set('beta', 'β');
      m.set('gamma', 'γ');
      m.set('delta', 'δ');
      m.set('epsilon', 'ε');
      m.set('theta', 'θ');
      m.set('lambda', 'λ');
      m.set('mu', 'μ');
      m.set('pi', 'π');
      m.set('sigma', 'σ');
      m.set('omega', 'ω');
      m.set('Alpha', 'Α');
      m.set('Beta', 'Β');
      m.set('Gamma', 'Γ');
      m.set('Delta', 'Δ');
      m.set('Omega', 'Ω');
      
      // 标点符号
      m.set('hellip', '\u2026');
      m.set('mdash', '\u2014');
      m.set('ndash', '\u2013');
      m.set('lsquo', '\u2018');
      m.set('rsquo', '\u2019');
      m.set('ldquo', '\u201C');
      m.set('rdquo', '\u201D');
      m.set('bull', '\u2022');
      m.set('middot', '\u00B7');
      
      // 空格
      m.set('ensp', '\u2002');
      m.set('emsp', '\u2003');
      m.set('thinsp', '\u2009');
      
      // 其他常用
      m.set('iexcl', '¡');
      m.set('iquest', '¿');
      m.set('laquo', '«');
      m.set('raquo', '»');
      m.set('sect', '§');
      m.set('para', '¶');
      m.set('dagger', '†');
      m.set('Dagger', '‡');
      m.set('permil', '‰');
      
      // 重音字母
      m.set('Agrave', 'À');
      m.set('Aacute', 'Á');
      m.set('Acirc', 'Â');
      m.set('Atilde', 'Ã');
      m.set('Auml', 'Ä');
      m.set('Aring', 'Å');
      m.set('AElig', 'Æ');
      m.set('Ccedil', 'Ç');
      m.set('Egrave', 'È');
      m.set('Eacute', 'É');
      m.set('Ecirc', 'Ê');
      m.set('Euml', 'Ë');
      m.set('Igrave', 'Ì');
      m.set('Iacute', 'Í');
      m.set('Icirc', 'Î');
      m.set('Iuml', 'Ï');
      m.set('Ntilde', 'Ñ');
      m.set('Ograve', 'Ò');
      m.set('Oacute', 'Ó');
      m.set('Ocirc', 'Ô');
      m.set('Otilde', 'Õ');
      m.set('Ouml', 'Ö');
      m.set('Oslash', 'Ø');
      m.set('Ugrave', 'Ù');
      m.set('Uacute', 'Ú');
      m.set('Ucirc', 'Û');
      m.set('Uuml', 'Ü');
      m.set('Yacute', 'Ý');
      m.set('szlig', 'ß');
      m.set('agrave', 'à');
      m.set('aacute', 'á');
      m.set('acirc', 'â');
      m.set('atilde', 'ã');
      m.set('auml', 'ä');
      m.set('aring', 'å');
      m.set('aelig', 'æ');
      m.set('ccedil', 'ç');
      m.set('egrave', 'è');
      m.set('eacute', 'é');
      m.set('ecirc', 'ê');
      m.set('euml', 'ë');
      m.set('igrave', 'ì');
      m.set('iacute', 'í');
      m.set('icirc', 'î');
      m.set('iuml', 'ï');
      m.set('ntilde', 'ñ');
      m.set('ograve', 'ò');
      m.set('oacute', 'ó');
      m.set('ocirc', 'ô');
      m.set('otilde', 'õ');
      m.set('ouml', 'ö');
      m.set('oslash', 'ø');
      m.set('ugrave', 'ù');
      m.set('uacute', 'ú');
      m.set('ucirc', 'û');
      m.set('uuml', 'ü');
      m.set('yacute', 'ý');
      m.set('yuml', 'ÿ');
    }
    return HtmlEntities._namedEntities;
  }

  /**
   * 获取反向映射表（懒加载）
   */
  private static getReverseEntities(): Map<string, string> {
    if (HtmlEntities._reverseEntities === null) {
      HtmlEntities._reverseEntities = new Map<string, string>();
      const named = HtmlEntities.getNamedEntities();
      named.forEach((char: string, name: string) => {
        if (!HtmlEntities._reverseEntities!.has(char)) {
          HtmlEntities._reverseEntities!.set(char, name);
        }
      });
    }
    return HtmlEntities._reverseEntities;
  }

  /**
   * 解码 HTML 实体
   * 支持命名实体（如 &amp;）和数字实体（如 &#38; 和 &#x26;）
   */
  static decode(text: string): string {
    if (!text || !text.includes('&')) {
      return text;
    }

    const namedEntities = HtmlEntities.getNamedEntities();

    return text.replace(/&(#?[a-zA-Z0-9]+);?/g, (match: string, entity: string): string => {
      // 数字实体 (十进制)
      if (entity.startsWith('#') && !entity.startsWith('#x') && !entity.startsWith('#X')) {
        const code = parseInt(entity.substring(1), 10);
        if (!isNaN(code) && code >= 0 && code <= 0x10FFFF) {
          return String.fromCharCode(code);
        }
        return match;
      }

      // 数字实体 (十六进制)
      if (entity.startsWith('#x') || entity.startsWith('#X')) {
        const code = parseInt(entity.substring(2), 16);
        if (!isNaN(code) && code >= 0 && code <= 0x10FFFF) {
          return String.fromCharCode(code);
        }
        return match;
      }

      // 命名实体
      const char = namedEntities.get(entity);
      if (char) {
        return char;
      }

      // 未知实体，保持原样
      return match;
    });
  }

  /**
   * 编码 HTML 特殊字符
   * 将 <, >, &, ", ' 转换为对应的 HTML 实体
   */
  static encode(text: string): string {
    if (!text) {
      return text;
    }

    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  /**
   * 编码所有非 ASCII 字符为 HTML 实体
   */
  static encodeNonAscii(text: string): string {
    if (!text) {
      return text;
    }

    const reverseEntities = HtmlEntities.getReverseEntities();
    let result = '';
    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      const code = char.charCodeAt(0);
      
      if (code > 127) {
        const entityName = reverseEntities.get(char);
        if (entityName) {
          result += `&${entityName};`;
        } else {
          result += `&#${code};`;
        }
      } else {
        result += char;
      }
    }
    return result;
  }

  /**
   * 转义 HTML 特殊字符（用于属性值）
   */
  static escape(text: string): string {
    return HtmlEntities.encode(text);
  }

  /**
   * 反转义 HTML 实体
   */
  static unescape(text: string): string {
    return HtmlEntities.decode(text);
  }

  /**
   * 检查字符串是否包含 HTML 实体
   */
  static containsEntities(text: string): boolean {
    return /&[#a-zA-Z0-9]+;/.test(text);
  }

  /**
   * 获取命名实体对应的字符
   */
  static getNamedEntity(name: string): string | undefined {
    return HtmlEntities.getNamedEntities().get(name);
  }

  /**
   * 获取字符对应的命名实体
   */
  static getEntityName(char: string): string | undefined {
    return HtmlEntities.getReverseEntities().get(char);
  }
}
