// 文件路径: entry/src/main/ets/Framework/Parsers/TxtMetadataExtractor.ets
// 职责: TXT 电子书智能元数据提取器
// 支持从 TXT 文件中智能识别：标题、作者、简介、标签等信息
// 支持多种常见格式：网络小说、经典文学、翻译作品等

import { EBookMetadata, EBookChapter } from '../../Models/EBookModels';
import { logger } from '../../Utils/Logger';

const TAG = 'TxtMetadataExtractor';

/**
 * 提取结果接口
 */
export interface TxtExtractionResult {
  metadata: EBookMetadata;
  chapters: TxtChapterInfo[];
  headerEndPosition: number;  // 头部信息结束位置（正文开始位置）
  rawHeaderText: string;      // 原始头部文本
}

/**
 * 章节信息接口
 */
export interface TxtChapterInfo {
  title: string;              // 章节标题
  chapterNumber: number;      // 章节编号
  startPosition: number;      // 起始位置（字符偏移）
  endPosition: number;        // 结束位置
}

/**
 * 主角/配角信息
 */
export interface CharacterInfo {
  protagonists: string[];     // 主角列表
  supporting: string[];       // 配角列表
  others: string[];           // 其他角色
}

/**
 * 章节匹配信息
 */
interface ChapterMatchInfo {
  index: number;
  title: string;
  number: number;
}

/**
 * TXT 元数据智能提取器
 * 支持多种常见的 TXT 小说格式：
 * - 网络小说（晋江、起点等）
 * - 经典文学作品
 * - 翻译作品
 * - 诺贝尔文学奖作品集等
 */
export class TxtMetadataExtractor {
  // ==================== 标题提取正则 ====================
  private static readonly TITLE_PATTERNS: RegExp[] = [
    // 书名号格式
    /^[　\s]*《([^》]+)》/m,                           // 《书名》
    /^[　\s]*【([^】]+)】/m,                           // 【书名】
    /^[　\s]*＜＜([^＞]+)＞＞/m,                        // ＜＜书名＞＞ 全角
    /^[　\s]*<<([^>]+)>>/m,                            // <<书名>> 半角
    // 明确标注格式
    /^[　\s]*书名[：:]\s*(.+)$/m,                      // 书名：xxx
    /^[　\s]*小说名[：:]\s*(.+)$/m,                    // 小说名：xxx
    /^[　\s]*题目[：:]\s*(.+)$/m,                      // 题目：xxx
    // 年份+作者+书名格式（诺贝尔文学奖作品集等）
    /^\d{4}[年]?诺贝尔文学奖[：:]\s*(.+?)\s+作者/m,    // 1909诺贝尔文学奖：xxx 作者
    /^\d{4}(.+?)[：:]\s*(.+)$/m,                       // 1954海明威：老人与海
  ];

  // ==================== 作者提取正则 ====================
  private static readonly AUTHOR_PATTERNS: RegExp[] = [
    // 标准格式
    /作者[：:]\s*([^\s\n\r]+)/,                        // 作者：xxx
    /著[：:]\s*([^\s\n\r]+)/,                          // 著：xxx
    /作\s*者[：:]\s*([^\s\n\r]+)/,                     // 作 者：xxx
    // 文件名格式
    /^[　\s]*《[^》]+》作者[：:]\s*([^\s\n\r]+)/m,     // 《书名》作者：xxx
    // 翻译作品格式
    /\[([^\]]+)\]([^《\[]+)$/m,                        // [国籍]作者名
    /【([^】]+)】([^《【]+)$/m,                        // 【国籍】作者名
    // 英文格式
    /by[：:\s]+([^\s\n\r]+)/i,                         // by xxx
    /By[：:\s]+([^\s\n\r]+)/,                          // By xxx
    // 年份+作者格式
    /^\d{4}([^：:]+)[：:]/m,                           // 1954海明威：
  ];

