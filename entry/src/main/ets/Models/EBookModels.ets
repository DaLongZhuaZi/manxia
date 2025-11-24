// 文件路径: entry/src/main/ets/Models/EBookModels.ets
// 职责: 电子书相关的数据模型定义

/**
 * 电子书格式枚举
 */
export enum EBookFormat {
  TXT = 'TXT',
  EPUB = 'EPUB',
  MOBI = 'MOBI',
  AZW = 'AZW',
  AZW3 = 'AZW3',
  PDF = 'PDF'
}

/**
 * 电子书状态枚举
 */
export enum EBookStatus {
  UNREAD = 'UNREAD',           // 未读
  READING = 'READING',         // 阅读中
  COMPLETED = 'COMPLETED',     // 已完成
  ARCHIVED = 'ARCHIVED'        // 已归档
}

/**
 * 电子书章节信息
 */
export interface EBookChapter {
  id: string;                  // 章节ID
  bookId: string;              // 所属书籍ID
  chapterNumber: number;       // 章节编号
  title: string;               // 章节标题
  content: string;             // 章节内容
  startPosition: number;       // 在原文件中的起始位置
  endPosition: number;         // 在原文件中的结束位置
  wordCount: number;           // 字数
  createTime: number;          // 创建时间
}

/**
 * 电子书阅读进度
 */
export interface EBookReadingProgress {
  bookId: string;              // 书籍ID
  currentChapterId: string;    // 当前章节ID
  currentPosition: number;     // 当前阅读位置（字符偏移量）
  progress: number;            // 阅读进度百分比 (0-100)
  lastReadTime: number;        // 最后阅读时间
  totalReadingTime: number;    // 总阅读时长（秒）
}

/**
 * 电子书阅读设置
 */
export interface EBookReadingSettings {
  fontSize: number;            // 字体大小 (12-32)
  lineHeight: number;          // 行高 (1.0-3.0)
  fontFamily: string;          // 字体名称
  backgroundColor: string;     // 背景颜色
  textColor: string;           // 文字颜色
  pageMargin: number;          // 页边距 (10-50)
  pageMode: EBookPageMode;     // 翻页模式
  brightness: number;          // 亮度 (0-100)
  autoSave: boolean;           // 自动保存进度
  saveInterval: number;        // 自动保存间隔（秒）
}

/**
 * 电子书翻页模式
 */
export enum EBookPageMode {
  SCROLL = 'SCROLL',           // 滚动模式
  PAGE = 'PAGE',               // 分页模式
  SIMULATION = 'SIMULATION'    // 仿真翻页
}

/**
 * 电子书元数据
 */
export interface EBookMetadata {
  title: string;               // 书名
  author: string;              // 作者
  publisher: string;           // 出版社
  publishDate: string;         // 出版日期
  isbn: string;                // ISBN
  language: string;            // 语言
  description: string;         // 简介
  coverImagePath: string;      // 封面图片路径
  tags: string[];              // 标签
  rating: number;              // 评分 (0-5)
}

/**
 * 电子书主模型
 */
@Observed
export class EBook {
  id: string;                  // 书籍ID
  format: EBookFormat;         // 书籍格式
  filePath: string;            // 文件路径
  fileSize: number;            // 文件大小（字节）
  metadata: EBookMetadata;     // 元数据
  chapters: EBookChapter[];    // 章节列表
  status: EBookStatus;         // 阅读状态
  readingProgress: EBookReadingProgress; // 阅读进度
  readingSettings: EBookReadingSettings; // 阅读设置
  addTime: number;             // 添加时间
  lastUpdateTime: number;      // 最后更新时间
  isFavorite: boolean;         // 是否收藏
  totalWordCount: number;      // 总字数

