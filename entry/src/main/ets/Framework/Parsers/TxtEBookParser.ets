// 文件路径: entry/src/main/ets/Framework/Parsers/TxtEBookParser.ets
/**
 * TXT电子书解析器
 * 支持章节识别、内容提取和智能分段
 */

import { EBookParser } from './EBookParser';
import { EBook, EBookFormat, EBookMetadata, EBookChapter, EBookStatus } from '../../Models/EBookModels';
import { logger } from '../../Utils/Logger';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

const TAG = 'TxtEBookParser';

// 章节标题正则表达式（支持多种格式）
const CHAPTER_PATTERNS = [
  /^第\s*([0-9零一二三四五六七八九十百千万亿]+)\s*[章回卷节集部篇]\s*(.*)$/,
  /^([0-9零一二三四五六七八九十百千万亿]+)\s*[、.．·]\s*(.+)$/,
  /^Chapter\s+(\d+)[：:\s]+(.*)$/i,
  /^卷\s*([0-9零一二三四五六七八九十百千万亿]+)\s*(.*)$/,
  /^\s*(\d+)\s*[、.．·]\s*(.+)$/,
  /^[【\[]第\s*([0-9零一二三四五六七八九十百千万亿]+)\s*[章回卷节集部篇][】\]]\s*(.*)$/,
];

/**
 * TXT电子书解析器实现
 */
export class TxtEBookParser extends EBookParser {
  private encoding: string = 'utf-8';

  constructor(filePath: string) {
    super(filePath, EBookFormat.TXT);
  }

  /**
   * 解析TXT电子书
   */
  public async parse(): Promise<EBook> {
    logger.info(TAG, `开始解析TXT文件: ${this.filePath}`);

    try {
      // 1. 读取文件内容
      const content = await this.readFileContent();
      logger.debug(TAG, `文件内容长度: ${content.length} 字符`);

      // 2. 检测编码（简单实现）
      this.detectEncoding(content);

      // 3. 获取文件大小
      const fileSize = await this.getFileSize();

      // 4. 提取元数据
      const metadata = this.extractMetadata(content);
      logger.debug(TAG, `提取的元数据: ${JSON.stringify(metadata)}`);

      // 5. 创建电子书对象
      const ebook = this.generateDefaultEBook(this.filePath, EBookFormat.TXT, metadata);
      ebook.fileSize = fileSize;

      // 6. 分割章节
      const chapters = this.splitIntoChapters(content, ebook.id);
      ebook.chapters = chapters;

      // 7. 计算总字数
      ebook.totalWordCount = this.calculateTotalWordCount(chapters);

      logger.info(TAG, `TXT文件解析完成: ${metadata.title}, 章节数: ${chapters.length}, 总字数: ${ebook.totalWordCount}`);

      return ebook;
    } catch (error) {
      logger.error(TAG, `解析TXT文件失败: ${String(error instanceof Error ? error.message : error)}`);
      throw error as Error;
    }
  }

