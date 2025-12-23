/**
 * 小说替换净化规则管理器
 * 管理全局替换规则，用于净化正文内容
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelReplaceRuleManager.ets
 */

import { logger } from '../../Utils/Logger';
import { getNovelDataManager } from './NovelDataManager';

const TAG = 'NovelReplaceRuleManager';

/**
 * 替换规则
 */
export interface ReplaceRule {
  id: string;
  name: string;
  pattern: string;
  replacement: string;
  isRegex: boolean;
  scope: ReplaceScope;
  enabled: boolean;
  order: number;
  sourceIds?: string[];
  createTime: number;
  updateTime: number;
}

/**
 * 添加规则参数
 */
export interface AddRuleParams {
  name: string;
  pattern: string;
  replacement: string;
  isRegex: boolean;
  scope: ReplaceScope;
  enabled: boolean;
  order: number;
  sourceIds?: string[];
}

/**
 * 替换规则作用范围
 */
export enum ReplaceScope {
  ALL = 'all',
  TITLE = 'title',
  CONTENT = 'content'
}

/**
 * 替换规则导入结果
 */
export interface ReplaceRuleImportResult {
  total: number;
  success: number;
  failed: number;
  errors: string[];
}

/**
 * 替换净化规则管理器
 */
export class NovelReplaceRuleManager {
  private static instance: NovelReplaceRuleManager | null = null;
  private rules: Map<string, ReplaceRule> = new Map();
  private initialized: boolean = false;

  private constructor() {}

