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
  currentChapterIndex: number; // 当前章节索引（用于 Reader Kit startPlay）
  currentPosition: number;     // 当前阅读位置（字符偏移量）
  domPos: string;              // Reader Kit DOM 位置（用于精确恢复阅读位置）
  progress: number;            // 阅读进度百分比 (0-100)
  lastReadTime: number;        // 最后阅读时间
  totalReadingTime: number;    // 总阅读时长（秒）
}

/**
 * 电子书阅读设置
 * 基于 HarmonyOS Reader Kit ReaderSetting 接口
 */
export interface EBookReadingSettings {
  // 字体设置
  fontSize: number;            // 字体大小 (12-48)
  fontFamily: string;          // 字体名称（如 'HarmonyOS Sans'）
  fontPath: string;            // 自定义字体文件路径（可选）
  fontWeight: number;          // 字体粗细 (100-900，默认400)
  
  // 排版设置
  lineHeight: number;          // 行高倍数 (1.0-3.0)
  
  // 颜色主题设置
  backgroundColor: string;     // 背景颜色（十六进制，如 '#FFFFFF'）
  textColor: string;           // 文字颜色（十六进制，如 '#333333'）
  themeBgImage: string;        // 主题背景图片路径（可选）
  nightMode: boolean;          // 夜间模式
  followSystemTheme: boolean;  // 是否跟随系统主题（默认true，选择护眼/羊皮纸等自定义主题后变为false）
  
  // 翻页设置
  pageMargin: number;          // 页边距 (10-50)
  pageMode: EBookPageMode;     // 翻页模式（仿真翻页/横向滑动）
  
  // 系统设置
  brightness: number;          // 亮度 (0-100)
  autoSave: boolean;           // 自动保存进度
  saveInterval: number;        // 自动保存间隔（秒）
}

/**
 * 电子书翻页模式
 * 对应 Reader Kit 的 flipMode
 */
export enum EBookPageMode {
  SIMULATION = '0',            // 仿真翻页（默认）
  HORIZONTAL = '1'             // 横向滑动
}

/**
 * 预设主题
 */
export interface EBookThemePreset {
  name: string;                // 主题名称
  backgroundColor: string;     // 背景颜色
  textColor: string;           // 文字颜色
  themeBgImage: string;        // 背景图片（可选）
  nightMode: boolean;          // 是否夜间模式
}

/**
 * 预设主题列表
 * 注意：'默认' 和 '夜间' 主题会跟随系统主题，其他主题不会
 */
export const EBOOK_THEME_PRESETS: EBookThemePreset[] = [
  { name: '默认', backgroundColor: '#FFFFFF', textColor: '#000000', themeBgImage: '', nightMode: false },
  { name: '护眼', backgroundColor: '#C7EDCC', textColor: '#2B2B2B', themeBgImage: '', nightMode: false },
  { name: '羊皮纸', backgroundColor: '#F4ECD8', textColor: '#5C4B37', themeBgImage: '', nightMode: false },
  { name: '夜间', backgroundColor: '#1E1E1E', textColor: '#D4D4D4', themeBgImage: '', nightMode: true }
];

/**
 * 默认电子书阅读设置
 * 注意：fontSize 使用 18，这是 Reader Kit 推荐的默认值
 */
export const DEFAULT_EBOOK_READING_SETTINGS: EBookReadingSettings = {
  // 字体设置
  fontSize: 18,                // 默认字体大小
  fontFamily: 'HarmonyOS Sans',
  fontPath: '',
  fontWeight: 400,
  // 排版设置
  lineHeight: 1.5,             // 默认行高（1.5 更紧凑，适合阅读）
  // 颜色主题设置
  backgroundColor: '#FFFFFF',
  textColor: '#000000',
  themeBgImage: '',
  nightMode: false,
  followSystemTheme: true,     // 默认跟随系统主题
  // 翻页设置
  pageMargin: 16,              // 默认页边距（16px 更紧凑）
  pageMode: EBookPageMode.SIMULATION,
  // 系统设置
  brightness: 100,
  autoSave: true,
  saveInterval: 30
};

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
        currentChapterIndex: 0,
        currentPosition: 0,
        domPos: '',
        progress: 0,
        lastReadTime: 0,
        totalReadingTime: 0
      } as EBookReadingProgress;
    }

    // 初始化阅读设置（使用默认设置常量）
    if (readingSettings) {
      this.readingSettings = readingSettings;
    } else {
      this.readingSettings = {
        fontSize: DEFAULT_EBOOK_READING_SETTINGS.fontSize,
        fontFamily: DEFAULT_EBOOK_READING_SETTINGS.fontFamily,
        fontPath: DEFAULT_EBOOK_READING_SETTINGS.fontPath,
        fontWeight: DEFAULT_EBOOK_READING_SETTINGS.fontWeight,
        lineHeight: DEFAULT_EBOOK_READING_SETTINGS.lineHeight,
        backgroundColor: DEFAULT_EBOOK_READING_SETTINGS.backgroundColor,
        textColor: DEFAULT_EBOOK_READING_SETTINGS.textColor,
        themeBgImage: DEFAULT_EBOOK_READING_SETTINGS.themeBgImage,
        nightMode: DEFAULT_EBOOK_READING_SETTINGS.nightMode,
        followSystemTheme: DEFAULT_EBOOK_READING_SETTINGS.followSystemTheme,
        pageMargin: DEFAULT_EBOOK_READING_SETTINGS.pageMargin,
        pageMode: DEFAULT_EBOOK_READING_SETTINGS.pageMode,
        brightness: DEFAULT_EBOOK_READING_SETTINGS.brightness,
        autoSave: DEFAULT_EBOOK_READING_SETTINGS.autoSave,
        saveInterval: DEFAULT_EBOOK_READING_SETTINGS.saveInterval
      };
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

