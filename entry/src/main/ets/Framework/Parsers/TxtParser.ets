import { SafeFileUtils } from '../../Utils/SafeFileUtils';
// 文件路径: entry/src/main/ets/Framework/Parsers/TxtParser.ets
// 职责: TXT格式电子书解析器

import { EBookParser } from './EBookParser';
import { EBook, EBookFormat, EBookMetadata, EBookChapter, EBookStatus } from '../../Models/EBookModels';
import { logger } from '../../Utils/Logger';
import { fileIo } from '@kit.CoreFileKit';
import { getNovelTxtTocRuleManager } from '../Novel/NovelTxtTocRuleManager';
import { getNovelContentProcessor } from '../Novel/NovelContentProcessor';
import { ReplaceScope } from '../Novel/NovelReplaceRuleManager';

const TAG = 'TxtParser';

/**
 * TXT解析器
 * 支持自动章节识别和分割
 */
export class TxtParser extends EBookParser {
  // 默认章节标题正则表达式（作为后备）
  private readonly DEFAULT_CHAPTER_PATTERNS: string[] = [
    '^\\s*第[0-9一二三四五六七八九十百千零]+[章节回集部卷篇]',
    '^Chapter\\s+\\d+',
    '^CHAPTER\\s+\\d+',
    '^\\d+\\.',
    '^[0-9]+、'
  ];
  
  // TXT目录规则管理器
  private txtTocRuleManager = getNovelTxtTocRuleManager();
  // 内容处理器
  private contentProcessor = getNovelContentProcessor();
  // 编译后的章节模式（从规则管理器获取）
  private compiledPattern: RegExp | null = null;

  /**
   * 解析TXT文件
   */
  async parse(filePath: string): Promise<EBook> {
    try {
      logger.info(TAG, `开始解析TXT文件: ${filePath}`);

      // 初始化TXT目录规则
      await this.initTocRules();

      // 读取文件内容
      const content = await this.readFileContent(filePath);
      
      // 提取元数据
      const metadata = await this.extractMetadata(filePath);
      
      // 分割章节
      const chapters = this.splitChapters(content, metadata.title);
      
      // 计算总字数
      const totalWordCount = content.length;
      
      // 获取文件大小
      const fileSize = this.getFileSize(filePath);
      
      // 创建EBook对象
      const bookId = this.generateId();
      const book = new EBook(
        bookId,
        EBookFormat.TXT,
        filePath,
        fileSize,
        metadata,
        chapters,
        EBookStatus.UNREAD,
        null,
        null,
        Date.now(),
        Date.now(),
        false,
        totalWordCount
      );

      logger.info(TAG, `TXT文件解析完成: ${metadata.title}, 章节数: ${chapters.length}, 字数: ${totalWordCount}`);
      return book;
    } catch (error) {
      logger.error(TAG, `解析TXT文件失败: ${String(error)}`);
      throw error;
    }
  }

  /**
   * 验证TXT格式
   */
  async validateFormat(filePath: string): Promise<boolean> {
    try {
      // 检查文件扩展名
      if (!filePath.toLowerCase().endsWith('.txt')) {
        return false;
      }

      // 尝试读取文件前1000字节
      const content = await this.readFileContent(filePath);
      if (!content || content.length === 0) {
        return false;
      }

      return true;
    } catch (error) {
      logger.error(TAG, `验证TXT格式失败: ${String(error)}`);
      return false;
    }
  }

  /**
   * 提取元数据
   */
  async extractMetadata(filePath: string): Promise<EBookMetadata> {
    // 从文件名提取标题
    const fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
    const title = fileName.substring(0, fileName.lastIndexOf('.')) || '未命名书籍';

    return {
      title: title,
      author: '未知作者',
      publisher: '',
      publishDate: '',
      isbn: '',
      language: 'zh-CN',
      description: '',
      coverImagePath: '',
      tags: [],
      rating: 0
    } as EBookMetadata;
  }

  /**
   * 初始化TXT目录规则
   */
  private async initTocRules(): Promise<void> {
    try {
      await this.txtTocRuleManager.initialize();
      this.compiledPattern = this.txtTocRuleManager.getCombinedPattern();
      logger.info(TAG, `TXT目录规则初始化完成，启用规则数: ${this.txtTocRuleManager.getEnabledRules().length}`);
    } catch (error) {
      logger.warn(TAG, `初始化TXT目录规则失败: ${String(error)}`);
    }
  }

