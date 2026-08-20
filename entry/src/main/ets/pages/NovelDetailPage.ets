import { ISettingsManagerFacade, SettingsManagerHolder } from 'manxia_core/src/main/ets/Framework/Contracts/ISettingsManagerFacade';
﻿/**
 * 小说详情页面
 * 展示书籍详情和章节列表
 * 使用 HdsNavDestination 实现统一的导航体验
 * 
 * 文件路径: entry/src/main/ets/pages/NovelDetailPage.ets
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { curves, promptAction } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { getNovelSourceManager } from '../Framework/Novel/NovelSourceManager';
import { getNovelDataManager } from '../Framework/Novel/NovelDataManager';
import { getNovelChapterCacheManager } from '../Framework/Novel/NovelChapterCacheManager';
import { getNovelSettingsManager, BrowseHistoryInput } from '../Framework/Novel/NovelSettingsManager';
import { getNovelCoverGenerator, NovelCoverGenerator } from 'manxia_novel/src/main/ets/Framework/Novel/NovelCoverGenerator';
import { getNovelSourceSearchService, SourceSearchResult, SearchTaskHandle } from '../Framework/Novel/NovelSourceSearchService';
import { LegadoBook, LegadoChapter } from 'manxia_novel/src/main/ets/Framework/Novel/LegadoSourceTypes';
import { NovelBook, NovelReadStatus, NovelSearchResult } from 'manxia_core/src/main/ets/Models/NovelModels';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { NovelDetailPageParams, NovelReaderPageParams } from './NovelBookshelfPage';
import { startBookOpenTransitionWithComponentId } from '../components/BookTransitionOverlay';
import { openNovelReaderInIsolatedAbility } from '../Framework/Reader/NovelReaderAbilityLauncher';
import { TextReaderSettings, DEFAULT_TEXT_READER_SETTINGS, BackgroundType, DEFAULT_TEXT_STYLE, TextAlignment } from 'manxia_core/src/main/ets/Models/TextReaderModels';
import { TextReaderSettingsPanel } from '../components/TextReaderSettingsPanel';
import { SettingKeys } from 'manxia_core/src/main/ets/Framework/Contracts/SettingKeys';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { ContentFilterManager } from '../Framework/Managers/ContentFilterManager';
import { AppColors } from 'manxia_theme/src/main/ets/Framework/Theme/AppColors';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from '../Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';

const TAG = 'NovelDetailPage';

@Component
export struct NovelDetailPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `NovelDetailPage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  @State book: LegadoBook | null = null;
  @State chapters: LegadoChapter[] = [];
  @State isLoading: boolean = true;
  @State loadErrorMessage: string = '';
  @State isFavorite: boolean = false;
  @State showAllChapters: boolean = false;
  @State showFullIntro: boolean = false; // 是否展开完整简介
  @State showChapterPanel: boolean = false;
  @State showChangeSourcePanel: boolean = false;
  @State showDownloadPanel: boolean = false; // 下载范围选择面板
  @State isDownloading: boolean = false;
  @State downloadProgress: number = 0;
  @State downloadStartIndex: number = 0; // 下载起始章节索引
  @State downloadEndIndex: number = 0; // 下载结束章节索引
  @State cachedChapterIndexes: Set<number> = new Set(); // 已缓存的章节索引
  @State alternativeSources: NovelSearchResult[] = [];
  @State alternativeSourceResults: SourceSearchResult[] = []; // 按书源分组的搜索结果
  @State isSearchingSource: boolean = false;
  @State searchSourceProgress: number = 0; // 搜索进度（0-100）
  @State searchSourceTotal: number = 0; // 总书源数
  @State searchSourceCompleted: number = 0; // 已完成搜索的书源数
  private searchTaskHandle: SearchTaskHandle | null = null; // 搜索任务句柄
  private sourceSearchService = getNovelSourceSearchService();
  @State lastReadChapterIndex: number = -1; // 上次阅读的章节索引，-1表示未阅读
  @State lastReadChapterTitle: string = ''; // 上次阅读的章节标题
  @State showNovelSettingsPanel: boolean = false; // 显示小说设置面板
  @State novelSettings: TextReaderSettings = DEFAULT_TEXT_READER_SETTINGS; // 小说阅读设置
  
  // 设置面板动画状态
  @State settingsPanelOpacity: number = 0;
  @State settingsPanelScale: number = 0.95;
  private settingsManager: ISettingsManagerFacade = SettingsManagerHolder.get();
  private sourceId: string = '';
  private bookUrl: string = '';
  private requestCarrierKey: string = '';
  private bookVariable: string = '';
  private bookId: string = ''; // 用于获取阅读进度
  private sourceManager = getNovelSourceManager();
  private dataManager = getNovelDataManager();
  private cacheManager = getNovelChapterCacheManager();
  private coverGenerator = getNovelCoverGenerator();
  // 从搜索结果传递的fallback信息
  private fallbackBookInfo: NovelDetailPageParams | null = null;
  // 生成的本地封面路径
  @State generatedCoverPath: string = '';
  // 封面字体倍率
  @State coverFontScale: number = 1.0;

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    
    // 初始化字体感知
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
  }

  private lifecycle = new PageLifecycleManager('NovelDetailPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    // 取消正在进行的换源搜索
    if (this.searchTaskHandle) {
      this.searchTaskHandle.cancel();
      this.searchTaskHandle = null;
    }
  }

  /**
   * 规范化封面路径：本地文件添加file://前缀
   */
  private normalizeCoverPath(path: string): string {
    if (!path || path.length === 0) {
      return '';
    }
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('file://')) {
      return path;
    }
    if (path.startsWith('/')) {
      return `file://${path}`;
    }
    return path;
  }

  async loadBookInfo(): Promise<void> {
    if (!this.sourceId || !this.bookUrl) {
      logger.error(TAG, '缺少必要参数');
      this.isLoading = false;
      return;
    }

    this.loadErrorMessage = '';
    try {
      /* if (this.bookId) {
        const settingsKey = `${SettingKeys.NOVEL_READER_SETTINGS}_${this.bookId}`;
        await this.settingsManager.setJSON<TextReaderSettings>(settingsKey, settings);
        this.novelSettings = settings;
        logger.info(TAG, `淇濆瓨涔︾睄涓撳睘璁剧疆: ${this.bookId}`);
        this.getUIContext().getPromptAction().showToast({ message: '璁剧疆宸蹭繚瀛? });
        return;
      } */
      // 尝试获取书籍详情
      this.book = await this.sourceManager.getBookInfo(
        this.sourceId,
        this.bookUrl,
        undefined,
        this.bookVariable.length > 0 ? this.bookVariable : undefined,
        this.requestCarrierKey.length > 0 ? this.requestCarrierKey : undefined
      );
      
      // 如果详情页返回了部分结果（如只有tocUrl没有name），用fallback补充缺失字段
      if (this.book && !this.book.name && this.fallbackBookInfo && this.fallbackBookInfo.bookName) {
        logger.info(TAG, `详情页部分解析成功，用fallback补充书名: ${this.fallbackBookInfo.bookName}`);
        this.book = this.mergeBookWithFallback(this.book);
      }
      
      // V2 全量/已验证执行时，搜索结果只能作为展示初值，不能替代
      // 失败的详情工作流继续进入目录和正文；否则会把 V2 语义错误
      // 伪装为一次成功阅读。
      if (!this.book && this.isV2DetailFailureTerminal()) {
        this.loadErrorMessage = 'V2 详情工作流未成功完成，请在书源管理查看脱敏 trace。';
        logger.warn(TAG, `V2 详情工作流失败，拒绝搜索结果 fallback: ${this.sourceId}`);
      }

      // 只有明确运行旧内核的路径才允许旧有搜索结果 fallback。
      if (!this.book && !this.isV2DetailFailureTerminal() && this.fallbackBookInfo && this.fallbackBookInfo.bookName) {
        logger.info(TAG, `详情页解析失败，使用fallback信息: ${this.fallbackBookInfo.bookName}`);
        this.book = this.createBookFromFallback();
      }
      
      if (this.book) {
        // 获取章节列表
        this.chapters = await this.sourceManager.getChapterList(this.sourceId, this.book);
        logger.info(TAG, `加载完成: ${this.book.name}, ${this.chapters.length}章`);
        
        // 检查SFW模式
        const sfwEnabled = ContentFilterManager.getInstance().isSFWModeEnabled();
        if (sfwEnabled && this.book.isNSFW) {
          logger.warn(TAG, 'SFW模式已启用，阻止访问NSFW内容');
          this.getUIContext().getPromptAction().showToast({
            message: 'SFW模式已启用，无法查看NSFW内容',
            duration: 2000
          });
          // 返回上一页
          if (this.pathStack) {
            this.pathStack.pop();
          }
          this.isLoading = false;
          return;
        }
        
        // 检查收藏状态
        await this.checkFavoriteStatus();
        
        // 加载阅读进度
        await this.loadReadProgress();
        
        // 加载缓存状态
        this.cachedChapterIndexes = await this.cacheManager.getCachedChapterIndexes(this.bookId, this.chapters.length);
        logger.info(TAG, `已缓存 ${this.cachedChapterIndexes.size} 章`);
        
        // 记录历史浏览（进入详情页即记录）
        await this.recordBrowseHistory();
      } else {
        logger.error(TAG, '无法获取书籍信息');
      }
    } catch (error) {
      logger.error(TAG, `加载失败: ${String(error)}`);
      if (this.isV2DetailFailureTerminal()) {
        this.loadErrorMessage = 'V2 详情工作流发生异常，请在书源管理查看脱敏 trace。';
        this.isLoading = false;
        return;
      }
      // 发生异常时也尝试使用fallback
      if (!this.book && this.fallbackBookInfo && this.fallbackBookInfo.bookName) {
        logger.info(TAG, `异常后使用fallback信息: ${this.fallbackBookInfo.bookName}`);
        this.book = this.createBookFromFallback();
        // 尝试获取章节列表
        if (this.book) {
          try {
            this.chapters = await this.sourceManager.getChapterList(this.sourceId, this.book);
          } catch (e) {
            logger.warn(TAG, `获取章节列表失败: ${String(e)}`);
          }
        }
      }
    }
    this.isLoading = false;
  }

  /**
   * A full V2 cutover must never turn a failed detail request into a usable
   * book merely because the preceding search result contained enough display
   * metadata to build a fallback object.  Verified-only mode uses the same
   * rule only for sources that are actually routed to V2.
   */
  private isV2DetailFailureTerminal(): boolean {
    return this.sourceManager.shouldBlockLegacyFallback(this.sourceId);
  }

  /**
   * 记录历史浏览
   */
  private async recordBrowseHistory(): Promise<void> {
    if (!this.book) return;
    
    try {
      const settingsManager = getNovelSettingsManager();
      const historyInput: BrowseHistoryInput = {
        sourceId: this.sourceId,
        bookUrl: this.bookUrl,
        bookName: this.book.name || '',
        author: this.book.author || '',
        coverUrl: this.book.coverUrl || '',
        sourceName: this.book.originName || ''
      };
      await settingsManager.addBrowseHistory(historyInput);
      logger.debug(TAG, `已记录历史浏览: ${this.book.name}`);
    } catch (error) {
      logger.warn(TAG, `记录历史浏览失败: ${String(error)}`);
    }
  }

  /**
   * 合并详情页解析结果和fallback信息
   * 详情页可能只解析出tocUrl，其他字段需要用fallback补充
   */
  private mergeBookWithFallback(parsedBook: LegadoBook): LegadoBook {
    const fallback = this.fallbackBookInfo!;
    const book: LegadoBook = {
      id: parsedBook.id,
      origin: parsedBook.origin,
      originName: parsedBook.originName || fallback.sourceName || '',
      bookUrl: parsedBook.bookUrl,
      name: parsedBook.name || fallback.bookName || '未知书名',
      author: parsedBook.author || fallback.author || '',
      kind: parsedBook.kind || fallback.kind,
      intro: parsedBook.intro || fallback.intro,
      coverUrl: parsedBook.coverUrl || fallback.coverUrl,
      tocUrl: parsedBook.tocUrl, // 使用详情页解析的tocUrl，这是关键
      latestChapterTitle: parsedBook.latestChapterTitle || fallback.latestChapterTitle,
      wordCount: parsedBook.wordCount || fallback.wordCount,
      type: parsedBook.type
    };
    return book;
  }

  /**
   * 从fallback信息创建书籍对象
   */
  private createBookFromFallback(): LegadoBook {
    const fallback = this.fallbackBookInfo!;
    const book: LegadoBook = {
      id: `fallback_${Date.now()}`,
      origin: this.sourceId,
      originName: fallback.sourceName || '',
      bookUrl: this.bookUrl,
      name: fallback.bookName || '未知书名',
      author: fallback.author || '',
      kind: fallback.kind,
      intro: fallback.intro,
      coverUrl: fallback.coverUrl,
      tocUrl: this.bookUrl, // 使用bookUrl作为目录URL
      latestChapterTitle: fallback.latestChapterTitle,
      wordCount: fallback.wordCount,
      type: 0
    };
    return book;
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.Bottom }) {
        // 背景层：扩展到系统栏区域，实现完全沉浸式背景
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
        
        // 内容层：预留标题栏高度
        Scroll() {
          Column() {
            // 标题栏占位
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
            
            if (this.isLoading) {
              this.buildLoading()
            } else if (this.book) {
              // 书籍信息
              this.buildBookInfo()
              
              // 操作按钮
              this.buildActions()
              
              // 章节列表
              this.buildChapterList()
            } else {
              this.buildError()
            }
            
            Blank().height(20)
          }
          .width('100%')
          .padding({ bottom: 24 + this.navigationBarHeight })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .id('novel_detail_root')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 章节列表面板
        Column() {
          // 遮罩层
          Column()
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('rgba(0,0,0,0.5)')
            .onClick(() => {
              this.showChapterPanel = false;
            })
          
          this.buildChapterPanel()
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .opacity(this.showChapterPanel ? 1 : 0)
        .translate({ y: this.showChapterPanel ? 0 : '100%' })
        .animation({ duration: 250, curve: Curve.EaseOut })
        .hitTestBehavior(this.showChapterPanel ? HitTestMode.Default : HitTestMode.None)
        
        // 换源面板
        Column() {
          // 遮罩层
          Column()
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('rgba(0,0,0,0.5)')
            .onClick(() => {
              this.showChangeSourcePanel = false;
            })
          
          this.buildChangeSourcePanel()
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .opacity(this.showChangeSourcePanel ? 1 : 0)
        .translate({ y: this.showChangeSourcePanel ? 0 : '100%' })
        .animation({ duration: 250, curve: Curve.EaseOut })
        .hitTestBehavior(this.showChangeSourcePanel ? HitTestMode.Default : HitTestMode.None)
        
        // 下载范围选择面板
        Column() {
          // 遮罩层
          Column()
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('rgba(0,0,0,0.5)')
            .onClick(() => {
              this.showDownloadPanel = false;
            })
          
          this.buildDownloadPanel()
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .opacity(this.showDownloadPanel ? 1 : 0)
        .translate({ y: this.showDownloadPanel ? 0 : '100%' })
        .animation({ duration: 250, curve: Curve.EaseOut })
        .hitTestBehavior(this.showDownloadPanel ? HitTestMode.Default : HitTestMode.None)
        
        // 小说设置面板
        if (this.showNovelSettingsPanel) {
          Stack() {
            // 遮罩
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('rgba(0,0,0,0.5)')
              .opacity(this.settingsPanelOpacity)
              .onClick(() => {
                this.hideNovelSettingsPanelWithAnimation();
              })
            
            // 设置面板
            Column() {
              TextReaderSettingsPanel({
                settings: this.novelSettings,
                onClose: () => {
                  this.hideNovelSettingsPanelWithAnimation();
                },
                onSettingsChange: (newSettings: TextReaderSettings) => {
                  this.saveNovelSettings(newSettings);
                }
              })
            }
            .width('95%')
            .height('80%')
            .constraintSize({ maxWidth: 450, minWidth: 320 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
            .borderRadius(16)
            .opacity(this.settingsPanelOpacity)
            .scale({ x: this.settingsPanelScale, y: this.settingsPanelScale })
            .clip(true)
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .alignContent(Alignment.Center)
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: this.book?.name || '涔︾睄璇︽儏',
          appFontFamily: this.appFontFamily
        })
        .align(Alignment.TopStart)
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      const param = context.pathInfo.param as NovelDetailPageParams | null;
      if (param) {
        this.sourceId = param.sourceId || '';
        this.bookUrl = param.bookUrl || '';
        this.requestCarrierKey = param.requestCarrierKey || '';
        this.bookVariable = param.bookVariable || '';
        // 生成bookId用于获取阅读进度
        this.bookId = `${this.sourceId}_${encodeURIComponent(this.bookUrl)}`;
        // 保存fallback信息
        this.fallbackBookInfo = param;
        this.loadBookInfo();
      } else {
        this.isLoading = false;
      }
    })
    .onShown(() => {
      // 页面显示时刷新阅读进度和缓存状态（无感刷新，不显示loading）
      logger.info(TAG, '页面显示，刷新阅读进度和缓存状态');
      this.refreshProgressAndCache();
    })
  }

  /**
   * 刷新阅读进度和缓存状态（无感刷新）
   */
  private async refreshProgressAndCache(): Promise<void> {
    if (!this.bookId || this.chapters.length === 0) return;
    
    try {
      // 刷新阅读进度
      await this.loadReadProgress();
      
      // 刷新收藏状态
      await this.checkFavoriteStatus();
      
      // 刷新缓存状态
      this.cachedChapterIndexes = await this.cacheManager.getCachedChapterIndexes(this.bookId, this.chapters.length);
      logger.debug(TAG, `刷新完成: 阅读进度=${this.lastReadChapterIndex}, 缓存=${this.cachedChapterIndexes.size}章`);
    } catch (error) {
      logger.warn(TAG, `刷新状态失败: ${String(error)}`);
    }
  }

  @Builder
  buildLoading() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      Text('加载中...')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
        .margin({ top: 16 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildError() {
    Column() {
      Text(this.loadErrorMessage.length > 0 ? this.loadErrorMessage : '加载失败')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
      Button('重试')
        .fontFamily(this.appFontFamily)
        .margin({ top: 16 })
        .onClick(() => {
          this.isLoading = true;
          this.loadBookInfo();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  buildBookInfo() {
    Row() {
      // 封面 - 添加id用于翻开动画
      if (this.book?.coverUrl) {
        Image(this.normalizeCoverPath(this.book.coverUrl))
          .width(100)
          .height(140)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
          .id(`novel_cover_${this.sourceId}_${encodeURIComponent(this.bookUrl)}`)
      } else {
        Column() {
          Text((this.book?.name || '').substring(0, 1))
            .fontSize(32)
            .fontFamily(this.appFontFamily)
            .fontColor('#FFFFFF')
        }
        .width(100)
        .height(140)
        .borderRadius(6)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .justifyContent(FlexAlign.Center)
        .id(`novel_cover_${this.sourceId}_${encodeURIComponent(this.bookUrl)}`)
      }
      
      // 信息
      Column() {
        Text(this.book?.name || '')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        
        Text(this.book?.author || '未知作者')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 8 })
        
        if (this.book?.kind) {
          Text(this.book.kind)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        
        Row() {
          Text(this.book?.originName || '')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(2)
          
          Text(`${this.chapters.length}章`)
            .id('novel_detail_chapter_count')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor('#52C41A')
            .margin({ left: 8 })
        }
        .margin({ top: 12 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 16 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })

    // 简介
    if (this.book?.intro) {
      Column() {
        Row() {
          Text('简介')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Text(this.showFullIntro ? '收起' : '展开')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .onClick(() => {
              this.showFullIntro = !this.showFullIntro;
            })
        }
        .width('100%')
        
        Text(this.book.intro)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .margin({ top: 8 })
          .maxLines(this.showFullIntro ? 100 : 3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(
        SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
        SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
      )
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
      .clip(true)
      .border({
        width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
        color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
      })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 8
      })
      .margin({ top: 8 })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  buildActions() {
    Column() {
      // 主要操作按钮
      Row() {
        Button(this.isFavorite ? '已收藏' : '加入书架')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.isFavorite ? 
            ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme) : '#FFFFFF')
          .backgroundColor(this.isFavorite ? 
            ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme) : 
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(20)
          .layoutWeight(1)
          .height(44)
          .margin({ right: 8 })
          .onClick(() => this.toggleFavorite())
        
        Button(this.lastReadChapterIndex >= 0 ? '继续阅读' : '开始阅读')
          .id('novel_detail_start_reading')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor('#52C41A')
          .borderRadius(20)
          .layoutWeight(1)
          .height(44)
          .margin({ left: 8 })
          .onClick(() => this.startReading())
      }
      .width('100%')
      
      // 次要操作按钮（换源、下载、设置）
      Row() {
        // 换源按钮
        Column() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise'))
            .fontSize(20)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
          Text('换源')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .onClick(() => this.searchAlternativeSources())
        
        // 下载按钮
        Column() {
          if (this.isDownloading) {
            Stack() {
              Progress({ value: this.downloadProgress, total: 100, type: ProgressType.Ring })
                .width(20)
                .height(20)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
          } else {
            SymbolGlyph($r('sys.symbol.arrow_down_circle'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
          }
          Text(this.isDownloading ? `${Math.round(this.downloadProgress)}%` : '缓存')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .onClick(() => {
          if (!this.isDownloading) {
            this.showDownloadOptions();
          }
        })
        
        // 小说设置按钮（仅在已收藏时显示）
        if (this.isFavorite) {
          Column() {
            SymbolGlyph($r('sys.symbol.sun_max'))
              .fontSize(20)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
            Text('设置')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .onClick(() => this.showNovelSettings())
        }
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ top: 8 })
  }

  @Builder
  buildChapterList() {
    Column() {
      Row() {
        Text('章节列表')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Text('查看全部')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .onClick(() => {
            this.showChapterPanel = true;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      // 章节列表
      ForEach(
        this.showAllChapters ? this.chapters : this.chapters.slice(0, 20),
        (chapter: LegadoChapter, index: number) => {
          Row() {
            // 阅读进度标记
            if (index === this.lastReadChapterIndex) {
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(10)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
                .margin({ right: 6 })
            }
            
            Text(chapter.title)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(index === this.lastReadChapterIndex ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                (chapter.isVip ? '#FF9800' : 
                  ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            
            // 缓存状态图标
            if (this.cachedChapterIndexes.has(index)) {
              Text('✓')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor('#52C41A')
                .margin({ left: 4 })
            }
            
            if (index === this.lastReadChapterIndex) {
              Text('上次阅读')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
                .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                .borderRadius(2)
                .margin({ left: 8 })
            } else if (chapter.isVip) {
              Text('VIP')
                .fontSize(10)
                .fontFamily(this.appFontFamily)
                .fontColor('#FF9800')
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .backgroundColor(index === this.lastReadChapterIndex ? 
            ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) : 
            Color.Transparent)
          .onClick(() => this.readChapter(chapter, index))
        }
      )
      
      if (!this.showAllChapters && this.chapters.length > 20) {
        Text(`还有${this.chapters.length - 20}章，点击展开`)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .padding(16)
          .onClick(() => {
            this.showAllChapters = true;
          })
      }
    }
    .width('100%')
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ top: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  async toggleFavorite(): Promise<void> {
    logger.info(TAG, `toggleFavorite 被调用: isFavorite=${this.isFavorite}, book=${this.book?.name}`);
    if (!this.book) {
      logger.warn(TAG, 'toggleFavorite: book 为空，无法操作');
      return;
    }
    
    this.isFavorite = !this.isFavorite;
    logger.info(TAG, `切换收藏状态: ${this.isFavorite ? '添加到书架' : '从书架移除'}`);
    
    const bookId = `${this.sourceId}_${encodeURIComponent(this.bookUrl)}`;
    let coverLocalPath: string | undefined = undefined;
    
    // 如果是添加到书架且没有封面URL，生成本地封面
    if (this.isFavorite && !this.book.coverUrl) {
      try {
        logger.info(TAG, `书籍没有封面，尝试生成本地封面: ${this.book.name}`);
        const generatedPath = await this.coverGenerator.generateCover(
          bookId,
          this.book.name,
          () => { this.buildNovelCoverForSnapshot(this.book!.name); },
          this.getUIContext()
        );
        if (generatedPath) {
          coverLocalPath = generatedPath;
          this.generatedCoverPath = generatedPath;
          logger.info(TAG, `本地封面生成成功: ${generatedPath}`);
        }
      } catch (error) {
        logger.warn(TAG, `生成封面失败: ${String(error)}`);
      }
    }
    
    // 保存到数据库
    const novelBook: NovelBook = {
      id: bookId,
      sourceId: this.sourceId,
      sourceName: this.book.originName,
      bookUrl: this.bookUrl,
      name: this.book.name,
      author: this.book.author,
      kind: this.book.kind,
      intro: this.book.intro,
      coverUrl: this.book.coverUrl,
      coverLocalPath: coverLocalPath,
      tocUrl: this.book.tocUrl,
      latestChapterTitle: this.book.latestChapterTitle,
      wordCount: this.book.wordCount,
      chapterCount: this.chapters.length,
      readStatus: NovelReadStatus.UNREAD,
      totalReadingTime: 0,
      isFavorite: this.isFavorite,
      createTime: Date.now(),
      updateDbTime: Date.now()
    };
    
    logger.info(TAG, `准备保存书籍: id=${bookId}, name=${this.book.name}, isFavorite=${this.isFavorite}`);
    try {
      await this.dataManager.saveBook(novelBook);
      logger.info(TAG, `书籍保存成功: ${this.book.name}`);
    } catch (error) {
      logger.error(TAG, `书籍保存失败: ${String(error)}`);
      throw error as Error;
    }
    
    if (this.isFavorite) {
      this.getUIContext().getPromptAction().showToast({ message: coverLocalPath ? '已加入书架（已生成封面）' : '已加入书架' });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '已从书架移除' });
    }
  }

  /**
   * 检查收藏状态
   */
  async checkFavoriteStatus(): Promise<void> {
    try {
      const existingBook = await this.dataManager.getBookByUrl(this.sourceId, this.bookUrl);
      if (existingBook && existingBook.isFavorite) {
        this.isFavorite = true;
        logger.info(TAG, `书籍已在书架: ${this.book?.name}`);
      } else {
        this.isFavorite = false;
      }
    } catch (error) {
      logger.warn(TAG, `检查收藏状态失败: ${String(error)}`);
    }
  }

  /**
   * 加载阅读进度
   */
  async loadReadProgress(): Promise<void> {
    try {
      const progress = await this.dataManager.getReadProgress(this.bookId);
      if (progress && progress.chapterIndex >= 0 && progress.chapterIndex < this.chapters.length) {
        this.lastReadChapterIndex = progress.chapterIndex;
        this.lastReadChapterTitle = this.chapters[progress.chapterIndex]?.title || '';
        logger.info(TAG, `加载阅读进度: 章节${progress.chapterIndex} - ${this.lastReadChapterTitle}`);
      }
    } catch (error) {
      logger.warn(TAG, `加载阅读进度失败: ${String(error)}`);
    }
  }

  startReading(): void {
    if (this.chapters.length > 0) {
      // 如果有阅读进度，从上次阅读的章节继续
      if (this.lastReadChapterIndex >= 0 && this.lastReadChapterIndex < this.chapters.length) {
        this.readChapter(this.chapters[this.lastReadChapterIndex], this.lastReadChapterIndex);
      } else {
        // 否则从第一章开始
        this.readChapter(this.chapters[0], 0);
      }
    }
  }

  readChapter(chapter: LegadoChapter, index: number): void {
    const tocUrl = this.book?.tocUrl || this.bookUrl;
    logger.info(TAG, `跳转阅读器: tocUrl=${tocUrl}, bookUrl=${this.bookUrl}`);
    const params: NovelReaderPageParams = {
      sourceId: this.sourceId,
      bookUrl: this.bookUrl,
      bookName: this.book?.name || '',
      chapterUrl: chapter.url,
      chapterTitle: chapter.title,
      chapterIndex: index,
      totalChapters: this.chapters.length,
      tocUrl: tocUrl // 传递目录URL
    };
    
    // 获取封面路径和组件ID
    const coverPath = this.book?.coverUrl || '';
    const bookId = `${this.sourceId}_${encodeURIComponent(this.bookUrl)}`;
    const coverComponentId = `novel_cover_${bookId}`;
    params.coverComponentId = coverComponentId;
    
    // 触发翻开动画
    logger.info(TAG, `触发翻开过渡动画: coverPath=${coverPath}, componentId=${coverComponentId}`);
    startBookOpenTransitionWithComponentId(
      coverPath,
      coverComponentId,
      bookId,
      'novel',
      () => {
        // 动画完成后导航到阅读器
        params.readerTitle = this.book?.name || '';
        if (!openNovelReaderInIsolatedAbility(this.getUIContext(), this.pathStack, params, TAG, false)) {
          this.pathStack.pushPathByName('NovelReaderPage', params);
        }
      },
      undefined,
      {
        title: this.book?.name || '',
        author: this.book?.author || '',
        intro: this.book?.intro || ''
      }
    );
  }

  /**
   * 换源 - 搜索同名书籍
   * 使用新的换源搜索服务，支持分批并行搜索和进度回调
   */
  searchAlternativeSources(): void {
    if (!this.book) return;
    
    // 取消之前的搜索任务
    if (this.searchTaskHandle) {
      this.searchTaskHandle.cancel();
    }
    
    // 重置状态
    this.isSearchingSource = true;
    this.alternativeSources = [];
    this.alternativeSourceResults = [];
    this.searchSourceCompleted = 0;
    this.searchSourceTotal = this.sourceSearchService.getSearchableSourceCount();
    this.searchSourceProgress = 0;
    this.showChangeSourcePanel = true;
    
    const bookName = this.book.name;
    const bookAuthor = this.book.author;
    
    logger.info(TAG, `开始换源搜索: ${bookName}, 共 ${this.searchSourceTotal} 个书源`);
    
    // 使用新的换源搜索服务
    this.searchTaskHandle = this.sourceSearchService.searchForSource(
      bookName,
      bookAuthor,
      {
        onSourceComplete: (sourceResult: SourceSearchResult) => {
          // 实时更新结果
          this.alternativeSourceResults = [...this.alternativeSourceResults, sourceResult];
          // 同时更新所有结果列表
          this.alternativeSources = [...this.alternativeSources, ...sourceResult.results];
        },
        onProgress: (completed: number, total: number) => {
          this.searchSourceCompleted = completed;
          this.searchSourceTotal = total;
          this.searchSourceProgress = total > 0 ? Math.round((completed / total) * 100) : 0;
        },
        onComplete: (allResults: NovelSearchResult[], sourceResults: SourceSearchResult[]) => {
          this.isSearchingSource = false;
          this.searchSourceProgress = 100;
          this.searchTaskHandle = null;
          logger.info(TAG, `换源搜索完成: 共 ${sourceResults.length} 个书源有结果，总计 ${allResults.length} 本`);
        },
        onCancelled: () => {
          this.isSearchingSource = false;
          this.searchTaskHandle = null;
          logger.info(TAG, '换源搜索已取消');
        }
      },
      50 // 最多搜索50个书源
    );
  }
  
  /**
   * 取消换源搜索
   */
  cancelSourceSearch(): void {
    if (this.searchTaskHandle) {
      this.searchTaskHandle.cancel();
      this.searchTaskHandle = null;
    }
    this.isSearchingSource = false;
  }

  /**
   * 切换书源
   */
  async changeSource(source: NovelSearchResult): Promise<void> {
    this.sourceId = source.sourceId;
    this.bookUrl = source.bookUrl;
    this.showChangeSourcePanel = false;
    this.isLoading = true;
    
    // 重新加载书籍信息
    await this.loadBookInfo();
    
    this.getUIContext().getPromptAction().showToast({ message: `已切换到: ${source.sourceName}` });
  }

  /**
   * 下载章节
   */
  async downloadChapters(startIndex: number = 0, endIndex?: number): Promise<void> {
    if (!this.book || this.chapters.length === 0) return;
    
    const end = endIndex ?? this.chapters.length - 1;
    this.isDownloading = true;
    this.downloadProgress = 0;
    
    // 保存书籍元数据
    await this.cacheManager.saveBookMetadata(
      this.bookId,
      this.book.name,
      this.book.author || '',
      this.book.coverUrl || ''
    );
    
    const taskId = this.cacheManager.createDownloadTask(
      this.bookId,
      this.book.name,
      startIndex,
      end
    );
    
    await this.cacheManager.startDownload(taskId, this.sourceId, this.chapters, {
      onProgress: (current: number, total: number, title: string) => {
        this.downloadProgress = (current / total) * 100;
        logger.debug(TAG, `下载进度: ${current}/${total} - ${title}`);
      },
      onComplete: async () => {
        this.isDownloading = false;
        this.downloadProgress = 100;
        // 刷新缓存状态
        this.cachedChapterIndexes = await this.cacheManager.getCachedChapterIndexes(this.bookId, this.chapters.length);
        this.getUIContext().getPromptAction().showToast({ message: '下载完成' });
      },
      onError: (error: string) => {
        this.isDownloading = false;
        this.getUIContext().getPromptAction().showToast({ message: `下载失败: ${error}` });
      }
    });
  }

  /**
   * 显示下载选项
   */
  async showDownloadOptions(): Promise<void> {
    if (this.chapters.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '没有可下载的章节' });
      return;
    }
    
    // 加载已缓存的章节信息
    this.cachedChapterIndexes = await this.cacheManager.getCachedChapterIndexes(this.bookId, this.chapters.length);
    
    // 初始化下载范围（默认从第一个未缓存的章节开始）
    this.downloadStartIndex = 0;
    this.downloadEndIndex = this.chapters.length - 1;
    
    // 找到第一个未缓存的章节作为起始点
    for (let i = 0; i < this.chapters.length; i++) {
      if (!this.cachedChapterIndexes.has(i)) {
        this.downloadStartIndex = i;
        break;
      }
    }
    
    this.showDownloadPanel = true;
  }

  /**
   * 获取下载范围内未缓存的章节数
   */
  getUncachedCount(): number {
    let count = 0;
    for (let i = this.downloadStartIndex; i <= this.downloadEndIndex; i++) {
      if (!this.cachedChapterIndexes.has(i)) {
        count++;
      }
    }
    return count;
  }

  /**
   * 显示小说设置面板（带动画）
   */
  private showNovelSettingsPanelWithAnimation(): void {
    this.showNovelSettingsPanel = true;
    this.getUIContext().animateTo({
      duration: 250,
      curve: curves.springMotion(0.5, 0.8)
    }, () => {
      this.settingsPanelOpacity = 1;
      this.settingsPanelScale = 1;
    });
  }
  
  /**
   * 隐藏小说设置面板（带动画）
   */
  private hideNovelSettingsPanelWithAnimation(): void {
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut
    }, () => {
      this.settingsPanelOpacity = 0;
      this.settingsPanelScale = 0.95;
    });
    setTimeout(() => {
      this.showNovelSettingsPanel = false;
    }, 200);
  }

  /**
   * 加载小说设置
   */
  async showNovelSettings(): Promise<void> {
    // 加载当前书籍的设置
    await this.loadNovelSettings();
    // 使用带动画的方法显示面板
    this.showNovelSettingsPanelWithAnimation();
  }

  /**
   * 加载小说设置（优先书籍专属，否则全局）
   */
  async loadNovelSettings(): Promise<void> {
    try {
      let bookSettings: TextReaderSettings | undefined = undefined;
      
      if (this.bookId) {
        const settingsKey = `${SettingKeys.NOVEL_READER_SETTINGS}_${this.bookId}`;
        try {
          bookSettings = this.settingsManager.getJSON<TextReaderSettings>(settingsKey, DEFAULT_TEXT_READER_SETTINGS);
          // 检查是否真的有书籍专属设置（通过检查key是否存在）
          const hasBookSettings = this.settingsManager.getString(settingsKey, '');
          if (!hasBookSettings) {
            bookSettings = undefined;
          }
        } catch (e) {
          bookSettings = undefined;
        }
      }
      
      if (bookSettings) {
        // 兼容性处理：确保所有子对象完整
        this.ensureSettingsComplete(bookSettings);
        this.novelSettings = bookSettings;
        logger.info(TAG, `加载书籍专属设置: ${this.bookId}`);
      } else {
        // 使用全局设置
        const globalSettings = this.settingsManager.getJSON<TextReaderSettings>(
          SettingKeys.NOVEL_READER_SETTINGS, 
          DEFAULT_TEXT_READER_SETTINGS
        );
        // 兼容性处理：确保所有子对象完整
        this.ensureSettingsComplete(globalSettings);
        this.novelSettings = globalSettings;
        logger.info(TAG, `使用全局小说阅读器设置`);
      }
    } catch (error) {
      logger.error(TAG, `加载小说设置失败: ${String(error)}`);
      this.novelSettings = DEFAULT_TEXT_READER_SETTINGS;
    }
  }
  
  /**
   * 确保设置对象的所有子属性完整（兼容旧版本设置）
   */
  private ensureSettingsComplete(settings: TextReaderSettings): void {
    // 确保background对象完整
    if (!settings.background) {
      settings.background = { type: BackgroundType.COLOR, color: '#F5F0E1' };
    } else if (!settings.background.type) {
      settings.background.type = BackgroundType.COLOR;
    }
    
    // 确保textStyle对象完整
    if (!settings.textStyle) {
      settings.textStyle = DEFAULT_TEXT_STYLE;
    } else {
      if (settings.textStyle.fontSize === undefined) settings.textStyle.fontSize = 18;
      if (settings.textStyle.lineHeight === undefined) settings.textStyle.lineHeight = 1.8;
      if (settings.textStyle.paragraphSpacing === undefined) settings.textStyle.paragraphSpacing = 16;
      if (settings.textStyle.firstLineIndent === undefined) settings.textStyle.firstLineIndent = 2;
      if (settings.textStyle.letterSpacing === undefined) settings.textStyle.letterSpacing = 0.5;
      if (settings.textStyle.textColor === undefined) settings.textStyle.textColor = '#333333';
      if (settings.textStyle.fontWeight === undefined) settings.textStyle.fontWeight = 400;
      if (settings.textStyle.fontFamily === undefined) settings.textStyle.fontFamily = 'HarmonyOS Sans';
      if (settings.textStyle.textAlignment === undefined) settings.textStyle.textAlignment = TextAlignment.JUSTIFY;
    }
    
    // 确保pageMargins对象完整
    if (!settings.pageMargins) {
      settings.pageMargins = { top: 48, bottom: 48, left: 24, right: 24 };
    }
  }

  /**
   * 保存小说设置
   */
  async saveNovelSettings(settings: TextReaderSettings): Promise<void> {
    try {
      if (this.bookId) {
        const settingsKey = `${SettingKeys.NOVEL_READER_SETTINGS}_${this.bookId}`;
        await this.settingsManager.setJSON<TextReaderSettings>(settingsKey, settings);
        this.novelSettings = settings;
        logger.info(TAG, `Saved book-specific novel settings: ${this.bookId}`);
        this.getUIContext().getPromptAction().showToast({ message: '设置已保存' });
        return;
      }
      // 保存为全局设置
      await this.settingsManager.setJSON<TextReaderSettings>(
        SettingKeys.NOVEL_READER_SETTINGS, 
        settings
      );
      
      // 同时保存为书籍专属设置
      if (this.bookId) {
        const settingsKey = `${SettingKeys.NOVEL_READER_SETTINGS}_${this.bookId}`;
        await this.settingsManager.setJSON<TextReaderSettings>(settingsKey, settings);
        logger.info(TAG, `保存书籍专属设置: ${this.bookId}`);
      }
      
      this.novelSettings = settings;
      this.getUIContext().getPromptAction().showToast({ message: '设置已保存' });
    } catch (error) {
      logger.error(TAG, `保存小说设置失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '保存设置失败' });
    }
  }

  @Builder
  buildDownloadPanel() {
    Column() {
      // 顶部栏
      Row() {
        Text('选择下载范围')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(24)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
          .onClick(() => {
            this.showDownloadPanel = false;
          })
      }
      .width('100%')
      .padding(16)
      
      // 缓存状态信息
      Row() {
        Text(`共 ${this.chapters.length} 章`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Text(`已缓存 ${this.cachedChapterIndexes.size} 章`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor('#52C41A')
          .margin({ left: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })
      
      // 起始章节选择
      Column() {
        Row() {
          Text('起始章节')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Text(`第 ${this.downloadStartIndex + 1} 章`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width('100%')
        
        Text(this.chapters[this.downloadStartIndex]?.title || '')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .width('100%')
        
        Slider({
          value: this.downloadStartIndex,
          min: 0,
          max: this.chapters.length - 1,
          step: 1,
          style: SliderStyle.OutSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ top: 8 })
          .onChange((value: number) => {
            this.downloadStartIndex = Math.round(value);
            // 确保起始不超过结束
            if (this.downloadStartIndex > this.downloadEndIndex) {
              this.downloadEndIndex = this.downloadStartIndex;
            }
          })
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
      
      // 结束章节选择
      Column() {
        Row() {
          Text('结束章节')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          Blank()
          
          Text(`第 ${this.downloadEndIndex + 1} 章`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .width('100%')
        
        Text(this.chapters[this.downloadEndIndex]?.title || '')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
          .width('100%')
        
        Slider({
          value: this.downloadEndIndex,
          min: 0,
          max: this.chapters.length - 1,
          step: 1,
          style: SliderStyle.OutSet
        })
          .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ top: 8 })
          .onChange((value: number) => {
            this.downloadEndIndex = Math.round(value);
            // 确保结束不小于起始
            if (this.downloadEndIndex < this.downloadStartIndex) {
              this.downloadStartIndex = this.downloadEndIndex;
            }
          })
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
      
      // 下载信息和按钮
      Column() {
        Text(`将下载 ${this.getUncachedCount()} 章（共选择 ${this.downloadEndIndex - this.downloadStartIndex + 1} 章）`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        
        Button('开始下载')
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontColor('#FFFFFF')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .borderRadius(24)
          .width('100%')
          .height(48)
          .margin({ top: 16 })
          .onClick(() => {
            this.showDownloadPanel = false;
            this.downloadChapters(this.downloadStartIndex, this.downloadEndIndex);
          })
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius({
      topLeft: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme),
      topRight: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme)
    })
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: -6
    })
  }

  @Builder
  buildChapterPanel() {
    Column() {
      // 顶部栏
      Row() {
        Text('章节列表')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(24)
          .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
          .onClick(() => {
            this.showChapterPanel = false;
          })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      
      // 章节列表
      List() {
        ForEach(this.chapters, (chapter: LegadoChapter, index: number) => {
          ListItem() {
            Row() {
              Text(`${index + 1}.`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(index === this.lastReadChapterIndex ? 
                  ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                  ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                .width(40)
              
              Text(chapter.title)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(index === this.lastReadChapterIndex ? 
                  ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                  (chapter.isVip ? '#FF9800' : 
                    ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)))
                .fontWeight(index === this.lastReadChapterIndex ? FontWeight.Medium : FontWeight.Normal)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              
              // 缓存状态图标
              if (this.cachedChapterIndexes.has(index)) {
                Text('✓')
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor('#52C41A')
                  .margin({ left: 4 })
              }
              
              if (index === this.lastReadChapterIndex) {
                Text('上次阅读')
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                  .margin({ left: 8 })
              } else if (chapter.isVip) {
                Text('VIP')
                  .fontSize(10)
                  .fontFamily(this.appFontFamily)
                  .fontColor('#FF9800')
                  .margin({ left: 8 })
              }
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              this.showChapterPanel = false;
              this.readChapter(chapter, index);
            })
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('80%')
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius({
      topLeft: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme),
      topRight: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme)
    })
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: -6
    })
  }

  @Builder
  buildChangeSourcePanel() {
    Column() {
      // 顶部栏
      Row() {
        Column() {
          Row() {
            Text('换源')
              .fontSize(16)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            
            if (this.alternativeSourceResults.length > 0) {
              Text(`(${this.alternativeSourceResults.length}个书源)`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                .margin({ left: 8 })
            }
          }
          
          // 搜索进度条
          if (this.isSearchingSource) {
            Row() {
              Progress({ value: this.searchSourceProgress, total: 100, type: ProgressType.Linear })
                .width('100%')
                .height(4)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
            }
            .width('100%')
            .margin({ top: 8 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        
        Row({ space: 12 }) {
          // 搜索进度文字
          if (this.isSearchingSource) {
            Text(`${this.searchSourceCompleted}/${this.searchSourceTotal}`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
          }
          
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(24)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
            .onClick(() => {
              this.cancelSourceSearch();
              this.showChangeSourcePanel = false;
            })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      
      // 搜索结果列表
      if (this.isSearchingSource && this.alternativeSourceResults.length === 0) {
        // 正在搜索且还没有结果
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
          Text(`正在搜索可用书源... (${this.searchSourceCompleted}/${this.searchSourceTotal})`)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (!this.isSearchingSource && this.alternativeSourceResults.length === 0) {
        // 搜索完成但没有结果
        Column() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(48)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme)])
          Text('未找到其他书源')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 12 })
          Text('试试导入更多书源后再换源')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 有结果，按书源分组展示
        List() {
          ForEach(this.alternativeSourceResults, (sourceResult: SourceSearchResult) => {
            // 书源分组标题
            ListItem() {
              Row() {
                Text(sourceResult.sourceName)
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                
                Text(`${sourceResult.results.length}本`)
                  .fontSize(11)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                  .margin({ left: 8 })
                
                if (sourceResult.sourceGroup && sourceResult.sourceGroup !== '未分组') {
                  Text(sourceResult.sourceGroup)
                    .fontSize(10)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .margin({ left: 8 })
                }
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 8 })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            }
            
            // 该书源下的书籍列表
            ForEach(sourceResult.results, (book: NovelSearchResult) => {
              ListItem() {
                Row() {
                  Column() {
                    Row() {
                      Text(book.name)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontFamily(this.appFontFamily)
                        .fontColor(book.sourceId === this.sourceId ? 
                          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) :
                          ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      
                      if (book.author) {
                        Text(`· ${book.author}`)
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                          .margin({ left: 8 })
                          .maxLines(1)
                      }
                    }
                    
                    Text(book.latestChapterTitle || '暂无最新章节信息')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_tertiary', this.themeState.currentTheme))
                      .margin({ top: 4 })
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  
                  if (book.sourceId === this.sourceId) {
                    Text('当前')
                      .fontSize(12)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
                      .borderRadius(4)
                  }
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                .onClick(() => {
                  if (book.sourceId !== this.sourceId) {
                    this.changeSource(book);
                  }
                })
              }
            }, (book: NovelSearchResult) => `${sourceResult.sourceId}_${book.bookUrl}`)
          }, (sourceResult: SourceSearchResult) => sourceResult.sourceId)
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 0.5, color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme) })
      }
    }
    .width('100%')
    .height('70%')
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(
      SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme),
      SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme)
    )
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius({
      topLeft: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme),
      topRight: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme)
    })
    .clip(true)
    .border({
      width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme),
      color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme)
    })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: -6
    })
  }

  // 封面生成器常量
  private static readonly COVER_WIDTH = 400;
  private static readonly COVER_HEIGHT = 600;
  private static readonly TITLE_AREA_TOP_PERCENT = 0.130;
  private static readonly TITLE_AREA_BOTTOM_PERCENT = 0.345;
  private static readonly TITLE_AREA_LEFT_PERCENT = 0.110;
  private static readonly TITLE_AREA_RIGHT_PERCENT = 0.895;

  /**
   * 格式化封面标题
   */
  private formatCoverTitle(title: string): string {
    let cleanTitle = title.replace(/\.(txt|epub|pdf|mobi|azw3?)$/i, '');
    if (cleanTitle.length > 20) {
      cleanTitle = cleanTitle.substring(0, 17) + '...';
    }
    return cleanTitle;
  }

  /**
   * 计算封面字体大小
   */
  private calculateCoverFontSize(title: string): number {
    const length = title.length;
    let baseSize = 24;
    if (length <= 2) baseSize = 70;
    else if (length <= 4) baseSize = 56;
    else if (length <= 6) baseSize = 48;
    else if (length <= 8) baseSize = 36;
    else if (length <= 12) baseSize = 32;
    else if (length <= 16) baseSize = 28;
    
    return baseSize * this.coverFontScale;
  }

  /**
   * 构建小说封面组件（用于 componentSnapshot）
   */
  @Builder
  buildNovelCoverForSnapshot(title: string) {
    Stack() {
      // 底层：默认封面图片
      Image($r('app.media.ebook'))
        .width(NovelDetailPage.COVER_WIDTH)
        .height(NovelDetailPage.COVER_HEIGHT)
        .objectFit(ImageFit.Cover)
      
      // 标题文字层
      Text(this.formatCoverTitle(title))
        .fontFamily(this.appFontFamily)
        .fontSize(this.calculateCoverFontSize(title))
        .fontWeight(FontWeight.Bold)
        .fontColor('#1a1a1a')
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(this.calculateCoverFontSize(title) * 1.3)
        .width(NovelDetailPage.COVER_WIDTH * (NovelDetailPage.TITLE_AREA_RIGHT_PERCENT - NovelDetailPage.TITLE_AREA_LEFT_PERCENT) - 24)
        .constraintSize({
          maxHeight: NovelDetailPage.COVER_HEIGHT * (NovelDetailPage.TITLE_AREA_BOTTOM_PERCENT - NovelDetailPage.TITLE_AREA_TOP_PERCENT) - 20
        })
        .position({
          x: NovelDetailPage.COVER_WIDTH * NovelDetailPage.TITLE_AREA_LEFT_PERCENT + 12,
          y: NovelDetailPage.COVER_HEIGHT * (NovelDetailPage.TITLE_AREA_TOP_PERCENT + NovelDetailPage.TITLE_AREA_BOTTOM_PERCENT) / 2 - this.calculateCoverFontSize(title) * 0.65
        })
    }
    .width(NovelDetailPage.COVER_WIDTH)
    .height(NovelDetailPage.COVER_HEIGHT)
  }
}
