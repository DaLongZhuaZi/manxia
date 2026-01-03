// 文件路径: entry/src/main/ets/Framework/Components/ScraperDialog.ets
/**
 * 刮削选择对话框
 * 用于搜索和选择元数据信息
 */

import { ThemeAwareState, ThemeAwareHelper } from './ThemeAware';
import { logger } from '../../Utils/Logger';
import { ScraperManager } from '../Scraper/ScraperManager';
import { ScraperSource, ScraperContentType, ScrapedMetadata } from '../Scraper/ScraperTypes';
import { LengthMetrics } from '@kit.ArkUI';

const TAG = 'ScraperDialog';

/**
 * 刮削对话框配置
 */
export interface ScraperDialogConfig {
  /** 初始搜索关键词 */
  initialKeyword?: string;
  /** 内容类型 */
  contentType?: ScraperContentType;
  /** 启用的刮削源 */
  enabledSources?: ScraperSource[];
  /** 对话框标题 */
  title?: string;
}

/**
 * 刮削结果回调数据
 */
export interface ScraperDialogResult {
  /** 选中的元数据 */
  metadata: ScrapedMetadata;
  /** 是否应用封面 */
  applyCover: boolean;
  /** 是否应用描述 */
  applyDescription: boolean;
  /** 是否应用标签 */
  applyTags: boolean;
  /** 是否应用作者 */
  applyAuthor: boolean;
  /** 是否应用出版社 */
  applyPublisher: boolean;
}

/**
 * 刮削选择对话框
 */
@CustomDialog
export struct ScraperDialog {
  controller: CustomDialogController;
  @Prop themeState: ThemeAwareState;
  @Prop config: ScraperDialogConfig;
  onConfirm: (result: ScraperDialogResult) => void = () => {};
  onCancel: () => void = () => {};

  // 搜索状态
  @State searchKeyword: string = '';
  @State isSearching: boolean = false;
  @State searchResults: ScrapedMetadata[] = [];
  @State searchError: string = '';

  // 选中状态
  @State selectedIndex: number = -1;
  @State selectedMetadata: ScrapedMetadata | null = null;

  // 应用选项
  @State applyCover: boolean = true;
  @State applyDescription: boolean = true;
  @State applyTags: boolean = true;
  @State applyAuthor: boolean = true;
  @State applyPublisher: boolean = true;

  // 源选择
  @State selectedSources: ScraperSource[] = [];
  @State availableSources: ScraperSource[] = [
    ScraperSource.BANGUMI,
    ScraperSource.ANILIST,
    ScraperSource.BOOKOF_MOE,
    ScraperSource.GOOGLE_BOOKS
  ];

  // 视图状态
  @State showDetail: boolean = false;
  
  // 海外网络提示状态
  @State showOverseasNetworkHint: boolean = false;
  
  // 搜索超时时间（毫秒）
  private readonly SEARCH_TIMEOUT: number = 15000;

  private scraperManager: ScraperManager = ScraperManager.getInstance();

  aboutToAppear(): void {
    // 初始化搜索关键词
    this.searchKeyword = this.config.initialKeyword || '';

    // 初始化启用的源
    if (this.config.enabledSources && this.config.enabledSources.length > 0) {
      this.selectedSources = this.config.enabledSources.slice();
    } else {
      // 根据内容类型选择默认源
      if (this.config.contentType === ScraperContentType.BOOK) {
        // 电子书优先使用 Google Books 和 BookOf.Moe
        this.selectedSources = [ScraperSource.GOOGLE_BOOKS, ScraperSource.BOOKOF_MOE, ScraperSource.BANGUMI];
      } else {
        this.selectedSources = [ScraperSource.BANGUMI, ScraperSource.ANILIST];
      }
    }

    // 如果有初始关键词，自动搜索
    if (this.searchKeyword.length > 0) {
      this.performSearch();
    }
  }

