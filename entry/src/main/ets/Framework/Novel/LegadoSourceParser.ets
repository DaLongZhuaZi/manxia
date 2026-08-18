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
  LegadoExploreKindStyle,
  LegadoReviewRule,
  LegadoSourceImportResult
} from './LegadoSourceTypes';

const TAG = 'LegadoSourceParser';

interface LegadoOldUrlOption {
  method?: string;
  charset?: string;
  headers?: Record<string, string>;
  body?: string;
}

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

    const isOldFlatSource = this.hasOldFlatSourceFields(obj);
    const oldSearchUrl = this.toNewUrl(this.readStringField(obj, 'ruleSearchUrl'));
    const oldExploreUrl = this.toNewUrls(this.readStringField(obj, 'ruleFindUrl'));
    const resolvedSearchUrl = this.readStringField(obj, 'searchUrl') || oldSearchUrl;
    const resolvedExploreUrl = this.readStringField(obj, 'exploreUrl') || oldExploreUrl;
    const resolvedHeader = this.readStringField(obj, 'header') ||
      this.uaToHeader(this.readStringField(obj, 'httpUserAgent'));
    const enabledValue = this.readField(obj, 'enabled') !== undefined
      ? this.readField(obj, 'enabled')
      : this.readField(obj, 'enable');
    const enabledExploreFallback = isOldFlatSource && (!resolvedExploreUrl || resolvedExploreUrl.trim().length <= 0)
      ? false
      : true;
    const parsedSearchRule = this.parseSearchRule(this.parseRuleObject(obj.ruleSearch));
    const parsedExploreRule = this.parseExploreRule(this.parseRuleObject(obj.ruleExplore));
    const parsedBookInfoRule = this.parseBookInfoRule(this.parseRuleObject(obj.ruleBookInfo));
    const parsedTocRule = this.parseTocRule(this.parseRuleObject(obj.ruleToc));
    const parsedContentRule = this.parseContentRule(this.parseRuleObject(obj.ruleContent));

    const source: LegadoBookSource = {
      bookSourceUrl: String(obj.bookSourceUrl),
      bookSourceName: String(obj.bookSourceName),
      bookSourceType: this.parseBookSourceType(obj.bookSourceType),
      bookSourceGroup: obj.bookSourceGroup ? String(obj.bookSourceGroup) : undefined,
      bookUrlPattern: this.readStringField(obj, 'bookUrlPattern') ||
        this.readStringField(obj, 'ruleBookUrlPattern'),
      customOrder: this.parseNumberField(
        this.readField(obj, 'customOrder') !== undefined
          ? this.readField(obj, 'customOrder')
          : this.readField(obj, 'serialNumber'),
        0
      ),
      enabled: this.parseBooleanField(enabledValue, true),
      enabledExplore: this.parseBooleanField(obj.enabledExplore, enabledExploreFallback),
      jsLib: obj.jsLib ? String(obj.jsLib) : undefined,
      enabledCookieJar: this.parseBooleanField(obj.enabledCookieJar, true),
      concurrentRate: obj.concurrentRate ? String(obj.concurrentRate) : undefined,
      header: resolvedHeader,
      loginUrl: obj.loginUrl ? String(obj.loginUrl) : undefined,
      loginUi: obj.loginUi ? String(obj.loginUi) : undefined,
      loginCheckJs: obj.loginCheckJs ? String(obj.loginCheckJs) : undefined,
      coverDecodeJs: obj.coverDecodeJs ? String(obj.coverDecodeJs) : undefined,
      bookSourceComment: obj.bookSourceComment ? String(obj.bookSourceComment) : undefined,
      variableComment: obj.variableComment ? String(obj.variableComment) : undefined,
      lastUpdateTime: this.parseNumberField(obj.lastUpdateTime, Date.now()),
      respondTime: this.parseNumberField(obj.respondTime, 180000),
      // V2 原始文档会完整保存；旧记录也必须保留 Legado 的排序权重，
      // 不能因为导入而隐式改写用户的排序语义。
      weight: this.parseNumberField(obj.weight, 0),
      exploreUrl: resolvedExploreUrl,
      exploreScreen: obj.exploreScreen ? String(obj.exploreScreen) : undefined,
      searchUrl: resolvedSearchUrl,
      ruleExplore: this.mergeExploreRule(parsedExploreRule, this.parseOldExploreRule(obj)),
      ruleSearch: this.mergeSearchRule(parsedSearchRule, this.parseOldSearchRule(obj)),
      ruleBookInfo: this.mergeBookInfoRule(parsedBookInfoRule, this.parseOldBookInfoRule(obj)),
      ruleToc: this.mergeTocRule(parsedTocRule, this.parseOldTocRule(obj)),
      ruleContent: this.mergeContentRule(parsedContentRule, this.parseOldContentRule(obj)),
      ruleReview: this.parseReviewRule(this.parseRuleObject(obj.ruleReview))
    };

    this.source = source;
    return source;
  }

  private hasOldFlatSourceFields(obj: ESObject): boolean {
    const oldFieldNames: string[] = [
      'ruleSearchUrl',
      'ruleFindUrl',
      'ruleSearchList',
      'ruleFindList',
      'ruleBookName',
      'ruleChapterList',
      'ruleBookContent',
      'httpUserAgent',
      'serialNumber',
      'enable',
      'ruleBookUrlPattern'
    ];
    for (let i = 0; i < oldFieldNames.length; i++) {
      if (this.hasField(obj, oldFieldNames[i])) {
        return true;
      }
    }
    return false;
  }

  private hasField(obj: ESObject, key: string): boolean {
    if (obj === null || obj === undefined || typeof obj !== 'object') {
      return false;
    }
    return Object.keys(obj).includes(key);
  }

  private readField(obj: ESObject, key: string): Object | undefined {
    if (!this.hasField(obj, key)) {
      return undefined;
    }
    const record = obj as Record<string, Object>;
    return record[key];
  }

  private readStringField(obj: ESObject, key: string): string {
    const value = this.readField(obj, key);
    if (value === null || value === undefined) {
      return '';
    }
    const text = String(value).trim();
    return text;
  }

  private preferString(primary: string | undefined, fallback: string | undefined): string | undefined {
    if (primary !== undefined && primary !== null && primary.length > 0) {
      return primary;
    }
    if (fallback !== undefined && fallback !== null && fallback.length > 0) {
      return fallback;
    }
    return undefined;
  }

  private parseOldSearchRule(obj: ESObject): LegadoSearchRule | undefined {
    const rule: LegadoSearchRule = {
      bookList: this.toNewRule(this.readStringField(obj, 'ruleSearchList')),
      name: this.toNewRule(this.readStringField(obj, 'ruleSearchName')),
      author: this.toNewRule(this.readStringField(obj, 'ruleSearchAuthor')),
      intro: this.toNewRule(this.readStringField(obj, 'ruleSearchIntroduce')),
      kind: this.toNewRule(this.readStringField(obj, 'ruleSearchKind')),
      bookUrl: this.toNewRule(this.readStringField(obj, 'ruleSearchNoteUrl')),
      coverUrl: this.toNewRule(this.readStringField(obj, 'ruleSearchCoverUrl')),
      lastChapter: this.toNewRule(this.readStringField(obj, 'ruleSearchLastChapter'))
    };
    return this.hasSearchRuleContent(rule) ? rule : undefined;
  }

  private parseOldExploreRule(obj: ESObject): LegadoExploreRule | undefined {
    const rule: LegadoExploreRule = {
      bookList: this.toNewRule(this.readStringField(obj, 'ruleFindList')),
      name: this.toNewRule(this.readStringField(obj, 'ruleFindName')),
      author: this.toNewRule(this.readStringField(obj, 'ruleFindAuthor')),
      intro: this.toNewRule(this.readStringField(obj, 'ruleFindIntroduce')),
      kind: this.toNewRule(this.readStringField(obj, 'ruleFindKind')),
      bookUrl: this.toNewRule(this.readStringField(obj, 'ruleFindNoteUrl')),
      coverUrl: this.toNewRule(this.readStringField(obj, 'ruleFindCoverUrl')),
      lastChapter: this.toNewRule(this.readStringField(obj, 'ruleFindLastChapter'))
    };
    return this.hasExploreRuleContent(rule) ? rule : undefined;
  }

  private parseOldBookInfoRule(obj: ESObject): LegadoBookInfoRule | undefined {
    const rule: LegadoBookInfoRule = {
      init: this.toNewRule(this.readStringField(obj, 'ruleBookInfoInit')),
      name: this.toNewRule(this.readStringField(obj, 'ruleBookName')),
      author: this.toNewRule(this.readStringField(obj, 'ruleBookAuthor')),
      intro: this.toNewRule(this.readStringField(obj, 'ruleIntroduce')),
      kind: this.toNewRule(this.readStringField(obj, 'ruleBookKind')),
      coverUrl: this.toNewRule(this.readStringField(obj, 'ruleCoverUrl')),
      lastChapter: this.toNewRule(this.readStringField(obj, 'ruleBookLastChapter')),
      tocUrl: this.toNewRule(this.readStringField(obj, 'ruleChapterUrl'))
    };
    return this.hasBookInfoRuleContent(rule) ? rule : undefined;
  }

  private parseOldTocRule(obj: ESObject): LegadoTocRule | undefined {
    const rule: LegadoTocRule = {
      chapterList: this.toNewRule(this.readStringField(obj, 'ruleChapterList')),
      chapterName: this.toNewRule(this.readStringField(obj, 'ruleChapterName')),
      chapterUrl: this.toNewRule(this.readStringField(obj, 'ruleContentUrl')),
      nextTocUrl: this.toNewRule(this.readStringField(obj, 'ruleChapterUrlNext'))
    };
    return this.hasTocRuleContent(rule) ? rule : undefined;
  }

  private parseOldContentRule(obj: ESObject): LegadoContentRule | undefined {
    let content = this.toNewRule(this.readStringField(obj, 'ruleBookContent'));
    if (content !== undefined && content.startsWith('$') && !content.startsWith('$.')) {
      content = content.substring(1);
    }
    const rule: LegadoContentRule = {
      content: content,
      replaceRegex: this.toNewRule(this.readStringField(obj, 'ruleBookContentReplace')),
      nextContentUrl: this.toNewRule(this.readStringField(obj, 'ruleContentUrlNext'))
    };
    return this.hasContentRuleContent(rule) ? rule : undefined;
  }

  private mergeSearchRule(primary: LegadoSearchRule | undefined, fallback: LegadoSearchRule | undefined):
    LegadoSearchRule | undefined {
    if (!primary) {
      return fallback;
    }
    if (!fallback) {
      return primary;
    }
    return {
      checkKeyWord: primary.checkKeyWord,
      bookList: this.preferString(primary.bookList, fallback.bookList),
      name: this.preferString(primary.name, fallback.name),
      author: this.preferString(primary.author, fallback.author),
      intro: this.preferString(primary.intro, fallback.intro),
      kind: this.preferString(primary.kind, fallback.kind),
      lastChapter: this.preferString(primary.lastChapter, fallback.lastChapter),
      updateTime: primary.updateTime,
      bookUrl: this.preferString(primary.bookUrl, fallback.bookUrl),
      coverUrl: this.preferString(primary.coverUrl, fallback.coverUrl),
      wordCount: primary.wordCount
    };
  }

  private mergeExploreRule(primary: LegadoExploreRule | undefined, fallback: LegadoExploreRule | undefined):
    LegadoExploreRule | undefined {
    if (!primary) {
      return fallback;
    }
    if (!fallback) {
      return primary;
    }
    return {
      bookList: this.preferString(primary.bookList, fallback.bookList),
      name: this.preferString(primary.name, fallback.name),
      author: this.preferString(primary.author, fallback.author),
      intro: this.preferString(primary.intro, fallback.intro),
      kind: this.preferString(primary.kind, fallback.kind),
      lastChapter: this.preferString(primary.lastChapter, fallback.lastChapter),
      updateTime: primary.updateTime,
      bookUrl: this.preferString(primary.bookUrl, fallback.bookUrl),
      coverUrl: this.preferString(primary.coverUrl, fallback.coverUrl),
      wordCount: primary.wordCount
    };
  }

  private mergeBookInfoRule(primary: LegadoBookInfoRule | undefined, fallback: LegadoBookInfoRule | undefined):
    LegadoBookInfoRule | undefined {
    if (!primary) {
      return fallback;
    }
    if (!fallback) {
      return primary;
    }
    return {
      init: this.preferString(primary.init, fallback.init),
      name: this.preferString(primary.name, fallback.name),
      author: this.preferString(primary.author, fallback.author),
      intro: this.preferString(primary.intro, fallback.intro),
      kind: this.preferString(primary.kind, fallback.kind),
      lastChapter: this.preferString(primary.lastChapter, fallback.lastChapter),
      updateTime: primary.updateTime,
      coverUrl: this.preferString(primary.coverUrl, fallback.coverUrl),
      tocUrl: this.preferString(primary.tocUrl, fallback.tocUrl),
      wordCount: primary.wordCount,
      canReName: primary.canReName,
      downloadUrls: primary.downloadUrls
    };
  }

  private mergeTocRule(primary: LegadoTocRule | undefined, fallback: LegadoTocRule | undefined):
    LegadoTocRule | undefined {
    if (!primary) {
      return fallback;
    }
    if (!fallback) {
      return primary;
    }
    return {
      preUpdateJs: primary.preUpdateJs,
      chapterList: this.preferString(primary.chapterList, fallback.chapterList),
      chapterName: this.preferString(primary.chapterName, fallback.chapterName),
      chapterUrl: this.preferString(primary.chapterUrl, fallback.chapterUrl),
      formatJs: primary.formatJs,
      isVolume: primary.isVolume,
      isVip: primary.isVip,
      isPay: primary.isPay,
      updateTime: primary.updateTime,
      nextTocUrl: this.preferString(primary.nextTocUrl, fallback.nextTocUrl)
    };
  }

  private mergeContentRule(primary: LegadoContentRule | undefined, fallback: LegadoContentRule | undefined):
    LegadoContentRule | undefined {
    if (!primary) {
      return fallback;
    }
    if (!fallback) {
      return primary;
    }
    return {
      content: this.preferString(primary.content, fallback.content),
      title: primary.title,
      nextContentUrl: this.preferString(primary.nextContentUrl, fallback.nextContentUrl),
      webJs: primary.webJs,
      sourceRegex: primary.sourceRegex,
      replaceRegex: this.preferString(primary.replaceRegex, fallback.replaceRegex),
      imageStyle: primary.imageStyle,
      imageDecode: primary.imageDecode,
      payAction: primary.payAction
    };
  }

  private hasSearchRuleContent(rule: LegadoSearchRule): boolean {
    return !!(rule.checkKeyWord || rule.bookList || rule.name || rule.author || rule.intro || rule.kind ||
      rule.lastChapter || rule.updateTime || rule.bookUrl || rule.coverUrl || rule.wordCount);
  }

  private hasExploreRuleContent(rule: LegadoExploreRule): boolean {
    return !!(rule.bookList || rule.name || rule.author || rule.intro || rule.kind || rule.lastChapter ||
      rule.updateTime || rule.bookUrl || rule.coverUrl || rule.wordCount);
  }

  private hasBookInfoRuleContent(rule: LegadoBookInfoRule): boolean {
    return !!(rule.init || rule.name || rule.author || rule.intro || rule.kind || rule.lastChapter ||
      rule.updateTime || rule.coverUrl || rule.tocUrl || rule.wordCount || rule.canReName || rule.downloadUrls);
  }

  private hasTocRuleContent(rule: LegadoTocRule): boolean {
    return !!(rule.preUpdateJs || rule.chapterList || rule.chapterName || rule.chapterUrl || rule.formatJs ||
      rule.isVolume || rule.isVip || rule.isPay || rule.updateTime || rule.nextTocUrl);
  }

  private hasContentRuleContent(rule: LegadoContentRule): boolean {
    return !!(rule.content || rule.title || rule.nextContentUrl || rule.webJs || rule.sourceRegex ||
      rule.replaceRegex || rule.imageStyle || rule.imageDecode || rule.payAction);
  }

  private toNewRule(oldRule: string): string | undefined {
    if (oldRule.trim().length <= 0) {
      return undefined;
    }
    let newRule = oldRule.trim();
    let reverse = false;
    let allInOne = false;
    if (newRule.startsWith('-')) {
      reverse = true;
      newRule = newRule.substring(1);
    }
    if (newRule.startsWith('+')) {
      allInOne = true;
      newRule = newRule.substring(1);
    }

    const lowerRule = newRule.toLowerCase();
    const shouldAdaptDefaultRule = !lowerRule.startsWith('@css:') &&
      !lowerRule.startsWith('@xpath:') &&
      !newRule.startsWith('//') &&
      !newRule.startsWith('##') &&
      !newRule.startsWith(':') &&
      !lowerRule.includes('@js:') &&
      !lowerRule.includes('<js>');

    if (shouldAdaptDefaultRule) {
      if (newRule.includes('#') && !newRule.includes('##')) {
        newRule = newRule.replace(/#/g, '##');
      }
      if (newRule.includes('|') && !newRule.includes('||')) {
        if (newRule.includes('##')) {
          const parts = newRule.split('##');
          if (parts.length > 0 && parts[0].includes('|')) {
            let rebuilt = parts[0].replace(/\|/g, '||');
            for (let i = 1; i < parts.length; i++) {
              rebuilt += `##${parts[i]}`;
            }
            newRule = rebuilt;
          }
        } else {
          newRule = newRule.replace(/\|/g, '||');
        }
      }
      if (newRule.includes('&') && !newRule.includes('&&') && !lowerRule.includes('http') && !newRule.startsWith('/')) {
        newRule = newRule.replace(/&/g, '&&');
      }
    }

    if (allInOne) {
      newRule = `+${newRule}`;
    }
    if (reverse) {
      newRule = `-${newRule}`;
    }
    return newRule;
  }

  private toNewUrls(oldUrls: string): string | undefined {
    const trimmed = oldUrls.trim();
    if (trimmed.length <= 0) {
      return undefined;
    }
    const lower = trimmed.toLowerCase();
    if (lower.startsWith('@js:') || lower.startsWith('<js>')) {
      return trimmed;
    }
    if (!trimmed.includes('\n') && !trimmed.includes('&&')) {
      return this.toNewUrl(trimmed);
    }
    const segments = trimmed.split(/(?:&&|\r?\n)+/);
    const result: string[] = [];
    for (let i = 0; i < segments.length; i++) {
      const converted = this.toNewUrl(segments[i].trim());
      if (converted !== undefined && converted.length > 0) {
        result.push(converted.replace(/\n\s*/g, ''));
      }
    }
    return result.length > 0 ? result.join('\n') : undefined;
  }

  private toNewUrl(oldUrl: string): string | undefined {
    const trimmed = oldUrl.trim();
    if (trimmed.length <= 0) {
      return undefined;
    }
    let url = trimmed;
    if (url.toLowerCase().startsWith('<js>')) {
      return url.replace(/=searchKey/g, '={{key}}').replace(/=searchPage/g, '={{page}}');
    }

    const option: LegadoOldUrlOption = {};
    const headerMatch = url.match(/@Header:\{.+?\}/i);
    if (headerMatch && headerMatch.index !== undefined) {
      const headerText = headerMatch[0].substring(8);
      const headerRecord = this.parseOldHeaderText(headerText);
      if (headerRecord !== undefined) {
        option.headers = headerRecord;
      }
      url = url.substring(0, headerMatch.index) +
        url.substring(headerMatch.index + headerMatch[0].length);
    }

    const charsetSplitIndex = url.indexOf('|');
    if (charsetSplitIndex >= 0) {
      const charsetPart = url.substring(charsetSplitIndex + 1);
      url = url.substring(0, charsetSplitIndex);
      const equalIndex = charsetPart.indexOf('=');
      if (equalIndex >= 0) {
        const charset = charsetPart.substring(equalIndex + 1).trim();
        if (charset.length > 0) {
          option.charset = charset;
        }
      }
    }

    const jsList: string[] = [];
    url = this.extractOldUrlJsBlocks(url, jsList);
    url = url.replace(/\{/g, '<').replace(/\}/g, '>');
    url = url.replace(/searchKey/g, '{{key}}');
    url = url.replace(/<searchPage([-+]1)>/g, '{{page$1}}')
      .replace(/searchPage([-+]1)/g, '{{page$1}}')
      .replace(/searchPage/g, '{{page}}');
    for (let i = 0; i < jsList.length; i++) {
      const convertedJs = jsList[i].replace(/searchKey/g, 'key').replace(/searchPage/g, 'page');
      url = url.replace(this.buildOldUrlJsPlaceholder(i), convertedJs);
    }

    const postSplitIndex = url.indexOf('@');
    if (postSplitIndex >= 0) {
      option.method = 'POST';
      option.body = url.substring(postSplitIndex + 1);
      url = url.substring(0, postSplitIndex);
    }

    if (this.hasOldUrlOptionContent(option)) {
      url += `,${SafeUtils.stringifyJson(option, '{}')}`;
    }
    return url;
  }

  private extractOldUrlJsBlocks(url: string, jsList: string[]): string {
    let result = url;
    const jsPattern = /\{\{.+?\}\}/i;
    let match = result.match(jsPattern);
    while (match && match.index !== undefined) {
      jsList.push(match[0]);
      const placeholder = this.buildOldUrlJsPlaceholder(jsList.length - 1);
      result = result.substring(0, match.index) +
        placeholder +
        result.substring(match.index + match[0].length);
      match = result.match(jsPattern);
    }
    return result;
  }

  private buildOldUrlJsPlaceholder(index: number): string {
    return `__LEGADO_OLD_JS_${index}__`;
  }

  private hasOldUrlOptionContent(option: LegadoOldUrlOption): boolean {
    return option.method !== undefined ||
      option.charset !== undefined ||
      option.headers !== undefined ||
      option.body !== undefined;
  }

  private parseOldHeaderText(headerText: string): Record<string, string> | undefined {
    const trimmed = headerText.trim();
    if (trimmed.length <= 0) {
      return undefined;
    }
    const strictParsed = this.tryParseOldHeaderRecord(trimmed);
    if (strictParsed !== undefined) {
      return strictParsed;
    }
    const fixedHeader = trimmed
      .replace(/([{,]\s*)([a-zA-Z_$][a-zA-Z0-9_$-]*)\s*:/g, '$1"$2":')
      .replace(/([{,]\s*)'([^']+)'\s*:/g, '$1"$2":')
      .replace(/:\s*'([^'\\]*(?:\\.[^'\\]*)*)'/g, (match: string, value: string): string => {
        const escapedValue = value.replace(/"/g, '\\"');
        return `:"${escapedValue}"`;
      });
    const fixedParsed = this.tryParseOldHeaderRecord(fixedHeader);
    if (fixedParsed !== undefined) {
      return fixedParsed;
    }
    return this.parseOldHeaderPairs(trimmed);
  }

  private tryParseOldHeaderRecord(headerJson: string): Record<string, string> | undefined {
    try {
      const parsed = SafeUtils.parseObj<Record<string, Object>>(headerJson);
      if (parsed === null || parsed === undefined || typeof parsed !== 'object' || Array.isArray(parsed)) {
        return undefined;
      }
      const keys = Object.keys(parsed);
      if (keys.length <= 0) {
        return undefined;
      }
      const headers: Record<string, string> = {};
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i].trim();
        const value = parsed[key];
        if (key.length > 0 && value !== undefined && value !== null) {
          headers[key] = String(value);
        }
      }
      return Object.keys(headers).length > 0 ? headers : undefined;
    } catch (_error) {
      return undefined;
    }
  }

  private parseOldHeaderPairs(headerText: string): Record<string, string> | undefined {
    let body = headerText.trim();
    if (body.startsWith('{') && body.endsWith('}')) {
      body = body.substring(1, body.length - 1);
    }
    const headers: Record<string, string> = {};
    const pairs = body.split(',');
    for (let i = 0; i < pairs.length; i++) {
      const pair = pairs[i].trim();
      const splitIndex = pair.indexOf(':');
      if (splitIndex <= 0) {
        continue;
      }
      const key = this.trimHeaderToken(pair.substring(0, splitIndex));
      const value = this.trimHeaderToken(pair.substring(splitIndex + 1));
      if (key.length > 0 && value.length > 0) {
        headers[key] = value;
      }
    }
    return Object.keys(headers).length > 0 ? headers : undefined;
  }

  private trimHeaderToken(value: string): string {
    let result = value.trim();
    if (result.length >= 2) {
      const first = result.charAt(0);
      const last = result.charAt(result.length - 1);
      if ((first === '"' && last === '"') || (first === '\'' && last === '\'')) {
        result = result.substring(1, result.length - 1).trim();
      }
    }
    return result;
  }

  private uaToHeader(userAgent: string): string | undefined {
    const trimmed = userAgent.trim();
    if (trimmed.length <= 0) {
      return undefined;
    }
    const header: Record<string, string> = {};
    header['User-Agent'] = trimmed;
    return SafeUtils.stringifyJson(header, '');
  }

  /**
   * 解析书源类型
   */
  private parseBookSourceType(type: ESObject): number {
    if (typeof type === 'number') {
      if (Number.isFinite(type)) {
        return type;
      }
      return LegadoBookSourceType.TEXT;
    }
    if (typeof type === 'string') {
      const normalized = type.trim().toLowerCase();
      switch (normalized) {
        case '0':
        case 'default':
        case 'text':
        case 'book':
        case 'novel':
          return LegadoBookSourceType.TEXT;
        case '1':
        case 'audio':
        case 'tts':
          return LegadoBookSourceType.AUDIO;
        case '2':
        case 'image':
        case 'manga':
        case 'comic':
          return LegadoBookSourceType.IMAGE;
        case '3':
        case 'file':
        case 'download':
          return LegadoBookSourceType.FILE;
        default:
          return LegadoBookSourceType.TEXT;
      }
    }
    return LegadoBookSourceType.TEXT;
  }

  private parseBooleanField(value: ESObject, fallback: boolean): boolean {
    if (typeof value === 'boolean') {
      return value;
    }
    if (typeof value === 'number') {
      return value !== 0;
    }
    if (typeof value === 'string') {
      const normalized = value.trim().toLowerCase();
      if (normalized === 'true' || normalized === '1' || normalized === 'yes' || normalized === 'y') {
        return true;
      }
      if (normalized === 'false' || normalized === '0' || normalized === 'no' || normalized === 'n') {
        return false;
      }
    }
    return fallback;
  }

  private parseNumberField(value: ESObject, fallback: number): number {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = Number(value.trim());
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
    return fallback;
  }

  private parseRuleObject(value: ESObject): ESObject {
    if (value === null || value === undefined) {
      return null;
    }
    if (typeof value === 'string') {
      const trimmed = value.trim();
      if (trimmed.length === 0) {
        return null;
      }
      try {
        const parsed = SafeUtils.parseObj<Record<string, Object>>(trimmed);
        if (parsed !== null && parsed !== undefined && typeof parsed === 'object' && !Array.isArray(parsed)) {
          return parsed as ESObject;
        }
      } catch (_error) {
      }
      return null;
    }
    if (typeof value === 'object' && !Array.isArray(value)) {
      return value;
    }
    return null;
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

  private parseReviewRule(obj: ESObject): LegadoReviewRule | undefined {
    if (!obj) {
      return undefined;
    }

    return {
      reviewList: obj.reviewList ? String(obj.reviewList) : undefined,
      content: obj.content ? String(obj.content) : undefined,
      author: obj.author ? String(obj.author) : undefined,
      time: obj.time ? String(obj.time) : undefined
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

    const ruleStr = exploreUrl.trim();

    // Legado uses its default Gson instance for Explore kinds. That parser
    // accepts literal control characters inside string values, while ArkTS
    // JSON.parse is strict. Normalize only those characters before parsing so
    // URL options with formatted request bodies retain their exact semantics.
    if (ruleStr.startsWith('[')) {
      const parsedArray = this.parseExploreKindsJson(ruleStr);
      for (let i = 0; i < parsedArray.length; i++) {
        const kind = this.parseExploreKindObject(parsedArray[i]);
        if (kind) {
          kinds.push(kind);
        }
      }
      return kinds;
    }

    // Legado 原版按 (&&|\n)+ 分割，URL 可省略
    const lines = ruleStr.split(/(?:&&|\n)+/);
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) {
        continue;
      }

      // 格式: 分类名::URL
      const parts = trimmed.split('::');
      const title = parts[0].trim();
      if (title.length === 0) {
        continue;
      }
      const url = parts.length >= 2 ? parts.slice(1).join('::').trim() : '';
      kinds.push({
        title: title,
        url: url
      });
    }

    return kinds;
  }

  private parseExploreKindsJson(ruleStr: string): Record<string, Object>[] {
    const normalizedJson = this.normalizeExploreKindsJson(ruleStr);
    try {
      const parsed: Object = JSON.parse(normalizedJson) as Object;
      if (!Array.isArray(parsed)) {
        logger.error(TAG, `LEGADO_EXPLORE_KINDS_JSON_NOT_ARRAY inputLength=${ruleStr.length};normalizedLength=${normalizedJson.length}`);
        throw new Error('LEGADO_EXPLORE_KINDS_JSON_NOT_ARRAY');
      }
      return parsed as Record<string, Object>[];
    } catch (error) {
      const message = String(error);
      if (message.includes('LEGADO_EXPLORE_KINDS_JSON_NOT_ARRAY')) {
        throw new Error('LEGADO_EXPLORE_KINDS_JSON_NOT_ARRAY');
      }
      logger.error(TAG, `LEGADO_EXPLORE_KINDS_JSON_PARSE_FAILED inputLength=${ruleStr.length};normalizedLength=${normalizedJson.length};reason=${message}`);
      throw new Error('LEGADO_EXPLORE_KINDS_JSON_PARSE_FAILED');
    }
  }

  /**
   * Converts literal JSON control characters only while inside a quoted value.
   * Pretty-print whitespace between object members stays untouched.
   */
  private normalizeExploreKindsJson(value: string): string {
    let normalized = '';
    let inString = false;
    let escaping = false;
    for (let index = 0; index < value.length; index++) {
      const character = value.charAt(index);
      if (!inString) {
        normalized += character;
        if (character === '"') {
          inString = true;
        }
        continue;
      }

      if (escaping) {
        normalized += character;
        escaping = false;
        continue;
      }
      if (character === '\\') {
        normalized += character;
        escaping = true;
        continue;
      }
      if (character === '"') {
        normalized += character;
        inString = false;
        continue;
      }
      const code = character.charCodeAt(0);
      if (code >= 0x20) {
        normalized += character;
        continue;
      }
      if (character === '\n') {
        normalized += '\\n';
      } else if (character === '\r') {
        normalized += '\\r';
      } else if (character === '\t') {
        normalized += '\\t';
      } else if (character === '\b') {
        normalized += '\\b';
      } else if (character === '\f') {
        normalized += '\\f';
      } else {
        const hex = code.toString(16);
        normalized += `\\u${'0000'.substring(0, 4 - hex.length)}${hex}`;
      }
    }
    return normalized;
  }

  private parseExploreKindObject(item: Record<string, Object>): LegadoExploreKind | null {
    const titleValue = this.pickStringField(item, ['title', 'name']);
    if (titleValue.length === 0) {
      return null;
    }

    const kind: LegadoExploreKind = {
      title: titleValue,
      url: this.pickStringField(item, ['url'])
    };

    const styleValue = item['style'];
    if (styleValue && typeof styleValue === 'object' && !Array.isArray(styleValue)) {
      kind.style = styleValue as LegadoExploreKindStyle;
    }

    return kind;
  }

  private pickStringField(item: Record<string, Object>, fieldNames: string[]): string {
    for (let i = 0; i < fieldNames.length; i++) {
      const value = item[fieldNames[i]];
      if (value === undefined || value === null) {
        continue;
      }
      const text = String(value).trim();
      if (text.length > 0) {
        return text;
      }
    }
    return '';
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