  // ==================== 简介/文案提取正则 ====================
  private static readonly DESCRIPTION_PATTERNS: RegExp[] = [
    // 网络小说格式
    /文案[：:]\s*([\s\S]*?)(?=内容标签|搜索关键字|一句话简介|立意|第[0-9一二三四五六七八九十百千]+[章回]|正文|$)/i,
    /简介[：:]\s*([\s\S]*?)(?=内容标签|搜索关键字|一句话简介|立意|第[0-9一二三四五六七八九十百千]+[章回]|正文|$)/i,
    /内容简介[：:]\s*([\s\S]*?)(?=内容标签|搜索关键字|一句话简介|立意|第[0-9一二三四五六七八九十百千]+[章回]|正文|$)/i,
    /作品简介[：:]\s*([\s\S]*?)(?=内容标签|搜索关键字|一句话简介|立意|第[0-9一二三四五六七八九十百千]+[章回]|正文|$)/i,
    // 经典文学格式
    /·内容提要·\s*([\s\S]*?)(?=·|第[0-9一二三四五六七八九十百千]+[章回部卷]|正文|[-]{3,}|$)/i,
    /·作品赏析·\s*([\s\S]*?)(?=·|第[0-9一二三四五六七八九十百千]+[章回部卷]|正文|[-]{3,}|$)/i,
    /内容提要[：:]\s*([\s\S]*?)(?=第[0-9一二三四五六七八九十百千]+[章回部卷]|正文|[-]{3,}|$)/i,
  ];

  // ==================== 标签提取正则 ====================
  private static readonly TAG_PATTERNS: RegExp[] = [
    /内容标签[：:]\s*([^\n]+)/,                        // 内容标签：xxx
    /标签[：:]\s*([^\n]+)/,                            // 标签：xxx
    /分类[：:]\s*([^\n]+)/,                            // 分类：xxx
    /类型[：:]\s*([^\n]+)/,                            // 类型：xxx
    /题材[：:]\s*([^\n]+)/,                            // 题材：xxx
  ];

  // ==================== 主角/配角提取正则 ====================
  private static readonly CHARACTER_PATTERNS: RegExp[] = [
    /搜索关键字[：:]\s*主角[：:]\s*([^┃|│\n]+)/,      // 搜索关键字：主角：xxx
    /主角[：:]\s*([^┃|│\n]+)/,                         // 主角：xxx
    /配角[：:]\s*([^┃|│\n]+)/,                         // 配角：xxx
  ];

  // 一句话简介
  private static readonly ONE_LINE_SUMMARY_PATTERN = /一句话简介[：:]\s*([^\n]+)/;

  // 立意
  private static readonly THEME_PATTERN = /立意[：:]\s*([^\n]+)/;

  // VIP推荐/编辑推荐
  private static readonly VIP_RECOMMEND_PATTERNS: RegExp[] = [
    /vip强推奖章\s*([\s\S]*?)(?=第[0-9一二三四五六七八九十百千]+[章回]|正文|$)/i,
    /编辑推荐[：:]\s*([\s\S]*?)(?=第[0-9一二三四五六七八九十百千]+[章回]|正文|$)/i,
  ];

  // ==================== 章节标题正则（支持多种格式）====================
  private static readonly CHAPTER_PATTERNS: RegExp[] = [
    // 中文章节格式
    /^[　\s]*第\s*([0-9零一二三四五六七八九十百千万亿]+)\s*[章回卷节集部篇]\s*(.*)$/gm,
    /^[　\s]*[【\[]第\s*([0-9零一二三四五六七八九十百千万亿]+)\s*[章回卷节集部篇][】\]]\s*(.*)$/gm,
    // 特殊符号章节格式
    /^[　\s]*◎卷([0-9零一二三四五六七八九十]+)\s*(.*)$/gm,                    // ◎卷一 xxx
    /^[　\s]*◎([^◎\n]{2,20})$/gm,                                              // ◎章节名
    // 英文章节格式
    /^[　\s]*Chapter\s+(\d+)[：:\s]*(.*)$/gim,
    /^[　\s]*Part\s+(\d+)[：:\s]*(.*)$/gim,
    // 数字章节格式
    /^[　\s]*(\d+)[、.．]\s*(.{2,30})$/gm,                                      // 1. xxx 或 1、xxx
    /^[　\s]*第(\d+)部分\s*(.*)$/gm,                                            // 第01部分
  ];

