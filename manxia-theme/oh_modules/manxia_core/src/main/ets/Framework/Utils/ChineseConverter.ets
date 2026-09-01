// 文件路径: entry/src/main/ets/Framework/Utils/ChineseConverter.ets
/**
 * 简繁体中文转换工具
 * 支持简体转繁体、繁体转简体、自动检测转换
 */

import { logger } from '../../Utils/Logger';

const TAG = 'ChineseConverter';

/**
 * 转换方向
 */
export type ConversionDirection = 'auto' | 's2t' | 't2s';

/**
 * 中文变体
 */
export type ChineseVariant = 'zh-CN' | 'zh-TW' | 'zh-HK';

/**
 * 简繁转换配置
 */
export interface ChineseConversionConfig {
  enabled: boolean;
  direction: ConversionDirection;
  applyTo: string[];
  variant: ChineseVariant;
}

/**
 * 映射表大小信息
 */
export interface MappingSizeInfo {
  s2t: number;
  t2s: number;
}

/**
 * 简繁体中文转换器（单例）
 */
export class ChineseConverter {
  private static instance: ChineseConverter | null = null;
  private static initialized: boolean = false;

  // 简体到繁体映射表（常用字）
  private static s2tMap: Map<string, string> = new Map<string, string>();

  // 繁体到简体映射表（常用字）
  private static t2sMap: Map<string, string> = new Map<string, string>();

  private constructor() {
    ChineseConverter.initialize();
  }

  static getInstance(): ChineseConverter {
    if (!ChineseConverter.instance) {
      ChineseConverter.instance = new ChineseConverter();
    }
    return ChineseConverter.instance;
  }

  /**
   * 初始化转换映射表
   */
  private static initialize(): void {
    if (ChineseConverter.initialized) {
      return;
    }

    // 常用简繁对照表（部分示例，实际应用中需要完整的映射表）
    const commonPairs: string[][] = [
      // 常用字
      ['万', '萬'], ['与', '與'], ['专', '專'], ['业', '業'], ['丛', '叢'],
      ['东', '東'], ['丝', '絲'], ['丢', '丟'], ['两', '兩'], ['严', '嚴'],
      ['丧', '喪'], ['个', '個'], ['丰', '豐'], ['临', '臨'], ['为', '為'],
      ['丽', '麗'], ['举', '舉'], ['么', '麼'], ['义', '義'], ['乌', '烏'],
      ['乐', '樂'], ['乔', '喬'], ['习', '習'], ['乡', '鄉'], ['书', '書'],
      ['买', '買'], ['乱', '亂'], ['争', '爭'], ['于', '於'], ['亏', '虧'],
      ['云', '雲'], ['亚', '亞'], ['产', '產'], ['亩', '畝'], ['享', '享'],
      ['京', '京'], ['亮', '亮'], ['亲', '親'], ['亿', '億'], ['仅', '僅'],
      ['从', '從'], ['仑', '侖'], ['仓', '倉'], ['仪', '儀'], ['们', '們'],
      ['价', '價'], ['众', '眾'], ['优', '優'], ['伙', '夥'], ['会', '會'],
      ['伟', '偉'], ['传', '傳'], ['伤', '傷'], ['伦', '倫'], ['伪', '偽'],
      ['伫', '佇'], ['体', '體'], ['余', '餘'], ['佣', '傭'], ['佩', '佩'],
      ['侠', '俠'], ['侣', '侶'], ['侥', '僥'], ['侦', '偵'], ['侧', '側'],
      ['侨', '僑'], ['侩', '儈'], ['侪', '儕'], ['侬', '儂'], ['俣', '俁'],
      ['俦', '儔'], ['俨', '儼'], ['俩', '倆'], ['俪', '儷'], ['俭', '儉'],
      ['债', '債'], ['倾', '傾'], ['偬', '傯'], ['偻', '僂'], ['偾', '僨'],
      ['偿', '償'], ['傥', '儻'], ['储', '儲'], ['催', '催'], ['傲', '傲'],

      // 漫画相关常用词
      ['漫画', '漫畫'], ['连载', '連載'], ['单行本', '單行本'], ['卷', '卷'],
      ['话', '話'], ['集', '集'], ['章', '章'], ['回', '回'], ['篇', '篇'],
      ['完结', '完結'], ['更新', '更新'], ['作者', '作者'], ['出版', '出版'],
      ['热门', '熱門'], ['最新', '最新'], ['推荐', '推薦'], ['收藏', '收藏'],
      ['评分', '評分'], ['评论', '評論'], ['标签', '標籤'], ['类型', '類型'],
      ['搜索', '搜尋'], ['查找', '查找'], ['阅读', '閱讀'], ['下载', '下載'],
      ['设置', '設置'], ['账号', '賬號'], ['登录', '登錄'], ['注册', '註冊'],

      // 数字
      ['零', '零'], ['一', '一'], ['二', '二'], ['三', '三'], ['四', '四'],
      ['五', '五'], ['六', '六'], ['七', '七'], ['八', '八'], ['九', '九'],
      ['十', '十'], ['百', '百'], ['千', '千'], ['万', '萬'], ['亿', '億']
    ];

    // 构建映射表
    for (let i = 0; i < commonPairs.length; i++) {
      const pair = commonPairs[i];
      const simplified = pair[0];
      const traditional = pair[1];
      ChineseConverter.s2tMap.set(simplified, traditional);
      ChineseConverter.t2sMap.set(traditional, simplified);
    }

    ChineseConverter.initialized = true;
    logger.info(TAG, `简繁转换映射表初始化完成: ${ChineseConverter.s2tMap.size}个字符对`);
  }

