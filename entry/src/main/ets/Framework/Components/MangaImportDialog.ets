import { SafeFileUtils } from '../../Utils/SafeFileUtils';
// 文件路径: entry/src/main/ets/Framework/Components/MangaImportDialog.ets
/**
 * 漫画导入配置对话框
 * 支持单行本、单章节、多章节三种导入模式
 * 支持无XML信息的压缩包导入
 * 支持刮削工具获取元数据
 */

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { FontAwareHelper, FontAwareState } from './FontAware';
import { logger } from '../../Utils/Logger';
import { removeFileExtension } from '../../Utils/FileNameUtils';
import { promptAction } from '@kit.ArkUI';
import { AppColors } from '../Theme/AppColors';
import { ScraperDialog, ScraperDialogConfig, ScraperDialogResult } from './ScraperDialog';
import { ScraperContentType } from '../Scraper/ScraperTypes';
import { fileIo } from '@kit.CoreFileKit';
import { ImportFlowContentType, ImportFlowEvent, ImportFlowEventType } from '../Import/ImportFlowTypes';

const TAG = 'MangaImportDialog';

/**
 * 漫画导入模式枚举
 */
export enum MangaImportMode {
  /** 单行本模式：整个压缩包作为一部完整的漫画（单章节） */
  TANKOUBON = 'tankoubon',
  /** 单章节模式：压缩包作为某部漫画的一个章节 */
  SINGLE_CHAPTER = 'single_chapter',
  /** 多章节模式：压缩包内包含多个章节（子文件夹或嵌套压缩包） */
  MULTI_CHAPTER = 'multi_chapter'
}

/**
 * 章节信息
 */
export interface ChapterInfo {
  /** 章节索引（用于排序） */
  index: number;
  /** 章节编号（显示用） */
  number: number;
  /** 章节标题 */
  title: string;
  /** 原始文件夹/压缩包名称 */
  originalName: string;
  /** 文件路径 */
  path: string;
  /** 页面数量 */
  pageCount: number;
}

/**
 * 预填充信息（从ComicInfo.xml解析）
 */
export interface PrefilledComicInfo {
  title?: string;
  series?: string;
  author?: string;
  description?: string;
  tags?: string[];
  number?: string;
}

/**
 * 解析后的压缩包结构
 * 注意：此接口与CompressionUtils中的ParsedArchiveStructure兼容
 */
export interface ParsedArchiveStructure {
  /** 是否包含ComicInfo.xml */
  hasComicInfo: boolean;
  /** ComicInfo.xml内容 */
  comicInfoContent?: string;
  /** 是否为多层结构（包含子文件夹或嵌套压缩包） */
  isMultiLayer: boolean;
  /** 检测到的章节列表 */
  detectedChapters: ChapterInfo[];
  /** 根目录图片数量（非章节目录的图片） */
  rootImageCount: number;
  /** 总图片数量 */
  totalImageCount: number;
  /** 解压后的根路径 */
  extractedPath: string;
  /** 临时目录列表（需要清理） */
  tempDirectories: string[];
  /** 警告信息 */
  warnings: string[];
  /** 预填充信息（从ComicInfo.xml解析） */
  prefilledInfo?: PrefilledComicInfo;
}

/**
 * 漫画导入对话框结果
 */
export interface MangaImportDialogResult {
  /** 导入模式 */
  importMode: MangaImportMode;
  /** 漫画标题 */
  title: string;
  /** 作者 */
  author: string;
  /** 简介 */
  description: string;
  /** 标签 */
  tags: string[];
  /** 章节列表（多章节模式） */
  chapters: ChapterInfo[];
  /** 单章节模式：章节编号 */
  chapterNumber?: number;
  /** 单章节模式：章节标题 */
  chapterTitle?: string;
  /** 是否合并到已有漫画 */
  mergeToExisting: boolean;
  /** 合并目标漫画ID */
  targetMangaId?: string;
  /** 解析后的结构信息 */
  parsedStructure: ParsedArchiveStructure;
  /** 选择的封面图片路径 */
  selectedCoverPath: string;
  /** 原文件URI（用于导入后删除） */
  sourceFileUri?: string;
}

