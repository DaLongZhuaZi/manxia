import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * 小说替换净化规则管理器
 * 管理全局替换规则，用于净化正文内容
 * 
 * 文件路径: entry/src/main/ets/Framework/Novel/NovelReplaceRuleManager.ets
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
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
      
      // 如果数据库中没有规则，添加默认规则
      if (this.rules.size === 0) {
        await this.loadDefaultRules();
      }
      
      this.initialized = true;
      logger.info(TAG, `替换规则管理器初始化完成，共 ${this.rules.size} 条规则`);
    } catch (error) {
      logger.error(TAG, `初始化失败: ${String(error)}`);
    }
  }
  
  /**
   * 刷新规则（从数据库重新加载）
   */
  async refreshRules(): Promise<void> {
    try {
      await this.loadRulesFromStorage();
      logger.info(TAG, `刷新替换规则完成，共 ${this.rules.size} 条规则`);
    } catch (error) {
      logger.error(TAG, `刷新规则失败: ${String(error)}`);
    }
  }

  /**
   * 加载默认替换净化规则
   */
  private async loadDefaultRules(): Promise<void> {
    // 使用函数逐个添加规则，避免ArkTS数组字面量类型推断问题
    const addDefaultRule = async (name: string, pattern: string, replacement: string, isRegex: boolean, scope: ReplaceScope, enabled: boolean, order: number): Promise<void> => {
      const params: AddRuleParams = {
        name: name,
        pattern: pattern,
        replacement: replacement,
        isRegex: isRegex,
        scope: scope,
        enabled: enabled,
        order: order
      };
      try {
        await this.addRule(params);
      } catch (error) {
        logger.warn(TAG, `添加默认规则失败 [${name}]: ${String(error)}`);
      }
    };
    
    logger.info(TAG, '开始加载默认替换规则');
    
    // 广告类规则
    await addDefaultRule('求收藏推荐', '(?:求|跪求|恳请).{0,10}(?:收藏|推荐|订阅|打赏|月票|评论|投票|追读)', '', true, ReplaceScope.CONTENT, true, 0);
    await addDefaultRule('首发声明', '(?:本书|本文|小说|作品).{0,20}(?:首发|独家|连载|发布).{0,20}(?:网站|平台|app|网)', '', true, ReplaceScope.CONTENT, true, 1);
    await addDefaultRule('更新提示', '(?:更多|更新|最新).{0,10}(?:章节|内容|小说).{0,20}(?:请|搜索|访问|百度)', '', true, ReplaceScope.CONTENT, true, 2);
    await addDefaultRule('阅读提示', '(?:手机|电脑|移动端).{0,10}(?:阅读|观看|访问).{0,20}(?:网址|地址|链接|搜索)', '', true, ReplaceScope.CONTENT, true, 3);
    await addDefaultRule('版权声明', '(?:正版|盗版|版权).{0,20}(?:支持|打击|举报|所有)', '', true, ReplaceScope.CONTENT, true, 4);
    await addDefaultRule('群聊广告', '(?:加入|欢迎|进入).{0,10}(?:书友群|QQ群|微信群|读者群|粉丝群)', '', true, ReplaceScope.CONTENT, true, 5);
    await addDefaultRule('网址链接', '(?:www\\.|http:|https:|\\.com|\\.cn|\\.net|\\.org)[^\\s]{5,}', '', true, ReplaceScope.CONTENT, true, 6);
    await addDefaultRule('网站名称广告', '(?:起点|晋江|纵横|17k|潇湘|红袖|番茄|七猫|书旗|飞卢|塔读|掌阅|咪咕|QQ阅读).{0,10}(?:中文网|小说网|文学|阅读|书城)', '', true, ReplaceScope.CONTENT, true, 7);
    await addDefaultRule('章节提示', '(?:本章|下章|上章|本节|下节).{0,10}(?:未完|待续|继续|完毕|结束)', '', true, ReplaceScope.CONTENT, false, 8);
    await addDefaultRule('作者有话说', '(?:作者|笔者|小编).{0,5}(?:有话说|的话|说|曰|云)', '', true, ReplaceScope.CONTENT, false, 9);
    
    // 乱码类规则
    await addDefaultRule('乱码符号', '[□■◇◆○●△▲▽▼☆★]{3,}', '', true, ReplaceScope.CONTENT, true, 10);
    await addDefaultRule('控制字符', '[\\x00-\\x08\\x0b\\x0c\\x0e-\\x1f]{2,}', '', true, ReplaceScope.CONTENT, true, 11);
    await addDefaultRule('重复标点', '([。！？，、；：]){3,}', '$1$1', true, ReplaceScope.CONTENT, true, 12);
    await addDefaultRule('多余空行', '\\n{4,}', '\\n\\n', true, ReplaceScope.CONTENT, true, 13);
    await addDefaultRule('多余空格', '[ ]{4,}', '  ', true, ReplaceScope.CONTENT, true, 14);
    
    // 标题净化规则
    await addDefaultRule('标题网站名', '[-_].{0,20}(?:起点|晋江|纵横|番茄|七猫).{0,10}$', '', true, ReplaceScope.TITLE, true, 15);
    await addDefaultRule('标题作者名', '[-_].{0,5}(?:作者|著|by).{0,20}$', '', true, ReplaceScope.TITLE, false, 16);
    
    logger.info(TAG, `默认替换规则加载完成，共 ${this.rules.size} 条`);
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
      return SafeUtils.parseArr(str) as string[];
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
      const data: Object = SafeUtils.parseObj(json);
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
