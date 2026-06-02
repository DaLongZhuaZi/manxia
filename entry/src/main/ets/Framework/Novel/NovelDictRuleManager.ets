import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * 字典规则管理器
 * 用于在线词典查询功能
 * 参照Legado实现
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelDictRuleManager.ets
 */

import { logger } from '../../Utils/Logger';
import { getNovelDataManager } from './NovelDataManager';
import { http } from '@kit.NetworkKit';

const TAG = 'NovelDictRuleManager';

/**
 * 字典规则
 */
export interface DictRule {
  id: string;
  name: string;
  urlRule: string;      // URL规则，支持{{key}}占位符
  showRule: string;     // 显示规则（可选，用于提取结果）
  enabled: boolean;
  sortNumber: number;
  createTime: number;
  updateTime: number;
}

/**
 * 添加字典规则参数
 */
export interface AddDictRuleParams {
  name: string;
  urlRule: string;
  showRule?: string;
  enabled?: boolean;
  sortNumber?: number;
}

/**
 * 字典规则导入结果
 */
export interface DictRuleImportResult {
  total: number;
  success: number;
  failed: number;
  errors: string[];
}

/**
 * 字典查询结果
 */
export interface DictSearchResult {
  word: string;
  content: string;
  source: string;
  success: boolean;
  error?: string;
}

/**
 * 默认字典规则
 */
export const DEFAULT_DICT_RULES: AddDictRuleParams[] = [
  {
    name: '百度百科',
    urlRule: 'https://baike.baidu.com/item/{{key}}',
    showRule: '',
    enabled: true
  },
  {
    name: '百度汉语',
    urlRule: 'https://hanyu.baidu.com/s?wd={{key}}&ptype=zici',
    showRule: '',
    enabled: true
  },
  {
    name: '维基百科',
    urlRule: 'https://zh.wikipedia.org/wiki/{{key}}',
    showRule: '',
    enabled: false
  },
  {
    name: '有道词典',
    urlRule: 'https://dict.youdao.com/result?word={{key}}&lang=en',
    showRule: '',
    enabled: false
  }
];

/**
 * 字典规则管理器
 */
export class NovelDictRuleManager {
  private static instance: NovelDictRuleManager | null = null;
  private rules: Map<string, DictRule> = new Map();
  private initialized: boolean = false;

  private constructor() {}

  static getInstance(): NovelDictRuleManager {
    if (!NovelDictRuleManager.instance) {
      NovelDictRuleManager.instance = new NovelDictRuleManager();
    }
    return NovelDictRuleManager.instance;
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
      }
      