  /**
   * 简体转繁体
   */
  simplifiedToTraditional(text: string): string {
    if (!text) {
      return text;
    }

    let result = text;
    ChineseConverter.s2tMap.forEach((traditional: string, simplified: string) => {
      if (result.includes(simplified)) {
        result = result.replace(new RegExp(simplified, 'g'), traditional);
      }
    });

    return result;
  }

  /**
   * 繁体转简体
   */
  traditionalToSimplified(text: string): string {
    if (!text) {
      return text;
    }

    let result = text;
    ChineseConverter.t2sMap.forEach((simplified: string, traditional: string) => {
      if (result.includes(traditional)) {
        result = result.replace(new RegExp(traditional, 'g'), simplified);
      }
    });

    return result;
  }

  /**
   * 自动检测并转换
   */
  autoConvert(text: string, targetVariant: ChineseVariant): string {
    if (!text) {
      return text;
    }

    // 检测文本中的简繁体比例
    const variant = this.detectVariant(text);

    if (targetVariant === 'zh-CN') {
      // 目标是简体
      if (variant === 'traditional') {
        return this.traditionalToSimplified(text);
      }
    } else if (targetVariant === 'zh-TW' || targetVariant === 'zh-HK') {
      // 目标是繁体
      if (variant === 'simplified') {
        return this.simplifiedToTraditional(text);
      }
    }

    return text;
  }

  /**
   * 检测文本变体（简体/繁体）
   */
  private detectVariant(text: string): 'simplified' | 'traditional' | 'mixed' {
    let simplifiedCount = 0;
    let traditionalCount = 0;

    // 统计简体字和繁体字的数量
    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      if (ChineseConverter.s2tMap.has(char)) {
        simplifiedCount++;
      } else if (ChineseConverter.t2sMap.has(char)) {
        traditionalCount++;
      }
    }

    const total = simplifiedCount + traditionalCount;
    if (total === 0) {
      return 'mixed';
    }

    const simplifiedRatio = simplifiedCount / total;

    if (simplifiedRatio > 0.7) {
      return 'simplified';
    } else if (simplifiedRatio < 0.3) {
      return 'traditional';
    } else {
      return 'mixed';
    }
  }

  /**
   * 转换对象中的文本字段
   */
  convertObject(obj: Record<string, Object>, config: ChineseConversionConfig): Record<string, Object> {
    if (!config.enabled) {
      return obj;
    }

    const result: Record<string, Object> = {};

    const keys = Object.keys(obj);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value = obj[key];

      // 检查是否需要转换此字段
      if (config.applyTo.includes(key) && typeof value === 'string') {
        result[key] = this.convert(value as string, config);
      } else if (typeof value === 'object' && value !== null && !Array.isArray(value)) {
        // 递归处理嵌套对象
        result[key] = this.convertObject(value as Record<string, Object>, config);
      } else if (Array.isArray(value)) {
        // 处理数组
        const arr = value as Object[];
        const convertedArr: Object[] = [];
        for (let j = 0; j < arr.length; j++) {
          const item = arr[j];
          if (typeof item === 'string') {
            convertedArr.push(this.convert(item as string, config));
          } else if (typeof item === 'object' && item !== null) {
            convertedArr.push(this.convertObject(item as Record<string, Object>, config));
          } else {
            convertedArr.push(item);
          }
        }
        result[key] = convertedArr;
      } else {
        result[key] = value;
      }
    }

    return result;
  }

  /**
   * 根据配置转换文本
   */
  convert(text: string, config: ChineseConversionConfig): string {
    if (!config.enabled || !text) {
      return text;
    }

    switch (config.direction) {
      case 's2t':
        return this.simplifiedToTraditional(text);
      case 't2s':
        return this.traditionalToSimplified(text);
      case 'auto':
      default:
        return this.autoConvert(text, config.variant);
    }
  }

  /**
   * 批量转换文本数组
   */
  convertArray(texts: string[], config: ChineseConversionConfig): string[] {
    if (!config.enabled) {
      return texts;
    }

    return texts.map(text => this.convert(text, config));
  }

  /**
   * 添加自定义映射
   */
  addCustomMapping(simplified: string, traditional: string): void {
    ChineseConverter.s2tMap.set(simplified, traditional);
    ChineseConverter.t2sMap.set(traditional, simplified);
    logger.debug(TAG, `添加自定义映射: ${simplified} <-> ${traditional}`);
  }

  /**
   * 批量添加自定义映射
   */
  addCustomMappings(mappings: string[][]): void {
    for (let i = 0; i < mappings.length; i++) {
      const pair = mappings[i];
      this.addCustomMapping(pair[0], pair[1]);
    }
    logger.info(TAG, `批量添加自定义映射: ${mappings.length}个`);
  }

  /**
   * 获取映射表大小
   */
  getMappingSize(): MappingSizeInfo {
    return {
      s2t: ChineseConverter.s2tMap.size,
      t2s: ChineseConverter.t2sMap.size
    };
  }
}

export default ChineseConverter;