  static getInstance(): NovelReplaceRuleManager {
    if (!NovelReplaceRuleManager.instance) {
      NovelReplaceRuleManager.instance = new NovelReplaceRuleManager();
    }
    return NovelReplaceRuleManager.instance;
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
      this.initialized = true;
      logger.info(TAG, `替换规则管理器初始化完成，共 ${this.rules.size} 条规则`);
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
    }
  }

  /**
   * 从数据库加载规则
   */
  private async loadRulesFromStorage(): Promise<void> {
    try {
      const dataManager = getNovelDataManager();
      const store = dataManager.getStore();
      const rs = await store.querySql(
        'SELECT * FROM novel_replace_rule ORDER BY ruleOrder ASC'
      );
      
      this.rules.clear();
      if (rs.goToFirstRow()) {
        do {
          const rule: ReplaceRule = {
            id: rs.getString(rs.getColumnIndex('id')),
            name: rs.getString(rs.getColumnIndex('name')),
            pattern: rs.getString(rs.getColumnIndex('pattern')),
            replacement: rs.getString(rs.getColumnIndex('replacement')),
            isRegex: rs.getLong(rs.getColumnIndex('isRegex')) === 1,
            scope: rs.getString(rs.getColumnIndex('scope')) as ReplaceScope,
            enabled: rs.getLong(rs.getColumnIndex('enabled')) === 1,
            order: rs.getLong(rs.getColumnIndex('ruleOrder')),
            sourceIds: this.parseSourceIds(rs.getString(rs.getColumnIndex('sourceIds'))),
            createTime: rs.getLong(rs.getColumnIndex('createTime')),
            updateTime: rs.getLong(rs.getColumnIndex('updateTime'))
          };
          this.rules.set(rule.id, rule);
        } while (rs.goToNextRow());
      }
      rs.close();
      logger.info(TAG, `从数据库加载了 ${this.rules.size} 条替换规则`);
    } catch (error) {
      logger.error(TAG, `加载替换规则失败: ${String(error)}`);
    }
  }

  /**
   * 解析sourceIds字符串
   */
  private parseSourceIds(str: string): string[] | undefined {
    if (!str || str === '') {
      return undefined;
    }
    try {
      return JSON.parse(str) as string[];
    } catch {
      return undefined;
    }
  }

  /**
   * 保存单个规则到数据库
   */
  private async saveRuleToDb(rule: ReplaceRule): Promise<void> {
    try {
      const dataManager = getNovelDataManager();
      const store = dataManager.getStore();
      
      // 使用 DELETE + INSERT 策略
      await store.executeSql('DELETE FROM novel_replace_rule WHERE id = ?', [rule.id]);
      
      const sql = `INSERT INTO novel_replace_rule 
        (id, name, pattern, replacement, isRegex, scope, enabled, ruleOrder, sourceIds, createTime, updateTime)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`;
      
      await store.executeSql(sql, [
        rule.id,
        rule.name,
        rule.pattern,
        rule.replacement,
        rule.isRegex ? 1 : 0,
        rule.scope,
        rule.enabled ? 1 : 0,
        rule.order,
        rule.sourceIds ? JSON.stringify(rule.sourceIds) : '',
        rule.createTime,
        rule.updateTime
      ]);
    } catch (error) {
      logger.error(TAG, `保存替换规则失败: ${String(error)}`);
    }
  }

  /**
   * 从数据库删除规则
   */
  private async deleteRuleFromDb(id: string): Promise<void> {
    try {
      const dataManager = getNovelDataManager();
      const store = dataManager.getStore();
      await store.executeSql('DELETE FROM novel_replace_rule WHERE id = ?', [id]);
    } catch (error) {
      logger.error(TAG, `删除替换规则失败: ${String(error)}`);
    }
  }

  /**
   * 添加规则
   */
  async addRule(rule: AddRuleParams): Promise<ReplaceRule> {
    const now = Date.now();
    const newRule: ReplaceRule = {
      id: this.generateId(),
      name: rule.name,
      pattern: rule.pattern,
      replacement: rule.replacement,
      isRegex: rule.isRegex,
      scope: rule.scope,
      enabled: rule.enabled,
      order: rule.order,
      sourceIds: rule.sourceIds,
      createTime: now,
      updateTime: now
    };

    this.rules.set(newRule.id, newRule);
    await this.saveRuleToDb(newRule);
    
    logger.info(TAG, `添加替换规则: ${newRule.name}`);
    return newRule;
  }

  /**
   * 更新规则
   */
  async updateRule(id: string, updates: AddRuleParams): Promise<boolean> {
    const rule = this.rules.get(id);
    if (!rule) {
      return false;
    }

    const updatedRule: ReplaceRule = {
      id: rule.id,
      name: updates.name !== undefined ? updates.name : rule.name,
      pattern: updates.pattern !== undefined ? updates.pattern : rule.pattern,
      replacement: updates.replacement !== undefined ? updates.replacement : rule.replacement,
      isRegex: updates.isRegex !== undefined ? updates.isRegex : rule.isRegex,
      scope: updates.scope !== undefined ? updates.scope : rule.scope,
      enabled: updates.enabled !== undefined ? updates.enabled : rule.enabled,
      order: updates.order !== undefined ? updates.order : rule.order,
      sourceIds: updates.sourceIds !== undefined ? updates.sourceIds : rule.sourceIds,
      createTime: rule.createTime,
      updateTime: Date.now()
    };

    this.rules.set(id, updatedRule);
    await this.saveRuleToDb(updatedRule);
    
    logger.info(TAG, `更新替换规则: ${updatedRule.name}`);
    return true;
  }

  /**
   * 删除规则
   */
  async deleteRule(id: string): Promise<boolean> {
    const deleted = this.rules.delete(id);
    if (deleted) {
      await this.deleteRuleFromDb(id);
      logger.info(TAG, `删除替换规则: ${id}`);
    }
    return deleted;
  }

  /**
   * 获取所有规则
   */
  getAllRules(): ReplaceRule[] {
    return Array.from(this.rules.values()).sort((a, b) => a.order - b.order);
  }

  /**
   * 获取启用的规则
   */
  getEnabledRules(scope?: ReplaceScope, sourceId?: string): ReplaceRule[] {
    return this.getAllRules().filter(rule => {
      if (!rule.enabled) {
        return false;
      }
      if (scope && rule.scope !== ReplaceScope.ALL && rule.scope !== scope) {
        return false;
      }
      if (sourceId && rule.sourceIds && rule.sourceIds.length > 0) {
        if (!rule.sourceIds.includes(sourceId)) {
          return false;
        }
      }
      return true;
    });
  }

  /**
   * 获取规则
   */
  getRule(id: string): ReplaceRule | null {
    return this.rules.get(id) || null;
  }

  /**
   * 应用替换规则到文本
   */
  applyRules(text: string, scope: ReplaceScope, sourceId?: string): string {
    if (!text) {
      return text;
    }

    const rules = this.getEnabledRules(scope, sourceId);
    let result = text;

    for (const rule of rules) {
      try {
        if (rule.isRegex) {
          const regex = new RegExp(rule.pattern, 'g');
          result = result.replace(regex, rule.replacement);
        } else {
          result = result.split(rule.pattern).join(rule.replacement);
        }
      } catch (error) {
        logger.warn(TAG, `应用规则失败 [${rule.name}]: ${String(error)}`);
      }
    }

    return result;
  }

  /**
   * 导入规则（JSON格式）
   */
  async importRules(json: string): Promise<ReplaceRuleImportResult> {
    const result: ReplaceRuleImportResult = {
      total: 0,
      success: 0,
      failed: 0,
      errors: []
    };

    try {
      const data: Object = JSON.parse(json);
      const rules: Object[] = Array.isArray(data) ? data as Object[] : [data];
      result.total = rules.length;

      for (let i = 0; i < rules.length; i++) {
        const ruleData = rules[i] as Record<string, Object>;
        try {
          const addParams: AddRuleParams = {
            name: (ruleData['name'] as string) || '未命名规则',
            pattern: (ruleData['pattern'] as string) || (ruleData['regex'] as string) || '',
            replacement: (ruleData['replacement'] as string) || '',
            isRegex: ruleData['isRegex'] !== false,
            scope: (ruleData['scope'] as ReplaceScope) || ReplaceScope.CONTENT,
            enabled: ruleData['enabled'] !== false,
            order: (ruleData['order'] as number) || this.rules.size,
            sourceIds: ruleData['sourceIds'] as string[] | undefined
          };
          await this.addRule(addParams);
          result.success++;
        } catch (error) {
          result.failed++;
          const ruleName = (ruleData['name'] as string) || '未知';
          result.errors.push(`规则 "${ruleName}": ${String(error)}`);
        }
      }
    } catch (error) {
      result.errors.push(`JSON解析失败: ${String(error)}`);
    }

    logger.info(TAG, `导入替换规则: 成功 ${result.success}/${result.total}`);
    return result;
  }

  /**
   * 导出规则
   */
  exportRules(): string {
    const allRules = this.getAllRules();
    const exportData: AddRuleParams[] = [];
    for (let i = 0; i < allRules.length; i++) {
      const rule = allRules[i];
      const exportRule: AddRuleParams = {
        name: rule.name,
        pattern: rule.pattern,
        replacement: rule.replacement,
        isRegex: rule.isRegex,
        scope: rule.scope,
        enabled: rule.enabled,
        order: rule.order,
        sourceIds: rule.sourceIds
      };
      exportData.push(exportRule);
    }
    return JSON.stringify(exportData, null, 2);
  }

  /**
   * 启用/禁用规则
   */
  async setRuleEnabled(id: string, enabled: boolean): Promise<boolean> {
    const rule = this.rules.get(id);
    if (!rule) {
      return false;
    }
    rule.enabled = enabled;
    rule.updateTime = Date.now();
    await this.saveRuleToDb(rule);
    return true;
  }

  /**
   * 调整规则顺序
   */
  async reorderRules(ids: string[]): Promise<void> {
    const updatedRules: ReplaceRule[] = [];
    ids.forEach((id, index) => {
      const rule = this.rules.get(id);
      if (rule) {
        rule.order = index;
        rule.updateTime = Date.now();
        updatedRules.push(rule);
      }
    });
    // 批量保存更新的规则
    for (const rule of updatedRules) {
      await this.saveRuleToDb(rule);
    }
  }

  /**
   * 清除所有规则
   */
  async clearAll(): Promise<void> {
    // 从数据库删除所有规则
    for (const id of this.rules.keys()) {
      await this.deleteRuleFromDb(id);
    }
    this.rules.clear();
    logger.info(TAG, '已清除所有替换规则');
  }

  /**
   * 生成唯一ID
   */
  private generateId(): string {
    return `rule_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }
}

/**
 * 获取替换规则管理器实例
 */
export function getNovelReplaceRuleManager(): NovelReplaceRuleManager {
  return NovelReplaceRuleManager.getInstance();
}
