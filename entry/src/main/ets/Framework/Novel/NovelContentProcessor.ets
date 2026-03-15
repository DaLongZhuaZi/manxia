/**
 * 小说内容处理器
 * 统一处理网络小说和本地TXT的内容净化
 * 参照Legado的ContentProcessor实现
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelContentProcessor.ets
 */

import { logger } from '../../Utils/Logger';
import { getNovelReplaceRuleManager, ReplaceRule, ReplaceScope } from './NovelReplaceRuleManager';

const TAG = 'NovelContentProcessor';

/**
 * 内容处理配置
 */
export interface ContentProcessConfig {
  useReplace: boolean;
  chineseConvert: number;
  reSegment: boolean;
  includeTitle: boolean;
  paragraphIndent: string;
  sourceId: string | undefined;
  enabledRuleIds?: string[];
}

/**
 * 内容处理结果
 */
export interface ContentProcessResult {
  content: string;
  paragraphs: string[];
  appliedRules: ReplaceRule[];
  titleRemoved: boolean;
}

/**
 * 去除重复标题结果
 */
interface RemoveTitleResult {
  content: string;
  removed: boolean;
}

/**
 * 应用替换规则结果
 */
interface ApplyRulesResult {
  content: string;
  appliedRules: ReplaceRule[];
}

/**
 * 创建默认配置
 */
function createDefaultConfig(): ContentProcessConfig {
  const config: ContentProcessConfig = {
    useReplace: true,
    chineseConvert: 0,
    reSegment: false,
    includeTitle: true,
    paragraphIndent: '　　',
    sourceId: undefined,
    enabledRuleIds: undefined
  };
  return config;
}

/**
 * 合并配置
 */
function mergeConfig(defaultCfg: ContentProcessConfig, customCfg: ContentProcessConfig | null): ContentProcessConfig {
  if (!customCfg) {
    return defaultCfg;
  }
  const result: ContentProcessConfig = {
    useReplace: customCfg.useReplace !== undefined ? customCfg.useReplace : defaultCfg.useReplace,
    chineseConvert: customCfg.chineseConvert !== undefined ? customCfg.chineseConvert : defaultCfg.chineseConvert,
    reSegment: customCfg.reSegment !== undefined ? customCfg.reSegment : defaultCfg.reSegment,
    includeTitle: customCfg.includeTitle !== undefined ? customCfg.includeTitle : defaultCfg.includeTitle,
    paragraphIndent: customCfg.paragraphIndent !== undefined ? customCfg.paragraphIndent : defaultCfg.paragraphIndent,
    sourceId: customCfg.sourceId !== undefined ? customCfg.sourceId : defaultCfg.sourceId,
    enabledRuleIds: customCfg.enabledRuleIds !== undefined ? customCfg.enabledRuleIds : defaultCfg.enabledRuleIds
  };
  return result;
}

/**
 * 小说内容处理器
 */
export class NovelContentProcessor {
  private static instance: NovelContentProcessor | null = null;
  private replaceRuleManager = getNovelReplaceRuleManager();

  private constructor() {}

  static getInstance(): NovelContentProcessor {
    if (!NovelContentProcessor.instance) {
      NovelContentProcessor.instance = new NovelContentProcessor();
    }
    return NovelContentProcessor.instance;
  }

