// 文件路径: entry/src/main/ets/Framework/Components/PdfImportDialog.ets
/**
 * PDF导入信息设置对话框
 * 融合分类选择和元数据输入
 */

import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { AppColors, ColorRole } from 'manxia_theme/src/main/ets/Framework/Theme/AppColors';
import { PdfContentType } from '../Parsers/PdfToMangaImporter';
import { ScraperDialog, ScraperDialogConfig, ScraperDialogResult } from './ScraperDialog';
import { ScraperContentType } from 'manxia_core/src/main/ets/Framework/Scraper/ScraperTypes';
import { ImportFilenameSuggestionPanel } from './ImportFilenameSuggestionPanel';
import {
  ImportFilenameIntelligenceService,
  ImportFilenameParseResult,
  ImportFilenameMetadataCandidate
} from '../Services/ImportFilenameIntelligenceService';

const TAG = 'PdfImportDialog';

/**
 * PDF导入模式枚举
 */
export enum PdfImportMode {
  /** 单行本模式：整个PDF作为一部完整的漫画 */
  TANKOUBON = 'tankoubon',
  /** 单章节模式：PDF作为某部漫画的一个章节 */
  SINGLE_CHAPTER = 'single_chapter'
}

/**
 * PDF导入结果
 */
export interface PdfImportDialogResult {
  contentType: PdfContentType;
  /** 导入模式 */
  importMode: PdfImportMode;
  title: string;
  author: string;
  description: string;
  tags: string[];
  // 电子书特有字段
  publisher?: string;
  isbn?: string;
  // 单章节模式特有字段
  /** 章节编号（单章节模式） */
  chapterNumber?: number;
  /** 章节标题（单章节模式） */
  chapterTitle?: string;
}

/**
 * PDF导入信息设置对话框
 */
@CustomDialog
export struct PdfImportDialog {
  controller: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @Prop defaultTitle: string = '';
  @Prop defaultAuthor: string = '';
  @Prop sourceFileName: string = '';
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  // 回调函数
  onConfirm: (result: PdfImportDialogResult) => void = () => {};
  onCancel: () => void = () => {};

  // 表单状态
  @State selectedType: PdfContentType = PdfContentType.MANGA;
  @State importMode: PdfImportMode = PdfImportMode.TANKOUBON;
  @State title: string = '';
  @State author: string = '';
  @State description: string = '';
  @State tagsText: string = '';
  // 电子书特有字段
  @State publisher: string = '';
  @State isbn: string = '';
  // 单章节模式字段
  @State chapterNumber: number = 1;
  @State chapterTitle: string = '';
  @State filenameParseResult: ImportFilenameParseResult | null = null;

  // 刮削对话框控制器
  private scraperDialogController: CustomDialogController | null = null;
  private filenameIntelligenceService: ImportFilenameIntelligenceService = ImportFilenameIntelligenceService.getInstance();

  aboutToAppear(): void {
    this.title = this.defaultTitle || '';
    this.author = this.defaultAuthor || '';
    this.filenameParseResult = this.filenameIntelligenceService.parseFileName(this.sourceFileName || this.defaultTitle || '');
    this.applyBestFilenameCandidateIfNeeded();
    this.guessChapterNumberFromTitle();
  }

  private applyBestFilenameCandidateIfNeeded(): void {
    if (!this.filenameParseResult) {
      return;
    }
    const candidate = this.filenameParseResult.bestCandidate;
    if (candidate.title.length > 0) {
      this.title = candidate.title;
    }
    if (this.author.trim().length === 0 && candidate.author.length > 0) {
      this.author = candidate.author;
    }
    if (this.tagsText.trim().length === 0 && candidate.tags.length > 0) {
      this.tagsText = candidate.tags.join(', ');
    }
    if (this.publisher.trim().length === 0 && candidate.publisher.length > 0) {
      this.publisher = candidate.publisher;
    }
    if (this.isbn.trim().length === 0 && candidate.isbn.length > 0) {
      this.isbn = candidate.isbn;
    }
    if (candidate.recommendedContentKind === 'ebook') {
      this.selectedType = PdfContentType.EBOOK;
    }
    if (candidate.chapterNumber !== undefined && candidate.chapterNumber > 0 && candidate.recommendedContentKind !== 'ebook') {
      this.importMode = PdfImportMode.SINGLE_CHAPTER;
      this.chapterNumber = candidate.chapterNumber;
      this.chapterTitle = candidate.chapterTitle || `第${candidate.chapterNumber}话`;
    }
  }

