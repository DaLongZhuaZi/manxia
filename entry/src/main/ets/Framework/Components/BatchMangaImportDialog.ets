import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
// 文件路径: entry/src/main/ets/Framework/Components/BatchMangaImportDialog.ets
/**
 * 批量漫画导入配置对话框
 * 支持智能分组、批量配置、章节识别等功能
 */

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { FontAwareHelper, FontAwareState } from './FontAware';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { AppColors } from '../Theme/AppColors';
import { fileIo } from '@kit.CoreFileKit';
import { MangaImportMode, ChapterInfo, ParsedArchiveStructure, PrefilledComicInfo, ExistingMangaCandidate } from './MangaImportDialog';
import { ScraperDialog, ScraperDialogConfig, ScraperDialogResult } from './ScraperDialog';
import { ScraperContentType } from 'manxia_core/src/main/ets/Framework/Scraper/ScraperTypes';
import { ImportFlowContentType, ImportFlowEvent, ImportFlowEventType, ImportFlowSeverity } from '../Import/ImportFlowTypes';

const TAG = 'BatchMangaImportDialog';

/**
 * 批量导入文件信息
 */
export interface BatchFileInfo {
  /** 文件URI */
  fileUri: string;
  /** 文件名 */
  fileName: string;
  /** 解析后的结构 */
  parsedStructure: ParsedArchiveStructure | null;
  /** 预填充信息 */
  prefilledInfo: PrefilledComicInfo | null;
  /** 推测的漫画标题（用于分组） */
  inferredTitle: string;
  /** 推测的章节编号（0 表示无法推测） */
  inferredChapterNumber: number;
  /** 推测的卷号（0 表示无卷号信息） */
  inferredVolumeNumber: number;
  /** 文件内容类型（智能推测，可手动调整） */
  contentType: FileContentType;
  /** 是否参与导入（用户可逐个开关） */
  enabled: boolean;
  /** 是否正在解析 */
  isParsing: boolean;
  /** 解析错误 */
  parseError: string | null;
}

/**
 * 漫画状态枚举
 */
export enum MangaStatus {
  UNKNOWN = 'unknown',
  ONGOING = 'ongoing',
  COMPLETED = 'completed',
  HIATUS = 'hiatus',
  CANCELLED = 'cancelled'
}

/**
 * 文件内容类型
 */
export enum FileContentType {
  /** 单话/章节（某部漫画的一个章节） */
  CHAPTER = 'chapter',
  /** 单行本/卷（独立完整的一本漫画） */
  VOLUME = 'volume',
  /** 多章节容器（内含多个章节的压缩包或文件夹） */
  MULTI_CHAPTER = 'multi_chapter',
}

/**
 * 漫画分组信息
 */
export interface MangaGroup {
  /** 分组ID */
  groupId: string;
  /** 漫画标题 */
  title: string;
  /** 作者 */
  author: string;
  /** 简介 */
  description: string;
  /** 标签 */
  tags: string[];
  /** 包含的文件列表 */
  files: BatchFileInfo[];
  /** 章节列表（按编号排序） */
  chapters: BatchChapterInfo[];
  /** 是否展开显示 */
  isExpanded: boolean;
  /** 导入模式 */
  importMode: MangaImportMode;
  /** 是否合并到已有漫画 */
  mergeToExisting: boolean;
  /** 合并目标漫画ID */
  targetMangaId: string;
  /** 选中的封面文件索引 */
  selectedCoverFileIndex: number;
  /** 封面候选图片路径列表 */
  coverCandidates: string[];
  /** 选中的封面索引 */
  selectedCoverIndex: number;
  /** 漫画状态 */
  status: MangaStatus;
  /** 是否为NSFW内容 */
  isNSFW: boolean;
}

/**
 * 批量章节信息
 */
export interface BatchChapterInfo {
  /** 章节编号 */
  number: number;
  /** 章节标题 */
  title: string;
  /** 对应的文件 */
  file: BatchFileInfo;
  /** 页面数量 */
  pageCount: number;
  /** 本章节实际图片所在目录；多章节容器必须指向对应的检测目录 */
  sourcePath: string;
  /** true 表示来源是用户选择的外部目录，导入时只能复制，不能移动或删除 */
  preserveSource: boolean;
  /** 是否可能已存在（根据章节编号判断） */
  mayExist?: boolean;
}

/**
 * 批量导入对话框结果
 */
export interface BatchMangaImportDialogResult {
  /** 漫画分组列表 */
  groups: MangaGroupResult[];
}

/**
 * 单个漫画分组的导入结果
 */
export interface MangaGroupResult {
  /** 漫画标题 */
  title: string;
  /** 作者 */
  author: string;
  /** 简介 */
  description: string;
  /** 标签 */
  tags: string[];
  /** 导入模式 */
  importMode: MangaImportMode;
  /** 章节列表 */
  chapters: BatchChapterResult[];
  /** 是否合并到已有漫画 */
  mergeToExisting: boolean;
  /** 合并目标漫画ID */
  targetMangaId: string | undefined;
  /** 选中的封面路径 */
  selectedCoverPath: string;
  /** ComicInfo发布状态（可由用户在弹窗中调整） */
  status: MangaStatus;
  /** 是否为NSFW内容 */
  isNSFW: boolean;
  /** ComicInfo网页地址 */
  webUrl: string;
  /** 原始图源名称，仅用于保留元数据 */
  metadataSource: string;
}

/**
 * 单个章节的导入结果
 */
export interface BatchChapterResult {
  /** 章节编号 */
  number: number;
  /** 章节标题 */
  title: string;
  /** 文件URI */
  fileUri: string;
  /** 解析后的结构 */
  parsedStructure: ParsedArchiveStructure | null;
  /** 本章节页面数量（不是整个容器的总数） */
  pageCount: number;
  /** 本章节实际图片所在目录 */
  sourcePath: string;
  /** 是否必须保留源目录 */
  preserveSource: boolean;
  /** ComicInfo中记录的章节发布日期；没有时为当前时间 */
  publishTime: number;
}

/**
 * 批量漫画导入配置对话框
 */
@CustomDialog
export struct BatchMangaImportDialog {
  controller: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @Prop fileUris: string[] = [];
  @Prop existingMangaCandidates: ExistingMangaCandidate[] = [];
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // 回调函数
  onConfirm: (result: BatchMangaImportDialogResult) => void = () => {};
  onCancel: () => void = () => {};
  onFlowEvent: (event: ImportFlowEvent) => void = () => {};
  // 解析文件结构的回调
  parseFileStructure: (fileUri: string) => Promise<ParsedArchiveStructure | null> = async () => null;
  onReleaseParsedStructure: (fileUri: string, structure: ParsedArchiveStructure) => void = () => {};
  onAnalysisSettled: () => void = () => {};
  onAnalysisGenerationInvalidated: () => void = () => {};
  // 解析ComicInfo.xml的回调
  parseComicInfoXml: (xmlContent: string) => PrefilledComicInfo | null = () => null;

  // 状态
  @State files: BatchFileInfo[] = [];
  @State groups: MangaGroup[] = [];
  @State isAnalyzing: boolean = true;
  @State analyzeProgress: number = 0;
  @State analyzeMessage: string = '正在分析文件...';
  @State currentTab: number = 0; // 0: 分组视图, 1: 文件列表视图
  @State private groupPageIndex: number = 0;
  @State private filePageIndex: number = 0;
  // 分组视图刷新计数器：每次切换回分组 tab 时递增，强制 ForEach 重建所有卡片
  @State groupViewRefreshTick: number = 0;
  // 数据版本号：每次文件状态变化时递增，驱动文件列表 & 分组视图 ForEach key 全量失效
  @State dataVersion: number = 0;
  // 文件列表多选状态
  @State selectedFileIndices: number[] = [];
  @State isMultiSelectMode: boolean = false;
  // 标签页横向滑动切换
  @State private swipeStartX: number = 0;
  @State private swipeOffsetX: number = 0;
  // 入场动画状态
  @State private animOpacity: number = 0.0;
  @State private animTranslateY: number = 20;

  // UI上下文（入场动画使用）
  private uiContext: UIContext | null = null;
  // 刮削对话框控制器
  private scraperDialogController: CustomDialogController | null = null;
  // 当前正在刮削的分组索引
  private currentScrapingGroupIndex: number = -1;
  private static readonly VIEW_PAGE_SIZE: number = 20;
  private isDisposed: boolean = false;
  private hasNotifiedAnalysisSettled: boolean = false;
  private hasNotifiedGenerationInvalidated: boolean = false;
  @State private isActionLocked: boolean = false;

  aboutToAppear(): void {
    this.isDisposed = false;
    this.isActionLocked = false;
    // 获取UI上下文，用于入场动画
    this.uiContext = this.getUIContext();
    const ctx = this.uiContext;
    if (ctx) {
      setTimeout(() => {
        if (this.isDisposed || this.uiContext !== ctx) {
          return;
        }
        const animateOptions = { duration: 300, curve: Curve.EaseOut } as AnimateParam;
        ctx.animateTo(animateOptions, () => {
          if (this.isDisposed || this.uiContext !== ctx) {
            return;
          }
          this.animOpacity = 1.0;
          this.animTranslateY = 0;
        });
      }, 0);
    } else {
      this.animOpacity = 1.0;
      this.animTranslateY = 0;
    }
    this.initializeFiles();
    void this.startAnalysis();
  }

  aboutToDisappear(): void {
    this.isDisposed = true;
    this.notifyGenerationInvalidatedOnce();
    this.uiContext = null;
    this.scraperDialogController?.close();
    this.scraperDialogController = null;
  }

  /**
   * 初始化文件列表
   */
  private initializeFiles(): void {
    this.files = this.fileUris.map((uri: string) => {
      const fileName = this.getFileNameFromUri(uri);
      const isFolder = uri.startsWith('folder:');
      return {
        fileUri: uri,
        fileName: fileName,
        parsedStructure: null,
        prefilledInfo: null,
        inferredTitle: this.inferTitleFromFileName(fileName),
        inferredChapterNumber: this.inferChapterNumberFromFileName(fileName),
        inferredVolumeNumber: this.inferVolumeNumberFromFileName(fileName),
        contentType: this.inferContentTypeFromFileName(fileName, isFolder),
        enabled: true,
        isParsing: true,
        parseError: null
      } as BatchFileInfo;
    });
  }

  /**
   * 开始分析所有文件
   */
  private async startAnalysis(): Promise<void> {
    try {
      await this.runAnalysis();
    } catch (error) {
      const analysisError: Error = error instanceof Error ? error : new Error(String(error));
      logger.error(TAG, '批量漫画分析失败', analysisError.message);
      if (!this.isDisposed) {
        this.isAnalyzing = false;
        this.analyzeMessage = '分析失败';
      }
    } finally {
      this.notifyAnalysisSettledOnce();
    }
  }

  private notifyAnalysisSettledOnce(): void {
    if (this.hasNotifiedAnalysisSettled) {
      return;
    }
    this.hasNotifiedAnalysisSettled = true;
    try {
      this.onAnalysisSettled();
    } catch (error) {
      const settledError: Error = error instanceof Error ? error : new Error(String(error));
      logger.error(TAG, '通知批量漫画分析结束失败', settledError.message);
    }
  }

  private notifyGenerationInvalidatedOnce(): void {
    if (this.hasNotifiedGenerationInvalidated) {
      return;
    }
    this.hasNotifiedGenerationInvalidated = true;
    try {
      this.onAnalysisGenerationInvalidated();
    } catch (error) {
      const invalidatedError: Error = error instanceof Error ? error : new Error(String(error));
      logger.error(TAG, '通知批量漫画分析代次失效失败', invalidatedError.message);
    }
  }

