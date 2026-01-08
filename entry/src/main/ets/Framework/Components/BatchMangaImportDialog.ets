// 文件路径: entry/src/main/ets/Framework/Components/BatchMangaImportDialog.ets
/**
 * 批量漫画导入配置对话框
 * 支持智能分组、批量配置、章节识别等功能
 */

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { FontAwareHelper, FontAwareState } from './FontAware';
import { logger } from '../../Utils/Logger';
import { fileIo } from '@kit.CoreFileKit';
import { MangaImportMode, ChapterInfo, ParsedArchiveStructure, PrefilledComicInfo, ExistingMangaCandidate } from './MangaImportDialog';
import { ScraperDialog, ScraperDialogConfig, ScraperDialogResult } from './ScraperDialog';
import { ScraperContentType } from '../Scraper/ScraperTypes';

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
  /** 推测的章节编号 */
  inferredChapterNumber: number;
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
  COMPLETED = 'completed'
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
  // 解析文件结构的回调
  parseFileStructure: (fileUri: string) => Promise<ParsedArchiveStructure | null> = async () => null;
  // 解析ComicInfo.xml的回调
  parseComicInfoXml: (xmlContent: string) => PrefilledComicInfo | null = () => null;

  // 状态
  @State files: BatchFileInfo[] = [];
  @State groups: MangaGroup[] = [];
  @State isAnalyzing: boolean = true;
  @State analyzeProgress: number = 0;
  @State analyzeMessage: string = '正在分析文件...';
  @State currentTab: number = 0; // 0: 分组视图, 1: 文件列表视图
  // 文件列表多选状态
  @State selectedFileIndices: Set<number> = new Set<number>();
  @State isMultiSelectMode: boolean = false;
  
  // 刮削对话框控制器
  private scraperDialogController: CustomDialogController | null = null;
  // 当前正在刮削的分组索引
  private currentScrapingGroupIndex: number = -1;

  aboutToAppear(): void {
    this.initializeFiles();
    this.startAnalysis();
  }

  /**
   * 初始化文件列表
   */
  private initializeFiles(): void {
    this.files = this.fileUris.map((uri: string) => {
      const fileName = this.getFileNameFromUri(uri);
      return {
        fileUri: uri,
        fileName: fileName,
        parsedStructure: null,
        prefilledInfo: null,
        inferredTitle: this.inferTitleFromFileName(fileName),
        inferredChapterNumber: this.inferChapterNumberFromFileName(fileName),
        isParsing: true,
        parseError: null
      } as BatchFileInfo;
    });
  }

  /**
   * 开始分析所有文件
   */
  private async startAnalysis(): Promise<void> {
    this.isAnalyzing = true;
    this.analyzeProgress = 0;
    
    const totalFiles = this.files.length;
    
    for (let i = 0; i < this.files.length; i++) {
      const file = this.files[i];
      this.analyzeMessage = `正在解析 (${i + 1}/${totalFiles}): ${file.fileName}`;
      this.analyzeProgress = ((i + 1) / totalFiles) * 80;
      
      try {
        // 解析文件结构
        const structure = await this.parseFileStructure(file.fileUri);
        file.parsedStructure = structure;
        file.isParsing = false;
        
        if (!structure) {
          logger.warn(TAG, `文件结构解析返回空: ${file.fileName}`);
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
        
        // 触发UI更新
        this.files = this.files.slice();
        
      } catch (error) {
        file.isParsing = false;
        file.parseError = String(error);
        logger.error(TAG, `解析文件失败: ${file.fileName}`, String(error));
        // 确保UI更新
        this.files = this.files.slice();
      }
    }
    
    // 智能分组
    this.analyzeMessage = '正在智能分组...';
    this.analyzeProgress = 90;
    await this.performSmartGrouping();
    
    this.analyzeMessage = '分析完成';
    this.analyzeProgress = 100;
    this.isAnalyzing = false;
  }

  /**
   * 执行智能分组
   */
  private async performSmartGrouping(): Promise<void> {
    // 按推测标题分组
    const groupMap = new Map<string, BatchFileInfo[]>();
    
    for (const file of this.files) {
      if (file.parseError) continue;
      
      const normalizedTitle = this.normalizeTitle(file.inferredTitle);
      
      if (!groupMap.has(normalizedTitle)) {
        groupMap.set(normalizedTitle, []);
      }
      groupMap.get(normalizedTitle)!.push(file);
    }
    
    // 创建分组
    this.groups = [];
    let groupIndex = 0;
    
    groupMap.forEach((files: BatchFileInfo[], title: string) => {
      // 按章节编号排序
      files.sort((a, b) => a.inferredChapterNumber - b.inferredChapterNumber);
      
      // 获取第一个文件的预填充信息作为默认值
      const firstFile = files[0];
      const prefilledInfo = firstFile.prefilledInfo;
      
      // 创建章节列表
      const chapters: BatchChapterInfo[] = files.map((file: BatchFileInfo, index: number) => {
        // 优先使用xml中的章节标题
        const chapterTitle = file.prefilledInfo?.title || `第${file.inferredChapterNumber || (index + 1)}话`;
        const chapterInfo: BatchChapterInfo = {
          number: file.inferredChapterNumber || (index + 1),
          title: chapterTitle,
          file: file,
          pageCount: file.parsedStructure?.totalImageCount || 0
        };
        return chapterInfo;
      });
      
      // 确定导入模式
      let importMode = MangaImportMode.TANKOUBON;
      if (files.length > 1) {
        // 多个文件，使用多章节模式（每个文件作为一个章节）
        importMode = MangaImportMode.SINGLE_CHAPTER;
      } else if (firstFile.parsedStructure?.detectedChapters && 
                 firstFile.parsedStructure.detectedChapters.length > 1) {
        // 单个文件但包含多个章节
        importMode = MangaImportMode.MULTI_CHAPTER;
      }
      
      // 初始化封面候选
      const coverCandidates = this.initCoverCandidatesForGroup(files);
      
      // 获取漫画标题
      const groupTitle = prefilledInfo?.series || prefilledInfo?.title || this.denormalizeTitle(title);
      
      // 自动检测是否有同名的已有漫画
      const matchedManga = this.findMatchingExistingManga(groupTitle);
      const shouldMerge = matchedManga !== null;
      const targetId = matchedManga?.id || '';
      
      const group: MangaGroup = {
        groupId: `group_${groupIndex++}`,
        title: groupTitle,
        author: prefilledInfo?.author || '',
        description: prefilledInfo?.description || '',
        tags: prefilledInfo?.tags || [],
        files: files,
        chapters: chapters,
        isExpanded: true,
        importMode: importMode,
        mergeToExisting: shouldMerge,
        targetMangaId: targetId,
        selectedCoverFileIndex: 0,
        coverCandidates: coverCandidates,
        selectedCoverIndex: 0,
        status: MangaStatus.UNKNOWN,
        isNSFW: false
      };
      
      if (shouldMerge && matchedManga) {
        logger.info(TAG, `自动匹配到已有漫画: ${groupTitle} -> ${matchedManga.title} (${matchedManga.id})`);
      }
      
      this.groups.push(group);
    });
    
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
    
    // 精确匹配
    for (const manga of this.existingMangaCandidates) {
      if (this.normalizeTitle(manga.title) === normalizedTitle) {
        return manga;
      }
    }
    
    // 模糊匹配（包含关系）
    for (const manga of this.existingMangaCandidates) {
      const normalizedMangaTitle = this.normalizeTitle(manga.title);
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
    const candidates: string[] = [];
    
    // 从第一个文件获取封面候选
    const firstFile = files[0];
    if (firstFile.parsedStructure?.extractedPath) {
      try {
        const extractedPath = firstFile.parsedStructure.extractedPath;
        const imageExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];
        
        const fileList = fileIo.listFileSync(extractedPath);
        const imageFiles: string[] = [];
        
        for (const file of fileList) {
          const lowerFile = file.toLowerCase();
          for (const ext of imageExtensions) {
            if (lowerFile.endsWith(ext)) {
              imageFiles.push(`${extractedPath}/${file}`);
              break;
            }
          }
        }
        
        imageFiles.sort();
        return imageFiles.slice(0, 3);
      } catch (error) {
        logger.error(TAG, `获取封面候选失败: ${error}`);
      }
    }
    
    return candidates;
  }

  /**
   * 从文件名推测漫画标题
   */
  private inferTitleFromFileName(fileName: string): string {
    // 移除扩展名
    let title = fileName;
    const lastDotIndex = title.lastIndexOf('.');
    if (lastDotIndex > 0) {
      title = title.substring(0, lastDotIndex);
    }
    
    // 移除常见的章节标识
    const patterns: RegExp[] = [
      /[\[\(【（]\d+[\]\)】）]/g,           // [1], (1), 【1】, （1）
      /第\d+[话話章回卷]/g,                  // 第1话、第1章
      /[话話章回卷]\d+/g,                    // 话1、章1
      /[Cc]h(?:apter)?[.\s]*\d+/gi,        // Ch.1, Chapter 1
      /[Ee]p(?:isode)?[.\s]*\d+/gi,        // Ep.1, Episode 1
      /[Vv]ol(?:ume)?[.\s]*\d+/gi,         // Vol.1, Volume 1
      /[_\-\s]+\d{1,4}[_\-\s]*/g,          // _001_, -01-
      /\s*\d{1,4}$/g                        // 末尾的数字
    ];
    
    for (const pattern of patterns) {
      title = title.replace(pattern, '');
    }
    
    // 清理多余的空格和符号
    title = title.replace(/[\s_\-]+/g, ' ').trim();
    
    // 如果标题为空，使用原文件名
    if (!title) {
      title = fileName.substring(0, lastDotIndex > 0 ? lastDotIndex : fileName.length);
    }
    
    return title;
  }

  /**
   * 从文件名推测章节编号
   */
  private inferChapterNumberFromFileName(fileName: string): number {
    const patterns: RegExp[] = [
      /第(\d+)[话話章回卷]/,           // 第1话、第1章
      /[话話章回卷](\d+)/,              // 话1、章1
      /[Cc]h(?:apter)?[.\s]*(\d+)/i,   // Ch.1, Chapter 1
      /[Ee]p(?:isode)?[.\s]*(\d+)/i,   // Ep.1, Episode 1
      /[Vv]ol(?:ume)?[.\s]*(\d+)/i,    // Vol.1, Volume 1
      /[\[\(【（](\d+)[\]\)】）]/,      // [1], (1), 【1】, （1）
      /[_\-\s](\d{1,4})[_\-\s.]/,      // _001_, -01-
      /(\d{1,4})$/                      // 末尾的数字
    ];

    for (const pattern of patterns) {
      const match = fileName.match(pattern);
      if (match && match[1]) {
        const num = parseInt(match[1], 10);
        if (num > 0 && num < 10000) {
          return num;
        }
      }
    }

    return 1;
  }

  /**
   * 标准化标题（用于分组比较）
   */
  private normalizeTitle(title: string): string {
    return title.toLowerCase()
      .replace(/[\s_\-]+/g, '')
      .replace(/[^\w\u4e00-\u9fa5]/g, '');
  }

  /**
   * 反标准化标题
   */
  private denormalizeTitle(normalizedTitle: string): string {
    // 尝试从文件中找到原始标题
    for (const file of this.files) {
      if (this.normalizeTitle(file.inferredTitle) === normalizedTitle) {
        return file.inferredTitle;
      }
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
   * 验证表单
   */
  private validateForm(): boolean {
    for (const group of this.groups) {
      if (!group.title || group.title.trim().length === 0) {
        this.showToast('请为所有漫画输入标题');
        return false;
      }
      
      if (group.mergeToExisting && !group.targetMangaId) {
        this.showToast(`请为"${group.title}"选择要合并的目标漫画`);
        return false;
      }
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
   * 构建结果
   */
  private buildResult(): BatchMangaImportDialogResult {
    const groupResults: MangaGroupResult[] = this.groups.map((group: MangaGroup) => {
      const chapterResults: BatchChapterResult[] = group.chapters.map((chapter: BatchChapterInfo) => {
        const result: BatchChapterResult = {
          number: chapter.number,
          title: chapter.title,
          fileUri: chapter.file.fileUri,
          parsedStructure: chapter.file.parsedStructure
        };
        return result;
      });
      
      // 获取选中的封面路径
      let selectedCoverPath = '';
      if (group.coverCandidates.length > 0 && group.selectedCoverIndex < group.coverCandidates.length) {
        selectedCoverPath = group.coverCandidates[group.selectedCoverIndex];
      }
      
      return {
        title: group.title.trim(),
        author: group.author.trim() || '未知作者',
        description: group.description.trim(),
        tags: group.tags,
        importMode: group.importMode,
        chapters: chapterResults,
        mergeToExisting: group.mergeToExisting,
        targetMangaId: group.mergeToExisting ? group.targetMangaId : undefined,
        selectedCoverPath: selectedCoverPath
      } as MangaGroupResult;
    });
    
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
        
        // 内容区域
        if (this.currentTab === 0) {
          this.buildGroupsView()
        } else {
          this.buildFilesListView()
        }
        
        // 操作按钮
        this.buildActionButtons()
      }
    }
    .width('100%')
    .height('90%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(16)
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
      this.buildTabItem('分组视图', 0, `${this.groups.length} 部漫画`)
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
    }
    .layoutWeight(1)
    .padding({ top: 12, bottom: 8 })
    .onClick(() => {
      this.currentTab = index;
    })
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
  
  /**
   * 构建分组视图
   */
  @Builder
  buildGroupsView() {
    Scroll() {
      Column({ space: 12 }) {
        ForEach(this.groups, (group: MangaGroup) => {
          this.buildGroupCardById(group.groupId)
        }, (group: MangaGroup) => `${group.groupId}_${group.isExpanded}_${group.mergeToExisting}_${group.targetMangaId}_${group.title}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    }
    .layoutWeight(1)
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
  }
  
  /**
   * 根据groupId构建分组卡片
   */
  @Builder
  buildGroupCardById(groupId: string) {
    // 在渲染时动态查找索引并构建
    this.buildGroupCard(this.getGroupByIdOrFirst(groupId), this.findGroupIndex(groupId))
  }
  
  /**
   * 根据groupId获取分组，如果找不到返回第一个
   */
  private getGroupByIdOrFirst(groupId: string): MangaGroup {
    const idx = this.findGroupIndex(groupId);
    return idx >= 0 ? this.groups[idx] : this.groups[0];
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
          SymbolGlyph(group.isExpanded ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
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
          TextInput({ text: group.title, placeholder: '漫画标题' })
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
          
          // 章节统计
          Text(`${group.chapters.length} 个章节 · ${this.getTotalPages(group)} 页`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        
        // 拆分按钮（仅当分组有多个文件时显示）
        if (group.files.length > 1) {
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
      if (group.isExpanded) {
        Column({ space: 12 }) {
          // 来源信息提示（如果有xml信息）
          if (this.hasXmlInfo(group)) {
            Row({ space: 4 }) {
              Text('📄')
                .fontSize(12)
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
          this.buildInputField('作者', group.author, '请输入作者', (value: string) => {
            this.groups[groupIndex].author = value;
          })
          
          // 简介输入（如果有xml信息则显示）
          if (group.description) {
            this.buildInputField('简介', group.description, '漫画简介', (value: string) => {
              this.groups[groupIndex].description = value;
            })
          }
          
          // 标签输入
          this.buildInputField('标签', group.tags.join(', '), '逗号分隔', (value: string) => {
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
      }
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
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
            .fontColor(group.status === MangaStatus.UNKNOWN ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(group.status === MangaStatus.UNKNOWN ?
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
            .fontColor(group.status === MangaStatus.ONGOING ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(group.status === MangaStatus.ONGOING ?
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
            .fontColor(group.status === MangaStatus.COMPLETED ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
              ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(group.status === MangaStatus.COMPLETED ?
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
        
        Toggle({ type: ToggleType.Switch, isOn: group.isNSFW })
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
        
        if (group.coverCandidates.length > 0) {
          Text(`已选第 ${group.selectedCoverIndex + 1} 张`)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
      }
      .width('100%')
      
      if (group.coverCandidates.length === 0) {
        Text('暂无封面候选')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      } else {
        Row({ space: 8 }) {
          ForEach(group.coverCandidates, (path: string, index: number) => {
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
                Text('✓')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor('#FFFFFF')
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .borderRadius(10)
                  .width(20)
                  .height(20)
                  .textAlign(TextAlign.Center)
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
   * 构建章节列表
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
        
        Text(`共 ${group.chapters.length} 章`)
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')
      
      // 章节列表（最多显示5个，其余折叠）
      Column({ space: 4 }) {
        ForEach(group.chapters.slice(0, 5), (chapter: BatchChapterInfo, chapterIndex: number) => {
          this.buildChapterItem(chapter, groupIndex, chapterIndex)
        }, (chapter: BatchChapterInfo, index: number) => `chapter_${groupIndex}_${index}`)
        
        if (group.chapters.length > 5) {
          Text(`... 还有 ${group.chapters.length - 5} 个章节`)
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
              this.groups[groupIndex].chapters[chapterIndex].number = num;
              // 检查章节是否可能已存在
              this.checkChapterExistence(groupIndex, chapterIndex);
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
            this.groups[groupIndex].chapters[chapterIndex].title = value;
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
            .fontColor(['#FF9800'])
          Text('该章节可能已存在于目标漫画中')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor('#FF9800')
        }
        .width('100%')
        .padding({ left: 53 })
      }
    }
    .width('100%')
  }

  /**
   * 构建合并选项
   */
  @Builder
  buildMergeOptions(group: MangaGroup, groupIndex: number) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Checkbox()
          .select(group.mergeToExisting)
          .onChange((value: boolean) => {
            this.toggleMergeToExisting(groupIndex, value);
          })
        
        Text('合并到已有漫画')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        // 如果已自动匹配，显示提示
        if (group.mergeToExisting && group.targetMangaId) {
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
          if (!group.mergeToExisting) {
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
                if (group.targetMangaId === manga.id && group.mergeToExisting) {
                  SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                    .fontSize(20)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                } else {
                  SymbolGlyph($r('sys.symbol.circle'))
                    .fontSize(20)
                    .fontColor([group.mergeToExisting ? 
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
                  .fontColor(group.mergeToExisting ? 
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
            .backgroundColor(group.targetMangaId === manga.id && group.mergeToExisting ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15' :
              'transparent')
            .borderRadius(4)
            .opacity(group.mergeToExisting ? 1.0 : 0.5)
            .onClick(() => {
              if (group.mergeToExisting) {
                this.selectTargetManga(groupIndex, manga.id);
              }
            })
          }, (manga: ExistingMangaCandidate) => `${manga.id}_${group.mergeToExisting}_${group.targetMangaId}`)
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
   * 构建文件列表视图
   */
  @Builder
  buildFilesListView() {
    Column({ space: 0 }) {
      // 操作栏
      this.buildFileListToolbar()
      
      Scroll() {
        Column({ space: 8 }) {
          ForEach(this.files, (file: BatchFileInfo, index: number) => {
            this.buildFileItem(file, index)
          }, (file: BatchFileInfo, index: number) => `file_${index}_${this.selectedFileIndices.has(index)}`)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      }
      .layoutWeight(1)
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .layoutWeight(1)
  }
  
  /**
   * 构建文件列表工具栏
   */
  @Builder
  buildFileListToolbar() {
    Row({ space: 8 }) {
      // 多选模式切换
      Row({ space: 4 }) {
        Checkbox()
          .select(this.isMultiSelectMode)
          .onChange((value: boolean) => {
            this.isMultiSelectMode = value;
            if (!value) {
              this.selectedFileIndices.clear();
              this.selectedFileIndices = new Set<number>(this.selectedFileIndices);
            }
          })
        Text('多选')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      
      if (this.isMultiSelectMode && this.selectedFileIndices.size > 0) {
        Text(`已选 ${this.selectedFileIndices.size} 个`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        
        // 合并按钮
        Button('合并为一部漫画')
          .fontSize(11)
          .height(28)
          .padding({ left: 8, right: 8 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .fontColor('#FFFFFF')
          .borderRadius(4)
          .enabled(this.selectedFileIndices.size >= 2)
          .onClick(() => {
            this.mergeSelectedFiles();
          })
      }
      
      Blank()
      
      // 全选/取消全选
      if (this.isMultiSelectMode) {
        Text(this.selectedFileIndices.size === this.files.length ? '取消全选' : '全选')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(() => {
            if (this.selectedFileIndices.size === this.files.length) {
              this.selectedFileIndices.clear();
            } else {
              for (let i = 0; i < this.files.length; i++) {
                this.selectedFileIndices.add(i);
              }
            }
            this.selectedFileIndices = new Set<number>(this.selectedFileIndices);
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
  }
  
  /**
   * 合并选中的文件为一个分组
   */
  private mergeSelectedFiles(): void {
    if (this.selectedFileIndices.size < 2) return;
    
    const selectedIndices = Array.from(this.selectedFileIndices).sort((a, b) => a - b);
    const selectedFiles: BatchFileInfo[] = selectedIndices.map(i => this.files[i]);
    
    // 收集被合并分组的用户自定义信息
    let customTitle = '';
    let customAuthor = '';
    let customDescription = '';
    let customTags: string[] = [];
    
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
    const prefilledInfo = firstFile.prefilledInfo;
    
    // 按章节编号排序
    selectedFiles.sort((a, b) => a.inferredChapterNumber - b.inferredChapterNumber);
    
    // 创建章节列表
    const chapters: BatchChapterInfo[] = selectedFiles.map((file: BatchFileInfo, index: number) => {
      const chapterInfo: BatchChapterInfo = {
        number: file.inferredChapterNumber || (index + 1),
        title: file.prefilledInfo?.title || `第${file.inferredChapterNumber || (index + 1)}话`,
        file: file,
        pageCount: file.parsedStructure?.totalImageCount || 0
      };
      return chapterInfo;
    });
    
    // 优先使用用户自定义信息，其次使用xml信息，最后使用推测信息
    const finalTitle = customTitle || prefilledInfo?.series || prefilledInfo?.title || firstFile.inferredTitle;
    const finalAuthor = customAuthor || prefilledInfo?.author || '';
    const finalDescription = customDescription || prefilledInfo?.description || '';
    const finalTags = customTags.length > 0 ? customTags : (prefilledInfo?.tags || []);
    
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
      status: MangaStatus.UNKNOWN,
      isNSFW: false
    };
    
    this.groups.push(newGroup);
    this.groups = this.groups.slice();
    
    // 清除选择
    this.selectedFileIndices.clear();
    this.selectedFileIndices = new Set<number>(this.selectedFileIndices);
    this.isMultiSelectMode = false;
    
    // 切换到分组视图
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
    const originalTags = group.tags.slice();
    
    // 移除原分组
    this.groups.splice(groupIndex, 1);
    
    // 为每个文件创建单独的分组
    for (const file of group.files) {
      const prefilledInfo = file.prefilledInfo;
      
      // 优先使用xml信息，其次使用原分组的用户自定义信息
      const newGroup: MangaGroup = {
        groupId: `group_split_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
        title: prefilledInfo?.series || prefilledInfo?.title || file.inferredTitle,
        author: prefilledInfo?.author || originalAuthor,
        description: prefilledInfo?.description || '',
        tags: prefilledInfo?.tags || originalTags,
        files: [file],
        chapters: [this.createChapterInfo(file, prefilledInfo)],
        isExpanded: false,
        importMode: MangaImportMode.TANKOUBON,
        mergeToExisting: false,
        targetMangaId: '',
        selectedCoverFileIndex: 0,
        coverCandidates: this.initCoverCandidatesForGroup([file]),
        selectedCoverIndex: 0,
        status: MangaStatus.UNKNOWN,
        isNSFW: false
      };
      
      this.groups.push(newGroup);
    }
    
    this.groups = this.groups.slice();
    logger.info(TAG, `拆分分组为 ${group.files.length} 个单独分组`);
  }

  /**
   * 构建文件项
   */
  @Builder
  buildFileItem(file: BatchFileInfo, index: number) {
    Row({ space: 12 }) {
      // 多选复选框
      if (this.isMultiSelectMode) {
        Checkbox()
          .select(this.selectedFileIndices.has(index))
          .onChange((value: boolean) => {
            if (value) {
              this.selectedFileIndices.add(index);
            } else {
              this.selectedFileIndices.delete(index);
            }
            this.selectedFileIndices = new Set<number>(this.selectedFileIndices);
          })
      }
      
      // 状态图标
      if (file.isParsing) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      } else if (file.parseError) {
        Text('❌')
          .fontSize(16)
          .fontFamily(this.appFontFamily)
      } else {
        Text('✅')
          .fontSize(16)
          .fontFamily(this.appFontFamily)
      }
      
      // 文件信息
      Column({ space: 2 }) {
        Text(file.fileName)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        if (file.parseError) {
          Text(file.parseError)
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor('#F44336')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else if (file.parsedStructure) {
          // 显示xml信息（如果有）
          if (file.prefilledInfo) {
            Text(`${file.parsedStructure.totalImageCount} 页 · ${file.prefilledInfo.series || file.prefilledInfo.title || file.inferredTitle} 第${file.inferredChapterNumber}话`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          } else {
            Text(`${file.parsedStructure.totalImageCount} 页 · 推测: ${file.inferredTitle} 第${file.inferredChapterNumber}话`)
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      
      // 导入模式标签（可点击切换）
      if (!file.isParsing && !file.parseError) {
        Text(this.getFileImportModeLabel(file))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .padding({ left: 6, right: 6, top: 3, bottom: 3 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20')
          .borderRadius(4)
          .onClick(() => {
            this.cycleFileImportMode(index);
          })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.selectedFileIndices.has(index) ?
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15' :
      ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(8)
    .border({
      width: this.selectedFileIndices.has(index) ? 2 : 0,
      color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
    })
    .onClick(() => {
      if (this.isMultiSelectMode) {
        if (this.selectedFileIndices.has(index)) {
          this.selectedFileIndices.delete(index);
        } else {
          this.selectedFileIndices.add(index);
        }
        this.selectedFileIndices = new Set<number>(this.selectedFileIndices);
      }
    })
  }
  
  /**
   * 获取文件的导入模式标签
   */
  private getFileImportModeLabel(file: BatchFileInfo): string {
    // 查找文件所属的分组
    for (const group of this.groups) {
      if (group.files.includes(file)) {
        return this.getImportModeLabel(group.importMode);
      }
    }
    return '单行本';
  }
  
  /**
   * 循环切换文件的导入模式
   */
  private cycleFileImportMode(fileIndex: number): void {
    const file = this.files[fileIndex];
    
    // 查找文件所属的分组
    for (let i = 0; i < this.groups.length; i++) {
      const group = this.groups[i];
      if (group.files.includes(file)) {
        // 循环切换模式
        const modes = [MangaImportMode.TANKOUBON, MangaImportMode.SINGLE_CHAPTER, MangaImportMode.MULTI_CHAPTER];
        const currentIndex = modes.indexOf(group.importMode);
        const nextIndex = (currentIndex + 1) % modes.length;
        this.groups[i].importMode = modes[nextIndex];
        this.groups = this.groups.slice();
        break;
      }
    }
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
        .onClick(() => {
          this.onCancel();
          this.controller.close();
        })

      Button('开始导入')
        .fontSize(15)
        .fontColor('#FFFFFF')
        .backgroundColor('#2196F3')
        .borderRadius(8)
        .height(44)
        .layoutWeight(1)
        .fontFamily(this.appFontFamily)
        .onClick(() => {
          if (this.validateForm()) {
            const result = this.buildResult();
            this.onConfirm(result);
            this.controller.close();
          }
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
    return group.chapters.reduce((sum, chapter) => sum + chapter.pageCount, 0);
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
      pageCount: file.parsedStructure?.totalImageCount || 0
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