  // 需要跳过的行（广告、网站信息等）
  private static readonly SKIP_LINE_PATTERNS: RegExp[] = [
    /^www\./i,                                          // 网站地址
    /^http/i,                                           // URL
    /电子书下载/,                                       // 下载信息
    /本站作品收集于网络/,                               // 版权声明
    /请下载后.*删除/,                                   // 版权声明
    /请购买正版/,                                       // 版权声明
    /上一页.*目录.*下一页/,                             // 导航信息
    /^[-=]{5,}$/,                                       // 分隔线
  ];

  // 中文数字转阿拉伯数字映射
  private static readonly CHINESE_NUM_MAP: Record<string, number> = {
    '零': 0, '一': 1, '二': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
    '十': 10, '百': 100, '千': 1000, '万': 10000, '亿': 100000000
  };
  
  // 文学类型关键词（用于自动标签）
  private static readonly GENRE_KEYWORDS: string[] = [
    '玄幻', '都市', '言情', '科幻', '武侠', '仙侠', '历史', '军事', 
    '网游', '竞技', '灵异', '同人', '悬疑', '推理', '恐怖', '奇幻',
    '现实主义', '魔幻现实主义', '意识流', '存在主义', '自然主义',
    '浪漫主义', '古典', '现代', '当代', '诗歌', '散文', '戏剧'
  ];

  /**
   * 从 TXT 内容中提取元数据
   * @param content TXT 文件完整内容
   * @param fileName 文件名（用于备用标题提取）
   * @returns 提取结果
   */
  public static extract(content: string, fileName: string): TxtExtractionResult {
    logger.info(TAG, `开始提取元数据，文件名: ${fileName}, 内容长度: ${content.length}`);

    // 获取头部文本（前 5000 字符用于元数据提取）
    const headerText = content.substring(0, Math.min(5000, content.length));
    
    // 提取各项元数据
    const title = TxtMetadataExtractor.extractTitle(headerText, fileName);
    
    // 提取作者（优先从内容，其次从文件名）
    let author = TxtMetadataExtractor.extractAuthor(headerText);
    if (author === '未知作者') {
      const fileNameAuthor = TxtMetadataExtractor.extractAuthorFromFileName(fileName);
      if (fileNameAuthor.length > 0) {
        author = fileNameAuthor;
        logger.info(TAG, `从文件名提取到作者: ${author}`);
      }
    }
    
    const description = TxtMetadataExtractor.extractDescription(headerText);
    const tags = TxtMetadataExtractor.extractTags(headerText);
    const characters = TxtMetadataExtractor.extractCharacters(headerText);
    
    // 自动检测文学类型标签
    const genreTags = TxtMetadataExtractor.detectGenreTags(headerText, title);
    for (const gt of genreTags) {
      if (!tags.includes(gt)) {
        tags.push(gt);
      }
    }
    
    // 提取章节信息
    const chapters = TxtMetadataExtractor.extractChapters(content);
    
    // 计算头部结束位置
    const headerEndPosition = TxtMetadataExtractor.findHeaderEndPosition(content, chapters);

    // 构建元数据
    const metadata: EBookMetadata = {
      title: title,
      author: author,
      publisher: '',
      publishDate: '',
      isbn: '',
      language: 'zh-CN',
      description: description,
      coverImagePath: '',
      tags: tags,
      rating: 0
    };

    // 将主角信息添加到标签
    if (characters.protagonists.length > 0) {
      const protagonistTags: string[] = [];
      for (const p of characters.protagonists) {
        protagonistTags.push(`主角:${p}`);
      }
      for (const pt of protagonistTags) {
        metadata.tags.push(pt);
      }
    }

    logger.info(TAG, `元数据提取完成: 标题="${title}", 作者="${author}", 标签=${tags.length}个, 章节=${chapters.length}个`);

    return {
      metadata,
      chapters,
      headerEndPosition,
      rawHeaderText: headerText
    };
  }

