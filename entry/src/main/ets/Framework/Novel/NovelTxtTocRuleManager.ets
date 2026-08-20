import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * TXT目录规则管理器
 * 用于本地TXT文件的章节识别
 * 参照Legado实现
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelTxtTocRuleManager.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { getNovelDataManager } from './NovelDataManager';
import { DEFAULT_TXT_TOC_RULES as SETTINGS_TXT_TOC_RULES, TxtTocRule as SettingsTxtTocRule } from 'manxia_core/src/main/ets/Framework/Novel/NovelSettingsManager';

const TAG = 'NovelTxtTocRuleManager';
const ENHANCED_BUILT_IN_RULE_VERSION_KEY = 'novel_txt_toc_enhanced_builtin_rules_version';
const ENHANCED_BUILT_IN_RULE_VERSION = '2026-06-12_multilingual_comic_photo_v2';

/**
 * TXT目录规则
 */
export interface TxtTocRule {
  id: string;
  name: string;
  rule: string;           // 正则表达式规则
  example: string;        // 示例文本
  serialNumber: number;   // 排序序号
  enabled: boolean;       // 是否启用
  createTime: number;
  updateTime: number;
}

/**
 * 添加TXT目录规则参数
 */
export interface AddTxtTocRuleParams {
  name: string;
  rule: string;
  example?: string;
  serialNumber?: number;
  enabled?: boolean;
}

/**
 * TXT目录规则导入结果
 */
export interface TxtTocRuleImportResult {
  total: number;
  success: number;
  failed: number;
  errors: string[];
}

/**
 * 获取默认TXT目录规则
 * 使用NovelSettingsManager中更完整的规则集
 */
function getDefaultTxtTocRules(): AddTxtTocRuleParams[] {
  // 将NovelSettingsManager中的规则转换为本地格式
  return SETTINGS_TXT_TOC_RULES.map((rule: SettingsTxtTocRule, index: number): AddTxtTocRuleParams => {
    const params: AddTxtTocRuleParams = {
      name: rule.name,
      rule: rule.pattern,
      example: rule.example,
      serialNumber: index,
      enabled: rule.enabled
    };
    return params;
  });
}

/**
 * 默认TXT目录规则（使用NovelSettingsManager中的完整规则集）
 */
export const DEFAULT_TXT_TOC_RULES: AddTxtTocRuleParams[] = getDefaultTxtTocRules();

/**
 * TXT目录规则管理器
 */
export class NovelTxtTocRuleManager {
  private static instance: NovelTxtTocRuleManager | null = null;
  private rules: Map<string, TxtTocRule> = new Map();
  private initialized: boolean = false;
  private compiledPatterns: Map<string, RegExp> = new Map();

  private constructor() {}

  static getInstance(): NovelTxtTocRuleManager {
    if (!NovelTxtTocRuleManager.instance) {
      NovelTxtTocRuleManager.instance = new NovelTxtTocRuleManager();
    }
    return NovelTxtTocRuleManager.instance;
  }

  /**
   * 初始化
   */
  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      await this.loadRulesFromStorage();
      
      // 如果没有规则，导入默认规则
      if (this.rules.size === 0) {
        await this.importDefaultRules();
        await this.markEnhancedBuiltInRulesSynced();
      } else {
        await this.syncEnhancedBuiltInRules();
      }
      