  private async runAnalysis(): Promise<void> {
    this.isAnalyzing = true;
    this.analyzeProgress = 0;
    
    const totalFiles = this.files.length;
    this.emitFlowEvent(ImportFlowEventType.ARCHIVE_PARSE_STARTED, 'batch_analysis_started', true, '', '', 0, totalFiles, 0);
    
    for (let i = 0; i < this.files.length; i++) {
      if (this.isDisposed) {
        return;
      }
      const file = this.files[i];
      this.analyzeMessage = `正在解析 (${i + 1}/${totalFiles}): ${file.fileName}`;
      this.analyzeProgress = ((i + 1) / totalFiles) * 80;
      const startedAt: number = Date.now();
      
      try {
        // 解析文件结构
        const structure = await this.parseFileStructure(file.fileUri);
        if (this.isDisposed) {
          if (structure !== null) {
            this.onReleaseParsedStructure(file.fileUri, structure);
          }
          return;
        }
        file.parsedStructure = structure;
        file.isParsing = false;
        if (structure === null) {
          file.parseError = '未能识别文件结构';
          file.enabled = false;
        } else if (structure.totalImageCount <= 0 || structure.extractedPath.length <= 0) {
          file.parseError = '未找到可导入的漫画图片';
          file.enabled = false;
        } else {
          file.parseError = null;
        }
        this.emitFlowEvent(
          ImportFlowEventType.ARCHIVE_PARSE_COMPLETED,
          'batch_file_parsed',
          file.parseError === null,
          file.fileName,
          structure ? `chapters=${structure.detectedChapters.length}, pages=${structure.totalImageCount}` : 'empty_structure',
          i + 1,
          totalFiles,
          Date.now() - startedAt
        );
        
        if (file.parseError !== null) {
          logger.warn(TAG, `文件不可导入: ${file.fileName}, ${file.parseError}`);
        }
        
        // 如果有ComicInfo.xml，解析预填充信息
        if (structure && structure.hasComicInfo && structure.comicInfoContent) {
          const prefilledInfo = this.parseComicInfoXml(structure.comicInfoContent);
          file.prefilledInfo = prefilledInfo;
          
          // 使用ComicInfo中的信息更新推测标题
          if (prefilledInfo) {
            if (prefilledInfo.series) {
              file.inferredTitle = prefilledInfo.series;
            } else if (prefilledInfo.title) {
              file.inferredTitle = prefilledInfo.title;
            }
            
            if (prefilledInfo.number) {
              const num = parseInt(prefilledInfo.number, 10);
              if (!isNaN(num) && num > 0) {
                file.inferredChapterNumber = num;
              }
            }
            
            logger.info(TAG, `解析ComicInfo成功: ${file.fileName}, series=${prefilledInfo.series}, title=${prefilledInfo.title}`);
          }
        }

        // 解析完成后基于结构信息精化内容类型
        file.contentType = this.inferContentTypeFromFile(
          file.fileName, file.fileUri, structure, file.prefilledInfo
        );

        // 触发UI更新
        this.files = this.files.slice();
        
      } catch (error) {
        if (this.isDisposed) {
          return;
        }
        file.isParsing = false;
        file.parseError = String(error);
        logger.error(TAG, `解析文件失败: ${file.fileName}`, String(error));
        this.emitFlowEvent(
          ImportFlowEventType.ARCHIVE_PARSE_FAILED,
          'batch_file_parse_failed',
          false,
          file.fileName,
          String(error),
          i + 1,
          totalFiles,
          Date.now() - startedAt
        );
        // 确保UI更新
        this.files = this.files.slice();
      }
      await this.yieldToUi();
    }

    if (this.isDisposed) {
      return;
    }
    
    // 智能分组
    this.analyzeMessage = '正在智能分组...';
    this.analyzeProgress = 90;
    await this.performSmartGrouping();
    
    this.analyzeMessage = '分析完成';
    this.analyzeProgress = 100;
    this.isAnalyzing = false;
    this.emitFlowEvent(ImportFlowEventType.METADATA_DETECTED, 'batch_analysis_completed', true, '', `groups=${this.groups.length}`, totalFiles, totalFiles, 0);
  }