  /**
   * 处理章节内容
   */
  processContent(
    content: string,
    chapterTitle: string,
    bookName: string,
    customConfig: ContentProcessConfig | null = null
  ): ContentProcessResult {
    const defaultCfg = createDefaultConfig();
    const cfg = mergeConfig(defaultCfg, customConfig);
    let mContent = content;
    let titleRemoved = false;
    const appliedRules: ReplaceRule[] = [];

    if (content === 'null' || !content) {
      const emptyResult: ContentProcessResult = {
        content: '',
        paragraphs: [],
        appliedRules: [],
        titleRemoved: false
      };
      return emptyResult;
    }

    // 1. 去除重复标题
    if (chapterTitle) {
      const result = this.removeDuplicateTitle(mContent, chapterTitle, bookName);
      mContent = result.content;
      titleRemoved = result.removed;
    }

    // 2. 重新分段
    if (cfg.reSegment) {
      mContent = this.reSegment(mContent, chapterTitle);
    }

    // 3. 简繁转换
    if (cfg.chineseConvert && cfg.chineseConvert > 0) {
      mContent = this.convertChinese(mContent, cfg.chineseConvert);
    }

    // 4. 应用替换规则
    if (cfg.useReplace) {
      const replaceResult = this.applyReplaceRules(mContent, ReplaceScope.CONTENT, cfg.sourceId, cfg.enabledRuleIds);
      mContent = replaceResult.content;
      for (let i = 0; i < replaceResult.appliedRules.length; i++) {
        appliedRules.push(replaceResult.appliedRules[i]);
      }
    }

    // 5. 重新添加标题
    if (cfg.includeTitle && chapterTitle) {
      let displayTitle = chapterTitle;
      if (cfg.useReplace) {
        const titleResult = this.applyReplaceRules(displayTitle, ReplaceScope.TITLE, cfg.sourceId, cfg.enabledRuleIds);
        displayTitle = titleResult.content;
      }
      mContent = displayTitle + '\n' + mContent;
    }

    // 6. 分段处理
    const paragraphs = this.splitToParagraphs(mContent, cfg.paragraphIndent, cfg.includeTitle);

    const finalResult: ContentProcessResult = {
      content: mContent,
      paragraphs: paragraphs,
      appliedRules: appliedRules,
      titleRemoved: titleRemoved
    };
    return finalResult;
  }

  /**
   * 处理标题
   */
  processTitle(
    title: string,
    sourceId: string | undefined = undefined,
    enabledRuleIds: string[] | undefined = undefined
  ): string {
    let rules = this.replaceRuleManager.getEnabledRules(ReplaceScope.TITLE, sourceId);
    if (enabledRuleIds !== undefined) {
      rules = rules.filter((rule) => enabledRuleIds.indexOf(rule.id) >= 0);
    }
    let result = title;

    for (let i = 0; i < rules.length; i++) {
      const rule = rules[i];
      try {
        if (rule.isRegex) {
          const regex = new RegExp(rule.pattern, 'g');
          result = result.replace(regex, rule.replacement);
        } else {
          result = result.split(rule.pattern).join(rule.replacement);
        }
      } catch (error) {
        logger.warn(TAG, `应用标题替换规则失败 [${rule.name}]: ${String(error)}`);
      }
    }

    return result;
  }

  /**
   * 去除重复标题
   */
  private removeDuplicateTitle(content: string, title: string, bookName: string): RemoveTitleResult {
    try {
      // 转义特殊字符
      const escapedName = this.escapeRegex(bookName);
      const escapedTitle = this.escapeRegex(title).replace(/\s+/g, '\\s*');
      
      // 构建匹配模式：开头可能有空白、标点、书名，然后是章节标题
      const pattern = new RegExp(`^(\\s|\\p{P}|${escapedName})*${escapedTitle}(\\s)*`, 'u');
      const match = content.match(pattern);
      
      if (match) {
        const result: RemoveTitleResult = {
          content: content.substring(match[0].length),
          removed: true
        };
        return result;
      }
    } catch (error) {
      logger.warn(TAG, `去除重复标题失败: ${String(error)}`);
    }

    const defaultResult: RemoveTitleResult = {
      content: content,
      removed: false
    };
    return defaultResult;
  }

  /**
   * 重新分段
   */
  private reSegment(content: string, title: string): string {
    // 移除多余空行
    let result = content.replace(/\n{3,}/g, '\n\n');
    
    // 在句号后添加换行（如果没有）
    result = result.replace(/([。！？」』])\s*(?=[^\n])/g, '$1\n');
    
    return result;
  }