  /**
   * 读取文件内容
   */
  private async readFileContent(): Promise<string> {
    try {
      let openTarget: string = this.filePath;
      if (!this.filePath.startsWith('file://') && !this.filePath.startsWith('/')) {
        openTarget = `/${this.filePath}`;
      }

      let file = fileIo.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      let stat = fileIo.statSync(file.fd);
      let buffer = new ArrayBuffer(stat.size);
      let readLen = fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);

      if (readLen !== stat.size) {
        throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
      }

      const decoder = new util.TextDecoder(this.encoding);
      const text = decoder.decodeToString(new Uint8Array(buffer));
      return text;
    } catch (firstError) {
      const firstMsg = firstError instanceof Error ? firstError.message : String(firstError);
      try {
        if (this.filePath.startsWith('file://')) {
          const stripped = this.filePath.substring(7);
          const candidate = stripped.startsWith('/') ? stripped : `/${stripped}`;
          const file = fileIo.openSync(candidate, fileIo.OpenMode.READ_ONLY);
          const stat = fileIo.statSync(file.fd);
          const buffer = new ArrayBuffer(stat.size);
          const readLen = fileIo.readSync(file.fd, buffer);
          fileIo.closeSync(file);

          if (readLen !== stat.size) {
            throw new Error(`读取长度不一致: 期望 ${stat.size} 实际 ${readLen}`);
          }
          const decoder = new util.TextDecoder(this.encoding);
          const text = decoder.decodeToString(new Uint8Array(buffer));
          return text;
        }
        throw new Error(firstMsg);
      } catch (error) {
        const errorMsg = error instanceof Error ? error.message : String(error);
        logger.error(TAG, `读取文件失败: ${errorMsg}`);
        throw new Error(`无法读取文件: ${this.filePath}`);
      }
    }
  }

  /**
   * 获取文件大小
   */
  private async getFileSize(): Promise<number> {
    try {
      let openTarget: string = this.filePath;
      if (!this.filePath.startsWith('file://') && !this.filePath.startsWith('/')) {
        openTarget = `/${this.filePath}`;
      }

      let file = fileIo.openSync(openTarget, fileIo.OpenMode.READ_ONLY);
      let stat = fileIo.statSync(file.fd);
      fileIo.closeSync(file);
      return stat.size;
    } catch (firstError) {
      try {
        if (this.filePath.startsWith('file://')) {
          const stripped = this.filePath.substring(7);
          const candidate = stripped.startsWith('/') ? stripped : `/${stripped}`;
          const file = fileIo.openSync(candidate, fileIo.OpenMode.READ_ONLY);
          const stat = fileIo.statSync(file.fd);
          fileIo.closeSync(file);
          return stat.size;
        }
        return 0;
      } catch (error) {
        logger.warn(TAG, `获取文件大小失败: ${String(error instanceof Error ? error.message : error)}`);
        return 0;
      }
    }
  }

  /**
   * 检测编码（简单实现）
   */
  private detectEncoding(content: string): void {
    // 简单的编码检测逻辑
    // 实际项目中可以使用更复杂的编码检测库
    if (content.includes('�') || content.includes('\ufffd')) {
      logger.warn(TAG, '可能存在编码问题，尝试使用GBK编码');
      this.encoding = 'gbk';
    }
  }

  /**
   * 提取元数据
   */
  private extractMetadata(content: string): EBookMetadata {
    const fileName = this.getFileNameFromPath(this.filePath);
    const lines = content.split('\n').slice(0, 50); // 只检查前50行

    // 提取书名
    let title = this.extractTitle(lines, fileName);

    // 提取作者
    let author = this.extractAuthor(lines);

    // 提取简介
    let description = this.extractDescription(content);

    // 从文件名提取可能的标签
    const tags = this.extractTagsFromFileName(fileName);

    return {
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
  }

  /**
   * 提取书名
   */
  private extractTitle(lines: string[], fallbackFileName: string): string {
    // 1. 查找"书名:"、"标题:"等标记
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.match(/^(书名|标题|名称|Title)[：:]/)) {
        const title = trimmed.replace(/^(书名|标题|名称|Title)[：:]\s*/, '').trim();
        if (title.length > 0 && title.length < 100) {
          return title;
        }
      }
    }

    // 2. 使用第一个非空行（如果不是章节标题）
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed.length > 0 && trimmed.length < 100) {
        // 检查是否为章节标题
        let isChapterTitle = false;
        for (const pattern of CHAPTER_PATTERNS) {
          if (pattern.test(trimmed)) {
            isChapterTitle = true;
            break;
          }
        }
        if (!isChapterTitle) {
          return trimmed;
        }
      }
    }

    // 3. 使用文件名
    return this.extractTitleFromFileName(fallbackFileName);
  }

  /**
   * 提取作者
   */
  private extractAuthor(lines: string[]): string {
    for (const line of lines) {
      const trimmed = line.trim();
      const match = trimmed.match(/^(作者|作家|著|Author|by)[：:]\s*(.+)$/i);
      if (match && match[2]) {
        const author = match[2].trim();
        if (author.length > 0 && author.length < 50) {
          return author;
        }
      }
    }
    return '未知作者';
  }

  /**
   * 提取简介
   */
  private extractDescription(content: string): string {
    const lines = content.split('\n');
    let descLines: string[] = [];
    let foundDesc = false;

    for (let i = 0; i < Math.min(lines.length, 100); i++) {
      const trimmed = lines[i].trim();
      
      if (trimmed.match(/^(简介|内容简介|内容提要|Description)[：:]/)) {
        foundDesc = true;
        const desc = trimmed.replace(/^(简介|内容简介|内容提要|Description)[：:]\s*/, '').trim();
        if (desc.length > 0) {
          descLines.push(desc);
        }
        continue;
      }

      if (foundDesc) {
        if (trimmed.length === 0) {
          break; // 遇到空行，简介结束
        }
        // 检查是否遇到章节标题
        let isChapterTitle = false;
        for (const pattern of CHAPTER_PATTERNS) {
          if (pattern.test(trimmed)) {
            isChapterTitle = true;
            break;
          }
        }
        if (isChapterTitle) {
          break;
        }
        descLines.push(trimmed);
        if (descLines.join('').length > 500) {
          break; // 简介最多500字
        }
      }
    }

    const description = descLines.join(' ').substring(0, 500);
    return description || '暂无简介';
  }

  /**
   * 从文件名提取标签
   */
  private extractTagsFromFileName(fileName: string): string[] {
    const tags: string[] = ['TXT'];
    
    // 检查文件名中的常见标签
    const tagKeywords = ['玄幻', '都市', '言情', '科幻', '武侠', '仙侠', '历史', '军事', '网游', '竞技', '灵异', '同人'];
    for (const keyword of tagKeywords) {
      if (fileName.includes(keyword)) {
        tags.push(keyword);
      }
    }

    return tags;
  }

  /**
   * 分割章节
   */
  private splitIntoChapters(content: string, bookId: string): EBookChapter[] {
    const chapters: EBookChapter[] = [];
    const lines = content.split('\n');
    
    let currentChapterTitle = '正文';
    let currentChapterNumber = 0;
    let currentChapterLines: string[] = [];
    let startPosition = 0;
    const now = Date.now();

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmed = line.trim();
      
      // 检查是否为章节标题
      let matchedChapter: RegExpMatchArray | null = null;
      for (const pattern of CHAPTER_PATTERNS) {
        const match = trimmed.match(pattern);
        if (match) {
          matchedChapter = match;
          break;
        }
      }

      if (matchedChapter && currentChapterLines.length > 0) {
        // 保存当前章节
        const chapterContent = currentChapterLines.join('\n').trim();
        if (chapterContent.length > 0) {
          const chapter: EBookChapter = {
            id: `${bookId}_chapter_${currentChapterNumber}`,
            bookId: bookId,
            chapterNumber: currentChapterNumber,
            title: currentChapterTitle,
            content: chapterContent,
            startPosition: startPosition,
            endPosition: startPosition + chapterContent.length,
            wordCount: this.countWords(chapterContent),
            createTime: now
          };
          chapters.push(chapter);
          currentChapterNumber++;
        }

        // 开始新章节
        currentChapterTitle = trimmed;
        currentChapterLines = [];
        startPosition += chapterContent.length + 1;
      } else {
        // 添加到当前章节
        currentChapterLines.push(line);
      }
    }

    // 保存最后一个章节
    if (currentChapterLines.length > 0) {
      const chapterContent = currentChapterLines.join('\n').trim();
      if (chapterContent.length > 0) {
        const chapter: EBookChapter = {
          id: `${bookId}_chapter_${currentChapterNumber}`,
          bookId: bookId,
          chapterNumber: currentChapterNumber,
          title: currentChapterTitle,
          content: chapterContent,
          startPosition: startPosition,
          endPosition: startPosition + chapterContent.length,
          wordCount: this.countWords(chapterContent),
          createTime: now
        };
        chapters.push(chapter);
      }
    }

    // 如果没有识别到章节，将整个文件作为一个章节
    if (chapters.length === 0) {
      const fullContent = content.trim();
      const chapter: EBookChapter = {
        id: `${bookId}_chapter_0`,
        bookId: bookId,
        chapterNumber: 0,
        title: '正文',
        content: fullContent,
        startPosition: 0,
        endPosition: fullContent.length,
        wordCount: this.countWords(fullContent),
        createTime: now
      };
      chapters.push(chapter);
    }

    logger.info(TAG, `识别到 ${chapters.length} 个章节`);
    return chapters;
  }

  /**
   * 计算字数
   */
  private countWords(text: string): number {
    // 移除空白字符
    const cleanText = text.replace(/\s/g, '');
    return cleanText.length;
  }

  /**
   * 计算总字数
   */
  private calculateTotalWordCount(chapters: EBookChapter[]): number {
    let total = 0;
    for (const chapter of chapters) {
      total += chapter.wordCount;
    }
    return total;
  }
}

