// 文件路径: entry/src/main/ets/Utils/LabelUtils.ets

export class LabelUtils {
  /**
   * 判断标题是否包含汉化/翻译相关的关键字
   * 用于给图源详情页和统一详情页的封面添加"汉化"标签
   * 
   * 支持中英日韩四种语言的常见表述
   */
  static isTranslatedContent(title: string | undefined | null): boolean {
    if (!title) {
      return false;
    }
    const lowerTitle = title.toLowerCase();
    
    // 关键字列表
    const keywords = [
      '汉化',        // 简体
      '漢化',        // 繁体
      '汉化组',      // 汉化组
      '漢化組',
      '翻译',        // 翻译
      '翻譯',
      '中国翻译',    // 中国翻译
      '中國翻譯',
      '中文',        // 中文
      '中字',        // 中字
      'chinese',     // 英文
      'translated',
      'translation',
      '中国語',      // 日文 - 中文
      '翻訳',        // 日文 - 翻译
      '번역',        // 韩文 - 翻译
      '중국어'       // 韩文 - 中文
    ];

    for (const keyword of keywords) {
      if (lowerTitle.includes(keyword)) {
        return true;
      }
    }
    
    return false;
  }
}