  /**
   * 简繁转换
   */
  private convertChinese(content: string, type: number): string {
    // 简单的简繁转换映射
    if (type === 1) {
      // 繁转简
      const t2sKeys = ['國', '書', '學', '說', '話', '時', '間', '開', '門', '問', '見', '長', '東', '車', '馬'];
      const t2sVals = ['国', '书', '学', '说', '话', '时', '间', '开', '门', '问', '见', '长', '东', '车', '马'];
      for (let i = 0; i < t2sKeys.length; i++) {
        content = content.split(t2sKeys[i]).join(t2sVals[i]);
      }
    } else if (type === 2) {
      // 简转繁
      const s2tKeys = ['国', '书', '学', '说', '话', '时', '间', '开', '门', '问', '见', '长', '东', '车', '马'];
      const s2tVals = ['國', '書', '學', '說', '話', '時', '間', '開', '門', '問', '見', '長', '東', '車', '馬'];
      for (let i = 0; i < s2tKeys.length; i++) {
        content = content.split(s2tKeys[i]).join(s2tVals[i]);
      }
    }
    return content;
  }

  /**
   * 应用替换规则
   */
  private applyReplaceRules(
    content: string, 
    scope: ReplaceScope, 
    sourceId: string | undefined,
    enabledRuleIds: string[] | undefined = undefined
  ): ApplyRulesResult {
    let rules = this.replaceRuleManager.getEnabledRules(scope, sourceId);
    if (enabledRuleIds !== undefined) {
      rules = rules.filter((rule) => enabledRuleIds.indexOf(rule.id) >= 0);
    }
    const appliedRules: ReplaceRule[] = [];
    let result = content;

    for (let i = 0; i < rules.length; i++) {
      const rule = rules[i];
      if (!rule.pattern) {
        continue;
      }

      try {
        let newContent: string;
        if (rule.isRegex) {
          const regex = new RegExp(rule.pattern, 'g');
          newContent = result.replace(regex, rule.replacement);
        } else {
          newContent = result.split(rule.pattern).join(rule.replacement);
        }

        if (newContent !== result) {
          appliedRules.push(rule);
          result = newContent;
        }
      } catch (error) {
        logger.warn(TAG, `应用替换规则失败 [${rule.name}]: ${String(error)}`);
      }
    }

    const applyResult: ApplyRulesResult = {
      content: result,
      appliedRules: appliedRules
    };
    return applyResult;
  }

  /**
   * 分割为段落
   */
  private splitToParagraphs(content: string, indent: string, includeTitle: boolean): string[] {
    const paragraphs: string[] = [];
    const lines = content.split('\n');
    let isFirstLine = true;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();
      if (!trimmed) {
        continue;
      }

      // 第一行（标题）不加缩进
      if (isFirstLine && includeTitle) {
        paragraphs.push(trimmed);
        isFirstLine = false;
      } else {
        paragraphs.push(indent + trimmed);
      }
    }

    return paragraphs;
  }

  /**
   * 转义正则表达式特殊字符
   */
  private escapeRegex(str: string): string {
    return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  /**
   * 快速应用替换规则（不分段）
   */
  quickReplace(
    text: string,
    scope: ReplaceScope = ReplaceScope.CONTENT,
    sourceId: string | undefined = undefined,
    enabledRuleIds: string[] | undefined = undefined
  ): string {
    const result = this.applyReplaceRules(text, scope, sourceId, enabledRuleIds);
    return result.content;
  }

  /**
   * 获取生效的替换规则
   */
  getEffectiveRules(
    scope: ReplaceScope,
    sourceId: string | undefined = undefined,
    enabledRuleIds: string[] | undefined = undefined
  ): ReplaceRule[] {
    let rules = this.replaceRuleManager.getEnabledRules(scope, sourceId);
    if (enabledRuleIds !== undefined) {
      rules = rules.filter((rule) => enabledRuleIds.indexOf(rule.id) >= 0);
    }
    return rules;
  }
}

/**
 * 获取内容处理器实例
 */
export function getNovelContentProcessor(): NovelContentProcessor {
  return NovelContentProcessor.getInstance();
}