/**
 * 已存在的漫画候选项
 */
export interface ExistingMangaCandidate {
  id: string;
  title: string;
  author: string;
  coverUrl: string;
  chapterCount: number;
}

/**
 * 漫画导入配置对话框
 */
@CustomDialog
export struct MangaImportDialog {
  controller: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @Prop fileName: string = '';
  @Prop parsedStructure: ParsedArchiveStructure;
  @Prop existingMangaCandidates: ExistingMangaCandidate[] = [];
  @Prop sourceFileUri: string = '';
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // 回调函数
  onConfirm: (result: MangaImportDialogResult) => void = () => {};
  onCancel: () => void = () => {};
  onFlowEvent: (event: ImportFlowEvent) => void = () => {};

  // 表单状态
  @State importMode: MangaImportMode = MangaImportMode.TANKOUBON;
  @State title: string = '';
  @State author: string = '';
  @State description: string = '';
  @State tagsText: string = '';
  
  // 章节信息
  @State chapters: ChapterInfo[] = [];
  @State chapterNumber: number = 1;
  @State chapterTitle: string = '';
  
  // 合并选项
  @State mergeToExisting: boolean = false;
  @State selectedMangaId: string = '';
  @State showMergeSelector: boolean = false;
  
  // 封面选择
  @State coverCandidates: string[] = [];  // 前三张图片路径
  @State selectedCoverIndex: number = 0;  // 选中的封面索引

  // 刮削对话框控制器
  private scraperDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    // 根据解析结构初始化
    if (this.parsedStructure) {
      this.initFromParsedStructure();
      // 初始化封面候选（前三张图片）
      this.initCoverCandidates();
      
      // 如果有预填充信息（从ComicInfo.xml解析），使用它来初始化表单
      if (this.parsedStructure.prefilledInfo) {
        this.initFromPrefilledInfo(this.parsedStructure.prefilledInfo);
      } else {
        // 没有预填充信息，使用文件名作为标题
        this.title = removeFileExtension(this.fileName);
      }
    } else {
      // 没有解析结构，使用文件名作为标题
      this.title = removeFileExtension(this.fileName);
    }
    