  private async yieldToUi(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, 0);
    });
  }

  private emitFlowEvent(
    eventType: ImportFlowEventType,
    reason: string,
    success: boolean,
    fileName: string,
    detail: string,
    currentIndex: number,
    totalCount: number,
    elapsedMs: number
  ): void {
    const event: ImportFlowEvent = new ImportFlowEvent();
    event.eventType = eventType;
    event.reason = reason;
    event.success = success;
    event.severity = success ? ImportFlowSeverity.INFO : ImportFlowSeverity.ERROR;
    event.contentType = ImportFlowContentType.MANGA;
    event.fileName = fileName;
    event.fileCount = this.files.length;
    event.batchMode = true;
    event.currentIndex = currentIndex;
    event.totalCount = totalCount;
    event.elapsedMs = elapsedMs;
    event.detail = detail;
    this.onFlowEvent(event);
  }

  /**
   * 执行智能分组（以 contentType 为核心分组依据）
   * - CHAPTER 文件：按规范化标题聚合，排序按卷号→章节号
   * - VOLUME / MULTI_CHAPTER 文件：每个文件独占一个分组
   */
  private shouldPreserveChapterSource(file: BatchFileInfo): boolean {
    const structure: ParsedArchiveStructure | null = file.parsedStructure;
    return structure !== null && structure.tempDirectories.length <= 0;
  }

  private getMangaStatusFromPrefilledInfo(prefilledInfo: PrefilledComicInfo | null): MangaStatus {
    const status: string = prefilledInfo?.publishingStatus?.trim().toLowerCase() || '';
    if (status === 'ongoing' || status === 'continuing') {
      return MangaStatus.ONGOING;
    }
    if (status === 'completed' || status === 'finished') {
      return MangaStatus.COMPLETED;
    }
    if (status === 'hiatus' || status === 'paused' || status === 'on hiatus') {
      return MangaStatus.HIATUS;
    }
    if (status === 'cancelled' || status === 'canceled') {
      return MangaStatus.CANCELLED;
    }
    return MangaStatus.UNKNOWN;
  }

  /**
   * 返回文件中第一个可用的 ComicInfo。章节文件并不保证都携带 XML，
   * 因此不能只读取排序后的第一项。
   */
  private getFirstPrefilledInfo(files: BatchFileInfo[]): PrefilledComicInfo | null {
    for (const file of files) {
      if (file.prefilledInfo !== null) {
        return file.prefilledInfo;
      }
    }
    return null;
  }

  /**
   * 生成不会把空标题文件误合并的分组键。
   */
  private getGroupingKey(file: BatchFileInfo): string {
    const normalizedTitle = this.normalizeTitle(file.inferredTitle);
    if (normalizedTitle.length > 0) {
      return normalizedTitle;
    }
    const fallback = file.fileUri.trim().toLowerCase() || file.fileName.trim().toLowerCase();
    return `__untitled_${fallback}`;
  }

  private getDefaultChapterSourcePath(file: BatchFileInfo): string {
    const structure: ParsedArchiveStructure | null = file.parsedStructure;
    if (structure === null) {
      return '';
    }
    if (structure.detectedChapters.length === 1) {
      return structure.detectedChapters[0].path;
    }
    return structure.extractedPath;
  }

  private getDefaultChapterPageCount(file: BatchFileInfo): number {
    const structure: ParsedArchiveStructure | null = file.parsedStructure;
    if (structure === null) {
      return 0;
    }
    if (structure.detectedChapters.length === 1) {
      return structure.detectedChapters[0].pageCount;
    }
    return structure.totalImageCount;
  }

  private createDetectedChapterInfo(file: BatchFileInfo, chapter: ChapterInfo): BatchChapterInfo {
    const chapterInfo: BatchChapterInfo = {
      number: chapter.number,
      title: chapter.title,
      file: file,
      pageCount: chapter.pageCount,
      sourcePath: chapter.path,
      preserveSource: this.shouldPreserveChapterSource(file)
    };
    return chapterInfo;
  }

  private async performSmartGrouping(): Promise<void> {
    this.groups = [];
    let groupIndex = 0;

    // CHAPTER 文件按规范化标题聚合
    const chapterMap = new Map<string, BatchFileInfo[]>();
    // VOLUME / MULTI_CHAPTER 文件各自独占一组
    const soloFiles: BatchFileInfo[] = [];

    for (const file of this.files) {
      if (file.parseError) continue;
      if (file.contentType === FileContentType.CHAPTER) {
        const key = this.getGroupingKey(file);
        if (!chapterMap.has(key)) {
          chapterMap.set(key, []);
        }
        chapterMap.get(key)!.push(file);
      } else {
        soloFiles.push(file);
      }
    }

    // 创建 CHAPTER 分组
    chapterMap.forEach((files: BatchFileInfo[], title: string) => {
      files.sort((a, b) => {
        if (a.inferredVolumeNumber !== b.inferredVolumeNumber) {
          return a.inferredVolumeNumber - b.inferredVolumeNumber;
        }
        return a.inferredChapterNumber - b.inferredChapterNumber;
      });

      const prefilledInfo = this.getFirstPrefilledInfo(files);

      const chapters: BatchChapterInfo[] = files.map((file: BatchFileInfo, index: number) => {
        const chapterInfo: BatchChapterInfo = {
          number: file.inferredChapterNumber || (index + 1),
          title: file.prefilledInfo?.title || `第${file.inferredChapterNumber || (index + 1)}话`,
          file: file,
          pageCount: this.getDefaultChapterPageCount(file),
          sourcePath: this.getDefaultChapterSourcePath(file),
          preserveSource: this.shouldPreserveChapterSource(file)
        };
        return chapterInfo;
      });

      const importMode = files.length > 1 ? MangaImportMode.SINGLE_CHAPTER : MangaImportMode.TANKOUBON;
      const groupTitle = prefilledInfo?.series || prefilledInfo?.title || this.denormalizeTitle(title);
      const matchedManga = this.findMatchingExistingManga(groupTitle);

      const group: MangaGroup = {
        groupId: `group_${groupIndex++}`,
        title: groupTitle,
        author: prefilledInfo?.author || '',
        description: prefilledInfo?.description || '',
        tags: prefilledInfo?.tags || [],
        files: files,
        chapters: chapters,
        isExpanded: files.length <= 12,
        importMode: importMode,
        mergeToExisting: matchedManga !== null,
        targetMangaId: matchedManga?.id || '',
        selectedCoverFileIndex: 0,
        coverCandidates: this.initCoverCandidatesForGroup(files),
        selectedCoverIndex: 0,
        status: this.getMangaStatusFromPrefilledInfo(prefilledInfo),
        isNSFW: prefilledInfo?.isNSFW || false
      };

      if (matchedManga) {
        logger.info(TAG, `自动匹配到已有漫画: ${groupTitle} -> ${matchedManga.title}`);
      }
      this.groups.push(group);
    });

    // 创建 VOLUME / MULTI_CHAPTER 独立分组
    for (const file of soloFiles) {
      const prefilledInfo = file.prefilledInfo;
      let chapters: BatchChapterInfo[];
      let importMode: MangaImportMode;

      if (file.contentType === FileContentType.MULTI_CHAPTER) {
        importMode = MangaImportMode.MULTI_CHAPTER;
        if (file.parsedStructure?.detectedChapters && file.parsedStructure.detectedChapters.length >= 1) {
          chapters = file.parsedStructure.detectedChapters.map((ch: ChapterInfo) => {
            return this.createDetectedChapterInfo(file, ch);
          });
        } else {
          chapters = [{
            number: file.inferredChapterNumber || 1,
            title: prefilledInfo?.title || `第${file.inferredChapterNumber || 1}话`,
            file: file,
            pageCount: this.getDefaultChapterPageCount(file),
            sourcePath: this.getDefaultChapterSourcePath(file),
            preserveSource: this.shouldPreserveChapterSource(file)
          }];
        }
      } else {
        // VOLUME
        importMode = MangaImportMode.TANKOUBON;
        chapters = [{
          number: file.inferredVolumeNumber || 1,
          title: prefilledInfo?.title ||
            (file.inferredVolumeNumber > 0 ? `第${file.inferredVolumeNumber}卷` : file.inferredTitle),
          file: file,
          pageCount: this.getDefaultChapterPageCount(file),
          sourcePath: this.getDefaultChapterSourcePath(file),
          preserveSource: this.shouldPreserveChapterSource(file)
        }];
      }

      const groupTitle = prefilledInfo?.series || prefilledInfo?.title || file.inferredTitle;
      const matchedManga = this.findMatchingExistingManga(groupTitle);

      const group: MangaGroup = {
        groupId: `__solo_${file.fileUri}`,
        title: groupTitle,
        author: prefilledInfo?.author || '',
        description: prefilledInfo?.description || '',
        tags: prefilledInfo?.tags || [],
        files: [file],
        chapters: chapters,
        isExpanded: true,
        importMode: importMode,
        mergeToExisting: matchedManga !== null,
        targetMangaId: matchedManga?.id || '',
        selectedCoverFileIndex: 0,
        coverCandidates: this.initCoverCandidatesForGroup([file]),
        selectedCoverIndex: 0,
        status: this.getMangaStatusFromPrefilledInfo(prefilledInfo),
        isNSFW: prefilledInfo?.isNSFW || false
      };
      this.groups.push(group);
      logger.info(TAG, `独立分组 (${file.contentType}): ${groupTitle}`);
    }

    logger.info(TAG, `智能分组完成: ${this.groups.length} 个漫画分组`);
  }
  
  /**
   * 查找匹配的已有漫画（同名或相似名称）
   */
  private findMatchingExistingManga(title: string): ExistingMangaCandidate | null {
    if (!title || this.existingMangaCandidates.length === 0) {
      return null;
    }
    
    const normalizedTitle = this.normalizeTitle(title);
    if (normalizedTitle.length === 0) {
      return null;
    }
    
    // 精确匹配
    for (const manga of this.existingMangaCandidates) {
      const normalizedMangaTitle = this.normalizeTitle(manga.title);
      if (normalizedMangaTitle.length > 0 && normalizedMangaTitle === normalizedTitle) {
        return manga;
      }
    }
    
    // 模糊匹配（包含关系）
    for (const manga of this.existingMangaCandidates) {
      const normalizedMangaTitle = this.normalizeTitle(manga.title);
      if (normalizedMangaTitle.length === 0) {
        continue;
      }
      if (normalizedMangaTitle.includes(normalizedTitle) || normalizedTitle.includes(normalizedMangaTitle)) {
        // 只有当长度差异不大时才认为匹配
        const lengthRatio = Math.min(normalizedTitle.length, normalizedMangaTitle.length) / 
                           Math.max(normalizedTitle.length, normalizedMangaTitle.length);
        if (lengthRatio > 0.7) {
          return manga;
        }
      }
    }
    
    return null;
  }

  /**
   * 初始化分组的封面候选
   */
  private initCoverCandidatesForGroup(files: BatchFileInfo[]): string[] {
    // 从第一个文件获取封面候选
    const firstFile = files[0];
    if (firstFile.parsedStructure?.extractedPath) {
      try {
        const extractedPath = firstFile.parsedStructure.extractedPath;
        const imageFiles = this.findImagesRecursive(extractedPath, 3);
        imageFiles.sort();
        return imageFiles.slice(0, 3);
      } catch (error) {
        logger.error(TAG, `获取封面候选失败: ${error}`);
      }
    }
    
    return [];
  }

  /**
   * 递归查找图片文件（先搜索当前目录，再搜索子目录）
   */
  private findImagesRecursive(dirPath: string, maxCount: number, currentDepth: number = 0): string[] {
    if (currentDepth > 3) return [];
    
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];
    const imageFiles: string[] = [];
    const subDirs: string[] = [];
    
    try {
      const fileList = SafeFileUtils.listFileSync(dirPath);
      
      for (const file of fileList) {
        const lowerFile = file.toLowerCase();
        const fullPath = `${dirPath}/${file}`;
        try {
          const stat = SafeFileUtils.lstatSyncStrict(fullPath);
          if (stat.isSymbolicLink()) {
            continue;
          }
          if (stat.isDirectory()) {
            subDirs.push(fullPath);
            continue;
          }
        } catch (_statError) {
          continue;
        }
        
        for (const ext of imageExtensions) {
          if (lowerFile.endsWith(ext)) {
            imageFiles.push(fullPath);
            break;
          }
        }
        
        if (imageFiles.length >= maxCount) break;
      }
      
      // 如果当前目录没有足够图片，递归搜索子目录
      if (imageFiles.length < maxCount && subDirs.length > 0) {
        subDirs.sort();
        for (const subDir of subDirs) {
          const subImages = this.findImagesRecursive(subDir, maxCount - imageFiles.length, currentDepth + 1);
          for (const img of subImages) {
            imageFiles.push(img);
            if (imageFiles.length >= maxCount) break;
          }
          if (imageFiles.length >= maxCount) break;
        }
      }
    } catch (error) {
      logger.warn(TAG, `扫描目录图片失败: ${dirPath}`, String(error));
    }
    
    return imageFiles;
  }

  /**
   * 移除文件扩展名
   */
  private getFileNameWithoutExt(fileName: string): string {
    const lastDotIndex = fileName.lastIndexOf('.');
    if (lastDotIndex > 0) {
      return fileName.substring(0, lastDotIndex);
    }
    return fileName;
  }

  /**
   * 从文件名推测漫画标题（增强版）
   */
  private inferTitleFromFileName(fileName: string): string {
    let title = this.getFileNameWithoutExt(fileName);

    // 移除扫描组/汉化组标签
    title = title.replace(/[\[\([［（][^\]\)[］）]{0,30}?(?:汉化|翻译|扫描|Digital|WEB|RAW|DL)[^\]\)[］）]{0,20}?[\]\)[］）]/gi, '');

    // 移除章节/卷标识
    const stripPatterns: RegExp[] = [
      /第\d+(\.\d+)?[话話章回]/g,
      /[话話章回]\d+/g,
      /[Cc]h(?:apter)?\.?\s*\d+(\.\d+)?/gi,
      /[Ee]p(?:isode)?\.?\s*\d+/gi,
      /[Vv]ol(?:ume)?\.?\s*\d+(\.\d+)?/gi,
      /第\d+[卷册]/g,
      /[\[\([［（]\d+(\.\d+)?[\]\)[］）]/g,
      /[_\-\s]+\d{1,4}(\.\d+)?[_\-\s]*/g,
      /\s*\d{1,4}(\.\d+)?$/g
    ];

    for (const pattern of stripPatterns) {
      title = title.replace(pattern, '');
    }

    title = title.replace(/[\s_\-]+/g, ' ').trim();
    if (!title) {
      title = this.getFileNameWithoutExt(fileName);
    }
    return title;
  }

  /**
   * 从文件名推测章节编号（增强版）
   */
  private inferChapterNumberFromFileName(fileName: string): number {
    const base = this.getFileNameWithoutExt(fileName);
    const patterns: RegExp[] = [
      /第(\d+(?:\.\d+)?)[话話章回]/,
      /[话話章回](\d+)/,
      /[Cc]h(?:apter)?\.?\s*(\d+(?:\.\d+)?)/i,
      /[Ee]p(?:isode)?\.?\s*(\d+)/i,
      /[\[\([［（](\d+(?:\.\d+)?)[\]\)[］）]/,
      /[_\-\s](\d{3,4})(?:[_\-\s.]|$)/,
      /(\d{1,4})$/
    ];
    for (const pattern of patterns) {
      const match = base.match(pattern);
      if (match && match[1]) {
        const num = parseFloat(match[1]);
        if (num > 0 && num < 10000) {
          return Math.floor(num);
        }
      }
    }
    return 1;
  }

  /**
   * 从文件名推测卷号
   */
  private inferVolumeNumberFromFileName(fileName: string): number {
    const base = this.getFileNameWithoutExt(fileName);
    const patterns: RegExp[] = [
      /第(\d+(?:\.\d+)?)[卷册]/,
      /[Vv]ol(?:ume)?\.?\s*(\d+(?:\.\d+)?)/,
      /v(\d+(?:\.\d+)?)(?:[_\-\s.]|$)/i
    ];
    for (const pattern of patterns) {
      const match = base.match(pattern);
      if (match && match[1]) {
        const num = parseFloat(match[1]);
        if (num > 0 && num < 1000) {
          return Math.floor(num);
        }
      }
    }
    return 0;
  }

  /**
   * 从文件名智能推断内容类型（基础阶段，无解析结构）
   */
  private inferContentTypeFromFileName(fileName: string, isFolder: boolean): FileContentType {
    if (isFolder) {
      return FileContentType.MULTI_CHAPTER;
    }
    const base = this.getFileNameWithoutExt(fileName).toLowerCase();

    // 章节范围检测：001-050，差値≥ 2 → 多章节合集
    const rangeMatch = base.match(/(?:ch(?:apter)?\.?\s*)?(\d+)\s*[-~到]\s*(\d+)/i);
    if (rangeMatch) {
      const start = parseInt(rangeMatch[1], 10);
      const end = parseInt(rangeMatch[2], 10);
      if (!isNaN(start) && !isNaN(end) && end - start >= 2) {
        return FileContentType.MULTI_CHAPTER;
      }
    }

    // 有卷号且无章节号 → 单行本
    const hasVol = /vol(?:ume)?\.?\s*\d+|第\d+[卷册]/.test(base);
    const hasCh = /ch(?:apter)?\.?\s*\d+|第\d+[话話章回]|ep(?:isode)?\.?\s*\d+/.test(base);
    if (hasVol && !hasCh) {
      return FileContentType.VOLUME;
    }

    // 多章节关键词
    const multiKeywords = ['合集', '合本', '合订', 'omnibus', 'anthology', 'collection', '精选', '特辑'];
    for (const kw of multiKeywords) {
      if (base.includes(kw)) {
        return FileContentType.MULTI_CHAPTER;
      }
    }

    return FileContentType.CHAPTER;
  }

  /**
   * 解析完成后精化内容类型
   */
  private inferContentTypeFromFile(
    fileName: string,
    fileUri: string,
    parsedStructure: ParsedArchiveStructure | null,
    prefilledInfo: PrefilledComicInfo | null
  ): FileContentType {
    const isFolder = fileUri.startsWith('folder:');
    let contentType = this.inferContentTypeFromFileName(fileName, isFolder);
    if (!parsedStructure) {
      return contentType;
    }
    const detectedChapterCount = parsedStructure.detectedChapters?.length ?? 0;
    const pageCount = parsedStructure.totalImageCount ?? 0;

    // 内含多个子目录 → 多章节
    if (detectedChapterCount > 1) {
      return FileContentType.MULTI_CHAPTER;
    }

    // 页数占位（仅当文件名未能确定类型时）
    if (detectedChapterCount <= 1 && contentType === FileContentType.CHAPTER) {
      if (pageCount >= 250) {
        return FileContentType.MULTI_CHAPTER;
      }
      if (pageCount >= 150) {
        return FileContentType.VOLUME;
      }
    }

    // ComicInfo series != title → 是章节形式
    if (prefilledInfo && prefilledInfo.series && prefilledInfo.series !== prefilledInfo.title) {
      if (contentType !== FileContentType.MULTI_CHAPTER) {
        return FileContentType.CHAPTER;
      }
    }

    return contentType;
  }

  /**
   * 标准化标题（用于分组比较）
   */
  private normalizeTitle(title: string): string {
    const rawTitle = title.trim().toLowerCase();
    // \w 只覆盖 ASCII，显式保留其余 Unicode 字符，避免日文假名、韩文
    // 或其他非 ASCII 标题被清空。ASCII 标点仍会被移除以便做稳定的比较。
    const normalizedTitle = rawTitle
      .replace(/[\s_\-]+/g, '')
      .replace(/[^\w\u0080-\uFFFF]/g, '');
    return normalizedTitle.length > 0 ? normalizedTitle : rawTitle;
  }

  /**
   * 反标准化标题
   */
  private denormalizeTitle(normalizedTitle: string): string {
    // 尝试从文件中找到原始标题
    for (const file of this.files) {
      if (this.getGroupingKey(file) === normalizedTitle) {
        return file.inferredTitle;
      }
    }
    // 仅用于无标题文件的 URI 隔离键不应直接显示给用户。
    if (normalizedTitle.startsWith('__untitled_')) {
      return '未命名漫画';
    }
    return normalizedTitle;
  }

  /**
   * 从URI获取文件名
   */
  private getFileNameFromUri(uri: string): string {
    try {
      const decodedUri = decodeURIComponent(uri);
      const parts = decodedUri.split('/');
      return parts[parts.length - 1] || uri;
    } catch {
      const parts = uri.split('/');
      return parts[parts.length - 1] || uri;
    }
  }

  /**
   * 验证表单（跳过全部文件均已禁用的分组）
   */
  private validateForm(): boolean {
    let hasImportableChapter: boolean = false;
    for (const group of this.groups) {
      // 全部禁用的分组不参与导入，跳过验证
      const hasEnabledFile = group.files.some((f: BatchFileInfo) => f.enabled && !f.parseError);
      if (!hasEnabledFile) continue;

      const hasValidChapter = group.chapters.some((chapter: BatchChapterInfo) =>
        chapter.file.enabled && !chapter.file.parseError && chapter.sourcePath.trim().length > 0 && chapter.pageCount > 0
      );
      if (!hasValidChapter) {
        this.showToast(`"${group.title || '未命名漫画'}"没有可导入的图片`);
        return false;
      }
      hasImportableChapter = true;

      if (!group.title || group.title.trim().length === 0) {
        this.showToast('请为所有漫画输入标题');
        return false;
      }

      if (group.mergeToExisting && !group.targetMangaId) {
        this.showToast(`请为"${group.title}"选择要合并的目标漫画`);
        return false;
      }
    }
    if (!hasImportableChapter) {
      this.showToast('没有可导入的漫画文件');
      return false;
    }
    return true;
  }

  /**
   * 显示提示
   */
  private showToast(message: string): void {
    logger.info(TAG, `Toast: ${message}`);
  }

  /**
   * 构建结果（过滤全禁用分组及禁用文件）
   */
  private buildResult(): BatchMangaImportDialogResult {
    const groupResults: MangaGroupResult[] = [];
    for (const group of this.groups) {
      const hasEnabledFile = group.files.some((f: BatchFileInfo) => f.enabled && !f.parseError);
      if (!hasEnabledFile) continue;

      const chapterResults: BatchChapterResult[] = group.chapters
        .filter((chapter: BatchChapterInfo) =>
          chapter.file.enabled && !chapter.file.parseError && chapter.sourcePath.trim().length > 0 && chapter.pageCount > 0
        )
        .map((chapter: BatchChapterInfo) => {
          const result: BatchChapterResult = {
            number: chapter.number,
            title: chapter.title,
            fileUri: chapter.file.fileUri,
            parsedStructure: chapter.file.parsedStructure,
            pageCount: chapter.pageCount,
            sourcePath: chapter.sourcePath,
            preserveSource: chapter.preserveSource,
            publishTime: chapter.file.prefilledInfo?.publishTime ?? Date.now()
          };
          return result;
        });
      if (chapterResults.length <= 0) {
        continue;
      }

      let selectedCoverPath = '';
      if (group.coverCandidates.length > 0 && group.selectedCoverIndex < group.coverCandidates.length) {
        selectedCoverPath = group.coverCandidates[group.selectedCoverIndex];
      }
      const metadataFile: BatchFileInfo | undefined = group.files.find(
        (file: BatchFileInfo): boolean => file.enabled && file.prefilledInfo !== null
      );

      groupResults.push({
        title: group.title.trim(),
        author: group.author.trim() || '未知作者',
        description: group.description.trim(),
        tags: group.tags,
        importMode: group.importMode,
        chapters: chapterResults,
        mergeToExisting: group.mergeToExisting,
        targetMangaId: group.mergeToExisting ? group.targetMangaId : undefined,
        selectedCoverPath: selectedCoverPath,
        status: group.status,
        isNSFW: group.isNSFW,
        webUrl: metadataFile?.prefilledInfo?.webUrl || '',
        metadataSource: metadataFile?.prefilledInfo?.source || ''
      } as MangaGroupResult);
    }
    return { groups: groupResults };
  }

  build() {
    Column({ space: 0 }) {
      // 标题栏
      this.buildHeader()
      
      if (this.isAnalyzing) {
        // 分析进度
        this.buildAnalyzingView()
      } else {
        // 标签页切换
        this.buildTabBar()
        
        // 内容区域：始终同时挂载两个视图，通过 Visibility 切换而非 if/else，
        // 防止 ArkUI 对 if/else 分支的组件缓存复用导致切回分组视图时显示旧数据。
        // Visibility.None 的组件仍保留在组件树中，@State 变化可实时传播给它。
        Column() {
          this.buildGroupsView()
        }
        .width('100%')
        .layoutWeight(1)
        .visibility(this.currentTab === 0 ? Visibility.Visible : Visibility.None)
        .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
            .onActionStart((event: GestureEvent) => {
              this.swipeStartX = event.offsetX;
              this.swipeOffsetX = 0;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.swipeOffsetX = event.offsetX - this.swipeStartX;
            })
            .onActionEnd(() => {
              this.handleTabSwipe();
            })
        )
        
        Column() {
          this.buildFilesListView()
        }
        .width('100%')
        .layoutWeight(1)
        .visibility(this.currentTab === 1 ? Visibility.Visible : Visibility.None)
        .gesture(
          PanGesture({ fingers: 1, direction: PanDirection.Horizontal, distance: 5 })
            .onActionStart((event: GestureEvent) => {
              this.swipeStartX = event.offsetX;
              this.swipeOffsetX = 0;
            })
            .onActionUpdate((event: GestureEvent) => {
              this.swipeOffsetX = event.offsetX - this.swipeStartX;
            })
            .onActionEnd(() => {
              this.handleTabSwipe();
            })
        )
        
        // 操作按钮
        this.buildActionButtons()
      }
    }
    .width('100%')
    .height('90%')
    .backgroundColor(DialogSurfaceStyleHelper.getPopupCardBackground(this.themeState))
    .backgroundBlurStyle(
      DialogSurfaceStyleHelper.getPopupCardBlurStyle(),
      DialogSurfaceStyleHelper.getPopupCardBlurOptions()
    )
    .backgroundEffect(DialogSurfaceStyleHelper.getPopupCardBackgroundEffect())
    .borderRadius(26)
    .clip(true)
    .border({
      width: 1,
      color: DialogSurfaceStyleHelper.getPopupCardBorderColor(this.themeState)
    })
    .shadow({
      radius: 26,
      color: DialogSurfaceStyleHelper.getPopupCardShadowColor(this.themeState),
      offsetX: 0,
      offsetY: 10
    })
    .opacity(this.animOpacity)
    .translate({ y: this.animTranslateY })
  }

  /**
   * 构建标题栏
   */
  @Builder
  buildHeader() {
    Row() {
      Text(`批量导入 ${this.fileUris.length} 个文件`)
        .fontSize(20)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Blank()

      // 关闭按钮
      Image($r('app.media.ic_close'))
        .width(24)
        .height(24)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .onClick(() => {
          if (this.isActionLocked) {
            return;
          }
          this.isActionLocked = true;
          this.emitFlowEvent(ImportFlowEventType.DIALOG_CANCELLED, 'batch_dialog_close_icon', true, '', '', 0, this.files.length, 0);
          this.onCancel();
          this.controller.close();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 12 })
  }

  /**
   * 构建分析进度视图
   */
  @Builder
  buildAnalyzingView() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(60)
        .height(60)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

      Text(this.analyzeMessage)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)

      Progress({ value: this.analyzeProgress, total: 100, type: ProgressType.Linear })
        .width('80%')
        .height(4)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))

      Text(`${Math.round(this.analyzeProgress)}%`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 构建标签页栏
   */
  @Builder
  buildTabBar() {
    Row({ space: 0 }) {
      this.buildTabItem('分组视图', 0, `${this.getEnabledGroupCount()} 部漫画`)
      this.buildTabItem('文件列表', 1, `${this.files.length} 个文件`)
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
  }

  /**
   * 构建标签项
   */
  @Builder
  buildTabItem(label: string, index: number, subtitle: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === index ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      
      Text(subtitle)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      
      // 下划线指示器
      Row()
        .width('100%')
        .height(2)
        .backgroundColor(this.currentTab === index ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          'transparent')
        .margin({ top: 4 })
        .animation({ duration: 200, curve: Curve.EaseOut })
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 8 })
    .onClick(() => {
      this.switchTab(index);
    })
  }

  private switchTab(index: number): void {
    if (index < 0 || index > 1 || index === this.currentTab) {
      return;
    }
    if (index === 0) {
      // 切换回分组视图前递增 tick，使 ForEach key 全部失效，强制重建分组卡片
      this.groupViewRefreshTick++;
    }
    this.currentTab = index;
  }

  private handleTabSwipe(): void {
    const swipeThreshold = 80;
    if (this.swipeOffsetX < -swipeThreshold) {
      this.switchTab(this.currentTab + 1);
    } else if (this.swipeOffsetX > swipeThreshold) {
      this.switchTab(this.currentTab - 1);
    }
    this.swipeOffsetX = 0;
  }

  /**
   * 根据groupId查找分组索引
   */
  private findGroupIndex(groupId: string): number {
    for (let i = 0; i < this.groups.length; i++) {
      if (this.groups[i].groupId === groupId) {
        return i;
      }
    }
    return -1;
  }

  private getPageCount(itemCount: number): number {
    return Math.max(1, Math.ceil(itemCount / BatchMangaImportDialog.VIEW_PAGE_SIZE));
  }

  private getEffectivePageIndex(pageIndex: number, itemCount: number): number {
    const pageCount: number = this.getPageCount(itemCount);
    return Math.max(0, Math.min(pageIndex, pageCount - 1));
  }

  private getEnabledGroupsForDisplay(): MangaGroup[] {
    return this.groups.filter((group: MangaGroup) => this.hasEnabledFiles(group));
  }

  private getVisibleGroups(): MangaGroup[] {
    const enabledGroups: MangaGroup[] = this.getEnabledGroupsForDisplay();
    const pageIndex: number = this.getEffectivePageIndex(this.groupPageIndex, enabledGroups.length);
    const startIndex: number = pageIndex * BatchMangaImportDialog.VIEW_PAGE_SIZE;
    return enabledGroups.slice(startIndex, startIndex + BatchMangaImportDialog.VIEW_PAGE_SIZE);
  }

  private getGroupPageCount(): number {
    return this.getPageCount(this.getEnabledGroupsForDisplay().length);
  }

  private getEffectiveGroupPageIndex(): number {
    return this.getEffectivePageIndex(this.groupPageIndex, this.getEnabledGroupsForDisplay().length);
  }

  private getVisibleFiles(): BatchFileInfo[] {
    const pageIndex: number = this.getEffectivePageIndex(this.filePageIndex, this.files.length);
    const startIndex: number = pageIndex * BatchMangaImportDialog.VIEW_PAGE_SIZE;
    return this.files.slice(startIndex, startIndex + BatchMangaImportDialog.VIEW_PAGE_SIZE);
  }

  private getFilePageCount(): number {
    return this.getPageCount(this.files.length);
  }

  private getEffectiveFilePageIndex(): number {
    return this.getEffectivePageIndex(this.filePageIndex, this.files.length);
  }

  @Builder
  buildGroupPager() {
    if (this.getGroupPageCount() > 1) {
      Row({ space: 12 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .enabled(this.getEffectiveGroupPageIndex() > 0)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .onClick(() => {
          this.groupPageIndex = Math.max(0, this.getEffectiveGroupPageIndex() - 1);
        })

        Text(`${this.getEffectiveGroupPageIndex() + 1} / ${this.getGroupPageCount()}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Button() {
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .enabled(this.getEffectiveGroupPageIndex() < this.getGroupPageCount() - 1)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .onClick(() => {
          this.groupPageIndex = Math.min(this.getGroupPageCount() - 1, this.getEffectiveGroupPageIndex() + 1);
        })
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  buildFilePager() {
    if (this.getFilePageCount() > 1) {
      Row({ space: 12 }) {
        Button() {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .enabled(this.getEffectiveFilePageIndex() > 0)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .onClick(() => {
          this.filePageIndex = Math.max(0, this.getEffectiveFilePageIndex() - 1);
        })

        Text(`${this.getEffectiveFilePageIndex() + 1} / ${this.getFilePageCount()}`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Button() {
          SymbolGlyph($r('sys.symbol.arrow_right'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
        }
        .width(36)
        .height(36)
        .enabled(this.getEffectiveFilePageIndex() < this.getFilePageCount() - 1)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .onClick(() => {
          this.filePageIndex = Math.min(this.getFilePageCount() - 1, this.getEffectiveFilePageIndex() + 1);
        })
      }
      .width('100%')
      .height(44)
      .justifyContent(FlexAlign.Center)
    }
  }
  
  /**
   * 构建分组视图
   */
  @Builder
  buildGroupsView() {
    Column({ space: 0 }) {
      Scroll() {
        Column({ space: 12 }) {
          ForEach(this.getVisibleGroups(), (group: MangaGroup) => {
            this.buildGroupCardById(group.groupId)
          }, (group: MangaGroup) => `r${this.groupViewRefreshTick}_v${this.dataVersion}_${group.groupId}_${group.isExpanded}_${group.mergeToExisting}_${group.targetMangaId}_${group.title}_${group.importMode}_${group.status}_${group.isNSFW}_${group.selectedCoverIndex}_${group.files.length}_${group.files.filter((f: BatchFileInfo) => f.enabled).length}_${group.chapters.length}_${group.files.map((f: BatchFileInfo) => f.contentType).join(',')}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)

      this.buildGroupPager()
    }
    .width('100%')
    .layoutWeight(1)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ x: -15 }).animation({ duration: 250, curve: Curve.EaseOut })),
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseIn })
    ))
  }
  
  /**
   * 根据groupId查找分组索引
   */
  @Builder
  buildGroupCardById(groupId: string) {
    if (this.groups.length > 0) {
      this.buildGroupCard(this.getGroupByIdOrFirst(groupId), this.getGroupIndexOrFirst(groupId))
    }
  }
  
  /**
   * 根据groupId获取分组，如果找不到返回第一个
   */
  private getGroupByIdOrFirst(groupId: string): MangaGroup {
    const idx = this.findGroupIndex(groupId);
    return idx >= 0 ? this.groups[idx] : this.groups[0];
  }

  private getGroupIndexOrFirst(groupId: string): number {
    const index: number = this.findGroupIndex(groupId);
    return index >= 0 ? index : 0;
  }

  /**
   * 切换分组展开/收起状态
   */
  private toggleGroupExpanded(groupIndex: number): void {
    if (groupIndex >= 0 && groupIndex < this.groups.length) {
      this.groups[groupIndex].isExpanded = !this.groups[groupIndex].isExpanded;
      this.groups = this.groups.slice();
    }
  }
  
  /**
   * 更新分组标题
   */
  private updateGroupTitle(groupIndex: number, title: string): void {
    if (groupIndex >= 0 && groupIndex < this.groups.length) {
      this.groups[groupIndex].title = title;
    }
  }
  
  /**
   * 切换合并到已有漫画选项
   */
  private toggleMergeToExisting(groupIndex: number, value: boolean): void {
    if (groupIndex >= 0 && groupIndex < this.groups.length) {
      this.groups[groupIndex].mergeToExisting = value;
      if (!value) {
        this.groups[groupIndex].targetMangaId = '';
        // 清除章节存在性标记
        for (const chapter of this.groups[groupIndex].chapters) {
          chapter.mayExist = false;
        }
      }
      this.groups = this.groups.slice();
    }
  }
  
  /**
   * 构建分组卡片
   */
  @Builder
  buildGroupCard(group: MangaGroup, groupIndex: number) {
    Column({ space: 0 }) {
      // 分组头部
      Row({ space: 12 }) {
        // 展开/折叠图标
        Row() {
          SymbolGlyph(this.groups[groupIndex].isExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        }
        .width(24)
        .height(24)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          this.toggleGroupExpanded(groupIndex);
        })
        
        // 漫画信息
        Column({ space: 4 }) {
          // 标题输入（可编辑）
          TextInput({ text: this.groups[groupIndex].title, placeholder: '漫画标题' })
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(4)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .height(36)
            .onChange((value: string) => {
              this.updateGroupTitle(groupIndex, value);
            })
          
          // 章节统计（显示已启用/总计）
          Text(`${this.groups[groupIndex].chapters.filter((c: BatchChapterInfo) => c.file.enabled && (this.dataVersion >= 0)).length}/${this.groups[groupIndex].chapters.length} 个章节 · ${this.getTotalPages(this.groups[groupIndex])} 页`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        
        // 拆分按钮（仅当分组有多个文件时显示）
        if (this.groups[groupIndex].files.length > 1) {
          Row({ space: 4 }) {
            Text('拆分')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(4)
          .onClick(() => {
            this.splitGroup(groupIndex);
          })
        }
        
        // 刮削按钮
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(12)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
          Text('刮削')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
        .borderRadius(4)
        .onClick(() => {
          this.openScraperDialogForGroup(groupIndex);
        })
      }
      .width('100%')
      .padding(12)
      
      // 展开的详细内容
      if (this.groups[groupIndex].isExpanded) {
        Column({ space: 12 }) {
          // 来源信息提示（如果有xml信息）
          if (this.hasXmlInfo(this.groups[groupIndex])) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.doc_text'))
                .fontSize(13)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
              Text('包含 ComicInfo.xml 元数据')
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '10')
            .borderRadius(4)
          }
          
          // 作者输入
          this.buildInputField('作者', this.groups[groupIndex].author, '请输入作者', (value: string) => {
            this.groups[groupIndex].author = value;
          })
          
          // 简介输入（如果有xml信息则显示）
          if (this.groups[groupIndex].description) {
            this.buildInputField('简介', this.groups[groupIndex].description, '漫画简介', (value: string) => {
              this.groups[groupIndex].description = value;
            })
          }
          
          // 标签输入
          this.buildInputField('标签', this.groups[groupIndex].tags.join(', '), '逗号分隔', (value: string) => {
            this.groups[groupIndex].tags = value.split(/[,，、]/).map(t => t.trim()).filter(t => t.length > 0);
          })
          
          // 状态和NSFW设置
          this.buildStatusAndNsfwSelector(group, groupIndex)
          
          // 封面选择
          this.buildCoverSelector(group, groupIndex)
          
          // 章节列表
          this.buildChapterList(group, groupIndex)
          
          // 合并选项（始终显示，不管是否有候选）
          this.buildMergeOptions(group, groupIndex)
        }
        .width('100%')
        .padding({ left: 12, right: 12, bottom: 12 })
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseOut })
            .combine(TransitionEffect.translate({ y: -8 }).animation({ duration: 200, curve: Curve.EaseOut })),
          TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.EaseIn })
        ))
      }
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ y: 10 }).animation({ duration: 250, curve: Curve.EaseOut })),
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseIn })
    ))
  }

  /**
   * 构建输入字段
   */
  @Builder
  buildInputField(label: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width(50)
      
      TextInput({ text: value, placeholder: placeholder })
        .fontSize(13)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .padding({ left: 10, right: 10 })
        .height(36)
        .layoutWeight(1)
        .onChange(onChange)
    }
    .width('100%')
  }
  
  /**
   * 构建状态和NSFW选择器
   */
  @Builder
  buildStatusAndNsfwSelector(group: MangaGroup, groupIndex: number) {
    Row({ space: 16 }) {
      // 状态选择
      Row({ space: 8 }) {
        Text('状态')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Row({ space: 4 }) {
          // 未知
          Text('未知')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.groups[groupIndex].status === MangaStatus.UNKNOWN ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.groups[groupIndex].status === MangaStatus.UNKNOWN ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20' :
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(4)
            .onClick(() => {
              this.updateGroupStatus(groupIndex, MangaStatus.UNKNOWN);
            })
          // 连载
          Text('连载')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.groups[groupIndex].status === MangaStatus.ONGOING ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.groups[groupIndex].status === MangaStatus.ONGOING ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20' :
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(4)
            .onClick(() => {
              this.updateGroupStatus(groupIndex, MangaStatus.ONGOING);
            })
          // 完结
          Text('完结')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(this.groups[groupIndex].status === MangaStatus.COMPLETED ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.groups[groupIndex].status === MangaStatus.COMPLETED ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20' :
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(4)
            .onClick(() => {
              this.updateGroupStatus(groupIndex, MangaStatus.COMPLETED);
            })
        }
      }
      .layoutWeight(1)
      
      // NSFW开关
      Row({ space: 8 }) {
        Text('NSFW')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Toggle({ type: ToggleType.Switch, isOn: this.groups[groupIndex].isNSFW })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            this.updateGroupNSFW(groupIndex, isOn);
          })
      }
    }
    .width('100%')
  }
  
  /**
   * 更新分组状态
   */
  private updateGroupStatus(groupIndex: number, status: MangaStatus): void {
    if (groupIndex >= 0 && groupIndex < this.groups.length) {
      this.groups[groupIndex].status = status;
      this.groups = this.groups.slice();
    }
  }
  
  /**
   * 更新分组NSFW标记
   */
  private updateGroupNSFW(groupIndex: number, isNSFW: boolean): void {
    if (groupIndex >= 0 && groupIndex < this.groups.length) {
      this.groups[groupIndex].isNSFW = isNSFW;
      this.groups = this.groups.slice();
    }
  }

  /**
   * 构建封面选择器
   */
  @Builder
  buildCoverSelector(group: MangaGroup, groupIndex: number) {
    Column({ space: 8 }) {
      Row() {
        Text('选择封面')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Blank()
        
        if (this.groups[groupIndex].coverCandidates.length > 0) {
          Text(`已选第 ${this.groups[groupIndex].selectedCoverIndex + 1} 张`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
      }
      .width('100%')
      
      if (this.groups[groupIndex].coverCandidates.length === 0) {
        Text('暂无封面候选')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      } else {
        Row({ space: 8 }) {
          ForEach(this.groups[groupIndex].coverCandidates, (path: string, index: number) => {
            Column() {
              Image(path.startsWith('file://') ? path : `file://${path}`)
                .width(60)
                .height(85)
                .objectFit(ImageFit.Cover)
                .borderRadius(4)
                .border({
                  width: this.groups[groupIndex].selectedCoverIndex === index ? 3 : 1,
                  color: this.groups[groupIndex].selectedCoverIndex === index ?
                    ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                    ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                })
              
              // 选中指示器
              if (this.groups[groupIndex].selectedCoverIndex === index) {
                Row() {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(12)
                    .fontColor([AppColors.onPrimary])
                }
                .width(20)
                .height(20)
                .justifyContent(FlexAlign.Center)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .borderRadius(10)
                .margin({ top: -15 })
              }
            }
            .onClick(() => {
              this.groups[groupIndex].selectedCoverIndex = index;
              // 强制触发UI更新
              const newGroups = this.groups.slice();
              this.groups = newGroups;
              logger.info(TAG, `选择封面: 分组${groupIndex}, 索引${index}`);
            })
          }, (path: string, index: number) => `cover_${groupIndex}_${index}_${this.groups[groupIndex].selectedCoverIndex}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(8)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(6)
  }

  /**
   * 构建章节列表（仅显示已启用的章节）
   */
  @Builder
  buildChapterList(group: MangaGroup, groupIndex: number) {
    Column({ space: 4 }) {
      Row() {
        Text('章节列表')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Blank()
        
        Text(`共 ${this.groups[groupIndex].chapters.filter((c: BatchChapterInfo) => c.file.enabled && (this.dataVersion >= 0)).length} 章`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      
      // 章节列表（仅显示已启用章节，最多5个，其余折叠）
      Column({ space: 4 }) {
        ForEach(this.groups[groupIndex].chapters.filter((c: BatchChapterInfo) => c.file.enabled && (this.dataVersion >= 0)).slice(0, 5),
          (chapter: BatchChapterInfo, chapterIndex: number) => {
            this.buildChapterItem(chapter, groupIndex, chapterIndex)
          }, (chapter: BatchChapterInfo) => `chapter_${groupIndex}_${chapter.file.fileUri}_${this.dataVersion}`)
        
        if (this.groups[groupIndex].chapters.filter((c: BatchChapterInfo) => c.file.enabled && (this.dataVersion >= 0)).length > 5) {
          Text(`... 还有 ${this.groups[groupIndex].chapters.filter((c: BatchChapterInfo) => c.file.enabled && (this.dataVersion >= 0)).length - 5} 个章节`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(8)
        }
      }
      .width('100%')
      .padding(8)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(6)
    }
    .width('100%')
  }

  /**
   * 构建章节项
   */
  @Builder
  buildChapterItem(chapter: BatchChapterInfo, groupIndex: number, chapterIndex: number) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        // 章节编号输入
        TextInput({ text: chapter.number.toString() })
          .type(InputType.Number)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(4)
          .padding({ left: 6, right: 6 })
          .height(28)
          .width(45)
          .onChange((value: string) => {
            const num = parseInt(value, 10);
            if (!isNaN(num) && num > 0) {
              chapter.number = num;
              // 检查章节是否可能已存在
              const realChapterIdx = this.groups[groupIndex].chapters.indexOf(chapter);
              if (realChapterIdx >= 0) {
                this.checkChapterExistence(groupIndex, realChapterIdx);
              }
              this.groups = this.groups.slice();
            }
          })
        
        // 章节标题输入
        TextInput({ text: chapter.title })
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .borderRadius(4)
          .padding({ left: 6, right: 6 })
          .height(28)
          .layoutWeight(1)
          .onChange((value: string) => {
            chapter.title = value;
            this.groups = this.groups.slice();
          })
        
        // 页数
        Text(`${chapter.pageCount}页`)
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width(35)
      }
      .width('100%')
      
      // 章节可能已存在提示
      if (chapter.mayExist) {
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
            .fontSize(12)
            .fontColor([AppColors.warning])
          Text('该章节可能已存在于目标漫画中')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(AppColors.warning)
        }
        .width('100%')
        .padding({ left: 53 })
      }
    }
    .width('100%')
    .opacity(chapter.file.enabled ? 1.0 : 0.35)
  }

  /**
   * 构建合并选项
   */
  @Builder
  buildMergeOptions(group: MangaGroup, groupIndex: number) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Checkbox()
          .select(this.groups[groupIndex].mergeToExisting)
          .onChange((value: boolean) => {
            this.toggleMergeToExisting(groupIndex, value);
          })
        
        Text('合并到已有漫画')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        // 如果已自动匹配，显示提示
        if (this.groups[groupIndex].mergeToExisting && this.groups[groupIndex].targetMangaId) {
          Text('(已自动匹配)')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
      }
      .width('100%')
      
      // 始终显示已有漫画列表（勾选后才能选择）
      if (this.existingMangaCandidates.length > 0) {
        Column({ space: 4 }) {
          if (!this.groups[groupIndex].mergeToExisting) {
            Text('勾选上方选项后可选择目标漫画')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .width('100%')
              .padding({ bottom: 4 })
          }
          
          ForEach(this.existingMangaCandidates.slice(0, 5), (manga: ExistingMangaCandidate) => {
            Row({ space: 8 }) {
              // 选中指示器
              Row() {
                if (this.groups[groupIndex].targetMangaId === manga.id && this.groups[groupIndex].mergeToExisting) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                    .fontSize(20)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                } else {
                  SymbolGlyph($r('sys.symbol.circle'))
                    .fontSize(20)
                    .fontColor([this.groups[groupIndex].mergeToExisting ? 
                      ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme) :
                      ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
                }
              }
              .width(24)
              .height(24)
              .justifyContent(FlexAlign.Center)
              
              Column({ space: 2 }) {
                Text(manga.title)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.groups[groupIndex].mergeToExisting ? 
                    ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) :
                    ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                
                Text(`${manga.author} · ${manga.chapterCount}章`)
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(6)
            .backgroundColor(this.groups[groupIndex].targetMangaId === manga.id && this.groups[groupIndex].mergeToExisting ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15' :
              'transparent')
            .borderRadius(4)
            .opacity(this.groups[groupIndex].mergeToExisting ? 1.0 : 0.5)
            .onClick(() => {
              if (this.groups[groupIndex].mergeToExisting) {
                this.selectTargetManga(groupIndex, manga.id);
              }
            })
          }, (manga: ExistingMangaCandidate) => `${manga.id}_${this.groups[groupIndex].mergeToExisting}_${this.groups[groupIndex].targetMangaId}`)
        }
        .width('100%')
        .padding(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
      } else {
        Text('暂无已有漫画可供合并')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .width('100%')
          .padding(8)
      }
    }
    .width('100%')
  }

  /**
   * 构建文件列表视图（分组分区）
   */
  @Builder
  buildFilesListView() {
    Column({ space: 0 }) {
      this.buildFileListToolbar()
      Scroll() {
        Column({ space: 10 }) {
          ForEach(this.getVisibleFiles(), (file: BatchFileInfo) => {
            this.buildFileItemInGroup(file, this.getFileIndex(file))
          }, (file: BatchFileInfo) =>
            `v${this.dataVersion}_file_${file.fileUri}_${file.enabled}_${file.contentType}_${file.parseError || ''}_${this.selectedFileIndices.includes(this.getFileIndex(file))}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)

      this.buildFilePager()
    }
    .width('100%')
    .layoutWeight(1)
    .transition(TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.EaseOut })
        .combine(TransitionEffect.translate({ x: 15 }).animation({ duration: 250, curve: Curve.EaseOut })),
      TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseIn })
    ))
  }
  
  /**
   * 构建文件列表工具栏
   */
  @Builder
  buildFileListToolbar() {
    Column({ space: 0 }) {
      // 第一行：多选控制
      Row({ space: 8 }) {
        Row({ space: 4 }) {
          Checkbox()
            .select(this.isMultiSelectMode)
            .onChange((value: boolean) => {
              this.isMultiSelectMode = value;
              if (!value) {
                this.selectedFileIndices = [];
              }
            })
          Text('多选')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        if (this.isMultiSelectMode && this.selectedFileIndices.length > 0) {
          Text(`已选 ${this.selectedFileIndices.length} 个`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          Button('合并')
            .fontSize(11)
            .height(28)
            .padding({ left: 8, right: 8 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(AppColors.onPrimary)
            .borderRadius(4)
            .enabled(this.selectedFileIndices.length >= 2)
            .onClick(() => { this.mergeSelectedFiles(); })
        }
        Blank()
        if (this.isMultiSelectMode) {
          Text(this.selectedFileIndices.length === this.files.length ? '取消全选' : '全选')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(() => {
              if (this.selectedFileIndices.length === this.files.length) {
                this.selectedFileIndices = [];
              } else {
                const allIndices: number[] = [];
                for (let i = 0; i < this.files.length; i++) {
                  allIndices.push(i);
                }
                this.selectedFileIndices = allIndices;
              }
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      // 第二行：批量操作（多选且有选中时显示）
      if (this.isMultiSelectMode && this.selectedFileIndices.length > 0) {
        Row({ space: 6 }) {
          Text('批量类型:')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .flexShrink(0)
          Text('章节')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor('#4FC3F7')
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor('#4FC3F720')
            .borderRadius(4)
            .onClick(() => { this.batchChangeContentType(FileContentType.CHAPTER); })
          Text('单行本')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor('#81C784')
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor('#81C78420')
            .borderRadius(4)
            .onClick(() => { this.batchChangeContentType(FileContentType.VOLUME); })
          Text('多章节')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFB74D')
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor('#FFB74D20')
            .borderRadius(4)
            .onClick(() => { this.batchChangeContentType(FileContentType.MULTI_CHAPTER); })
          Blank()
          Text('启用')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor('#81C784')
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor('#81C78420')
            .borderRadius(4)
            .onClick(() => { this.batchToggleEnabled(true); })
          Text('禁用')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(AppColors.error)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor(AppColors.error + '20')
            .borderRadius(4)
            .onClick(() => { this.batchToggleEnabled(false); })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 8 })
      }
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
  }
  
  /**
   * 合并选中的文件为一个分组
   */
  private mergeSelectedFiles(): void {
    if (this.selectedFileIndices.length < 2) return;
    
    const selectedIndices = this.selectedFileIndices.slice().sort((a, b) => a - b);
    const selectedFiles: BatchFileInfo[] = selectedIndices.map(i => this.files[i]);
    
    // 收集被合并分组的用户自定义信息
    let customTitle = '';
    let customAuthor = '';
    let customDescription = '';
    let customTags: string[] = [];
    let customStatus: MangaStatus = MangaStatus.UNKNOWN;
    let customIsNSFW: boolean = false;
    
    // 从现有分组中收集用户可能修改过的信息，并移除这些文件
    for (let i = this.groups.length - 1; i >= 0; i--) {
      const group = this.groups[i];
      const hasSelectedFile = group.files.some(f => selectedFiles.includes(f));
      
      if (hasSelectedFile) {
        // 保留第一个有效的用户自定义信息
        if (!customTitle && group.title) {
          customTitle = group.title;
        }
        if (!customAuthor && group.author) {
          customAuthor = group.author;
        }
        if (!customDescription && group.description) {
          customDescription = group.description;
        }
        if (customTags.length === 0 && group.tags.length > 0) {
          customTags = group.tags.slice();
        }
        if (customStatus === MangaStatus.UNKNOWN && group.status !== MangaStatus.UNKNOWN) {
          customStatus = group.status;
        }
        if (group.isNSFW) {
          customIsNSFW = true;
        }
      }
      
      group.files = group.files.filter(f => !selectedFiles.includes(f));
      group.chapters = group.chapters.filter(c => !selectedFiles.includes(c.file));
      
      // 如果分组为空，删除它
      if (group.files.length === 0) {
        this.groups.splice(i, 1);
      }
    }
    
    // 使用第一个文件的信息作为基础（如果没有用户自定义信息）
    const firstFile = selectedFiles[0];
    const prefilledInfo = this.getFirstPrefilledInfo(selectedFiles);
    
    // 合并后统一设置为 CHAPTER 类型
    selectedFiles.forEach((f: BatchFileInfo) => { f.contentType = FileContentType.CHAPTER; });
    // 按章节编号排序
    selectedFiles.sort((a, b) => a.inferredChapterNumber - b.inferredChapterNumber);

    // 创建章节列表
    const chapters: BatchChapterInfo[] = selectedFiles.map((file: BatchFileInfo, index: number) => {
      const chapterInfo: BatchChapterInfo = {
        number: file.inferredChapterNumber || (index + 1),
        title: file.prefilledInfo?.title || `第${file.inferredChapterNumber || (index + 1)}话`,
        file: file,
        pageCount: this.getDefaultChapterPageCount(file),
        sourcePath: this.getDefaultChapterSourcePath(file),
        preserveSource: this.shouldPreserveChapterSource(file)
      };
      return chapterInfo;
    });
    
    // 优先使用用户自定义信息，其次使用xml信息，最后使用推测信息
    const finalTitle = customTitle || prefilledInfo?.series || prefilledInfo?.title || firstFile.inferredTitle;
    const finalAuthor = customAuthor || prefilledInfo?.author || '';
    const finalDescription = customDescription || prefilledInfo?.description || '';
    const finalTags = customTags.length > 0 ? customTags : (prefilledInfo?.tags || []);
    const metadataStatus = this.getMangaStatusFromPrefilledInfo(prefilledInfo);
    const finalStatus = customStatus !== MangaStatus.UNKNOWN ? customStatus : metadataStatus;
    const finalIsNSFW = customIsNSFW || prefilledInfo?.isNSFW || false;
    
    // 创建新分组
    const newGroup: MangaGroup = {
      groupId: `group_merged_${Date.now()}`,
      title: finalTitle,
      author: finalAuthor,
      description: finalDescription,
      tags: finalTags,
      files: selectedFiles,
      chapters: chapters,
      isExpanded: true,
      importMode: MangaImportMode.SINGLE_CHAPTER,
      mergeToExisting: false,
      targetMangaId: '',
      selectedCoverFileIndex: 0,
      coverCandidates: this.initCoverCandidatesForGroup(selectedFiles),
      selectedCoverIndex: 0,
      status: finalStatus,
      isNSFW: finalIsNSFW
    };
    
    this.groups.push(newGroup);
    this.groups = this.groups.slice();
    
    // 清除选择
    this.selectedFileIndices = [];
    this.isMultiSelectMode = false;
    
    // 切换到分组视图（同时递增 tick 强制刷新）
    this.groupViewRefreshTick++;
    this.currentTab = 0;
    
    logger.info(TAG, `合并 ${selectedFiles.length} 个文件为新分组: ${newGroup.title}`);
  }
  
  /**
   * 拆分分组为多个单独的分组
   */
  private splitGroup(groupIndex: number): void {
    const group = this.groups[groupIndex];
    if (group.files.length <= 1) return;
    
    // 保存原分组的用户自定义信息（用于没有xml信息的文件）
    const originalAuthor = group.author;
    const originalDescription = group.description;
    const originalTags = group.tags.slice();
    
    // 移除原分组
    this.groups.splice(groupIndex, 1);
    
    // 为每个文件创建单独的分组
    for (const file of group.files) {
      const prefilledInfo = file.prefilledInfo;
      
      // 优先使用xml信息，其次使用原分组的用户自定义信息
      const splitImportMode = this.contentTypeToImportMode(file.contentType);
      const fileStatus = this.getMangaStatusFromPrefilledInfo(prefilledInfo);
      const newGroup: MangaGroup = {
        groupId: file.contentType !== FileContentType.CHAPTER
          ? `__solo_${file.fileUri}`
          : `group_split_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        title: prefilledInfo?.series || prefilledInfo?.title || file.inferredTitle,
        author: prefilledInfo?.author || originalAuthor,
        description: prefilledInfo?.description || originalDescription,
        tags: prefilledInfo?.tags || originalTags,
        files: [file],
        chapters: [this.createChapterInfo(file, prefilledInfo)],
        isExpanded: false,
        importMode: splitImportMode,
        mergeToExisting: false,
        targetMangaId: '',
        selectedCoverFileIndex: 0,
        coverCandidates: this.initCoverCandidatesForGroup([file]),
        selectedCoverIndex: 0,
        status: fileStatus !== MangaStatus.UNKNOWN ? fileStatus : group.status,
        isNSFW: (prefilledInfo?.isNSFW === true) || group.isNSFW
      };
      
      this.groups.push(newGroup);
    }
    
    this.groups = this.groups.slice();
    logger.info(TAG, `拆分分组为 ${group.files.length} 个单独分组`);
  }

  /**
   * 构建文件分组区域（每个分组占一个卡片）
   */
  @Builder
  buildFileGroupSection(group: MangaGroup) {
    Column({ space: 0 }) {
      Row({ space: 6 }) {
        Text(this.getImportModeLabel(group.importMode))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(group.importMode === MangaImportMode.MULTI_CHAPTER ? '#FFB74D' :
            group.importMode === MangaImportMode.TANKOUBON ? '#81C784' : '#4FC3F7')
          .padding({ left: 5, right: 5, top: 2, bottom: 2 })
          .backgroundColor(group.importMode === MangaImportMode.MULTI_CHAPTER ? '#FFB74D20' :
            group.importMode === MangaImportMode.TANKOUBON ? '#81C78420' : '#4FC3F720')
          .borderRadius(3)
          .flexShrink(0)
        Text(group.title || '(无标题)')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`${group.files.filter((f: BatchFileInfo) => f.enabled && !f.parseError).length}/${group.files.filter((f: BatchFileInfo) => !f.parseError).length}`)
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .flexShrink(0)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 6 })

      ForEach(group.files.filter((f: BatchFileInfo) => !f.parseError), (file: BatchFileInfo) => {
        this.buildFileItemInGroup(file, this.getFileIndex(file))
      }, (file: BatchFileInfo) =>
        `v${this.dataVersion}_fgi_${file.fileUri}_${file.enabled}_${file.contentType}_${this.selectedFileIndices.includes(this.getFileIndex(file))}`)
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(8)
    .clip(true)
  }

  /**
   * 构建单个文件项（启用开关 + 内容类型徽章）
   */
  @Builder
  buildFileItemInGroup(file: BatchFileInfo, fileIdx: number) {
    Row({ space: 8 }) {
      // 多选复选框
      if (this.isMultiSelectMode) {
        Checkbox()
          .select(this.selectedFileIndices.includes(fileIdx))
          .onChange((value: boolean) => {
            if (value) {
              if (!this.selectedFileIndices.includes(fileIdx)) {
                this.selectedFileIndices = [...this.selectedFileIndices, fileIdx];
              }
            } else {
              this.selectedFileIndices = this.selectedFileIndices.filter((i: number) => i !== fileIdx);
            }
          })
      }
      // 选中/启用指示器
      if (file.isParsing) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      } else {
        SymbolGlyph(file.enabled ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.circle'))
          .fontSize(22)
          .fontColor([file.enabled ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
          .onClick(() => {
            if (!this.isMultiSelectMode) {
              this.setFileEnabled(file, !file.enabled);
              // setFileEnabled 内部会同步 files/groups 并触发刷新
            }
          })
      }
      // 文件信息
      Column({ space: 2 }) {
        Row({ space: 4 }) {
          if (file.fileUri.startsWith('folder:')) {
            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
          }
          Text(file.fileName)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        if (file.parsedStructure) {
          Text(`${file.parsedStructure.totalImageCount} 页 · ${file.inferredTitle}`)
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else if (file.parseError) {
          Text('解析失败')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(AppColors.error)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .opacity(file.enabled ? 1.0 : 0.5)
      .animation({ duration: 200, curve: Curve.EaseOut })
      // 内容类型标签（点击循环切换）
      Text(this.getContentTypeLabel(file.contentType))
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getContentTypeColor(file.contentType))
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .backgroundColor(this.getContentTypeColor(file.contentType) + '20')
        .borderRadius(4)
        .flexShrink(0)
        .onClick(() => { this.cycleFileContentType(file); })
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(this.selectedFileIndices.includes(fileIdx) ?
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15' :
      'transparent')
    .onClick(() => {
      if (this.isMultiSelectMode) {
        if (this.selectedFileIndices.includes(fileIdx)) {
          this.selectedFileIndices = this.selectedFileIndices.filter((i: number) => i !== fileIdx);
        } else {
          this.selectedFileIndices = [...this.selectedFileIndices, fileIdx];
        }
      }
      // 非多选模式下，启用状态由左侧 SymbolGlyph 单独处理
      // 避免点击子元素（SymbolGlyph / 内容类型徽章）时事件冒泡到 Row 导致二次触发
    })
  }
  
  /**
   * 获取文件在 this.files 中的索引
   */
  private getFileIndex(file: BatchFileInfo): number {
    const index = this.files.indexOf(file);
    if (index >= 0) {
      return index;
    }
    return this.files.findIndex((item: BatchFileInfo) => item.fileUri === file.fileUri);
  }

  /**
   * 获取解析失败的文件列表
   */
  private getErrorFiles(): BatchFileInfo[] {
    return this.files.filter((f: BatchFileInfo) => f.parseError !== null);
  }

  /**
   * 内容类型标签
   */
  private getContentTypeLabel(contentType: FileContentType): string {
    switch (contentType) {
      case FileContentType.CHAPTER: return '章节';
      case FileContentType.VOLUME: return '单行本';
      case FileContentType.MULTI_CHAPTER: return '多章节';
      default: return '未知';
    }
  }

  /**
   * 内容类型颜色
   */
  private getContentTypeColor(contentType: FileContentType): string {
    switch (contentType) {
      case FileContentType.CHAPTER: return '#4FC3F7';
      case FileContentType.VOLUME: return '#81C784';
      case FileContentType.MULTI_CHAPTER: return '#FFB74D';
      default: return '#90A4AE';
    }
  }

  /**
   * 内容类型 → 导入模式
   */
  private contentTypeToImportMode(contentType: FileContentType): MangaImportMode {
    switch (contentType) {
      case FileContentType.CHAPTER: return MangaImportMode.SINGLE_CHAPTER;
      case FileContentType.VOLUME: return MangaImportMode.TANKOUBON;
      case FileContentType.MULTI_CHAPTER: return MangaImportMode.MULTI_CHAPTER;
      default: return MangaImportMode.TANKOUBON;
    }
  }

  /**
   * 循环切换文件内容类型
   */
  private cycleFileContentType(file: BatchFileInfo): void {
    const types = [FileContentType.CHAPTER, FileContentType.VOLUME, FileContentType.MULTI_CHAPTER];
    const nextType = types[(types.indexOf(file.contentType) + 1) % types.length];
    this.changeFileContentType(this.getFileIndex(file), nextType);
  }

  /**
   * 修改文件内容类型（含拆组逻辑）
   * triggerUpdate=false 时不立即刷新 UI，用于批量操作
   */
  private changeFileContentType(fileIndex: number, newContentType: FileContentType, triggerUpdate: boolean = true): void {
    if (fileIndex < 0 || fileIndex >= this.files.length) return;
    const file = this.files[fileIndex];
    file.contentType = newContentType;

    for (let i = 0; i < this.groups.length; i++) {
      const group = this.groups[i];
      if (!group.files.includes(file)) continue;

      if (group.files.length === 1) {
        // 单文件分组：直接更新 importMode
        this.groups[i].importMode = this.contentTypeToImportMode(newContentType);
        if (newContentType !== FileContentType.CHAPTER) {
          this.groups[i].groupId = `__solo_${file.fileUri}`;
        }
      } else if (newContentType !== FileContentType.CHAPTER) {
        // 多文件分组 + 非 CHAPTER：将文件移出，创建独立分组
        this.groups[i].files = group.files.filter(f => f !== file);
        this.groups[i].chapters = group.chapters.filter(c => c.file !== file);
        if (this.groups[i].files.length === 0) {
          this.groups.splice(i, 1);
        }
        const fileStatus = this.getMangaStatusFromPrefilledInfo(file.prefilledInfo);
        const soloGroup: MangaGroup = {
          groupId: `__solo_${file.fileUri}`,
          title: file.prefilledInfo?.series || file.prefilledInfo?.title || file.inferredTitle,
          author: file.prefilledInfo?.author || group.author,
          description: file.prefilledInfo?.description || group.description,
          tags: file.prefilledInfo?.tags || group.tags.slice(),
          files: [file],
          chapters: [{
            number: newContentType === FileContentType.VOLUME
              ? (file.inferredVolumeNumber || 1)
              : (file.inferredChapterNumber || 1),
            title: file.prefilledInfo?.title || file.inferredTitle,
            file: file,
            pageCount: this.getDefaultChapterPageCount(file),
            sourcePath: this.getDefaultChapterSourcePath(file),
            preserveSource: this.shouldPreserveChapterSource(file)
          }],
          isExpanded: false,
          importMode: this.contentTypeToImportMode(newContentType),
          mergeToExisting: false,
          targetMangaId: '',
          selectedCoverFileIndex: 0,
          coverCandidates: this.initCoverCandidatesForGroup([file]),
          selectedCoverIndex: 0,
          status: fileStatus !== MangaStatus.UNKNOWN ? fileStatus : group.status,
          isNSFW: (file.prefilledInfo?.isNSFW === true) || group.isNSFW
        };
        this.groups.push(soloGroup);
      }
      // CHAPTER + 多文件分组：保留在组内，无需操作
      break;
    }

    if (triggerUpdate) {
      this.dataVersion++;
      this.files = this.files.slice();
      this.groups = this.groups.slice();
    }
  }

  /**
   * 批量修改选中文件的内容类型
   */
  private batchChangeContentType(newContentType: FileContentType): void {
    for (const idx of this.selectedFileIndices) {
      this.changeFileContentType(idx, newContentType, false);
    }
    this.dataVersion++;
    this.files = this.files.slice();
    this.groups = this.groups.slice();
  }

  /**
   * 批量设置选中文件的启用/禁用状态
   */
  private batchToggleEnabled(enabled: boolean): void {
    let hasChanges = false;
    for (const idx of this.selectedFileIndices) {
      if (idx >= 0 && idx < this.files.length) {
        if (this.setFileEnabled(this.files[idx], enabled, false)) {
          hasChanges = true;
        }
      }
    }
    if (hasChanges) {
      this.dataVersion++;
      this.files = this.files.slice();
      this.groups = this.groups.slice();
    }
    // setFileEnabled(false) already syncs chapter arrays; commit batched state here.
  }
  
  /**
   * 深度更新包含指定文件的分组的 chapters 数组（触发响应式更新）
   */
  private setFileEnabled(file: BatchFileInfo, enabled: boolean, triggerUpdate: boolean = true): boolean {
    const fileIndex = this.getFileIndex(file);
    if (fileIndex < 0) {
      return false;
    }

    const targetUri = this.files[fileIndex].fileUri;
    let hasChanges = false;

    if (this.files[fileIndex].enabled !== enabled) {
      this.files[fileIndex].enabled = enabled;
      hasChanges = true;
    }

    for (let i = 0; i < this.groups.length; i++) {
      let groupChanged = false;
      for (const groupFile of this.groups[i].files) {
        if (groupFile.fileUri === targetUri && groupFile.enabled !== enabled) {
          groupFile.enabled = enabled;
          groupChanged = true;
          hasChanges = true;
        }
      }
      if (groupChanged) {
        this.rebuildGroupFromEnabledFiles(this.groups[i]);
      }
    }

    if (triggerUpdate && hasChanges) {
      this.dataVersion++;
      this.files = this.files.slice();
      this.groups = this.groups.slice();
    }
    return hasChanges;
  }
  
  private rebuildGroupFromEnabledFiles(group: MangaGroup): void {
    const enabledFiles = group.files.filter((f: BatchFileInfo) => f.enabled && !f.parseError);
    if (enabledFiles.length === 0) {
      group.chapters = [];
      return;
    }

    const existingChaptersByFile = new Map<string, BatchChapterInfo[]>();
    for (const chapter of group.chapters) {
      const fileUri = chapter.file.fileUri;
      const existing = existingChaptersByFile.get(fileUri) || [];
      existing.push(chapter);
      existingChaptersByFile.set(fileUri, existing);
    }

    let chapters: BatchChapterInfo[] = [];
    if (enabledFiles.length > 1 && enabledFiles.every((f: BatchFileInfo) => f.contentType === FileContentType.CHAPTER)) {
      const sortedFiles = enabledFiles.slice().sort((a: BatchFileInfo, b: BatchFileInfo) => {
        if (a.inferredVolumeNumber !== b.inferredVolumeNumber) {
          return a.inferredVolumeNumber - b.inferredVolumeNumber;
        }
        return a.inferredChapterNumber - b.inferredChapterNumber;
      });
      chapters = sortedFiles.map((f: BatchFileInfo, index: number) => {
        const existing = existingChaptersByFile.get(f.fileUri)?.[0];
        return {
          number: existing?.number ?? (f.inferredChapterNumber || (index + 1)),
          title: existing?.title || f.prefilledInfo?.title || f.inferredTitle,
          file: f,
          pageCount: existing?.pageCount ?? this.getDefaultChapterPageCount(f),
          sourcePath: existing?.sourcePath || this.getDefaultChapterSourcePath(f),
          preserveSource: existing?.preserveSource ?? this.shouldPreserveChapterSource(f),
          mayExist: existing?.mayExist
        } as BatchChapterInfo;
      });
      group.importMode = MangaImportMode.SINGLE_CHAPTER;
    } else {
      for (const enabledFile of enabledFiles) {
        const existing = existingChaptersByFile.get(enabledFile.fileUri);
        if (existing && existing.length > 0) {
          chapters.push(...existing.map((chapter: BatchChapterInfo) => ({
            number: chapter.number,
            title: chapter.title,
            file: enabledFile,
            pageCount: chapter.pageCount,
            sourcePath: chapter.sourcePath,
            preserveSource: chapter.preserveSource,
            mayExist: chapter.mayExist
          } as BatchChapterInfo)));
        } else {
          chapters.push(...this.inferChaptersFromFile(enabledFile));
        }
      }
      chapters.sort((a: BatchChapterInfo, b: BatchChapterInfo) => a.number - b.number);
      group.importMode = enabledFiles.length === 1
        ? this.contentTypeToImportMode(enabledFiles[0].contentType)
        : MangaImportMode.MULTI_CHAPTER;
    }

    group.chapters = chapters;
    group.coverCandidates = this.initCoverCandidatesForGroup(enabledFiles);
    if (group.selectedCoverIndex >= group.coverCandidates.length) {
      group.selectedCoverIndex = 0;
    }
  }

  private inferChaptersFromFile(file: BatchFileInfo): BatchChapterInfo[] {
    if (file.contentType === FileContentType.MULTI_CHAPTER &&
      file.parsedStructure?.detectedChapters &&
      file.parsedStructure.detectedChapters.length >= 1) {
      return file.parsedStructure.detectedChapters.map((chapter: ChapterInfo) =>
        this.createDetectedChapterInfo(file, chapter)
      );
    }

    if (file.contentType === FileContentType.VOLUME) {
      return [{
        number: file.inferredVolumeNumber || 1,
        title: file.prefilledInfo?.title || file.inferredTitle,
        file: file,
        pageCount: this.getDefaultChapterPageCount(file),
        sourcePath: this.getDefaultChapterSourcePath(file),
        preserveSource: this.shouldPreserveChapterSource(file)
      }];
    }

    return [{
      number: file.inferredChapterNumber || 1,
      title: file.prefilledInfo?.title || file.inferredTitle,
      file: file,
      pageCount: this.getDefaultChapterPageCount(file),
      sourcePath: this.getDefaultChapterSourcePath(file),
      preserveSource: this.shouldPreserveChapterSource(file)
    }];
  }

  private rebuildGroupsChapters(file: BatchFileInfo): void {
    for (let i = 0; i < this.groups.length; i++) {
      const group = this.groups[i];
      if (group.files.includes(file)) {
        // 克隆 chapters 数组，触发深度变化检测
        this.groups[i].chapters = group.chapters.slice();
      }
    }
    this.groups = this.groups.slice();
  }
  
  /**
   * 深度更新所有分组的 chapters 数组（用于批量操作）
   */
  private rebuildAllGroupsChapters(): void {
    for (let i = 0; i < this.groups.length; i++) {
      this.groups[i].chapters = this.groups[i].chapters.slice();
    }
    this.groups = this.groups.slice();
  }

  /**
   * 构建操作按钮
   */
  @Builder
  buildActionButtons() {
    Row({ space: 12 }) {
      Button('取消')
        .fontSize(15)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .borderRadius(8)
        .height(44)
        .layoutWeight(1)
        .fontFamily(this.appFontFamily)
        .enabled(!this.isActionLocked)
        .onClick(() => {
          if (this.isActionLocked) {
            return;
          }
          this.isActionLocked = true;
          this.emitFlowEvent(ImportFlowEventType.DIALOG_CANCELLED, 'batch_dialog_cancelled', true, '', '', 0, this.files.length, 0);
          this.onCancel();
          this.controller.close();
        })

      Button('开始导入')
        .fontSize(15)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(8)
        .height(44)
        .layoutWeight(1)
        .fontFamily(this.appFontFamily)
        .enabled(!this.isActionLocked)
        .onClick(() => {
          if (this.isActionLocked || !this.validateForm()) {
            return;
          }
          const result = this.buildResult();
          this.isActionLocked = true;
          this.emitFlowEvent(ImportFlowEventType.DIALOG_CONFIRMED, 'batch_dialog_confirmed', true, '', `groups=${result.groups.length}`, result.groups.length, result.groups.length, 0);
          this.onConfirm(result);
          this.controller.close();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 20 })
  }

  /**
   * 获取导入模式标签
   */
  private getImportModeLabel(mode: MangaImportMode): string {
    switch (mode) {
      case MangaImportMode.TANKOUBON:
        return '单行本';
      case MangaImportMode.SINGLE_CHAPTER:
        return '多章节';
      case MangaImportMode.MULTI_CHAPTER:
        return '嵌套章节';
      default:
        return '未知';
    }
  }

  /**
   * 获取分组总页数
   */
  private getTotalPages(group: MangaGroup): number {
    return group.chapters
      .filter((chapter: BatchChapterInfo) => chapter.file.enabled)
      .reduce((sum, chapter) => sum + chapter.pageCount, 0);
  }
  
  /**
   * 分组是否存在可参与导入的启用文件
   */
  private hasEnabledFiles(group: MangaGroup): boolean {
    return group.files.some((file: BatchFileInfo) => file.enabled && !file.parseError);
  }
  
  private getEnabledGroupCount(): number {
    return this.groups.filter((group: MangaGroup) => this.hasEnabledFiles(group)).length;
  }
  
  /**
   * 检查分组是否包含xml信息
   */
  private hasXmlInfo(group: MangaGroup): boolean {
    return group.files.some(file => file.prefilledInfo !== null);
  }
  
  /**
   * 检查章节是否可能已存在于目标漫画中
   */
  private checkChapterExistence(groupIndex: number, chapterIndex: number): void {
    const group = this.groups[groupIndex];
    if (!group.mergeToExisting || !group.targetMangaId) {
      group.chapters[chapterIndex].mayExist = false;
      return;
    }
    
    // 查找目标漫画
    const targetManga = this.existingMangaCandidates.find(m => m.id === group.targetMangaId);
    if (!targetManga) {
      group.chapters[chapterIndex].mayExist = false;
      return;
    }
    
    // 检查章节编号是否在目标漫画的章节范围内
    const chapterNumber = group.chapters[chapterIndex].number;
    group.chapters[chapterIndex].mayExist = chapterNumber <= targetManga.chapterCount;
  }
  
  /**
   * 检查分组中所有章节的存在性
   */
  private checkAllChaptersExistence(groupIndex: number): void {
    const group = this.groups[groupIndex];
    for (let i = 0; i < group.chapters.length; i++) {
      this.checkChapterExistence(groupIndex, i);
    }
  }
  
  /**
   * 选择目标漫画进行合并
   */
  private selectTargetManga(groupIndex: number, mangaId: string): void {
    if (groupIndex >= 0 && groupIndex < this.groups.length) {
      this.groups[groupIndex].targetMangaId = mangaId;
      // 检查所有章节的存在性
      this.checkAllChaptersExistence(groupIndex);
      this.groups = this.groups.slice();
      logger.info(TAG, `选择目标漫画: groupIndex=${groupIndex}, mangaId=${mangaId}`);
    }
  }
  
  /**
   * 创建章节信息对象
   */
  private createChapterInfo(file: BatchFileInfo, prefilledInfo: PrefilledComicInfo | null): BatchChapterInfo {
    const chapterInfo: BatchChapterInfo = {
      number: file.inferredChapterNumber || 1,
      title: prefilledInfo?.title || `第${file.inferredChapterNumber || 1}话`,
      file: file,
      pageCount: this.getDefaultChapterPageCount(file),
      sourcePath: this.getDefaultChapterSourcePath(file),
      preserveSource: this.shouldPreserveChapterSource(file)
    };
    return chapterInfo;
  }
  
  /**
   * 打开刮削对话框（针对特定分组）
   */
  private openScraperDialogForGroup(groupIndex: number): void {
    this.currentScrapingGroupIndex = groupIndex;
    const group = this.groups[groupIndex];
    
    const config: ScraperDialogConfig = {
      contentType: ScraperContentType.MANGA,
      initialKeyword: group.title
    };

    this.scraperDialogController = new CustomDialogController({
      builder: ScraperDialog({
        config: config,
        themeState: this.themeState,
        onConfirm: (result: ScraperDialogResult) => {
          if (this.isDisposed) {
            return;
          }
          this.applyScraperResultToGroup(result);
          this.scraperDialogController?.close();
        },
        onCancel: () => {
          this.scraperDialogController?.close();
        }
      }),
      autoCancel: true,
      customStyle: true,
      alignment: DialogAlignment.Center
    });

    this.scraperDialogController.open();
  }

  /**
   * 应用刮削结果到分组
   */
  private applyScraperResultToGroup(result: ScraperDialogResult): void {
    if (this.currentScrapingGroupIndex < 0 || this.currentScrapingGroupIndex >= this.groups.length) {
      return;
    }
    
    const metadata = result.metadata;
    const groupIndex = this.currentScrapingGroupIndex;
    
    if (metadata.title) {
      this.groups[groupIndex].title = metadata.title;
    }
    if (result.applyAuthor && metadata.author) {
      this.groups[groupIndex].author = metadata.author;
    }
    if (metadata.description) {
      this.groups[groupIndex].description = metadata.description;
    }
    if (metadata.tags && metadata.tags.length > 0) {
      this.groups[groupIndex].tags = metadata.tags;
    }
    
    // 触发UI更新
    this.groups = this.groups.slice();
    
    logger.info(TAG, `应用刮削结果到分组 ${groupIndex}: ${metadata.title}`);
    this.currentScrapingGroupIndex = -1;
  }
}