      this.initialized = true;
      logger.info(TAG, `字典规则管理器初始化完成，共 ${this.rules.size} 条规则`);
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
    }
  }

  /**
   * 导入默认规则
   */
  private async importDefaultRules(): Promise<void> {
    for (let i = 0; i < DEFAULT_DICT_RULES.length; i++) {
      const rule = DEFAULT_DICT_RULES[i];
      const params: AddDictRuleParams = {
        name: rule.name,
        urlRule: rule.urlRule,
        showRule: rule.showRule,
        sortNumber: i,
        enabled: rule.enabled !== false
      };
      await this.addRule(params);
    }
    logger.info(TAG, `已导入 ${DEFAULT_DICT_RULES.length} 条默认字典规则`);
  }

  /**
   * 从数据库加载规则
   */
  private async loadRulesFromStorage(): Promise<void> {
    try {
      const dataManager = getNovelDataManager();
      const store = dataManager.getStore();
      const rs = await store.querySql(
        'SELECT * FROM novel_dict_rule ORDER BY sortNumber ASC'
      );
      
      this.rules.clear();
      if (rs.goToFirstRow()) {
        do {
          const rule: DictRule = {
            id: rs.getString(rs.getColumnIndex('id')),
            name: rs.getString(rs.getColumnIndex('name')),
            urlRule: rs.getString(rs.getColumnIndex('urlRule')),
            showRule: rs.getString(rs.getColumnIndex('showRule')) || '',
            enabled: rs.getLong(rs.getColumnIndex('enabled')) === 1,
            sortNumber: rs.getLong(rs.getColumnIndex('sortNumber')),
            createTime: rs.getLong(rs.getColumnIndex('createTime')),
            updateTime: rs.getLong(rs.getColumnIndex('updateTime'))
          };
          this.rules.set(rule.id, rule);
        } while (rs.goToNextRow());
      }
      rs.close();
      logger.info(TAG, `从数据库加载了 ${this.rules.size} 条字典规则`);
    } catch (error) {
      logger.warn(TAG, `加载字典规则失败: ${String(error)}`);
    }
  }

  /**
   * 保存单个规则到数据库
   */
  private async saveRuleToDb(rule: DictRule): Promise<void> {
    try {
      const dataManager = getNovelDataManager();
      const store = dataManager.getStore();
      
      await store.executeSql('DELETE FROM novel_dict_rule WHERE id = ?', [rule.id]);
      
      const sql = `INSERT INTO novel_dict_rule 
        (id, name, urlRule, showRule, enabled, sortNumber, createTime, updateTime)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)`;
      
      await store.executeSql(sql, [
        rule.id,
        rule.name,
        rule.urlRule,
        rule.showRule,
        rule.enabled ? 1 : 0,
        rule.sortNumber,
        rule.createTime,
        rule.updateTime
      ]);
    } catch (error) {
      logger.error(TAG, `保存字典规则失败: ${String(error)}`);
    }
  }

  /**
   * 从数据库删除规则
   */
  private async deleteRuleFromDb(id: string): Promise<void> {
    try {
      const dataManager = getNovelDataManager();
      const store = dataManager.getStore();
      await store.executeSql('DELETE FROM novel_dict_rule WHERE id = ?', [id]);
    } catch (error) {
      logger.error(TAG, `删除字典规则失败: ${String(error)}`);
    }
  }

  /**
   * 生成ID
   */
  private generateId(): string {
    return `dict_${Date.now()}_${Math.random().toString(36).substring(2, 9)}`;
  }

  /**
   * 添加规则
   */
  async addRule(params: AddDictRuleParams): Promise<DictRule> {
    const now = Date.now();
    const newRule: DictRule = {
      id: this.generateId(),
      name: params.name,
      urlRule: params.urlRule,
      showRule: params.showRule || '',
      enabled: params.enabled !== false,
      sortNumber: params.sortNumber !== undefined ? params.sortNumber : this.rules.size,
      createTime: now,
      updateTime: now
    };

    this.rules.set(newRule.id, newRule);
    await this.saveRuleToDb(newRule);
    
    logger.info(TAG, `添加字典规则: ${newRule.name}`);
    return newRule;
  }

  /**
   * 更新规则
   */
  async updateRule(id: string, updates: Partial<AddDictRuleParams>): Promise<boolean> {
    const rule = this.rules.get(id);
    if (!rule) {
      return false;
    }

    const updatedRule: DictRule = {
      id: rule.id,
      name: updates.name !== undefined ? updates.name : rule.name,
      urlRule: updates.urlRule !== undefined ? updates.urlRule : rule.urlRule,
      showRule: updates.showRule !== undefined ? updates.showRule : rule.showRule,
      enabled: updates.enabled !== undefined ? updates.enabled : rule.enabled,
      sortNumber: updates.sortNumber !== undefined ? updates.sortNumber : rule.sortNumber,
      createTime: rule.createTime,
      updateTime: Date.now()
    };

    this.rules.set(id, updatedRule);
    await this.saveRuleToDb(updatedRule);
    
    logger.info(TAG, `更新字典规则: ${updatedRule.name}`);
    return true;
  }

  /**
   * 删除规则
   */
  async deleteRule(id: string): Promise<boolean> {
    const deleted = this.rules.delete(id);
    if (deleted) {
      await this.deleteRuleFromDb(id);
      logger.info(TAG, `删除字典规则: ${id}`);
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
  getAllRules(): DictRule[] {
    return Array.from(this.rules.values()).sort((a, b) => a.sortNumber - b.sortNumber);
  }

  /**
   * 获取启用的规则
   */
  getEnabledRules(): DictRule[] {
    return this.getAllRules().filter(rule => rule.enabled);
  }

  /**
   * 获取规则
   */
  getRule(id: string): DictRule | null {
    return this.rules.get(id) || null;
  }

  /**
   * 构建查询URL
   */
  buildSearchUrl(rule: DictRule, word: string): string {
    return rule.urlRule.replace(/\{\{key\}\}/g, encodeURIComponent(word));
  }

  /**
   * 使用指定规则搜索词语
   */
  async searchWithRule(rule: DictRule, word: string): Promise<DictSearchResult> {
    const result: DictSearchResult = {
      word: word,
      content: '',
      source: rule.name,
      success: false
    };

    try {
      const url = this.buildSearchUrl(rule, word);
      logger.info(TAG, `字典查询: ${rule.name} - ${word}`);

      const httpRequest = http.createHttp();
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        },
        connectTimeout: 10000,
        readTimeout: 15000
      });

      if (response.responseCode === 200) {
        let content = response.result as string;
        
        // 如果有显示规则，应用规则提取内容
        if (rule.showRule && rule.showRule.trim()) {
          content = this.applyShowRule(content, rule.showRule);
        }
        
        result.content = content;
        result.success = true;
      } else {
        result.error = `HTTP ${response.responseCode}`;
      }

      httpRequest.destroy();
    } catch (error) {
      result.error = String(error);
      logger.error(TAG, `字典查询失败 [${rule.name}]: ${String(error)}`);
    }

    return result;
  }

  /**
   * 应用显示规则提取内容
   */
  private applyShowRule(content: string, showRule: string): string {
    // 简单的正则提取
    try {
      const regex = new RegExp(showRule, 's');
      const match = content.match(regex);
      if (match && match[1]) {
        return match[1];
      } else if (match && match[0]) {
        return match[0];
      }
    } catch (error) {
      logger.warn(TAG, `应用显示规则失败: ${String(error)}`);
    }
    return content;
  }

  /**
   * 使用第一个启用的规则搜索
   */
  async search(word: string): Promise<DictSearchResult> {
    const enabledRules = this.getEnabledRules();
    if (enabledRules.length === 0) {
      return {
        word: word,
        content: '',
        source: '',
        success: false,
        error: '没有启用的字典规则'
      };
    }

    return this.searchWithRule(enabledRules[0], word);
  }

  /**
   * 使用所有启用的规则搜索
   */
  async searchAll(word: string): Promise<DictSearchResult[]> {
    const enabledRules = this.getEnabledRules();
    const results: DictSearchResult[] = [];

    for (const rule of enabledRules) {
      const result = await this.searchWithRule(rule, word);
      results.push(result);
    }

    return results;
  }

  /**
   * 导入规则（从JSON）
   */
  async importFromJSON(jsonStr: string): Promise<DictRuleImportResult> {
    const result: DictRuleImportResult = {
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
          const itemUrlRule = item['urlRule'] as string;
          if (!itemName || !itemUrlRule) {
            result.failed++;
            result.errors.push(`规则缺少必要字段`);
            continue;
          }

          const params: AddDictRuleParams = {
            name: itemName,
            urlRule: itemUrlRule,
            showRule: (item['showRule'] as string) || '',
            sortNumber: item['sortNumber'] as number,
            enabled: item['enabled'] !== false
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

    logger.info(TAG, `导入字典规则完成: ${result.success}/${result.total} 成功`);
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
      exportRule['urlRule'] = rule.urlRule;
      exportRule['showRule'] = rule.showRule;
      exportRule['sortNumber'] = rule.sortNumber;
      exportRule['enabled'] = rule.enabled;
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
    
    logger.info(TAG, '已重置为默认字典规则');
  }
}

/**
 * 获取字典规则管理器实例
 */
export function getNovelDictRuleManager(): NovelDictRuleManager {
  return NovelDictRuleManager.getInstance();
}