      this.compilePatterns();
      this.initialized = true;
      logger.info(TAG, `TXT目录规则管理器初始化完成，共 ${this.rules.size} 条规则`);
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
    }
  }

  /**
   * 导入默认规则
   */
  private async importDefaultRules(): Promise<void> {
    for (let i = 0; i < DEFAULT_TXT_TOC_RULES.length; i++) {
      const rule = DEFAULT_TXT_TOC_RULES[i];
      const params: AddTxtTocRuleParams = {
        name: rule.name,
        rule: rule.rule,
        example: rule.example,
        serialNumber: i,
        enabled: rule.enabled !== false
      };
      await this.addRule(params);
    }
    logger.info(TAG, `已导入 ${DEFAULT_TXT_TOC_RULES.length} 条默认TXT目录规则`);
  }

  private async syncEnhancedBuiltInRules(): Promise<void> {
    const settingsManager = SettingsManager.getInstance();
    const syncedVersion = settingsManager.getString(ENHANCED_BUILT_IN_RULE_VERSION_KEY, '');
    if (syncedVersion === ENHANCED_BUILT_IN_RULE_VERSION) {
      return;
    }

    let nextSerialNumber = this.getNextSerialNumber();
    let addedCount = 0;
    for (let i = 0; i < DEFAULT_TXT_TOC_RULES.length; i++) {
      const rule = DEFAULT_TXT_TOC_RULES[i];
      if (!this.isEnhancedBuiltInRule(rule) || this.hasRuleWithName(rule.name)) {
        continue;
      }
      const params: AddTxtTocRuleParams = {
        name: rule.name,
        rule: rule.rule,
        example: rule.example,
        serialNumber: nextSerialNumber,
        enabled: rule.enabled !== false
      };
      await this.addRule(params);
      nextSerialNumber++;
      addedCount++;
    }

    await this.markEnhancedBuiltInRulesSynced();
    logger.info(TAG, `增强内置TXT目录规则同步完成: version=${ENHANCED_BUILT_IN_RULE_VERSION}, added=${addedCount}`);
  }

  private async markEnhancedBuiltInRulesSynced(): Promise<void> {
    const settingsManager = SettingsManager.getInstance();
    await settingsManager.setString(ENHANCED_BUILT_IN_RULE_VERSION_KEY, ENHANCED_BUILT_IN_RULE_VERSION);
  }

  private isEnhancedBuiltInRule(rule: AddTxtTocRuleParams): boolean {
    return rule.name.indexOf('多语言目录') === 0 || rule.name.indexOf('漫画写真目录') === 0;
  }

  private hasRuleWithName(name: string): boolean {
    for (const rule of this.rules.values()) {
      if (rule.name === name) {
        return true;
      }
    }
    return false;
  }

  private getNextSerialNumber(): number {
    let maxSerialNumber = -1;
    for (const rule of this.rules.values()) {
      if (rule.serialNumber > maxSerialNumber) {
        maxSerialNumber = rule.serialNumber;
      }
    }
    return maxSerialNumber + 1;
  }

  /**
   * 从数据库加载规则
   */
  private async loadRulesFromStorage(): Promise<void> {
    try {
      const dataManager = getNovelDataManager();
      const store = dataManager.getStore();
      const rs = await store.querySql(
        'SELECT * FROM novel_txt_toc_rule ORDER BY serialNumber ASC'
      );
      
      this.rules.clear();
      if (rs.goToFirstRow()) {
        do {
          const rule: TxtTocRule = {
            id: rs.getString(rs.getColumnIndex('id')),
            name: rs.getString(rs.getColumnIndex('name')),
            rule: rs.getString(rs.getColumnIndex('rule')),
            example: rs.getString(rs.getColumnIndex('example')) || '',
            serialNumber: rs.getLong(rs.getColumnIndex('serialNumber')),
            enabled: rs.getLong(rs.getColumnIndex('enabled')) === 1,
            createTime: rs.getLong(rs.getColumnIndex('createTime')),
            updateTime: rs.getLong(rs.getColumnIndex('updateTime'))
          };
          this.rules.set(rule.id, rule);
        } while (rs.goToNextRow());
      }
      rs.close();
      logger.info(TAG, `从数据库加载了 ${this.rules.size} 条TXT目录规则`);
    } catch (error) {
      logger.warn(TAG, `加载TXT目录规则失败: ${String(error)}`);
    }
  }

  /**
   * 编译正则表达式
   */
  private compilePatterns(): void {
    this.compiledPatterns.clear();
    for (const rule of this.getEnabledRules()) {
      try {
        const pattern = new RegExp(rule.rule, 'm');
        this.compiledPatterns.set(rule.id, pattern);
      } catch (error) {
        logger.warn(TAG, `编译正则失败 [${rule.name}]: ${String(error)}`);
      }
    }
  }

  /**
   * 保存单个规则到数据库
   */
  private async saveRuleToDb(rule: TxtTocRule): Promise<void> {
    try {
      const dataManager = getNovelDataManager();
      const store = dataManager.getStore();
      
      await store.executeSql('DELETE FROM novel_txt_toc_rule WHERE id = ?', [rule.id]);
      
      const sql = `INSERT INTO novel_txt_toc_rule 
        (id, name, rule, example, serialNumber, enabled, createTime, updateTime)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)`;
      
      await store.executeSql(sql, [
        rule.id,
        rule.name,
        rule.rule,
        rule.example,
        rule.serialNumber,
        rule.enabled ? 1 : 0,
        rule.createTime,
        rule.updateTime
      ]);
    } catch (error) {
      logger.error(TAG, `保存TXT目录规则失败: ${String(error)}`);
    }
  }

  /**
   * 从数据库删除规则
   */
  private async deleteRuleFromDb(id: string): Promise<void> {
    try {
      const dataManager = getNovelDataManager();
      const store = dataManager.getStore();
      await store.executeSql('DELETE FROM novel_txt_toc_rule WHERE id = ?', [id]);
    } catch (error) {
      logger.error(TAG, `删除TXT目录规则失败: ${String(error)}`);
    }
  }

  /**
   * 生成ID
   */
  private generateId(): string {
    return `txt_toc_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }

  /**
   * 添加规则
   */
  async addRule(params: AddTxtTocRuleParams): Promise<TxtTocRule> {
    const now = Date.now();
    const newRule: TxtTocRule = {
      id: this.generateId(),
      name: params.name,
      rule: params.rule,
      example: params.example || '',
      serialNumber: params.serialNumber !== undefined ? params.serialNumber : this.rules.size,
      enabled: params.enabled !== false,
      createTime: now,
      updateTime: now
    };

    this.rules.set(newRule.id, newRule);
    await this.saveRuleToDb(newRule);
    this.compilePatterns();
    
    logger.info(TAG, `添加TXT目录规则: ${newRule.name}`);
    return newRule;
  }

  /**
   * 更新规则
   */
  async updateRule(id: string, updates: Partial<AddTxtTocRuleParams>): Promise<boolean> {
    const rule = this.rules.get(id);
    if (!rule) {
      return false;
    }

    const updatedRule: TxtTocRule = {
      id: rule.id,
      name: updates.name !== undefined ? updates.name : rule.name,
      rule: updates.rule !== undefined ? updates.rule : rule.rule,
      example: updates.example !== undefined ? updates.example : rule.example,
      serialNumber: updates.serialNumber !== undefined ? updates.serialNumber : rule.serialNumber,
      enabled: updates.enabled !== undefined ? updates.enabled : rule.enabled,
      createTime: rule.createTime,
      updateTime: Date.now()
    };

    this.rules.set(id, updatedRule);
    await this.saveRuleToDb(updatedRule);
    this.compilePatterns();
    
    logger.info(TAG, `更新TXT目录规则: ${updatedRule.name}`);
    return true;
  }

  /**
   * 删除规则
   */
  async deleteRule(id: string): Promise<boolean> {
    const deleted = this.rules.delete(id);
    if (deleted) {
      await this.deleteRuleFromDb(id);
      this.compiledPatterns.delete(id);
      logger.info(TAG, `删除TXT目录规则: ${id}`);
    }
    return deleted;
  }

  /**
   * 设置规则启用状态
   */
  async setRuleEnabled(id: string, enabled: boolean): Promise<boolean> {
    return this.updateRule(id, { enabled });
  }

  /**
   * 获取所有规则
   */
  getAllRules(): TxtTocRule[] {
    return Array.from(this.rules.values()).sort((a, b) => a.serialNumber - b.serialNumber);
  }

  /**
   * 获取启用的规则
   */
  getEnabledRules(): TxtTocRule[] {
    return this.getAllRules().filter(rule => rule.enabled);
  }

  /**
   * 获取规则
   */
  getRule(id: string): TxtTocRule | null {
    return this.rules.get(id) || null;
  }

  /**
   * 匹配文本，返回匹配的规则
   */
  matchText(text: string): TxtTocRule | null {
    for (const rule of this.getEnabledRules()) {
      const pattern = this.compiledPatterns.get(rule.id);
      if (pattern && pattern.test(text)) {
        return rule;
      }
    }
    return null;
  }

  /**
   * 获取匹配的正则表达式
   * 用于TXT文件章节解析
   */
  getMatchingPattern(sampleText: string): RegExp | null {
    for (const rule of this.getEnabledRules()) {
      const pattern = this.compiledPatterns.get(rule.id);
      if (pattern && pattern.test(sampleText)) {
        logger.info(TAG, `匹配到TXT目录规则: ${rule.name}`);
        return pattern;
      }
    }
    return null;
  }

  /**
   * 获取合并的正则表达式（所有启用规则的组合）
   */
  getCombinedPattern(): RegExp | null {
    const enabledRules = this.getEnabledRules();
    if (enabledRules.length === 0) {
      return null;
    }

    const patterns = enabledRules.map(rule => `(${rule.rule})`);
    try {
      return new RegExp(patterns.join('|'), 'gm');
    } catch (error) {
      logger.error(TAG, `合并正则表达式失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 使用指定规则解析章节
   * @param content 文本内容
   * @param ruleId 规则ID，空字符串表示使用所有启用规则
   */
  parseChaptersByRuleId(content: string, ruleId: string): TxtChapter[] {
    let pattern: RegExp | null = null;
    
    if (ruleId && ruleId.length > 0) {
      // 使用指定规则 - rules是Map类型，使用get方法
      const rule: TxtTocRule | undefined = this.rules.get(ruleId);
      if (rule) {
        try {
          pattern = new RegExp(rule.rule, 'gm');
          logger.info(TAG, `使用指定规则解析章节: ${rule.name}`);
        } catch (error) {
          logger.error(TAG, `规则正则表达式无效: ${rule.name}, ${String(error)}`);
        }
      }
    }
    
    if (!pattern) {
      // 使用所有启用规则的组合
      pattern = this.getCombinedPattern();
    }
    
    return this.parseChaptersWithPattern(content, pattern);
  }

  /**
   * 解析TXT文本的章节
   */
  parseChapters(content: string): TxtChapter[] {
    const pattern = this.getCombinedPattern();
    return this.parseChaptersWithPattern(content, pattern);
  }

  /**
   * 使用指定正则表达式解析章节
   * 添加安全机制：最大章节数限制和进度日志
   */
  private parseChaptersWithPattern(content: string, pattern: RegExp | null): TxtChapter[] {
    const chapters: TxtChapter[] = [];
    
    // 安全限制：最大章节数量，防止无限循环
    const MAX_CHAPTERS = 10000;
    
    if (!pattern) {
      // 没有规则，按固定长度分割
      return this.splitByLength(content, 10000);
    }

    let match: RegExpExecArray | null;
    let chapterIndex = 0;
    const startTime = Date.now();

    // 重置正则表达式
    pattern.lastIndex = 0;

    while ((match = pattern.exec(content)) !== null) {
      // 安全检查：防止超过最大章节数
      if (chapters.length >= MAX_CHAPTERS) {
        logger.warn(TAG, `章节数量达到上限 ${MAX_CHAPTERS}，停止解析`);
        break;
      }
      
      const chapterStart = match.index;
      const chapterTitle = match[0].trim();

      // 如果不是第一个章节，保存前一个章节
      if (chapterIndex > 0 || chapterStart > 0) {
        if (chapterIndex === 0 && chapterStart > 0) {
          // 第一个章节之前有内容，作为前言
          const preContent = content.substring(0, chapterStart).trim();
          if (preContent.length > 100) {
            chapters.push({
              index: chapterIndex++,
              title: '前言',
              start: 0,
              end: chapterStart
            });
          }
        }
      }

      // 找到下一个章节的位置
      const nextMatch = pattern.exec(content);
      const chapterEnd = nextMatch ? nextMatch.index : content.length;
      
      // 回退正则位置
      if (nextMatch) {
        pattern.lastIndex = nextMatch.index;
      }

      chapters.push({
        index: chapterIndex++,
        title: chapterTitle,
        start: chapterStart,
        end: chapterEnd
      });
      
      // 每1000章输出一次进度日志
      if (chapters.length % 1000 === 0) {
        logger.info(TAG, `章节解析进度: ${chapters.length} 章`);
      }
    }

    // 如果没有找到任何章节，按长度分割
    if (chapters.length === 0) {
      return this.splitByLength(content, 10000);
    }
    
    const elapsed = Date.now() - startTime;
    if (elapsed > 100 || chapters.length > 500) {
      logger.info(TAG, `章节解析完成: ${chapters.length} 章, 耗时 ${elapsed}ms`);
    }

    return chapters;
  }

  /**
   * 按固定长度分割内容
   */
  private splitByLength(content: string, maxLength: number): TxtChapter[] {
    const chapters: TxtChapter[] = [];
    let start = 0;
    let index = 0;

    while (start < content.length) {
      let end = Math.min(start + maxLength, content.length);
      
      // 尝试在段落结束处分割
      if (end < content.length) {
        const lastNewline = content.lastIndexOf('\n', end);
        if (lastNewline > start + maxLength / 2) {
          end = lastNewline + 1;
        }
      }

      chapters.push({
        index: index,
        title: `第${index + 1}节`,
        start: start,
        end: end
      });

      start = end;
      index++;
    }

    return chapters;
  }

  /**
   * 导入规则（从JSON）
   */
  async importFromJSON(jsonStr: string): Promise<TxtTocRuleImportResult> {
    const result: TxtTocRuleImportResult = {
      total: 0,
      success: 0,
      failed: 0,
      errors: []
    };

    try {
      const data: Object = SafeUtils.parseObj(jsonStr);
      const rules: Object[] = Array.isArray(data) ? data as Object[] : [data];
      result.total = rules.length;

      for (let i = 0; i < rules.length; i++) {
        const item = rules[i] as Record<string, Object>;
        try {
          // 验证必要字段
          const itemName = item['name'] as string;
          const itemRule = item['rule'] as string;
          if (!itemName || !itemRule) {
            result.failed++;
            result.errors.push(`规则缺少必要字段`);
            continue;
          }

          // 验证正则表达式
          try {
            new RegExp(itemRule);
          } catch (regexErr) {
            result.failed++;
            result.errors.push(`无效的正则表达式: ${itemRule}`);
            continue;
          }

          const params: AddTxtTocRuleParams = {
            name: itemName,
            rule: itemRule,
            example: (item['example'] as string) || '',
            serialNumber: item['serialNumber'] as number,
            enabled: item['enable'] !== false && item['enabled'] !== false
          };
          await this.addRule(params);
          result.success++;
        } catch (error) {
          result.failed++;
          result.errors.push(`导入规则失败: ${String(error)}`);
        }
      }
    } catch (error) {
      result.errors.push(`解析JSON失败: ${String(error)}`);
    }

    logger.info(TAG, `导入TXT目录规则完成: ${result.success}/${result.total} 成功`);
    return result;
  }

  /**
   * 导出规则为JSON
   */
  exportToJSON(): string {
    const allRules = this.getAllRules();
    const exportData: Object[] = [];
    for (let i = 0; i < allRules.length; i++) {
      const rule = allRules[i];
      const exportRule: Record<string, Object> = new Object() as Record<string, Object>;
      exportRule['name'] = rule.name;
      exportRule['rule'] = rule.rule;
      exportRule['example'] = rule.example;
      exportRule['serialNumber'] = rule.serialNumber;
      exportRule['enable'] = rule.enabled;
      exportData.push(exportRule);
    }
    return JSON.stringify(exportData, null, 2);
  }

  /**
   * 重置为默认规则
   */
  async resetToDefault(): Promise<void> {
    // 删除所有现有规则
    for (const rule of this.getAllRules()) {
      await this.deleteRule(rule.id);
    }
    
    // 导入默认规则
    await this.importDefaultRules();
    await this.markEnhancedBuiltInRulesSynced();
    this.compilePatterns();
    
    logger.info(TAG, '已重置为默认TXT目录规则');
  }
}

/**
 * TXT章节信息
 */
export interface TxtChapter {
  index: number;
  title: string;
  start: number;  // 在文本中的起始位置
  end: number;    // 在文本中的结束位置
}

/**
 * 获取TXT目录规则管理器实例
 */
export function getNovelTxtTocRuleManager(): NovelTxtTocRuleManager {
  return NovelTxtTocRuleManager.getInstance();
}