  build() {
    Column() {
      // 标题栏
      this.buildHeader()

      // 搜索区域
      this.buildSearchArea()

      // 源选择
      this.buildSourceSelector()
      
      // 海外网络提示
      if (this.showOverseasNetworkHint) {
        this.buildOverseasNetworkHint()
      }

      // 内容区域
      if (this.showDetail && this.selectedMetadata) {
        this.buildDetailView()
      } else {
        this.buildResultList()
      }

      // 底部按钮
      this.buildFooter()
    }
    .width('95%')
    .constraintSize({ maxWidth: 500 })
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(16)
    .border({
      width: 1,
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
  }

  @Builder
  buildHeader() {
    Row() {
      Text(this.config.title || '刮削元数据')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      Blank()

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
    .padding({ bottom: 12 })
  }

  @Builder
  buildSearchArea() {
    Row({ space: 8 }) {
      TextInput({ text: this.searchKeyword, placeholder: '输入书名/作品名搜索...' })
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .height(40)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.searchKeyword = value;
        })
        .onSubmit(() => {
          this.performSearch();
        })

      Button() {
        if (this.isSearching) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(Color.White)
        } else {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([Color.White])
        }
      }
      .width(44)
      .height(40)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      .borderRadius(8)
      .enabled(!this.isSearching && this.searchKeyword.length > 0)
      .onClick(() => {
        this.performSearch();
      })
    }
    .width('100%')
    .padding({ bottom: 12 })
  }

