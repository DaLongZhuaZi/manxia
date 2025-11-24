// 文件路径: entry/src/main/ets/pages/EBookDetailPage.ets
/**
 * 电子书详情页
 * 显示电子书的详细信息、章节列表、阅读进度等
 */

import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { EBook, EBookChapter, EBookFormat, EBookStatus } from '../Models/EBookModels';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';

const TAG = 'EBookDetailPage';

/**
 * 电子书详情页参数
 */
export interface EBookDetailPageParams {
  bookId: string;
}

@Component
export struct EBookDetailPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private componentId: string = 'EBookDetailPage';

  // 沉浸式显示状态
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 电子书数据
  @State ebook: EBook | null = null;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  
  // UI状态
  @State showChapterList: boolean = false;
  @State expandedDescription: boolean = false;

  // 数据管理器
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  /**
   * 加载电子书详情
   */
  private async loadEBookDetail(bookId: string): Promise<void> {
    try {
      this.isLoading = true;
      this.errorMessage = '';

      logger.info(TAG, `加载电子书详情: ${bookId}`);
      const ebook = await this.ebookDataManager.getEBookById(bookId);

      if (!ebook) {
        throw new Error('电子书不存在');
      }

      this.ebook = ebook;
      logger.info(TAG, `电子书详情加载完成: ${ebook.metadata.title}`);
    } catch (error) {
      this.errorMessage = `加载失败: ${String(error instanceof Error ? error.message : error)}`;
      logger.error(TAG, this.errorMessage);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 开始阅读
   */
  private startReading(): void {
    if (!this.ebook) {
      return;
    }

    logger.info(TAG, `开始阅读: ${this.ebook.metadata.title}`);
    const readerParams: EBookReaderPageParams = {
      bookId: this.ebook.id
    };
    this.pathStack.pushPath({ name: 'EBookReaderPage', param: readerParams });
  }

  /**
   * 切换收藏状态
   */
  private async toggleFavorite(): Promise<void> {
    if (!this.ebook) {
      return;
    }

    try {
      this.ebook.isFavorite = !this.ebook.isFavorite;
      this.ebook.lastUpdateTime = Date.now();
      
      await this.ebookDataManager.saveEBook(this.ebook);
      logger.info(TAG, `收藏状态已更新: ${this.ebook.isFavorite}`);
    } catch (error) {
      logger.error(TAG, `更新收藏状态失败: ${String(error)}`);
    }
  }

  build() {
    NavDestination() {
      Stack() {
        // 背景层（沉浸式扩展）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        Column() {
          if (this.isLoading) {
            this.buildLoadingView()
          } else if (this.errorMessage.length > 0) {
            this.buildErrorView()
          } else if (this.ebook) {
            this.buildDetailView()
          }
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
      }
    }
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as EBookDetailPageParams | null;
      if (param && param.bookId) {
        this.loadEBookDetail(param.bookId);
      } else {
        this.errorMessage = '无效的电子书ID';
      }
    })
    .mode(NavDestinationMode.STANDARD)
    .hideTitleBar(true)
  }

  /**
   * 构建加载视图
   */
  @Builder
  buildLoadingView() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(60)
        .height(60)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

      Text('加载中...')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 构建错误视图
   */
  @Builder
  buildErrorView() {
    Column({ space: 16 }) {
      Image($r('app.media.ic_error'))
        .width(80)
        .height(80)
        .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

      Text(this.errorMessage)
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)

      Button('返回')
        .fontSize(16)
        .height(40)
        .onClick(() => {
          this.pathStack.pop();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(20)
  }

  /**
   * 构建详情视图
   */
  @Builder
  buildDetailView() {
    if (this.ebook) {
      Column() {
        // 顶部操作栏
        this.buildTopBar()

        // 可滚动内容
        Scroll() {
          Column({ space: 20 }) {
            // 封面和基本信息
            this.buildCoverSection()

            // 操作按钮区域
            this.buildActionButtons()

            // 书籍详细信息
            this.buildInfoSection()

            // 章节列表
            this.buildChapterSection()
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
  }

  /**
   * 构建顶部操作栏
   */
  @Builder
  buildTopBar() {
    Row({ space: 12 }) {
      // 返回按钮
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width(40)
      .height(40)
      .backgroundColor('transparent')
      .onClick(() => {
        this.pathStack.pop();
      })

      Blank()

      // 收藏按钮
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_ebook'))
          .width(24)
          .height(24)
          .fillColor(this.ebook?.isFavorite 
            ? '#FF4444' 
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width(40)
      .height(40)
      .backgroundColor('transparent')
      .onClick(() => {
        this.toggleFavorite();
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  /**
   * 构建封面部分
   */
  @Builder
  buildCoverSection() {
    if (this.ebook) {
      Row({ space: 16 }) {
        // 封面
        Column() {
          Image($r('app.media.ic_ebook'))
            .width(80)
            .height(80)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width(120)
        .height(180)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(12)
        .justifyContent(FlexAlign.Center)
        .shadow({
          radius: 12,
          color: '#1F000000',
          offsetY: 6
        })

        // 基本信息
        Column({ space: 8 }) {
          Text(this.ebook.metadata.title)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.ebook.metadata.author)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

          // 格式标签
          Row({ space: 8 }) {
            Text(this.ebook.format)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .borderRadius(4)

            Text(this.getStatusText())
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(this.getStatusColor())
              .borderRadius(4)
          }

          // 阅读进度
          if (this.ebook.readingProgress && this.ebook.readingProgress.progress > 0) {
            Column({ space: 4 }) {
              Row() {
                Text(`已读 ${Math.floor(this.ebook.readingProgress.progress)}%`)
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .width('100%')

              Progress({
                value: this.ebook.readingProgress.progress,
                total: 100,
                type: ProgressType.Linear
              })
              .width('100%')
              .height(4)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .padding(16)
    }
  }

  /**
   * 构建操作按钮
   */
  @Builder
  buildActionButtons() {
    Row({ space: 12 }) {
      Button('开始阅读')
        .fontSize(16)
        .layoutWeight(1)
        .height(48)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .onClick(() => {
          this.startReading();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  /**
   * 构建信息部分
   */
  @Builder
  buildInfoSection() {
    if (this.ebook) {
      Column({ space: 12 }) {
        // 简介
        if (this.ebook.metadata.description.length > 0) {
          Column({ space: 8 }) {
            Text('简介')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

            Text(this.ebook.metadata.description)
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .lineHeight(22)
              .maxLines(this.expandedDescription ? 999 : 3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                this.expandedDescription = !this.expandedDescription;
              })
          }
          .width('100%')
        }

        // 详细信息
        Column({ space: 8 }) {
          Text('详细信息')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          this.buildInfoItem('出版社', this.ebook.metadata.publisher || '未知')
          this.buildInfoItem('出版日期', this.ebook.metadata.publishDate || '未知')
          this.buildInfoItem('ISBN', this.ebook.metadata.isbn || '无')
          this.buildInfoItem('语言', this.ebook.metadata.language)
          this.buildInfoItem('文件大小', this.formatFileSize(this.ebook.fileSize))
          this.buildInfoItem('章节数', `${this.ebook.chapters.length}章`)
          if (this.ebook.totalWordCount > 0) {
            this.buildInfoItem('总字数', `${Math.floor(this.ebook.totalWordCount / 10000)}万字`)
          }
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)
    }
  }

  /**
   * 构建信息项
   */
  @Builder
  buildInfoItem(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width(80)

      Text(value)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .layoutWeight(1)
    }
    .width('100%')
  }

  /**
   * 构建章节列表
   */
  @Builder
  buildChapterSection() {
    if (this.ebook && this.ebook.chapters.length > 0) {
      Column({ space: 12 }) {
        Row() {
          Text(`章节列表 (${this.ebook.chapters.length})`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Blank()

          Button(this.showChapterList ? '收起' : '展开')
            .fontSize(12)
            .height(28)
            .padding({ left: 12, right: 12 })
            .backgroundColor('transparent')
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .border({
              width: 1,
              color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            })
            .onClick(() => {
              this.showChapterList = !this.showChapterList;
            })
        }
        .width('100%')

        if (this.showChapterList) {
          List({ space: 8 }) {
            ForEach(this.ebook.chapters, (chapter: EBookChapter, index: number) => {
              ListItem() {
                this.buildChapterItem(chapter, index)
              }
            })
          }
          .width('100%')
          .height(300)
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)
    }
  }

  /**
   * 构建章节项
   */
  @Builder
  buildChapterItem(chapter: EBookChapter, index: number) {
    Row({ space: 12 }) {
      Text(`${index + 1}`)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width(40)

      Text(chapter.title)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .layoutWeight(1)

      if (chapter.wordCount > 0) {
        Text(`${Math.floor(chapter.wordCount / 1000)}k字`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
    .borderRadius(8)
  }

  /**
   * 获取状态文本
   */
  private getStatusText(): string {
    if (!this.ebook) {
      return '';
    }

    switch (this.ebook.status) {
      case EBookStatus.UNREAD:
        return '未读';
      case EBookStatus.READING:
        return '阅读中';
      case EBookStatus.COMPLETED:
        return '已完成';
      case EBookStatus.ARCHIVED:
        return '已归档';
      default:
        return '未知';
    }
  }

  /**
   * 获取状态颜色
   */
  private getStatusColor(): string {
    if (!this.ebook) {
      return '#999999';
    }

    switch (this.ebook.status) {
      case EBookStatus.UNREAD:
        return '#999999';
      case EBookStatus.READING:
        return '#4CAF50';
      case EBookStatus.COMPLETED:
        return '#2196F3';
      case EBookStatus.ARCHIVED:
        return '#FF9800';
      default:
        return '#999999';
    }
  }

  /**
   * 格式化文件大小
   */
  private formatFileSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    } else if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(2)} KB`;
    } else if (bytes < 1024 * 1024 * 1024) {
      return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
    } else {
      return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
    }
  }
}

/**
 * 电子书阅读器页面参数
 */
interface EBookReaderPageParams {
  bookId: string;
}