    // 从文件名推测章节编号
    this.guessChapterNumberFromTitle();
    this.emitFlowEvent(ImportFlowEventType.METADATA_DETECTED, 'manga_dialog_ready', true, `chapters=${this.chapters.length}, candidates=${this.existingMangaCandidates.length}`);
  }

  private emitFlowEvent(eventType: ImportFlowEventType, reason: string, success: boolean, detail: string): void {
    const event: ImportFlowEvent = new ImportFlowEvent();
    event.eventType = eventType;
    event.reason = reason;
    event.success = success;
    event.contentType = ImportFlowContentType.MANGA;
    event.fileName = this.fileName;
    event.sourceUri = this.sourceFileUri;
    event.displayName = this.title;
    event.chapterCount = this.chapters.length;
    event.detail = detail;
    this.onFlowEvent(event);
  }
  
  /**
   * 从预填充信息初始化表单
   */
  private initFromPrefilledInfo(info: PrefilledComicInfo): void {
    // 优先使用series作为漫画标题，其次使用title
    if (info.series) {
      this.title = info.series;
    } else if (info.title) {
      this.title = info.title;
    } else {
      this.title = removeFileExtension(this.fileName);
    }
    
    // 作者
    if (info.author) {
      this.author = info.author;
    }
    
    // 简介
    if (info.description) {
      this.description = info.description;
    }
    
    // 标签
    if (info.tags && info.tags.length > 0) {
      this.tagsText = info.tags.join(', ');
    }
    
    // 章节编号
    if (info.number) {
      const num = parseInt(info.number, 10);
      if (!isNaN(num) && num > 0) {
        this.chapterNumber = num;
        this.chapterTitle = info.title || `第${num}话`;
      }
    }
    
    logger.info(TAG, `从ComicInfo.xml预填充: 标题=${this.title}, 作者=${this.author}`);
  }
  
  /**
   * 初始化封面候选图片
   */
  private initCoverCandidates(): void {
    if (!this.parsedStructure || !this.parsedStructure.extractedPath) {
      return;
    }
    
    try {
      const extractedPath = this.parsedStructure.extractedPath;
      const imageFiles = this.findImagesRecursive(extractedPath, 3);
      
      imageFiles.sort();
      this.coverCandidates = imageFiles.slice(0, 3);
      this.selectedCoverIndex = 0;
      
      logger.info(TAG, `封面候选初始化完成: ${this.coverCandidates.length} 张图片`);
    } catch (error) {
      logger.error(TAG, `初始化封面候选失败: ${error}`);
    }
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
      const files = SafeFileUtils.listFileSync(dirPath);
      
      for (const file of files) {
        const lowerFile = file.toLowerCase();
        const fullPath = `${dirPath}/${file}`;
        let isImage = false;
        
        for (const ext of imageExtensions) {
          if (lowerFile.endsWith(ext)) {
            imageFiles.push(fullPath);
            isImage = true;
            break;
          }
        }
        
        if (!isImage) {
          // 检查是否为目录
          try {
            const stat = SafeFileUtils.statSync(fullPath);
            if (stat.isDirectory()) {
              subDirs.push(fullPath);
            }
          } catch (_e) {
            // 忽略
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
   * 从解析结构初始化
   */
  private initFromParsedStructure(): void {
    const structure = this.parsedStructure;
    
    // 如果检测到多个章节，默认使用多章节模式
    if (structure.detectedChapters.length > 1) {
      this.importMode = MangaImportMode.MULTI_CHAPTER;
      this.chapters = structure.detectedChapters.slice();
      // 按索引排序
      this.sortChapters();
    } else if (structure.detectedChapters.length === 1) {
      // 单个章节，可能是单行本或单章节
      this.importMode = MangaImportMode.TANKOUBON;
    } else {
      // 没有检测到章节结构，使用单行本模式
      this.importMode = MangaImportMode.TANKOUBON;
    }
    
    // 如果有ComicInfo.xml，尝试从中提取信息
    // 注意：这里只是初始化，实际解析在外部完成
  }

  /**
   * 从文件名推测章节编号
   */
  private guessChapterNumberFromTitle(): void {
    const fileName = this.fileName || '';
    if (!fileName) return;

    // 常见的章节编号模式
    const patterns: RegExp[] = [
      /第(\d+)[话話章回卷]/,           // 第1话、第1章、第1回、第1卷
      /[话話章回卷](\d+)/,              // 话1、章1
      /[Cc]h(?:apter)?[.\s]*(\d+)/i,   // Ch.1, Chapter 1, ch1
      /[Ee]p(?:isode)?[.\s]*(\d+)/i,   // Ep.1, Episode 1
      /[Vv]ol(?:ume)?[.\s]*(\d+)/i,    // Vol.1, Volume 1
      /[\[\(【（](\d+)[\]\)】）]/,      // [1], (1), 【1】, （1）
      /[_\-\s](\d{1,4})[_\-\s.]/,      // _001_, -01-, 空格分隔的数字
      /(\d{1,4})$/                      // 末尾的数字
    ];

    for (const pattern of patterns) {
      const match = fileName.match(pattern);
      if (match && match[1]) {
        const num = parseInt(match[1], 10);
        if (num > 0 && num < 10000) {
          this.chapterNumber = num;
          this.chapterTitle = `第${num}话`;
          logger.info(TAG, `从文件名推测章节编号: ${num}`);
          return;
        }
      }
    }

    // 默认章节
    this.chapterNumber = 1;
    this.chapterTitle = '第1话';
  }


  /**
   * 排序章节
   * 将外传章节放到最末尾，然后在外传部分内部按名称排序
   */
  private sortChapters(): void {
    this.chapters.sort((a, b) => {
      const aIsExtra = this.isExtraChapter(a.title);
      const bIsExtra = this.isExtraChapter(b.title);
      
      // 如果一个是外传，一个不是，外传排在后面
      if (aIsExtra && !bIsExtra) return 1;
      if (!aIsExtra && bIsExtra) return -1;
      
      // 如果都是外传，按标题排序
      if (aIsExtra && bIsExtra) {
        return a.title.localeCompare(b.title, 'zh-CN');
      }
      
      // 如果都不是外传，按索引排序
      return a.index - b.index;
    });
  }

  /**
   * 判断是否为外传章节
   * 支持多语言：外传、番外、特别篇、Extra、Side Story、Omake、Special等
   */
  private isExtraChapter(title: string): boolean {
    const extraKeywords = [
      '外传', '番外', '特别篇', '特典', '附录',
      'extra', 'side story', 'omake', 'special', 'bonus',
      'gaiden', 'bangai', 'tokubetsu'
    ];
    
    const lowerTitle = title.toLowerCase();
    return extraKeywords.some(keyword => lowerTitle.includes(keyword));
  }

  /**
   * 解析标签文本
   */
  private parseTags(tagsText: string): string[] {
    if (!tagsText || tagsText.trim().length === 0) {
      return [];
    }
    return tagsText.split(/[,，、]/)
      .map(tag => tag.trim())
      .filter(tag => tag.length > 0);
  }

  /**
   * 验证表单
   */
  private validateForm(): boolean {
    if (!this.title || this.title.trim().length === 0) {
      this.showToast('请输入漫画标题');
      return false;
    }
    
    if (this.importMode === MangaImportMode.MULTI_CHAPTER && this.chapters.length === 0) {
      this.showToast('多章节模式需要至少一个章节');
      return false;
    }
    
    if (this.mergeToExisting && !this.selectedMangaId) {
      this.showToast('请选择要合并的目标漫画');
      return false;
    }
    
    // 封面可选（不再阻止导入）
    if (this.coverCandidates.length === 0) {
      logger.warn(TAG, '未找到封面候选图片，将使用默认封面');
    }
    
    return true;
  }

  /**
   * 显示提示
   */
  private showToast(message: string): void {
    logger.info(TAG, `Toast: ${message}`);
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
  }

  /**
   * 打开刮削对话框
   */
  private openScraperDialog(): void {
    const config: ScraperDialogConfig = {
      contentType: ScraperContentType.MANGA,
      initialKeyword: this.title
    };

    this.scraperDialogController = new CustomDialogController({
      builder: ScraperDialog({
        config: config,
        themeState: this.themeState,
        onConfirm: (result: ScraperDialogResult) => {
          this.applyScraperResult(result);
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
   * 应用刮削结果
   * 使用$$双向绑定后，状态变量的变化会自动同步到输入框
   */
  private applyScraperResult(result: ScraperDialogResult): void {
    const metadata = result.metadata;
    
    if (metadata.title) {
      this.title = metadata.title;
    }
    if (result.applyAuthor && metadata.author) {
      this.author = metadata.author;
    }
    if (metadata.description) {
      this.description = metadata.description;
    }
    if (metadata.tags && metadata.tags.length > 0) {
      this.tagsText = metadata.tags.join(', ');
    }
    
    logger.info(TAG, `应用刮削结果: ${metadata.title}, title=${this.title}, author=${this.author}`);
  }

  build() {
    Column({ space: 16 }) {
      // 标题栏
      Row() {
        Text('漫画导入设置')
          .fontSize(20)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Blank()

        // 刮削按钮
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

          Text('刮削')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .padding({ left: 10, right: 12, top: 6, bottom: 6 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
        .borderRadius(16)
        .onClick(() => {
          this.openScraperDialog();
        })
      }
      .width('100%')

      // 文件信息
      Row({ space: 8 }) {
        Text('📁')
          .fontSize(16)
          .fontFamily(this.appFontFamily)
        Text(this.fileName)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding(8)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(6)

      // 导入模式选择
      this.buildImportModeSelector()

      Scroll() {
        Column({ space: 12 }) {
          // 章节信息（单章节模式）
          if (this.importMode === MangaImportMode.SINGLE_CHAPTER) {
            this.buildSingleChapterFields()
          }

          // 章节列表（多章节模式）
          if (this.importMode === MangaImportMode.MULTI_CHAPTER) {
            this.buildMultiChapterList()
          }

          // 漫画标题
          this.buildTitleField()

          // 作者
          this.buildAuthorField()

          // 简介
          this.buildDescriptionField()

          // 标签
          this.buildTagsField()
          
          // 封面选择（必选）
          this.buildCoverSelector()

          // 合并选项（如果有候选漫画）
          if (this.existingMangaCandidates.length > 0) {
            this.buildMergeOptions()
          }
        }
        .width('100%')
      }
      .height(400)
      .width('100%')

      // 操作按钮
      Row({ space: 12 }) {
        Button('取消')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .borderRadius(8)
          .height(44)
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
          .onClick(() => {
            this.emitFlowEvent(ImportFlowEventType.DIALOG_CANCELLED, 'manga_dialog_cancelled', true, '');
            this.onCancel();
            this.controller.close();
          })

        Button('开始导入')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .height(44)
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
          .onClick(() => {
            if (this.validateForm()) {
              // 获取选中的封面路径
              const selectedCoverPath = this.coverCandidates.length > 0 
                ? this.coverCandidates[this.selectedCoverIndex] 
                : '';
              
              const result: MangaImportDialogResult = {
                importMode: this.importMode,
                title: this.title.trim(),
                author: this.author.trim() || '未知作者',
                description: this.description.trim(),
                tags: this.parseTags(this.tagsText),
                chapters: this.chapters,
                chapterNumber: this.chapterNumber,
                chapterTitle: this.chapterTitle.trim() || `第${this.chapterNumber}话`,
                mergeToExisting: this.mergeToExisting,
                targetMangaId: this.selectedMangaId || undefined,
                parsedStructure: this.parsedStructure,
                selectedCoverPath: selectedCoverPath,
                sourceFileUri: this.sourceFileUri || undefined
              };
              this.emitFlowEvent(ImportFlowEventType.DIALOG_CONFIRMED, 'manga_dialog_confirmed', true, `mode=${this.importMode}, merge=${this.mergeToExisting}`);
              this.onConfirm(result);
              this.controller.close();
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
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
  }

  /**
   * 构建导入模式选择器
   */
  @Builder
  buildImportModeSelector() {
    Column({ space: 8 }) {
      Text('导入模式')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 8 }) {
        this.buildModeOption('单行本', MangaImportMode.TANKOUBON, '整部漫画')
        this.buildModeOption('单章节', MangaImportMode.SINGLE_CHAPTER, '添加到漫画')
        this.buildModeOption('多章节', MangaImportMode.MULTI_CHAPTER, `${this.parsedStructure?.detectedChapters?.length || 0}个章节`)
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 构建模式选项
   */
  @Builder
  buildModeOption(label: string, mode: MangaImportMode, subtitle: string) {
    Column({ space: 2 }) {
      Text(label)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontWeight(this.importMode === mode ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.importMode === mode ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      
      Text(subtitle)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(this.importMode === mode ?
      ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20' :
      ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(8)
    .border({
      width: this.importMode === mode ? 1 : 0,
      color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
    })
    .layoutWeight(1)
    .onClick(() => {
      this.importMode = mode;
    })
  }

  /**
   * 构建单章节字段
   */
  @Builder
  buildSingleChapterFields() {
    Column({ space: 8 }) {
      Text('章节信息')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 12 }) {
        // 章节编号
        Column({ space: 4 }) {
          Text('编号')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          TextInput({ text: this.chapterNumber.toString(), placeholder: '1' })
            .type(InputType.Number)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 12, right: 12 })
            .height(36)
            .width(80)
            .onChange((value: string) => {
              const num = parseInt(value, 10);
              if (!isNaN(num) && num > 0) {
                this.chapterNumber = num;
              }
            })
        }

        // 章节标题
        Column({ space: 4 }) {
          Text('标题')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          
          TextInput({ text: this.chapterTitle, placeholder: '第1话' })
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 12, right: 12 })
            .height(36)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.chapterTitle = value;
            })
        }
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
  }

  /**
   * 构建多章节列表
   */
  @Builder
  buildMultiChapterList() {
    Column({ space: 8 }) {
      Row() {
        Text('章节列表')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text(`共 ${this.chapters.length} 章`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width('100%')

      // 章节列表
      List({ space: 4 }) {
        ForEach(this.chapters, (chapter: ChapterInfo, index: number) => {
          ListItem() {
            this.buildChapterItem(chapter, index)
          }
        })
      }
      .width('100%')
      .height(Math.min(this.chapters.length * 56, 200))
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
      .borderRadius(8)
      .padding(8)
    }
    .width('100%')
  }

  /**
   * 构建章节项
   */
  @Builder
  buildChapterItem(chapter: ChapterInfo, index: number) {
    Row({ space: 8 }) {
      // 排序序号
      Text(`${index + 1}`)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width(24)
        .textAlign(TextAlign.Center)

      // 章节编号输入
      TextInput({ text: chapter.number.toString() })
        .type(InputType.Number)
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(4)
        .padding({ left: 8, right: 8 })
        .height(32)
        .width(50)
        .onChange((value: string) => {
          const num = parseInt(value, 10);
          if (!isNaN(num) && num > 0) {
            this.chapters[index].number = num;
            this.chapters[index].index = num;
          }
        })

      // 章节标题输入
      TextInput({ text: chapter.title })
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        .borderRadius(4)
        .padding({ left: 8, right: 8 })
        .height(32)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.chapters[index].title = value;
        })

      // 页数
      Text(`${chapter.pageCount}页`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width(40)

      // 上移/下移按钮
      Row({ space: 4 }) {
        Text('↑')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(index > 0 ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .onClick(() => {
            if (index > 0) {
              this.swapChapters(index, index - 1);
            }
          })
        
        Text('↓')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(index < this.chapters.length - 1 ?
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
            ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          .onClick(() => {
            if (index < this.chapters.length - 1) {
              this.swapChapters(index, index + 1);
            }
          })
      }
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
  }

  /**
   * 交换章节位置
   */
  private swapChapters(index1: number, index2: number): void {
    const temp = this.chapters[index1];
    this.chapters[index1] = this.chapters[index2];
    this.chapters[index2] = temp;
    // 触发UI更新
    this.chapters = this.chapters.slice();
  }

  /**
   * 构建合并选项
   */
  @Builder
  buildMergeOptions() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Checkbox()
          .select(this.mergeToExisting)
          .onChange((value: boolean) => {
            this.mergeToExisting = value;
            if (!value) {
              this.selectedMangaId = '';
            }
          })
        
        Text('合并到已有漫画')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')

      // 候选漫画列表
      if (this.mergeToExisting) {
        Column({ space: 4 }) {
          Text('选择目标漫画:')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')

          ForEach(this.existingMangaCandidates, (manga: ExistingMangaCandidate) => {
            Row({ space: 8 }) {
              Radio({ value: manga.id, group: 'targetManga' })
                .checked(this.selectedMangaId === manga.id)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.selectedMangaId = manga.id;
                  }
                })

              Column({ space: 2 }) {
                Text(manga.title)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                
                Text(`${manga.author} · ${manga.chapterCount}章`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding(8)
            .backgroundColor(this.selectedMangaId === manga.id ?
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15' :
              'transparent')
            .borderRadius(6)
            .onClick(() => {
              this.selectedMangaId = manga.id;
            })
          })
        }
        .width('100%')
        .padding(8)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
  }

  /**
   * 构建文本输入字段（用于其他非关键字段）
   */
  @Builder
  buildTextField(label: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      TextInput({ text: value, placeholder: placeholder })
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .padding({ left: 12, right: 12 })
        .height(40)
        .width('100%')
        .onChange(onChange)
    }
    .width('100%')
  }

  /**
   * 构建文本区域字段（用于其他非关键字段）
   */
  @Builder
  buildTextArea(label: string, value: string, placeholder: string, onChange: (value: string) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      TextArea({ text: value, placeholder: placeholder })
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .padding(12)
        .height(80)
        .width('100%')
        .onChange(onChange)
    }
    .width('100%')
  }

  /**
   * 构建漫画标题字段
   */
  @Builder
  buildTitleField() {
    Column({ space: 4 }) {
      Text('漫画标题 *')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      TextInput({ text: this.title, placeholder: '请输入漫画标题' })
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .padding({ left: 12, right: 12 })
        .height(40)
        .width('100%')
        .onChange((value: string) => {
          this.title = value;
        })
    }
    .width('100%')
  }

  /**
   * 构建作者字段
   */
  @Builder
  buildAuthorField() {
    Column({ space: 4 }) {
      Text('作者')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      TextInput({ text: this.author, placeholder: '请输入作者' })
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .padding({ left: 12, right: 12 })
        .height(40)
        .width('100%')
        .onChange((value: string) => {
          this.author = value;
        })
    }
    .width('100%')
  }

  /**
   * 构建简介字段
   */
  @Builder
  buildDescriptionField() {
    Column({ space: 4 }) {
      Text('简介')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      TextArea({ text: this.description, placeholder: '请输入简介...' })
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .padding(12)
        .height(60)
        .width('100%')
        .onChange((value: string) => {
          this.description = value;
        })
    }
    .width('100%')
  }

  /**
   * 构建标签字段
   */
  @Builder
  buildTagsField() {
    Column({ space: 4 }) {
      Text('标签（逗号分隔）')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      TextInput({ text: this.tagsText, placeholder: '例如: 热血, 冒险, 校园' })
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .padding({ left: 12, right: 12 })
        .height(40)
        .width('100%')
        .onChange((value: string) => {
          this.tagsText = value;
        })
    }
    .width('100%')
  }

  /**
   * 构建封面选择器
   */
  @Builder
  buildCoverSelector() {
    Column({ space: 8 }) {
      Text('选择封面 *')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      if (this.coverCandidates.length === 0) {
        Text('暂无封面候选，将使用默认封面')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      } else {
        Row({ space: 12 }) {
          ForEach(this.coverCandidates, (path: string, index: number) => {
            Column() {
              // 使用file://协议加载本地图片
              Image(path.startsWith('file://') ? path : `file://${path}`)
                .width(80)
                .height(110)
                .objectFit(ImageFit.Cover)
                .borderRadius(6)
                .border({
                  width: this.selectedCoverIndex === index ? 3 : 1,
                  color: this.selectedCoverIndex === index ?
                    ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                    ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                })
                .onClick(() => {
                  this.selectedCoverIndex = index;
                })

              Radio({ value: `cover_${index}`, group: 'coverGroup' })
                .checked(this.selectedCoverIndex === index)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.selectedCoverIndex = index;
                  }
                })
                .margin({ top: 4 })
            }
          }, (path: string, index: number) => `cover_${index}`)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
  }
}