  @Builder
  buildSourceSelector() {
    Column({ space: 8 }) {
      Text('搜索源')
        .fontSize(12)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) } }) {
        ForEach(this.availableSources, (source: ScraperSource) => {
          this.buildSourceChip(source)
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ bottom: 12 })
  }

  @Builder
  buildSourceChip(source: ScraperSource) {
    Row({ space: 4 }) {
      Text(this.getSourceDisplayName(source))
        .fontSize(12)
        .fontColor(this.isSourceSelected(source)
          ? ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.isSourceSelected(source)
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(16)
    .onClick(() => {
      this.toggleSource(source);
    })
  }

  @Builder
  buildOverseasNetworkHint() {
    Row({ space: 8 }) {
      Image($r('app.media.ic_info'))
        .width(16)
        .height(16)
        .fillColor('#FF9800')
      
      Text(this.isSearching ? '当前刮削源需要海外网络环境' : '请检查当前网络环境')
        .fontSize(12)
        .fontColor('#FF9800')
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor('#FFF3E0')
    .borderRadius(8)
    .margin({ bottom: 8 })
  }

  @Builder
  buildResultList() {
    Column() {
      if (this.searchError.length > 0) {
        // 错误提示
        Column({ space: 8 }) {
          Image($r('app.media.ic_error'))
            .width(48)
            .height(48)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

          Text(this.searchError)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else if (this.searchResults.length === 0 && !this.isSearching) {
        // 空状态
        Column({ space: 8 }) {
          Image($r('app.media.ic_scraper'))
            .width(48)
            .height(48)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

          Text(this.searchKeyword.length > 0 ? '未找到相关结果' : '输入关键词开始搜索')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else {
        // 结果列表
        Scroll() {
          Column({ space: 8 }) {
            ForEach(this.searchResults, (item: ScrapedMetadata, index: number) => {
              this.buildResultItem(item, index)
            })
          }
          .width('100%')
        }
        .height(280)
        .width('100%')
        .scrollBar(BarState.Auto)
      }
    }
    .width('100%')
  }

  @Builder
  buildResultItem(item: ScrapedMetadata, index: number) {
    Row({ space: 12 }) {
      // 封面
      if (item.coverUrl) {
        Image(item.coverUrl)
          .width(50)
          .height(70)
          .borderRadius(4)
          .objectFit(ImageFit.Cover)
          .alt($r('app.media.ic_book'))
      } else {
        Column() {
          Image($r('app.media.ic_book'))
            .width(24)
            .height(24)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .width(50)
        .height(70)
        .borderRadius(4)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
      }

      // 信息
      Column({ space: 4 }) {
        Text(item.title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (item.author) {
          Text(item.author)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        Row({ space: 4 }) {
          // 来源标签
          Text(this.getSourceDisplayName(item.source))
            .fontSize(10)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(this.getSourceColor(item.source))
            .borderRadius(4)

          // 评分
          if (item.score) {
            Text(`★ ${item.score.toFixed(1)}`)
              .fontSize(10)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 选中指示
      if (this.selectedIndex === index) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .padding(10)
    .backgroundColor(this.selectedIndex === index
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '20'
      : ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
    .border({
      width: this.selectedIndex === index ? 2 : 1,
      color: this.selectedIndex === index
        ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
        : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme)
    })
    .onClick(() => {
      this.selectedIndex = index;
      this.selectedMetadata = item;
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          this.selectedIndex = index;
          this.selectedMetadata = item;
          this.showDetail = true;
        })
    )
  }

  @Builder
  buildDetailView() {
    Column({ space: 12 }) {
      // 返回按钮
      Row() {
        Image($r('app.media.ic_arrow_back'))
          .width(20)
          .height(20)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Text('返回列表')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ left: 4 })
      }
      .onClick(() => {
        this.showDetail = false;
      })
      .padding({ bottom: 8 })

      Scroll() {
        Column({ space: 12 }) {
          // 封面和基本信息
          Row({ space: 12 }) {
            if (this.selectedMetadata!.coverUrl) {
              Image(this.selectedMetadata!.coverUrl)
                .width(80)
                .height(112)
                .borderRadius(6)
                .objectFit(ImageFit.Cover)
            }

            Column({ space: 6 }) {
              Text(this.selectedMetadata!.title)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              if (this.selectedMetadata!.author) {
                Text(`作者: ${this.selectedMetadata!.author}`)
                  .fontSize(13)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }

              if (this.selectedMetadata!.publisher) {
                Text(`出版社: ${this.selectedMetadata!.publisher}`)
                  .fontSize(13)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }

              if (this.selectedMetadata!.score) {
                Text(`评分: ${this.selectedMetadata!.score.toFixed(1)}/${this.selectedMetadata!.scoreMax || 10}`)
                  .fontSize(13)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          // 简介
          if (this.selectedMetadata!.description) {
            Column({ space: 4 }) {
              Text('简介')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .width('100%')

              Text(this.selectedMetadata!.description)
                .fontSize(13)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .maxLines(6)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .width('100%')
          }

          // 标签
          if (this.selectedMetadata!.tags && this.selectedMetadata!.tags.length > 0) {
            Column({ space: 4 }) {
              Text('标签')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .width('100%')

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.selectedMetadata!.tags!.slice(0, 10), (tag: string) => {
                  Text(tag)
                    .fontSize(11)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                    .borderRadius(12)
                    .margin({ right: 6, bottom: 6 })
                })
              }
              .width('100%')
            }
            .width('100%')
          }

          // 应用选项
          Column({ space: 8 }) {
            Text('选择要应用的信息')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')

            this.buildApplyOption('封面图片', this.applyCover, (value: boolean) => {
              this.applyCover = value;
            }, this.selectedMetadata!.coverUrl !== undefined)

            this.buildApplyOption('简介描述', this.applyDescription, (value: boolean) => {
              this.applyDescription = value;
            }, this.selectedMetadata!.description !== undefined)

            this.buildApplyOption('标签分类', this.applyTags, (value: boolean) => {
              this.applyTags = value;
            }, this.selectedMetadata!.tags !== undefined && this.selectedMetadata!.tags.length > 0)

            this.buildApplyOption('作者信息', this.applyAuthor, (value: boolean) => {
              this.applyAuthor = value;
            }, this.selectedMetadata!.author !== undefined)

            this.buildApplyOption('出版社', this.applyPublisher, (value: boolean) => {
              this.applyPublisher = value;
            }, this.selectedMetadata!.publisher !== undefined)
          }
          .width('100%')
          .padding(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
        }
        .width('100%')
      }
      .height(280)
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  buildApplyOption(label: string, value: boolean, onChange: (value: boolean) => void, available: boolean) {
    Row() {
      Text(label)
        .fontSize(13)
        .fontColor(available
          ? ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

      Blank()

      if (available) {
        Toggle({ type: ToggleType.Switch, isOn: value })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            onChange(isOn);
          })
      } else {
        Text('无数据')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .height(36)
  }

  @Builder
  buildFooter() {
    Row({ space: 12 }) {
      Button('取消')
        .fontSize(15)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .borderRadius(8)
        .height(44)
        .layoutWeight(1)
        .onClick(() => {
          this.onCancel();
          this.controller.close();
        })

      Button('应用')
        .fontSize(15)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(8)
        .height(44)
        .layoutWeight(1)
        .enabled(this.selectedMetadata !== null)
        .opacity(this.selectedMetadata !== null ? 1 : 0.5)
        .onClick(() => {
          if (this.selectedMetadata) {
            const result: ScraperDialogResult = {
              metadata: this.selectedMetadata,
              applyCover: this.applyCover,
              applyDescription: this.applyDescription,
              applyTags: this.applyTags,
              applyAuthor: this.applyAuthor,
              applyPublisher: this.applyPublisher
            };
            this.onConfirm(result);
            this.controller.close();
          }
        })
    }
    .width('100%')
    .padding({ top: 12 })
  }

  /**
   * 检查是否选择了需要海外网络的刮削源
   */
  private hasOverseasSource(): boolean {
    return this.selectedSources.includes(ScraperSource.BOOKOF_MOE) ||
           this.selectedSources.includes(ScraperSource.GOOGLE_BOOKS);
  }

  /**
   * 执行搜索（带超时机制）
   */
  private async performSearch(): Promise<void> {
    if (this.searchKeyword.trim().length === 0 || this.isSearching) {
      return;
    }

    this.isSearching = true;
    this.searchError = '';
    this.searchResults = [];
    this.selectedIndex = -1;
    this.selectedMetadata = null;
    
    // 检查是否需要显示海外网络提示
    const needsOverseasNetwork = this.hasOverseasSource();
    this.showOverseasNetworkHint = needsOverseasNetwork;

    try {
      logger.info(TAG, `开始搜索: ${this.searchKeyword}`);

      // 创建超时 Promise
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => {
          reject(new Error('搜索超时'));
        }, this.SEARCH_TIMEOUT);
      });

      // 执行搜索，带超时
      const searchPromise = this.scraperManager.searchMultipleSources(
        this.searchKeyword.trim(),
        this.config.contentType,
        this.selectedSources
      );

      const result = await Promise.race([searchPromise, timeoutPromise]);

      if (result.success && result.mergedResults.length > 0) {
        this.searchResults = result.mergedResults;
        this.showOverseasNetworkHint = false; // 搜索成功，隐藏提示
        logger.info(TAG, `搜索完成，找到 ${this.searchResults.length} 条结果`);
      } else {
        // 检查是否有错误
        const errors: string[] = [];
        result.errors.forEach((error: string, source: ScraperSource) => {
          errors.push(`${this.getSourceDisplayName(source)}: ${error}`);
        });

        if (errors.length > 0) {
          this.searchError = errors.join('\n');
        } else {
          this.searchError = '未找到相关结果';
        }
        
        // 如果使用了海外源且搜索失败，保持提示显示
        if (needsOverseasNetwork) {
          this.showOverseasNetworkHint = true;
        }
      }
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `搜索失败: ${errorMsg}`);
      
      // 超时或网络错误时，如果使用了海外源，显示网络环境提示
      if (needsOverseasNetwork) {
        this.showOverseasNetworkHint = true;
        if (errorMsg.includes('超时')) {
          this.searchError = '搜索超时，请检查网络连接';
        } else {
          this.searchError = `搜索失败: ${errorMsg}`;
        }
      } else {
        this.searchError = `搜索失败: ${errorMsg}`;
      }
    } finally {
      this.isSearching = false;
    }
  }

  /**
   * 获取源显示名称
   */
  private getSourceDisplayName(source: ScraperSource): string {
    switch (source) {
      case ScraperSource.BANGUMI:
        return 'Bangumi';
      case ScraperSource.ANILIST:
        return 'AniList';
      case ScraperSource.BOOKOF_MOE:
        return 'BookOf.Moe';
      case ScraperSource.GOOGLE_BOOKS:
        return 'Google Books';
      default:
        return source;
    }
  }

  /**
   * 获取源颜色
   */
  private getSourceColor(source: ScraperSource): ResourceColor {
    switch (source) {
      case ScraperSource.BANGUMI:
        return '#F09199'; // 粉色
      case ScraperSource.ANILIST:
        return '#02A9FF'; // 蓝色
      case ScraperSource.BOOKOF_MOE:
        return '#7C4DFF'; // 紫色
      case ScraperSource.GOOGLE_BOOKS:
        return '#4285F4'; // Google蓝
      default:
        return '#888888';
    }
  }

  /**
   * 检查源是否选中
   */
  private isSourceSelected(source: ScraperSource): boolean {
    return this.selectedSources.includes(source);
  }

  /**
   * 切换源选择
   */
  private toggleSource(source: ScraperSource): void {
    const index = this.selectedSources.indexOf(source);
    if (index >= 0) {
      // 至少保留一个源
      if (this.selectedSources.length > 1) {
        this.selectedSources = this.selectedSources.filter((s: ScraperSource) => s !== source);
      }
    } else {
      this.selectedSources = this.selectedSources.concat([source]);
    }
  }
}

/**
 * 刮削按钮组件 - 可复用的刮削入口按钮
 */
@Component
export struct ScraperButton {
  @Prop themeState: ThemeAwareState;
  @Prop iconSize: number = 24;
  @Prop showLabel: boolean = false;
  onButtonClick: () => void = () => {};

  build() {
    Row({ space: 4 }) {
      Image($r('app.media.ic_scraper'))
        .width(this.iconSize)
        .height(this.iconSize)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

      if (this.showLabel) {
        Text('刮削')
          .fontSize(13)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
    }
    .padding(this.showLabel ? { left: 8, right: 12, top: 6, bottom: 6 } : 8)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
    .borderRadius(this.showLabel ? 16 : 8)
    .onClick(() => {
      this.onButtonClick();
    })
  }
}
