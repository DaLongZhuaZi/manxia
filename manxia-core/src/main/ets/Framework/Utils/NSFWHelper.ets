/**
 * NSFW辅助工具类
 * 提供NSFW内容判断和管理的辅助方法
 */

import { logger } from '../../Utils/Logger';

const TAG = 'NSFWHelper';

/**
 * NSFW关键词列表
 */
export const NSFW_KEYWORDS = [
  'nsfw', '18+', 'adult', '成人', 'r18', 'h', '里番', '肉番', 
  '色情', '成人向', 'hentai', 'ecchi', '工口', 'エロ', 
  '18禁', 'r-18', 'xxx', 'porn', '限制级'
];

/**
 * NSFW辅助类
 */
export class NSFWHelper {
  /**
   * 从标签判断是否为NSFW内容
   */
  public static isNSFWByTags(tags: string[]): boolean {
    if (!tags || tags.length === 0) {
      return false;
    }
    
    const tagsLower = tags.map(t => t.toLowerCase()).join(',');
    return NSFW_KEYWORDS.some(keyword => tagsLower.includes(keyword));
  }

  /**
   * 从分类判断是否为NSFW内容
   */
  public static isNSFWByCategories(categories: string[]): boolean {
    if (!categories || categories.length === 0) {
      return false;
    }
    
    const categoriesLower = categories.map(c => c.toLowerCase()).join(',');
    return NSFW_KEYWORDS.some(keyword => categoriesLower.includes(keyword));
  }

  /**
   * 从标题或描述判断是否为NSFW内容
   */
  public static isNSFWByText(text: string): boolean {
    if (!text) {
      return false;
    }
    
    const textLower = text.toLowerCase();
    return NSFW_KEYWORDS.some(keyword => textLower.includes(keyword));
  }

  /**
   * 综合判断是否为NSFW内容
   */
  public static isNSFWContent(params: {
    tags?: string[];
    categories?: string[];
    title?: string;
    description?: string;
  }): boolean {
    return this.isNSFWByTags(params.tags || []) ||
           this.isNSFWByCategories(params.categories || []) ||
           this.isNSFWByText(params.title || '') ||
           this.isNSFWByText(params.description || '');
  }

  /**
   * 格式化NSFW状态显示文本
   */
  public static formatNSFWStatus(isNSFW: boolean): string {
    return isNSFW ? 'NSFW (成人内容)' : 'SFW (全年龄)';
  }

  /**
   * 获取NSFW警告文本
   */
  public static getNSFWWarning(): string {
    return '此内容包含成人向内容，请确认您已满18岁';
  }
}