  constructor(
    id: string,
    format: EBookFormat,
    filePath: string,
    fileSize: number,
    metadata: EBookMetadata,
    chapters: EBookChapter[] = [],
    status: EBookStatus = EBookStatus.UNREAD,
    readingProgress: EBookReadingProgress | null = null,
    readingSettings: EBookReadingSettings | null = null,
    addTime: number = Date.now(),
    lastUpdateTime: number = Date.now(),
    isFavorite: boolean = false,
    totalWordCount: number = 0
  ) {
    this.id = id;
    this.format = format;
    this.filePath = filePath;
    this.fileSize = fileSize;
    this.metadata = metadata;
    this.chapters = chapters;
    this.status = status;
    this.addTime = addTime;
    this.lastUpdateTime = lastUpdateTime;
    this.isFavorite = isFavorite;
    this.totalWordCount = totalWordCount;

    // 初始化阅读进度
    if (readingProgress) {
      this.readingProgress = readingProgress;
    } else {
      this.readingProgress = {
        bookId: id,
        currentChapterId: chapters.length > 0 ? chapters[0].id : '',
        currentPosition: 0,
        progress: 0,
        lastReadTime: 0,
        totalReadingTime: 0
      } as EBookReadingProgress;
    }

    // 初始化阅读设置
    if (readingSettings) {
      this.readingSettings = readingSettings;
    } else {
      this.readingSettings = {
        fontSize: 18,
        lineHeight: 1.8,
        fontFamily: 'HarmonyOS Sans',
        backgroundColor: '#FFFFFF',
        textColor: '#333333',
        pageMargin: 20,
        pageMode: EBookPageMode.PAGE,
        brightness: 100,
        autoSave: true,
        saveInterval: 30
      } as EBookReadingSettings;
    }
  }

  /**
   * 获取当前章节
   */
  getCurrentChapter(): EBookChapter | null {
    const chapter = this.chapters.find((ch: EBookChapter) => ch.id === this.readingProgress.currentChapterId);
    return chapter || null;
  }

  /**
   * 更新阅读进度
   */
  updateReadingProgress(chapterId: string, position: number): void {
    this.readingProgress.currentChapterId = chapterId;
    this.readingProgress.currentPosition = position;
    this.readingProgress.lastReadTime = Date.now();
    
    // 计算总体进度
    const chapter = this.chapters.find((ch: EBookChapter) => ch.id === chapterId);
    if (chapter) {
      const chapterIndex = this.chapters.indexOf(chapter);
      const completedChapters = chapterIndex;
      const currentChapterProgress = position / chapter.content.length;
      this.readingProgress.progress = ((completedChapters + currentChapterProgress) / this.chapters.length) * 100;
    }

    // 更新状态
    if (this.readingProgress.progress > 0 && this.readingProgress.progress < 100) {
      this.status = EBookStatus.READING;
    } else if (this.readingProgress.progress >= 100) {
      this.status = EBookStatus.COMPLETED;
    }
  }

  /**
   * 获取下一章节
   */
  getNextChapter(): EBookChapter | null {
    const currentChapter = this.getCurrentChapter();
    if (!currentChapter) {
      return null;
    }
    
    const currentIndex = this.chapters.indexOf(currentChapter);
    if (currentIndex < this.chapters.length - 1) {
      return this.chapters[currentIndex + 1];
    }
    
    return null;
  }

  /**
   * 获取上一章节
   */
  getPreviousChapter(): EBookChapter | null {
    const currentChapter = this.getCurrentChapter();
    if (!currentChapter) {
      return null;
    }
    
    const currentIndex = this.chapters.indexOf(currentChapter);
    if (currentIndex > 0) {
      return this.chapters[currentIndex - 1];
    }
    
    return null;
  }
}

/**
 * 电子书导入结果
 */
export interface EBookImportResult {
  success: boolean;            // 是否成功
  book: EBook | null;          // 导入的书籍
  error: string;               // 错误信息
  needsMetadata: boolean;      // 是否需要补充元数据
  missingFields: string[];     // 缺失的字段列表
}

/**
 * 电子书搜索过滤器
 */
export interface EBookFilter {
  format: EBookFormat | null;  // 格式筛选
  status: EBookStatus | null;  // 状态筛选
  tags: string[];              // 标签筛选
  searchKeyword: string;       // 搜索关键词
  sortBy: EBookSortType;       // 排序方式
  sortOrder: 'asc' | 'desc';   // 排序顺序
}

/**
 * 电子书排序类型
 */
export enum EBookSortType {
  ADD_TIME = 'ADD_TIME',           // 添加时间
  LAST_READ = 'LAST_READ',         // 最后阅读时间
  TITLE = 'TITLE',                 // 书名
  AUTHOR = 'AUTHOR',               // 作者
  PROGRESS = 'PROGRESS',           // 阅读进度
  FILE_SIZE = 'FILE_SIZE'          // 文件大小
}