  /**
   * 提取标题（增强版，支持多种格式）
   */
  private static extractTitle(headerText: string, fileName: string): string {
    // 清理头部文本（移除广告等）
    const cleanedHeader = TxtMetadataExtractor.cleanHeaderText(headerText);
    
    // 1. 尝试从内容中提取书名号格式
    for (const pattern of TxtMetadataExtractor.TITLE_PATTERNS) {
      const match = cleanedHeader.match(pattern);
      if (match) {
        // 处理多个捕获组的情况
        const title = (match[2] || match[1] || '').trim();
        if (title.length > 0 && title.length < 100 && !TxtMetadataExtractor.isSkipLine(title)) {
          logger.info(TAG, `从内容提取到标题: ${title}`);
          return title;
        }
      }
    }
    
    // 2. 尝试从第一行非空行提取（经典文学作品常见格式）
    const lines = cleanedHeader.split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.length > 0 && trimmed.length < 50) {
        // 跳过广告、网站信息等
        if (TxtMetadataExtractor.isSkipLine(trimmed)) continue;
        // 跳过作者行
        if (/^作者[：:]/.test(trimmed)) continue;
        // 跳过章节标题
        if (/^第[0-9一二三四五六七八九十百千]+[章回卷节集部篇]/.test(trimmed)) continue;
        // 跳过目录标记
        if (/^(目录|序|前言|引子|楔子)$/.test(trimmed)) continue;
        
        // 可能是标题
        logger.info(TAG, `从首行提取到标题: ${trimmed}`);
        return trimmed;
      }
    }

    // 3. 尝试从文件名提取
    return TxtMetadataExtractor.extractTitleFromFileName(fileName);
  }
  
  /**
   * 从文件名提取标题
   */
  private static extractTitleFromFileName(fileName: string): string {
    // 移除时间戳前缀（如 1764782701130_）
    let cleanName = fileName.replace(/^\d{10,}_/, '');
    
    // 尝试提取书名号内容
    const bookNameMatch = cleanName.match(/《([^》]+)》/);
    if (bookNameMatch && bookNameMatch[1]) {
      logger.info(TAG, `从文件名书名号提取到标题: ${bookNameMatch[1]}`);
      return bookNameMatch[1].trim();
    }
    
    // 尝试提取"年份+作者：书名"格式
    const yearAuthorMatch = cleanName.match(/^\d{4}[^：:]*[：:](.+?)(?:\.|$)/);
    if (yearAuthorMatch && yearAuthorMatch[1]) {
      const title = yearAuthorMatch[1].replace(/\.(txt|TXT)$/, '').trim();
      if (title.length > 0) {
        logger.info(TAG, `从年份格式提取到标题: ${title}`);
        return title;
      }
    }
    
    // 移除扩展名和作者信息
    let title = cleanName.replace(/\.(txt|TXT)$/, '');
    title = title.replace(/作者[：:].+$/, '').trim();
    title = title.replace(/^《|》$/g, '').trim();
    // 移除年份前缀
    title = title.replace(/^\d{4}/, '').trim();
    
    logger.info(TAG, `使用文件名作为标题: ${title}`);
    return title || '未知书名';
  }
  
  /**
   * 清理头部文本（移除广告、网站信息等）
   */
  private static cleanHeaderText(text: string): string {
    const lines = text.split('\n');
    const cleanedLines: string[] = [];
    
    for (const line of lines) {
      const trimmed = line.trim();
      if (!TxtMetadataExtractor.isSkipLine(trimmed)) {
        cleanedLines.push(line);
      }
    }
    
    return cleanedLines.join('\n');
  }
  
  /**
   * 检查是否是需要跳过的行
   */
  private static isSkipLine(line: string): boolean {
    for (const pattern of TxtMetadataExtractor.SKIP_LINE_PATTERNS) {
      if (pattern.test(line)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 提取作者（增强版，支持多种格式）
   */
  private static extractAuthor(headerText: string): string {
    // 清理头部文本
    const cleanedHeader = TxtMetadataExtractor.cleanHeaderText(headerText);
    
    for (const pattern of TxtMetadataExtractor.AUTHOR_PATTERNS) {
      const match = cleanedHeader.match(pattern);
      if (match) {
        // 处理多个捕获组
        const author = (match[2] || match[1] || '').trim();
        // 过滤掉明显不是作者名的内容
        if (author.length > 0 && author.length < 50 && 
            !author.includes('http') && 
            !author.includes('www') &&
            !/^\d+$/.test(author)) {
          logger.info(TAG, `提取到作者: ${author}`);
          return author;
        }
      }
    }
    return '未知作者';
  }
  
  /**
   * 从文件名提取作者
   */
  private static extractAuthorFromFileName(fileName: string): string {
    // 移除时间戳前缀
    let cleanName = fileName.replace(/^\d{10,}_/, '');
    
    // 尝试提取"《书名》作者：xxx"格式
    const authorMatch = cleanName.match(/作者[：:]([^.]+)/);
    if (authorMatch && authorMatch[1]) {
      const author = authorMatch[1].replace(/\.(txt|TXT)$/, '').trim();
      if (author.length > 0 && author.length < 50) {
        return author;
      }
    }
    
    // 尝试提取"年份+作者：书名"格式
    const yearAuthorMatch = cleanName.match(/^\d{4}([^：:]+)[：:]/);
    if (yearAuthorMatch && yearAuthorMatch[1]) {
      const author = yearAuthorMatch[1].trim();
      if (author.length > 0 && author.length < 50) {
        return author;
      }
    }
    
    return '';
  }
  
  /**
   * 自动检测文学类型标签
   */
  private static detectGenreTags(headerText: string, title: string): string[] {
    const detectedTags: string[] = [];
    const textToCheck = (headerText + ' ' + title).toLowerCase();
    
    for (const keyword of TxtMetadataExtractor.GENRE_KEYWORDS) {
      if (textToCheck.includes(keyword.toLowerCase())) {
        detectedTags.push(keyword);
      }
    }
    
    // 检测特殊类型
    if (/诺贝尔/.test(textToCheck)) {
      detectedTags.push('诺贝尔文学奖');
    }
    if (/译|翻译/.test(textToCheck)) {
      detectedTags.push('翻译作品');
    }
    if (/经典|名著/.test(textToCheck)) {
      detectedTags.push('经典文学');
    }
    
    return detectedTags;
  }

  /**
   * 提取简介/文案
   */
  private static extractDescription(headerText: string): string {
    let description = '';

    // 尝试提取文案/简介
    for (const pattern of TxtMetadataExtractor.DESCRIPTION_PATTERNS) {
      const match = headerText.match(pattern);
      if (match && match[1]) {
        description = match[1].trim();
        break;
      }
    }

    // 尝试提取 VIP 推荐语作为补充
    if (description.length < 50) {
      for (const pattern of TxtMetadataExtractor.VIP_RECOMMEND_PATTERNS) {
        const match = headerText.match(pattern);
        if (match && match[1]) {
          const vipDesc = match[1].trim();
          if (vipDesc.length > description.length) {
            description = vipDesc;
          }
          break;
        }
      }
    }

    // 尝试提取一句话简介
    const oneLineMatch = headerText.match(TxtMetadataExtractor.ONE_LINE_SUMMARY_PATTERN);
    if (oneLineMatch && oneLineMatch[1]) {
      const oneLine = oneLineMatch[1].trim();
      if (description.length === 0) {
        description = oneLine;
      } else if (!description.includes(oneLine)) {
        description = oneLine + '\n\n' + description;
      }
    }

    // 清理描述文本
    description = TxtMetadataExtractor.cleanDescription(description);

    if (description.length > 0) {
      logger.info(TAG, `提取到简介: ${description.substring(0, 100)}...`);
    }

    return description;
  }

  /**
   * 清理描述文本
   */
  private static cleanDescription(text: string): string {
    return text
      // 移除广告链接
      .replace(/B\s*站.*?www\.[^\s]+/gi, '')
      .replace(/https?:\/\/[^\s]+/gi, '')
      // 移除多余空白
      .replace(/[　\s]+/g, ' ')
      .replace(/\n{3,}/g, '\n\n')
      // 移除首尾空白
      .trim();
  }

  /**
   * 提取标签
   */
  private static extractTags(headerText: string): string[] {
    const tags: string[] = [];

    for (const pattern of TxtMetadataExtractor.TAG_PATTERNS) {
      const match = headerText.match(pattern);
      if (match && match[1]) {
        // 分割标签（支持多种分隔符）
        const tagStr = match[1].trim();
        const splitTags = tagStr.split(/[,，、\s]+/).filter(t => t.length > 0 && t.length < 20);
        for (const st of splitTags) {
          tags.push(st);
        }
      }
    }

    // 尝试提取立意作为标签
    const themeMatch = headerText.match(TxtMetadataExtractor.THEME_PATTERN);
    if (themeMatch && themeMatch[1]) {
      const theme = themeMatch[1].trim();
      if (theme.length > 0 && theme.length < 20) {
        tags.push(theme);
      }
    }

    // 去重
    const uniqueTags: string[] = [];
    const seen = new Set<string>();
    for (const tag of tags) {
      if (!seen.has(tag)) {
        seen.add(tag);
        uniqueTags.push(tag);
      }
    }
    logger.info(TAG, `提取到标签: ${uniqueTags.join(', ')}`);
    return uniqueTags;
  }

  /**
   * 提取主角/配角信息
   */
  private static extractCharacters(headerText: string): CharacterInfo {
    const result: CharacterInfo = {
      protagonists: [],
      supporting: [],
      others: []
    };

    // 提取主角
    const protagonistMatch = headerText.match(/主角[：:]\s*([^┃|│\n]+)/);
    if (protagonistMatch && protagonistMatch[1]) {
      const chars = protagonistMatch[1].split(/[,，、\s]+/).filter(c => c.length > 0 && c.length < 20);
      result.protagonists = chars;
    }

    // 提取配角
    const supportingMatch = headerText.match(/配角[：:]\s*([^┃|│\n]+)/);
    if (supportingMatch && supportingMatch[1]) {
      const chars = supportingMatch[1].split(/[,，、\s]+/).filter(c => c.length > 0 && c.length < 20);
      result.supporting = chars;
    }

    logger.info(TAG, `提取到角色: 主角=${result.protagonists.join(',')}, 配角=${result.supporting.join(',')}`);
    return result;
  }

  /**
   * 提取章节信息（增强版，支持多种格式）
   */
  private static extractChapters(content: string): TxtChapterInfo[] {
    const chapters: TxtChapterInfo[] = [];
    const chapterMatches: ChapterMatchInfo[] = [];
    let match: RegExpExecArray | null;

    // 1. 尝试标准中文章节格式：第X章/回/卷/节/集/部/篇
    const mainPattern = /^[　\s]*第\s*([0-9零一二三四五六七八九十百千万亿]+)\s*[章回卷节集部篇]\s*(.*)$/gm;
    while ((match = mainPattern.exec(content)) !== null) {
      const chapterNumStr = match[1];
      const chapterTitle = match[2]?.trim() || '';
      const chapterNum = TxtMetadataExtractor.parseChapterNumber(chapterNumStr);
      
      const matchInfo: ChapterMatchInfo = {
        index: match.index,
        title: `第${chapterNumStr}章 ${chapterTitle}`.trim(),
        number: chapterNum
      };
      chapterMatches.push(matchInfo);
    }

    // 2. 如果没有找到，尝试英文章节格式
    if (chapterMatches.length === 0) {
      const chapterPattern = /^[　\s]*Chapter\s+(\d+)[：:\s]*(.*)$/gim;
      while ((match = chapterPattern.exec(content)) !== null) {
        const chapterNum = parseInt(match[1], 10);
        const chapterTitle = match[2]?.trim() || '';
        
        const matchInfo: ChapterMatchInfo = {
          index: match.index,
          title: `Chapter ${chapterNum} ${chapterTitle}`.trim(),
          number: chapterNum
        };
        chapterMatches.push(matchInfo);
      }
    }
    
    // 3. 如果还没有找到，尝试特殊符号格式：◎卷一、◎章节名
    if (chapterMatches.length === 0) {
      const specialPattern = /^[　\s]*◎卷?([0-9零一二三四五六七八九十]+)?\s*(.*)$/gm;
      while ((match = specialPattern.exec(content)) !== null) {
        const chapterNumStr = match[1] || '';
        const chapterTitle = match[2]?.trim() || '';
        if (chapterTitle.length < 2 || chapterTitle.length > 30) continue;
        
        const chapterNum = chapterNumStr ? TxtMetadataExtractor.parseChapterNumber(chapterNumStr) : chapterMatches.length + 1;
        
        const matchInfo: ChapterMatchInfo = {
          index: match.index,
          title: chapterNumStr ? `卷${chapterNumStr} ${chapterTitle}`.trim() : chapterTitle,
          number: chapterNum
        };
        chapterMatches.push(matchInfo);
      }
    }
    
    // 4. 如果还没有找到，尝试数字格式：1. xxx 或 1、xxx
    if (chapterMatches.length === 0) {
      const numPattern = /^[　\s]*(\d+)[、.．]\s*(.{2,30})$/gm;
      while ((match = numPattern.exec(content)) !== null) {
        const chapterNum = parseInt(match[1], 10);
        const chapterTitle = match[2]?.trim() || '';
        // 过滤掉明显不是章节标题的内容
        if (/^[0-9]+$/.test(chapterTitle)) continue;
        if (chapterTitle.includes('http')) continue;
        
        const matchInfo: ChapterMatchInfo = {
          index: match.index,
          title: `${chapterNum}. ${chapterTitle}`.trim(),
          number: chapterNum
        };
        chapterMatches.push(matchInfo);
      }
    }
    
    // 5. 如果还没有找到，尝试第X部分格式
    if (chapterMatches.length === 0) {
      const partPattern = /^[　\s]*第(\d+)部分\s*(.*)$/gm;
      while ((match = partPattern.exec(content)) !== null) {
        const chapterNum = parseInt(match[1], 10);
        const chapterTitle = match[2]?.trim() || '';
        
        const matchInfo: ChapterMatchInfo = {
          index: match.index,
          title: `第${chapterNum}部分 ${chapterTitle}`.trim(),
          number: chapterNum
        };
        chapterMatches.push(matchInfo);
      }
    }

    // 构建章节信息
    for (let i = 0; i < chapterMatches.length; i++) {
      const current = chapterMatches[i];
      const next = chapterMatches[i + 1];
      
      chapters.push({
        title: current.title,
        chapterNumber: current.number,
        startPosition: current.index,
        endPosition: next ? next.index : content.length
      });
    }

    logger.info(TAG, `提取到 ${chapters.length} 个章节`);
    return chapters;
  }

  /**
   * 解析章节编号（支持中文数字）
   */
  private static parseChapterNumber(numStr: string): number {
    // 如果是纯数字
    if (/^\d+$/.test(numStr)) {
      return parseInt(numStr, 10);
    }

    // 中文数字转换
    let result = 0;
    let temp = 0;
    let prevUnit = 1;

    for (const char of numStr) {
      const num = TxtMetadataExtractor.CHINESE_NUM_MAP[char];
      if (num === undefined) continue;

      if (num >= 10) {
        // 是单位（十、百、千、万、亿）
        if (temp === 0) temp = 1;
        if (num >= 10000) {
          result = (result + temp) * num;
          temp = 0;
        } else {
          temp *= num;
          if (num < prevUnit) {
            result += temp;
            temp = 0;
          }
        }
        prevUnit = num;
      } else {
        // 是数字
        temp = temp * 10 + num;
      }
    }

    return result + temp;
  }

  /**
   * 查找头部信息结束位置
   */
  private static findHeaderEndPosition(content: string, chapters: TxtChapterInfo[]): number {
    // 如果有章节，返回第一章的起始位置
    if (chapters.length > 0) {
      return chapters[0].startPosition;
    }

    // 尝试查找"正文"标记
    const zhengwenMatch = content.match(/^[　\s]*正文[　\s]*$/m);
    if (zhengwenMatch) {
      return zhengwenMatch.index! + zhengwenMatch[0].length;
    }

    // 默认返回前 2000 字符作为头部
    return Math.min(2000, content.length);
  }

  /**
   * 快速提取（仅提取基本元数据，不解析章节）
   * 用于书籍列表预览
   */
  public static quickExtract(headerText: string, fileName: string): EBookMetadata {
    const title = TxtMetadataExtractor.extractTitle(headerText, fileName);
    const author = TxtMetadataExtractor.extractAuthor(headerText);
    const tags = TxtMetadataExtractor.extractTags(headerText);

    return {
      title,
      author,
      publisher: '',
      publishDate: '',
      isbn: '',
      language: 'zh-CN',
      description: '',
      coverImagePath: '',
      tags,
      rating: 0
    };
  }
}
