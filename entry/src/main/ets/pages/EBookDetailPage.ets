// 文件路径: entry/src/main/ets/pages/EBookDetailPage.ets
/**
 * 电子书详情页
 * 显示电子书的详细信息、章节列表、阅读进度等
 * 使用 HdsNavDestination 实现统一的导航体验
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { EBook, EBookChapter, EBookFormat, EBookStatus } from '../Models/EBookModels';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { EBookReaderParams } from './EBookReaderPage';
import { DeviceAdaptationManager, DeviceChangeListener, DeviceInfo } from '../Framework/Managers/DeviceAdaptationManager';
import { ScraperDialog, ScraperDialogConfig, ScraperDialogResult } from '../Framework/Components/ScraperDialog';
import { ScraperContentType } from '../Framework/Scraper/ScraperTypes';

const TAG = 'EBookDetailPage';
const TITLE_BAR_HEIGHT = 56;

/**
 * 电子书详情页参数
 */
export interface EBookDetailPageParams {
  bookId: string;
}

/**
 * 电子书设置页参数
 */
export interface EBookSettingsPageParams {
  bookId: string;
}

@Component
export struct EBookDetailPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private componentId: string = 'EBookDetailPage';
  private scroller: Scroller = new Scroller();

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
  
  // 编辑状态
  @State showEditDialog: boolean = false;
  @State editTitle: string = '';
  @State editAuthor: string = '';
  @State editPublisher: string = '';
  @State editPublishDate: string = '';
  @State editIsbn: string = '';
  @State editDescription: string = '';

  // 设备方向检测
  @State private isLandscape: boolean = false;
  private deviceOrientationListener: DeviceChangeListener | null = null;
  private deviceAdaptationManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();

  // 数据管理器
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

  // 刮削对话框控制器
  private scraperDialogController: CustomDialogController | null = null;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    
    // 初始化设备方向
    this.updateDeviceOrientation();
    
    // 注册设备方向变化监听器
    this.deviceOrientationListener = (deviceInfo: DeviceInfo) => {
      logger.info(TAG, `设备方向变化: ${deviceInfo.isLandscape ? '横屏' : '竖屏'}`);
      this.isLandscape = deviceInfo.isLandscape;
    };
    this.deviceAdaptationManager.addListener(this.deviceOrientationListener);
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    
    // 移除设备方向监听器
    if (this.deviceOrientationListener) {
      this.deviceAdaptationManager.removeListener(this.deviceOrientationListener);
      this.deviceOrientationListener = null;
    }
  }

  /**
   * 更新设备方向
   */
  private updateDeviceOrientation(): void {
    const deviceInfo = this.deviceAdaptationManager.getDeviceInfo();
    this.isLandscape = deviceInfo.isLandscape;
    logger.info(TAG, `设备方向初始化: ${this.isLandscape ? '横屏' : '竖屏'}`);
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
    const readerParams: EBookReaderParams = {
      bookId: this.ebook.id
    };
    this.pathStack.pushPath({ name: 'EBookReaderPage', param: readerParams });
  }

  /**
   * 检查是否有阅读进度
   * 判断条件：有 domPos 或 currentChapterIndex > 0 或 progress > 0
   */
  private hasReadingProgress(): boolean {
    if (!this.ebook || !this.ebook.readingProgress) {
      return false;
    }
    const progress = this.ebook.readingProgress;
    // 有 domPos 表示有精确的阅读位置
    if (progress.domPos && progress.domPos.length > 0) {
      return true;
    }
    // 章节索引大于 0 表示已经翻过页
    if (progress.currentChapterIndex > 0) {
      return true;
    }
    // 进度大于 0 也表示有阅读记录
    if (progress.progress > 0) {
      return true;
    }
    return false;
  }

  /**
   * 打开设置页面
   */
  private openSettings(): void {
    if (!this.ebook) {
      return;
    }

    logger.info(TAG, `打开电子书设置: ${this.ebook.metadata.title}`);
    const settingsParams: EBookSettingsPageParams = {
      bookId: this.ebook.id
    };
    this.pathStack.pushPath({ name: 'EBookSettingsPage', param: settingsParams });
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

  /**
   * 打开编辑弹窗
   */
  private openEditDialog(): void {
    if (!this.ebook) {
      return;
    }
    
    // 初始化编辑字段
    this.editTitle = this.ebook.metadata.title;
    this.editAuthor = this.ebook.metadata.author;
    this.editPublisher = this.ebook.metadata.publisher || '';
    this.editPublishDate = this.ebook.metadata.publishDate || '';
    this.editIsbn = this.ebook.metadata.isbn || '';
    this.editDescription = this.ebook.metadata.description || '';
    
    this.showEditDialog = true;
    logger.info(TAG, '打开编辑弹窗');
  }

  /**
   * 保存编辑内容
   */
  private async saveEditContent(): Promise<void> {
    if (!this.ebook) {
      return;
    }

    try {
      // 更新元数据
      this.ebook.metadata.title = this.editTitle;
      this.ebook.metadata.author = this.editAuthor;
      this.ebook.metadata.publisher = this.editPublisher;
      this.ebook.metadata.publishDate = this.editPublishDate;
      this.ebook.metadata.isbn = this.editIsbn;
      this.ebook.metadata.description = this.editDescription;
      this.ebook.lastUpdateTime = Date.now();
      
      // 保存到数据库
      await this.ebookDataManager.saveEBook(this.ebook);
      
      this.showEditDialog = false;
      logger.info(TAG, '书籍信息已保存');
    } catch (error) {
      logger.error(TAG, `保存书籍信息失败: ${String(error)}`);
    }
  }

  /**
   * 打开刮削对话框
   */
  private openScraperDialog(): void {
    if (!this.ebook) {
      return;
    }

    const config: ScraperDialogConfig = {
      initialKeyword: this.ebook.metadata.title || '',
      contentType: ScraperContentType.BOOK,
      title: '搜索电子书信息'
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
  private async applyScraperResult(result: ScraperDialogResult): Promise<void> {
    if (!this.ebook) {
      return;
    }

    const metadata = result.metadata;
    logger.info(TAG, `应用刮削结果: ${metadata.title}`);

    // 应用作者
    if (result.applyAuthor && metadata.author) {
      this.ebook.metadata.author = metadata.author;
    }

    // 应用描述
    if (result.applyDescription && metadata.description) {
      this.ebook.metadata.description = metadata.description;
    }

    // 应用出版社
    if (result.applyPublisher && metadata.publisher) {
      this.ebook.metadata.publisher = metadata.publisher;
    }

    // 应用发布日期
    if (metadata.releaseDate) {
      this.ebook.metadata.publishDate = metadata.releaseDate;
    }

    // 应用标签
    if (result.applyTags && metadata.tags && metadata.tags.length > 0) {
      this.ebook.metadata.tags = metadata.tags;
    }

    // 更新时间戳
    this.ebook.lastUpdateTime = Date.now();

    try {
      // 保存到数据库
      await this.ebookDataManager.saveEBook(this.ebook);
      logger.info(TAG, '刮削结果已保存');
    } catch (error) {
      logger.error(TAG, `保存刮削结果失败: ${String(error)}`);
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层（沉浸式扩展）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        if (this.isLoading) {
          this.buildLoadingView()
        } else if (this.errorMessage.length > 0) {
          this.buildErrorView()
        } else if (this.ebook) {
          if (this.isLandscape) {
            // 横屏布局
            this.buildLandscapeLayout()
          } else {
            // 竖屏布局
            Scroll(this.scroller) {
              Column({ space: 20 }) {
                this.buildDetailContent()
              }
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 20 })
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          }
        }

        // 编辑弹窗
        if (this.showEditDialog) {
          this.buildEditDialog()
        }
      }
    }
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as EBookDetailPageParams | null;
      if (param && param.bookId) {
        this.loadEBookDetail(param.bookId);
      } else {
        this.errorMessage = '无效的电子书ID';
        this.isLoading = false;
      }
    })
    .backgroundColor(Color.Transparent)
    .hideTitleBar(true)
    /*
    // 注释掉不支持的 toolbarConfiguration
    .titleBar({
      safeAreaPadding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme),
          },
          contentStyle: {
            titleStyle: { 
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme), 
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme) 
            },
            menuStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            },
            backIconStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.LIGHT ? '#E6FFFFFF' : '#E6000000',
          },
          contentStyle: {
            titleStyle: { 
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme), 
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme) 
            },
            menuStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            },
            backIconStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            }
          }
        }
      },
      content: {
        title: {
          mainTitle: this.ebook?.metadata.title || '电子书详情',
        }
      }
    })
    */
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
   * 构建详情内容
   */
  @Builder
  buildDetailContent() {
    if (this.ebook) {
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
    }
  }

  /**
   * 构建封面部分
   */
  @Builder
  buildCoverSection() {
    if (this.ebook) {
      Row({ space: 16 }) {
        // 封面
        Stack() {
          if (this.ebook.metadata.coverImagePath && this.ebook.metadata.coverImagePath.length > 0) {
            // 有封面图片 - 本地文件需要添加 file:// 前缀
            Image(this.ebook.metadata.coverImagePath.startsWith('/') 
              ? `file://${this.ebook.metadata.coverImagePath}` 
              : this.ebook.metadata.coverImagePath)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .borderRadius(12)
          } else {
            // 默认图标
            Column() {
              Image($r('app.media.ic_ebook'))
                .width(60)
                .height(60)
                .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .width('100%')
            .height('100%')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(12)
            .justifyContent(FlexAlign.Center)
          }
        }
        .width(120)
        .height(180)
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
      // 开始阅读按钮 - 根据阅读进度显示不同文本
      Button(this.hasReadingProgress() ? '继续阅读' : '开始阅读')
        .fontSize(16)
        .layoutWeight(1)
        .height(48)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .onClick(() => {
          this.startReading();
        })

      // 收藏按钮
      Button() {
        Image(this.ebook?.isFavorite ? $r('app.media.ic_favorite_filled') : $r('app.media.ic_favorite_outline'))
          .width(24)
          .height(24)
          .fillColor(this.ebook?.isFavorite 
            ? ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .border({
        width: 1,
        color: ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme),
        radius: 8
      })
      .onClick(() => {
        this.toggleFavorite();
      })

      // 设置按钮
      Button() {
        Image($r('app.media.ic_settings'))
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .width(48)
      .height(48)
      .backgroundColor(Color.Transparent)
      .border({
        width: 1,
        color: ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme),
        radius: 8
      })
      .onClick(() => {
        this.openSettings();
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
        // 简介与详细信息标题栏（带刮削和编辑按钮）
        Row() {
          Text('简介与详细信息')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()

          // 刮削按钮
          Row({ space: 4 }) {
            Image($r('app.media.ic_scraper'))
              .width(14)
              .height(14)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            Text('刮削')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          .height(28)
          .padding({ left: 10, right: 10 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
          .borderRadius(14)
          .onClick(() => {
            this.openScraperDialog();
          })
          .margin({ right: 8 })
          
          // 编辑按钮
          Button() {
            Row({ space: 4 }) {
              Image($r('app.media.ic_edit'))
                .width(16)
                .height(16)
                .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Text('编辑')
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
          }
          .height(28)
          .padding({ left: 10, right: 10 })
          .backgroundColor('transparent')
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme),
            radius: 14
          })
          .onClick(() => {
            this.openEditDialog();
          })
        }
        .width('100%')

        // 简介
        if (this.ebook.metadata.description.length > 0) {
          Column({ space: 8 }) {
            Text('简介')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

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

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

        // 详细信息
        Column({ space: 8 }) {
          Text('详细信息')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

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

  /**
   * 构建横屏布局
   * 左侧40%显示电子书信息，右侧60%显示章节列表
   */
  @Builder
  buildLandscapeLayout() {
    if (this.ebook) {
      Row({ space: 0 }) {
        // 左侧40%：电子书信息（可滚动）
        Scroll() {
          Column({ space: 16 }) {
            // 封面图片
            Stack() {
              if (this.ebook.metadata.coverImagePath && this.ebook.metadata.coverImagePath.length > 0) {
                Image(this.ebook.metadata.coverImagePath.startsWith('/') 
                  ? `file://${this.ebook.metadata.coverImagePath}` 
                  : this.ebook.metadata.coverImagePath)
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
                  .borderRadius(8)
              } else {
                Column() {
                  Image($r('app.media.ic_ebook'))
                    .width(50)
                    .height(50)
                    .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                }
                .width('100%')
                .height('100%')
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .borderRadius(8)
                .justifyContent(FlexAlign.Center)
              }
            }
            .width(100)
            .height(150)
            .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })

            // 标题
            Text(this.ebook.metadata.title)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .textAlign(TextAlign.Center)

            // 作者
            Text(this.ebook.metadata.author)
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .width('100%')
              .textAlign(TextAlign.Center)

            // 状态标签
            Row({ space: 8 }) {
              Text(this.ebook.format)
                .fontSize(11)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .borderRadius(4)

              Text(this.getStatusText())
                .fontSize(11)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                .backgroundColor(this.getStatusColor())
                .borderRadius(4)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)

            // 阅读进度
            if (this.ebook.readingProgress && this.ebook.readingProgress.progress > 0) {
              Column({ space: 4 }) {
                Text(`已读 ${Math.floor(this.ebook.readingProgress.progress)}%`)
                  .fontSize(11)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                Progress({
                  value: this.ebook.readingProgress.progress,
                  total: 100,
                  type: ProgressType.Linear
                })
                .width('100%')
                .height(4)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
            }

            // 操作按钮（横屏缩小版）
            Row({ space: 6 }) {
              Button({ stateEffect: true }) {
                Text(this.hasReadingProgress() ? '继续' : '开始')
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              }
              .height(32)
              .layoutWeight(1)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .borderRadius(6)
              .onClick(() => this.startReading())

              Button() {
                Image(this.ebook.isFavorite ? $r('app.media.ic_favorite_filled') : $r('app.media.ic_favorite_outline'))
                  .width(16)
                  .height(16)
                  .fillColor(this.ebook.isFavorite 
                    ? ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .border({
                width: 1,
                color: ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme),
                radius: 6
              })
              .onClick(() => this.toggleFavorite())

              Button() {
                Image($r('app.media.ic_settings'))
                  .width(16)
                  .height(16)
                  .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .width(32)
              .height(32)
              .backgroundColor(Color.Transparent)
              .border({
                width: 1,
                color: ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme),
                radius: 6
              })
              .onClick(() => this.openSettings())
            }
            .width('100%')
            .padding({ left: 16, right: 16 })

            // 简介
            if (this.ebook.metadata.description.length > 0) {
              Column({ space: 8 }) {
                Text('简介')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .width('100%')

                Text(this.ebook.metadata.description)
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .lineHeight(18)
                  .maxLines(this.expandedDescription ? 999 : 5)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .onClick(() => {
                    this.expandedDescription = !this.expandedDescription;
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
            }
          }
          .width('100%')
          .padding({ top: 16, bottom: 20 })
        }
        .width('40%')
        .height('100%')
        .padding({ left: 16, right: 8 })
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)

        // 右侧60%：章节列表和详细信息
        Scroll() {
          Column({ space: 16 }) {
            // 详细信息卡片
            Column({ space: 8 }) {
              Text('详细信息')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .width('100%')

              this.buildInfoItem('出版社', this.ebook.metadata.publisher || '未知')
              this.buildInfoItem('出版日期', this.ebook.metadata.publishDate || '未知')
              this.buildInfoItem('ISBN', this.ebook.metadata.isbn || '无')
              this.buildInfoItem('语言', this.ebook.metadata.language)
              this.buildInfoItem('文件大小', this.formatFileSize(this.ebook.fileSize))
              this.buildInfoItem('章节数', `${this.ebook.chapters.length}章`)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(8)

            // 章节列表
            if (this.ebook.chapters.length > 0) {
              Column({ space: 8 }) {
                Text(`章节列表 (${this.ebook.chapters.length})`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .width('100%')

                List({ space: 6 }) {
                  ForEach(this.ebook.chapters, (chapter: EBookChapter, index: number) => {
                    ListItem() {
                      Row({ space: 8 }) {
                        Text(`${index + 1}`)
                          .fontSize(12)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                          .width(30)

                        Text(chapter.title)
                          .fontSize(12)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                          .layoutWeight(1)
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      .width('100%')
                      .padding(8)
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                      .borderRadius(6)
                    }
                  })
                }
                .width('100%')
                .height(400)
                .scrollBar(BarState.Auto)
              }
              .width('100%')
              .padding(12)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
            }
          }
          .width('100%')
          .padding({ top: 16, bottom: 20 })
        }
        .width('60%')
        .height('100%')
        .padding({ left: 8, right: 16 })
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .height('100%')
    }
  }

  /**
   * 构建编辑弹窗
   */
  @Builder
  buildEditDialog() {
    Stack() {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.showEditDialog = false;
        })

      // 编辑面板
      Column() {
        // 标题栏
        Row() {
          Text('编辑书籍信息')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .layoutWeight(1)

          Button() {
            Image($r('app.media.ic_close'))
              .width(20)
              .height(20)
              .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.showEditDialog = false;
          })
        }
        .width('100%')
        .padding({ left: 20, right: 12, top: 16, bottom: 12 })

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

        // 编辑表单
        Scroll() {
          Column({ space: 16 }) {
            // 书名
            this.buildEditField('书名', this.editTitle, (value: string) => {
              this.editTitle = value;
            })

            // 作者
            this.buildEditField('作者', this.editAuthor, (value: string) => {
              this.editAuthor = value;
            })

            // 出版社
            this.buildEditField('出版社', this.editPublisher, (value: string) => {
              this.editPublisher = value;
            })

            // 出版日期
            this.buildEditField('出版日期', this.editPublishDate, (value: string) => {
              this.editPublishDate = value;
            })

            // ISBN
            this.buildEditField('ISBN', this.editIsbn, (value: string) => {
              this.editIsbn = value;
            })

            // 简介（多行）
            Column({ space: 8 }) {
              Text('简介')
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                .width('100%')

              TextArea({ text: this.editDescription, placeholder: '请输入简介' })
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                .borderRadius(8)
                .padding(12)
                .width('100%')
                .height(120)
                .onChange((value: string) => {
                  this.editDescription = value;
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 20 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

        // 底部按钮
        Row({ space: 12 }) {
          Button('取消')
            .fontSize(14)
            .layoutWeight(1)
            .height(44)
            .backgroundColor('transparent')
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .border({
              width: 1,
              color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme)
            })
            .onClick(() => {
              this.showEditDialog = false;
            })

          Button('保存')
            .fontSize(14)
            .layoutWeight(1)
            .height(44)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .onClick(() => {
              this.saveEditContent();
            })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      }
      .width('90%')
      .height('80%')
      .constraintSize({ maxWidth: 450, maxHeight: 650 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
      .borderRadius(16)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .zIndex(1000)
  }

  /**
   * 构建编辑字段
   */
  @Builder
  buildEditField(label: string, value: string, onChange: (value: string) => void) {
    Column({ space: 8 }) {
      Text(label)
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      TextInput({ text: value, placeholder: `请输入${label}` })
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .width('100%')
        .height(44)
        .onChange((newValue: string) => {
          onChange(newValue);
        })
    }
    .width('100%')
  }
}