  private applyFilenameCandidate(candidate: ImportFilenameMetadataCandidate): void {
    if (candidate.title.length > 0) {
      this.title = candidate.title;
    }
    if (candidate.author.length > 0) {
      this.author = candidate.author;
    }
    if (candidate.publisher.length > 0) {
      this.publisher = candidate.publisher;
    }
    if (candidate.isbn.length > 0) {
      this.isbn = candidate.isbn;
    }
    if (candidate.tags.length > 0) {
      this.tagsText = candidate.tags.join(', ');
    }
    if (candidate.recommendedContentKind === 'ebook') {
      this.selectedType = PdfContentType.EBOOK;
    }
    if (candidate.chapterNumber !== undefined && candidate.chapterNumber > 0 && candidate.recommendedContentKind !== 'ebook') {
      this.importMode = PdfImportMode.SINGLE_CHAPTER;
      this.chapterNumber = candidate.chapterNumber;
      this.chapterTitle = candidate.chapterTitle || `第${candidate.chapterNumber}话`;
    }
  }

  /**
   * 从文件名推测章节编号
   */
  private guessChapterNumberFromTitle(): void {
    if (this.filenameParseResult && this.filenameParseResult.bestCandidate.chapterNumber !== undefined) {
      const chapterNumber = this.filenameParseResult.bestCandidate.chapterNumber;
      if (chapterNumber && chapterNumber > 0) {
        this.chapterNumber = chapterNumber;
        this.chapterTitle = this.filenameParseResult.bestCandidate.chapterTitle || `第${chapterNumber}话`;
        return;
      }
    }
    const fileName = this.sourceFileName || this.defaultTitle || '';
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

  build() {
    Column({ space: 16 }) {
      // 标题栏
      Row() {
        Text('PDF导入设置')
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

      // 提示文本
      Text('⚠️ PDF转换为图片是耗时操作，大文件可能需要几分钟')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(AppColors.warning)
        .width('100%')
        .textAlign(TextAlign.Center)

      // 分类选择
      this.buildTypeSelector()

      // 导入模式选择（单行本/单章节）- 仅漫画类型显示
      if (this.selectedType === PdfContentType.MANGA) {
        this.buildImportModeSelector()
      }

      Scroll() {
        Column({ space: 12 }) {
          if (this.filenameParseResult) {
            ImportFilenameSuggestionPanel({
              themeState: this.themeState,
              parseResult: this.filenameParseResult,
              currentTitle: this.title,
              currentAuthor: this.author,
              onApplyCandidate: (candidate: ImportFilenameMetadataCandidate) => {
                this.applyFilenameCandidate(candidate);
              },
              onApplyTitle: (value: string) => {
                this.title = value;
              },
              onApplyAuthor: (value: string) => {
                this.author = value;
              }
            })
          }

          // 单章节模式：章节信息输入
          if (this.selectedType === PdfContentType.MANGA && this.importMode === PdfImportMode.SINGLE_CHAPTER) {
            this.buildChapterInputFields()
          }

          // 标题 *
          Column({ space: 4 }) {
            Text(this.importMode === PdfImportMode.SINGLE_CHAPTER ? '漫画标题 *' : '标题 *')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')

            TextInput({ text: this.title, placeholder: '请输入标题' })
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

          // 作者
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

          // 简介
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
              .height(80)
              .width('100%')
              .onChange((value: string) => {
                this.description = value;
              })
          }
          .width('100%')

          // 标签
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

          // 电子书特有字段
          if (this.selectedType === PdfContentType.EBOOK) {
            Column({ space: 4 }) {
              Text('出版社')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .width('100%')

              TextInput({ text: this.publisher, placeholder: '请输入出版社' })
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .borderRadius(6)
                .padding({ left: 12, right: 12 })
                .height(40)
                .width('100%')
                .onChange((value: string) => {
                  this.publisher = value;
                })
            }
            .width('100%')

            Column({ space: 4 }) {
              Text('ISBN')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .width('100%')

              TextInput({ text: this.isbn, placeholder: '请输入ISBN' })
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .borderRadius(6)
                .padding({ left: 12, right: 12 })
                .height(40)
                .width('100%')
                .onChange((value: string) => {
                  this.isbn = value;
                })
            }
            .width('100%')
          }
        }
        .width('100%')
      }
      .height(280)
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
              const result: PdfImportDialogResult = {
                contentType: this.selectedType,
                importMode: this.importMode,
                title: this.title.trim() || this.defaultTitle || '未知标题',
                author: this.author.trim() || '未知作者',
                description: this.description.trim(),
                tags: this.parseTags(this.tagsText),
                publisher: this.publisher.trim(),
                isbn: this.isbn.trim(),
                // 单章节模式特有字段
                chapterNumber: this.importMode === PdfImportMode.SINGLE_CHAPTER ? this.chapterNumber : undefined,
                chapterTitle: this.importMode === PdfImportMode.SINGLE_CHAPTER ? (this.chapterTitle.trim() || `第${this.chapterNumber}话`) : undefined
              };
              this.onConfirm(result);
              this.controller.close();
            }
          })
      }
      .width('100%')
    }
    .width('90%')
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

  @Builder
  buildTypeSelector() {
    Column({ space: 8 }) {
      Text('选择分类')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 12 }) {
        // 漫画选项
        this.buildTypeOption(
          '📚 漫画',
          '适合图片为主的PDF',
          PdfContentType.MANGA
        )

        // 电子书选项
        this.buildTypeOption(
          '📖 电子书',
          '适合文字为主的PDF',
          PdfContentType.EBOOK
        )
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
    }
    .width('100%')
  }

  @Builder
  buildTypeOption(title: string, subtitle: string, type: PdfContentType) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.selectedType === type ? AppColors.primary : 
          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Text(subtitle)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.selectedType === type ? AppColors.primaryContainer : 
      ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(8)
    .border({
      width: 2,
      color: this.selectedType === type ? AppColors.primary : Color.Transparent
    })
    .layoutWeight(1)
    .onClick(() => {
      this.selectedType = type;
      // 切换到电子书时，重置为单行本模式
      if (type === PdfContentType.EBOOK) {
        this.importMode = PdfImportMode.TANKOUBON;
      }
    })
  }

  @Builder
  buildImportModeSelector() {
    Column({ space: 8 }) {
      Text('导入模式')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 12 }) {
        // 单行本选项
        Column({ space: 4 }) {
          Text('📖 单行本')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.importMode === PdfImportMode.TANKOUBON ? AppColors.primary :
              ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text('整个PDF作为一部漫画')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor(this.importMode === PdfImportMode.TANKOUBON ? AppColors.primaryContainer :
          ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
        .border({
          width: 2,
          color: this.importMode === PdfImportMode.TANKOUBON ? AppColors.primary : Color.Transparent
        })
        .layoutWeight(1)
        .onClick(() => {
          this.importMode = PdfImportMode.TANKOUBON;
        })

        // 单章节选项
        Column({ space: 4 }) {
          Text('📄 单章节')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.importMode === PdfImportMode.SINGLE_CHAPTER ? AppColors.primary :
              ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text('作为漫画的一个章节')
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .backgroundColor(this.importMode === PdfImportMode.SINGLE_CHAPTER ? AppColors.primaryContainer :
          ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
        .border({
          width: 2,
          color: this.importMode === PdfImportMode.SINGLE_CHAPTER ? AppColors.primary : Color.Transparent
        })
        .layoutWeight(1)
        .onClick(() => {
          this.importMode = PdfImportMode.SINGLE_CHAPTER;
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly)
    }
    .width('100%')
  }

  @Builder
  buildChapterInputFields() {
    Column({ space: 12 }) {
      // 提示信息
      Text('💡 单章节模式：此PDF将作为漫画的一个章节导入。如果已存在同名漫画，将自动合并。')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(AppColors.warning)
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .backgroundColor(AppColors.withAlpha(ColorRole.WARNING, 0.1))
        .borderRadius(6)

      // 章节编号和标题
      Row({ space: 12 }) {
        // 章节编号
        Column({ space: 4 }) {
          Text('章节编号 *')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')

          TextInput({ text: this.chapterNumber.toString(), placeholder: '1' })
            .type(InputType.Number)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 12, right: 12 })
            .height(40)
            .width('100%')
            .onChange((value: string) => {
              const num = parseInt(value, 10);
              if (!isNaN(num) && num > 0) {
                this.chapterNumber = num;
                // 自动更新章节标题
                this.chapterTitle = `第${num}话`;
              }
            })
        }
        .layoutWeight(1)

        // 章节标题
        Column({ space: 4 }) {
          Text('章节标题')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width('100%')

          TextInput({ text: this.chapterTitle, placeholder: '第1话' })
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(6)
            .padding({ left: 12, right: 12 })
            .height(40)
            .width('100%')
            .onChange((value: string) => {
              this.chapterTitle = value;
            })
        }
        .layoutWeight(2)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  buildInputField(label: string, value: string, onChange: (value: string) => void, placeholder: string) {
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
        .onChange((newValue: string) => {
          onChange(newValue);
        })
    }
    .width('100%')
  }

  @Builder
  buildTextAreaField(label: string, value: string, onChange: (value: string) => void) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      TextArea({ text: value, placeholder: '请输入简介...' })
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(6)
        .padding(12)
        .height(80)
        .width('100%')
        .onChange((newValue: string) => {
          onChange(newValue);
        })
    }
    .width('100%')
  }

  /**
   * 验证表单
   */
  private validateForm(): boolean {
    if (this.title.trim().length === 0 && (!this.defaultTitle || this.defaultTitle.length === 0)) {
      logger.warn(TAG, '标题不能为空');
      return false;
    }
    return true;
  }

  /**
   * 解析标签字符串
   */
  private parseTags(tagsText: string): string[] {
    if (!tagsText || tagsText.trim().length === 0) {
      return [];
    }

    return tagsText
      .split(/[,，、]/)
      .map((tag: string) => tag.trim())
      .filter((tag: string) => tag.length > 0);
  }

  /**
   * 打开刮削对话框
   */
  private openScraperDialog(): void {
    // 根据当前选择的类型确定内容类型
    const contentType = this.selectedType === PdfContentType.EBOOK
      ? ScraperContentType.BOOK
      : ScraperContentType.MANGA;

    const config: ScraperDialogConfig = {
      initialKeyword: this.title || this.defaultTitle || '',
      contentType: contentType,
      title: this.selectedType === PdfContentType.EBOOK ? '搜索电子书信息' : '搜索漫画信息'
    };

    this.scraperDialogController = new CustomDialogController({
      builder: ScraperDialog({
        themeState: this.themeState,
        config: config,
        onConfirm: (result: ScraperDialogResult) => {
          this.applyScraperResult(result);
        },
        onCancel: () => {
          logger.info(TAG, '用户取消刮削');
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });

    this.scraperDialogController.open();
  }

  /**
   * 应用刮削结果
   */
  private applyScraperResult(result: ScraperDialogResult): void {
    const metadata = result.metadata;
    logger.info(TAG, `应用刮削结果: ${metadata.title}`);

    // 应用标题
    if (metadata.title) {
      this.title = metadata.title;
    }

    // 应用作者
    if (result.applyAuthor && metadata.author) {
      this.author = metadata.author;
    }

    // 应用描述
    if (result.applyDescription && metadata.description) {
      this.description = metadata.description;
    }

    // 应用标签
    if (result.applyTags && metadata.tags && metadata.tags.length > 0) {
      this.tagsText = metadata.tags.join(', ');
    }

    // 电子书特有字段
    if (this.selectedType === PdfContentType.EBOOK) {
      if (result.applyPublisher && metadata.publisher) {
        this.publisher = metadata.publisher;
      }
    }

    logger.info(TAG, '刮削结果已应用');
  }
}