  /**
   * 分割章节
   */
  private splitChapters(content: string, bookTitle: string): EBookChapter[] {
    const chapters: EBookChapter[] = [];
    const lines = content.split('\n');
    
    let currentChapterTitle = '';
    let currentChapterContent = '';
    let currentChapterStart = 0;
    let chapterNumber = 0;
    let position = 0;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      const lineLength = lines[i].length + 1; // +1 for newline

      // 检查是否是章节标题（优先使用规则管理器）
      if (this.isChapterTitle(line)) {
        // 保存上一章节
        if (currentChapterTitle) {
          // 有标题的正常章节
          const processedContent = this.contentProcessor.quickReplace(
            currentChapterContent,
            ReplaceScope.CONTENT
          );
          chapters.push(this.createChapter(
            bookTitle,
            chapterNumber,
            currentChapterTitle,
            processedContent,
            currentChapterStart,
            position
          ));
          chapterNumber++;
        } else if (currentChapterContent) {
          // 第一个章节标题之前的内容，作为前言/序章保存
          const processedContent = this.contentProcessor.quickReplace(
            currentChapterContent,
            ReplaceScope.CONTENT
          );
          chapters.push(this.createChapter(
            bookTitle,
            chapterNumber,
            '前言',
            processedContent,
            currentChapterStart,
            position
          ));
          chapterNumber++;
        }

        // 开始新章节
        currentChapterTitle = line;
        currentChapterContent = '';
        currentChapterStart = position;
      } else if (line.length > 0) {
        // 添加内容到当前章节
        if (currentChapterContent.length > 0) {
          currentChapterContent += '\n';
        }
        currentChapterContent += line;
      }

      position += lineLength;
    }

    // 保存最后一章
    if (currentChapterTitle || currentChapterContent) {
      const processedContent = this.contentProcessor.quickReplace(
        currentChapterContent, 
        ReplaceScope.CONTENT
      );
      chapters.push(this.createChapter(
        bookTitle,
        chapterNumber,
        currentChapterTitle || `第${chapterNumber + 1}章`,
        processedContent,
        currentChapterStart,
        position
      ));
    }

    // 如果没有识别到章节，将整本书作为一个章节
    if (chapters.length === 0) {
      const processedContent = this.contentProcessor.quickReplace(content, ReplaceScope.CONTENT);
      chapters.push(this.createChapter(
        bookTitle,
        0,
        bookTitle,
        processedContent,
        0,
        content.length
      ));
    }

    logger.info(TAG, `章节分割完成，共 ${chapters.length} 章`);
    return chapters;
  }

  /**
   * 判断是否是章节标题
   * 优先使用TXT目录规则管理器的规则
   */
  private isChapterTitle(line: string): boolean {
    if (line.length === 0 || line.length > 100) {
      return false;
    }

    // 优先使用规则管理器的编译模式
    if (this.compiledPattern) {
      // 重置正则表达式的lastIndex
      this.compiledPattern.lastIndex = 0;
      if (this.compiledPattern.test(line)) {
        return true;
      }
    }

    // 回退到默认模式
    for (let i = 0; i < this.DEFAULT_CHAPTER_PATTERNS.length; i++) {
      try {
        const pattern = new RegExp(this.DEFAULT_CHAPTER_PATTERNS[i]);
        if (pattern.test(line)) {
          return true;
        }
      } catch (error) {
        // 忽略无效的正则表达式
      }
    }

    return false;
  }

  /**
   * 创建章节对象
   */
  private createChapter(
    bookTitle: string,
    chapterNumber: number,
    title: string,
    content: string,
    startPosition: number,
    endPosition: number
  ): EBookChapter {
    return {
      id: `${bookTitle}_chapter_${chapterNumber}`,
      bookId: '',  // 将在EBook构造函数中设置
      chapterNumber: chapterNumber,
      title: title,
      content: content,
      startPosition: startPosition,
      endPosition: endPosition,
      wordCount: content.length,
      createTime: Date.now()
    } as EBookChapter;
  }

  /**
   * 获取文件大小
   */
  private getFileSize(filePath: string): number {
    try {
      let openTarget: string = filePath;
      if (!filePath.startsWith('file://') && !filePath.startsWith('/')) {
        openTarget = `/${filePath}`;
      }

      const file = SafeFileUtils.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      const stat = SafeFileUtils.statSync(file.fd);
      SafeFileUtils.closeSync(file);
      return stat.size;
    } catch (firstError) {
      try {
        if (filePath.startsWith('file://')) {
          const stripped = filePath.substring(7);
          const candidate = stripped.startsWith('/') ? stripped : `/${stripped}`;
          const file = SafeFileUtils.openSync(candidate, fileIo.OpenMode.READ_ONLY);
          const stat = SafeFileUtils.statSync(file.fd);
          SafeFileUtils.closeSync(file);
          return stat.size;
        }
        return 0;
      } catch (error) {
        logger.warn(TAG, `获取文件大小失败: ${String(error instanceof Error ? error.message : error)}`);
        return 0;
      }
    }
  }
}

