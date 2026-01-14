// 文件路径: src/main/ets/pages/StorageManagementPage.ets
/**
 * 存储管理页面
 * 统一管理和可视化展示应用的所有存储使用情况
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { logger } from '../Utils/Logger';
import { StorageAnalyzer, StorageStatistics, StorageItem, StorageType, ClearOptions } from '../Framework/Storage/StorageAnalyzer';
import { ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { LengthMetrics } from '@kit.ArkUI';
import { PermanentImageCacheManager, MangaCacheStats } from '../Framework/Cache/PermanentImageCacheManager';
import { CoverCacheManager } from '../Framework/Cache/CoverCacheManager';
import { DataManager } from '../Framework/Data/DataManager';
import { ImageCacheManager } from '../Framework/Cache/ImageCacheManager';
import { CacheConfigManager, CacheConfig } from '../Framework/Cache/CacheConfigManager';
import { SmartPreloadStrategy, PreloadStats } from '../Framework/Cache/SmartPreloadStrategy';
import { DiskCacheManager } from '../Framework/Cache/DiskCacheManager';
import { CacheManagementPanel } from '../components/CacheManagementPanel';
import { getHelpPanelManagerV2 } from '../Framework/Components/HelpPanelV2';

const TAG = 'StorageManagementPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

interface ThemeState {
  currentTheme: ThemeType;
}

interface SourceCoverInfo {
  sourceId: number;
  sourceName: string;
  coverCount: number;
  totalSize: number;
}

interface CacheDetailInfo {
  memoryCacheSize: number;
  diskCacheSize: number;
  permanentCacheSize: number;
  mangaCacheList: MangaCacheStats[];
  coverCacheList: SourceCoverInfo[];
}

interface DiskCacheStatsInfo {
  count: number;
  totalSize: number;
  usagePercent: number;
}

@ComponentV2
export struct StorageManagementPage {
  @Local themeState: ThemeState = { currentTheme: ThemeType.DARK };
  @Local fontState: FontAwareState = new FontAwareState();
  @Local appFontFamily: string = 'HarmonyOS Sans';
  @Local isLoading: boolean = true;
  @Local statistics: StorageStatistics | null = null;
  @Local selectedItems: Set<StorageType> = new Set();
  @Local selectedCount: number = 0; // 用于触发UI更新
  @Local isClearing: boolean = false;
  @Local cacheDetails: CacheDetailInfo | null = null;
  @Local showCacheDetails: boolean = false;
  @Local showCacheConfig: boolean = false;
  @Local showPreloadStats: boolean = false;
  @Local cacheConfig: CacheConfig | null = null;
  @Local preloadStats: PreloadStats | null = null;
  @Local diskCacheStats: DiskCacheStatsInfo | null = null;
  private storageAnalyzer: StorageAnalyzer = StorageAnalyzer.getInstance();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private cacheConfigManager: CacheConfigManager = CacheConfigManager.getInstance();
  private smartPreloadStrategy: SmartPreloadStrategy = SmartPreloadStrategy.getInstance();
  private diskCacheManager: DiskCacheManager = DiskCacheManager.getInstance();
  private lifecycle = new PageLifecycleManager('StorageManagementPage', { enableDebug: true });
  private themeChangeCallback: ((theme: ThemeType) => void) | null = null;
  pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    logger.info(TAG, '存储管理页面初始化');

    // 初始化主题并监听变化（使用getActualTheme获取实际显示的主题）
    this.themeManager.getActualTheme().then((theme: ThemeType) => {
      this.themeState = { currentTheme: theme };
    });
    this.themeChangeCallback = (newTheme: ThemeType) => {
      logger.info(TAG, `主题切换到: ${newTheme}`);
      this.themeState = { currentTheme: newTheme };
    };
    this.themeManager.onThemeChange(this.themeChangeCallback);

    // 加载存储统计
    this.loadStorageStatistics();
    
    // 初始化字体管理
    FontAwareHelper.initializeFontAware('StorageManagementPage', this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
      this.appFontFamily = newState.appFontFamily;
    });
  }

  aboutToDisappear(): void {
    logger.info(TAG, '存储管理页面销毁');
    // 移除主题监听器
    if (this.themeChangeCallback) {
      this.themeManager.offThemeChange(this.themeChangeCallback);
    }
    this.lifecycle.destroy();
    FontAwareHelper.cleanupFontAware('StorageManagementPage');
  }

  /**
   * 加载存储统计信息
   */
  private async loadStorageStatistics(): Promise<void> {
    try {
      this.isLoading = true;
      this.statistics = await this.storageAnalyzer.analyzeStorage(true);
      logger.info(TAG, `存储统计加载完成，总使用: ${this.storageAnalyzer.formatSize(this.statistics.usedSize)}`);
    } catch (error) {
      logger.error(TAG, `加载存储统计失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({ message: '加载失败' });
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 刷新统计信息
   */
  private async refreshStatistics(): Promise<void> {
    await this.loadStorageStatistics();
    if (this.showCacheDetails) {
      await this.loadCacheDetails();
    }
    this.getUIContext().getPromptAction().showToast({ message: '已刷新' });
  }

  /**
   * 加载缓存详情
   */
  private async loadCacheDetails(): Promise<void> {
    try {
      const imageCacheManager = ImageCacheManager.getInstance();
      const permanentCacheManager = PermanentImageCacheManager.getInstance();
      const coverCacheManager = CoverCacheManager.getInstance();
      const dataManager = DataManager.getInstance();

      // 获取内存缓存统计
      const cacheStats = await imageCacheManager.getCacheStats();
      const memoryCacheSize = cacheStats.memoryCache.size;
      const diskCacheSize = cacheStats.diskCache.size;

      // 获取永久缓存统计（按漫画分类）
      const sources = await dataManager.getAllComicSources();
      const mangaCacheList: MangaCacheStats[] = [];
      let permanentCacheSize = 0;

      for (const source of sources) {
        if (source.id && typeof source.id === 'number') {
          const stats = await permanentCacheManager.getSourceMangaCacheStats(source.id as number);
          mangaCacheList.push(...stats);
          for (let i = 0; i < stats.length; i++) {
            permanentCacheSize += stats[i].totalSize;
          }
        }
      }

      // 获取封面缓存统计（按图源分类）
      const coverCacheList: SourceCoverInfo[] = [];
      const allCoverStats = await coverCacheManager.getAllSourceCoverStats();

      const entries = Array.from(allCoverStats.entries());
      for (let i = 0; i < entries.length; i++) {
        const entry = entries[i];
        const sourceId = entry[0];
        const stat = entry[1];
        const source = await dataManager.getComicSourceById(sourceId);
        coverCacheList.push({
          sourceId: sourceId,
          sourceName: source?.name || `图源${sourceId}`,
          coverCount: stat.count,
          totalSize: stat.size
        });
      }

      this.cacheDetails = {
        memoryCacheSize,
        diskCacheSize,
        permanentCacheSize,
        mangaCacheList,
        coverCacheList
      };

      logger.info(TAG, '缓存详情加载完成');
    } catch (error) {
      logger.error(TAG, `加载缓存详情失败: ${error}`);
    }
  }

  /**
   * 切换缓存详情显示
   */
  private async toggleCacheDetails(): Promise<void> {
    this.showCacheDetails = !this.showCacheDetails;
    if (this.showCacheDetails && !this.cacheDetails) {
      await this.loadCacheDetails();
    }
  }

  /**
   * 删除漫画缓存
   */
  private async deleteMangaCache(sourceId: number, mangaId: string): Promise<void> {
    try {
      const permanentCacheManager = PermanentImageCacheManager.getInstance();
      await permanentCacheManager.cleanMangaCache(sourceId, mangaId);
      this.getUIContext().getPromptAction().showToast({ message: '删除成功' });
      await this.loadCacheDetails();
      await this.loadStorageStatistics();
    } catch (error) {
      logger.error(TAG, `删除漫画缓存失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
    }
  }

  /**
   * 删除图源封面缓存
   */
  private async deleteSourceCovers(sourceId: number): Promise<void> {
    try {
      const coverCacheManager = CoverCacheManager.getInstance();
      await coverCacheManager.cleanSourceCovers(sourceId);
      this.getUIContext().getPromptAction().showToast({ message: '删除成功' });
      await this.loadCacheDetails();
      await this.loadStorageStatistics();
    } catch (error) {
      logger.error(TAG, `删除封面缓存失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({ message: '删除失败' });
    }
  }

  /**
   * 显示清理确认对话框
   * 显示即将清理的详细文件夹路径
   */
  private showClearConfirmDialog(): void {
    if (this.selectedItems.size === 0) {
      return;
    }

    // 构建详细的清理信息，包含文件夹路径
    const detailLines: string[] = [];
    let totalSize = 0;
    let totalFiles = 0;

    Array.from(this.selectedItems).forEach(type => {
      const item = this.statistics?.items.find(i => i.type === type);
      if (item) {
        const sizeFmt = this.storageAnalyzer.formatSize(item.size);
        const pathInfo = item.path ? `\n   路径: ${item.path}` : '';
        detailLines.push(`• ${item.name}\n   大小: ${sizeFmt}, ${item.fileCount} 个文件${pathInfo}`);
        totalSize += item.size;
        totalFiles += item.fileCount;
      }
    });

    const totalSizeFmt = this.storageAnalyzer.formatSize(totalSize);
    const summary = `\n\n【总计】${totalSizeFmt}, ${totalFiles} 个文件`;

    AlertDialog.show({
      title: '确认清理',
      message: `确定要清理以下项目吗？\n\n${detailLines.join('\n\n')}${summary}\n\n⚠️ 此操作不可撤销！`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
          logger.info(TAG, '用户取消清理操作');
        }
      },
      secondaryButton: {
        value: '确认清理',
        fontColor: Color.Red,
        action: () => {
          this.clearSelectedItems();
        }
      }
    });
  }

  /**
   * 清理选中的存储项
   */
  private async clearSelectedItems(): Promise<void> {
    if (this.selectedItems.size === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请选择要清理的项' });
      return;
    }

    try {
      this.isClearing = true;
      const options: ClearOptions = {
        types: Array.from(this.selectedItems)
      };

      const result = await this.storageAnalyzer.clearStorage(options);

      if (result.success) {
        this.getUIContext().getPromptAction().showToast({
          message: `清理完成: ${this.storageAnalyzer.formatSize(result.clearedSize)}`
        });
        this.selectedItems.clear();
        this.selectedCount = 0;
        await this.loadStorageStatistics();
      } else {
        this.getUIContext().getPromptAction().showToast({ message: `清理失败: ${result.errors.join(', ')}` });
      }
    } catch (error) {
      logger.error(TAG, `清理失败: ${error}`);
      this.getUIContext().getPromptAction().showToast({ message: '清理失败' });
    } finally {
      this.isClearing = false;
    }
  }

  /**
   * 检查项目是否被选中（使用selectedCount触发UI更新）
   */
  private isItemSelected(type: StorageType): boolean {
    // 引用selectedCount确保UI更新
    const _ = this.selectedCount;
    return this.selectedItems.has(type);
  }

  /**
   * 切换选中状态
   */
  private toggleSelection(type: StorageType, canClear: boolean): void {
    if (!canClear) {
      this.getUIContext().getPromptAction().showToast({ message: '该项不可清理' });
      return;
    }

    if (this.selectedItems.has(type)) {
      this.selectedItems.delete(type);
    } else {
      this.selectedItems.add(type);
    }
    // 更新计数以触发UI刷新
    this.selectedCount = this.selectedItems.size;
  }

  /**
   * 构建总览卡片
   */
  @Builder
  buildOverviewCard() {
    Column({ space: 16 }) {
      Text('存储总览')
        .fontSize(18)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      if (this.statistics) {
        Column({ space: 12 }) {
          Row() {
            Text('总使用空间')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Blank()
            Text(this.storageAnalyzer.formatSize(this.statistics.usedSize))
              .fontSize(16)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
          .width('100%')

          Progress({
            value: this.statistics.usedSize,
            total: this.statistics.usedSize * 1.2,
            type: ProgressType.Linear
          })
            .width('100%')
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .height(8)
            .borderRadius(4)

          Text(`共 ${this.statistics.items.length} 个存储项`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  /**
   * 构建存储项卡片
   */
  @Builder
  buildStorageItemCard(item: StorageItem) {
    Row({ space: 12 }) {
      // 选择图标 - 使用SymbolGlyph组件显示Symbol图标
      SymbolGlyph(this.isItemSelected(item.type) ? $r('sys.symbol.checkmark_square_fill') : $r('sys.symbol.square'))
        .fontSize(24)
        .fontColor([item.canClear 
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
        .onClick(() => {
          if (item.canClear) {
            this.toggleSelection(item.type, item.canClear);
          }
        })

      // 信息区域
      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(item.name)
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          if (!item.canClear) {
            Text('不可清理')
              .fontSize(10)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .padding({
                left: 6,
                right: 6,
                top: 2,
                bottom: 2
              })
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border',
                this.themeState.currentTheme))
              .borderRadius(4)
          }
        }

        Text(item.description)
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 显示文件夹路径（如果有）
        if (item.path && item.path.length > 0) {
          Text(`📁 ${item.path}`)
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        Row({ space: 8 }) {
          Text(this.storageAnalyzer.formatSize(item.size))
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

          if (item.fileCount > 0) {
            Text(`${item.fileCount} 个文件`)
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .onClick(() => {
      this.toggleSelection(item.type, item.canClear);
    })
  }

  /**
   * 构建操作按钮区域
   */
  @Builder
  buildActionButtons() {
    Row({ space: 12 }) {
      Button('刷新')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background',
          this.themeState.currentTheme))
        .borderRadius(8)
        .layoutWeight(1)
        .enabled(!this.isLoading && !this.isClearing)
        .onClick(() => {
          this.refreshStatistics();
        })

      Button(`清理选中 (${this.selectedCount})`)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(Color.White)
        .backgroundColor(this.selectedCount > 0
          ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
          : ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
        .borderRadius(8)
        .layoutWeight(1)
        .enabled(this.selectedCount > 0 && !this.isClearing)
        .onClick(() => {
          this.showClearConfirmDialog();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundBlurStyle(BlurStyle.Thin)
    .backgroundColor(this.themeState.currentTheme === ThemeType.DARK 
      ? 'rgba(30, 30, 30, 0.85)' 
      : 'rgba(245, 245, 245, 0.85)')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark',
            this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Column() {
          // 空白区域
          Blank()
            .width('100%')
            .height(56)

          if (this.isLoading) {
            // 加载中
            Column({ space: 20 }) {
              LoadingProgress()
                .width(40)
                .height(40)
                .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              Text('加载中...')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                  this.themeState.currentTheme))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.statistics) {
            // 有数据时显示
            Column({ space: 12 }) {
              this.buildOverviewCard()

              // 缓存管理按钮组
              Row({ space: 8 }) {
                Button('缓存管理')
                  .layoutWeight(1)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(Color.White)
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue',
                    this.themeState.currentTheme))
                  .borderRadius(8)
                  .onClick(() => {
                    this.showCacheConfig = true;
                  })

                Button(this.showCacheDetails ? '收起详情' : '查看详情')
                  .layoutWeight(1)
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                    this.themeState.currentTheme))
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background',
                    this.themeState.currentTheme))
                  .borderRadius(8)
                  .onClick(() => {
                    this.toggleCacheDetails();
                  })
              }
              .width('100%')

              // 缓存详情内容
              if (this.showCacheDetails && this.cacheDetails) {
                Column({ space: 8 }) {
                  Text('缓存详情')
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                      this.themeState.currentTheme))

                  Text(`内存缓存: ${this.storageAnalyzer.formatSize(this.cacheDetails.memoryCacheSize)}`)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                      this.themeState.currentTheme))

                  Text(`磁盘缓存: ${this.storageAnalyzer.formatSize(this.cacheDetails.diskCacheSize)}`)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                      this.themeState.currentTheme))

                  Text(`永久缓存: ${this.storageAnalyzer.formatSize(this.cacheDetails.permanentCacheSize)}`)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                      this.themeState.currentTheme))
                }
                .width('100%')
                .padding(16)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background',
                  this.themeState.currentTheme))
                .borderRadius(12)
              }

              // 存储项列表
              Column({ space: 8 }) {
                Text('存储项目')
                  .fontSize(16)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary',
                    this.themeState.currentTheme))
                  .margin({ bottom: 4 })

                List({ space: 12 }) {
                  ForEach(this.statistics.items, (item: StorageItem) => {
                    ListItem() {
                      this.buildStorageItemCard(item)
                    }
                  }, (item: StorageItem) => item.type)
                }
                .layoutWeight(1)
                .scrollBar(BarState.Auto)
                .edgeEffect(EdgeEffect.Spring)
              }
              .layoutWeight(1)
              .width('100%')
            }
            .layoutWeight(1)
            .padding({ left: 16, right: 16, top: 8 })

            // 操作按钮
            this.buildActionButtons()
          } else {
            // 错误状态
            Column({ space: 20 }) {
              Text('加载失败')
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary',
                  this.themeState.currentTheme))
              Button('重试')
                .fontFamily(this.appFontFamily)
                .onClick(() => {
                  this.loadStorageStatistics();
                })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))

        // 缓存管理面板弹窗
        if (this.showCacheConfig) {
          Column() {
            CacheManagementPanel({
              onClose: () => {
                this.showCacheConfig = false;
                this.refreshStatistics();
              }
            })
          }
          .width('90%')
          .height('80%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(16)
          .shadow({ radius: 20, color: 'rgba(0, 0, 0, 0.3)' })
          .position({ x: '5%', y: '10%' })
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 }).combine(TransitionEffect.scale({ x: 0.9, y: 0.9 })))
        }
      }
    }
    .hideTitleBar(false)
    .mode(NavDestinationMode.STANDARD)
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '存储管理' },
        menu: {
          value: [{
            content: {
              label: '帮助',
              icon: $r('sys.symbol.questionmark_circle'),
              isEnabled: true,
              action: () => {
                this.showStorageHelp();
              }
            }
          }]
        }
      }
    })
  }

  private showStorageHelp(): void {
    const helpContent = `# 存储管理帮助

## 功能介绍

存储管理页面帮助您了解和管理应用占用的存储空间。

## 存储类型说明

### 缓存数据
- **内存缓存**: 临时存储在内存中的图片，应用关闭后自动清除
- **磁盘缓存**: 存储在本地的图片缓存，加快重复访问速度
- **永久缓存**: 已下载的漫画章节图片，不会自动清除

### 应用数据
- **漫画数据**: 漫画信息、阅读进度、收藏等
- **电子书数据**: 电子书文件和阅读记录
- **小说数据**: 小说内容和阅读进度
- **封面图片**: 漫画和电子书的封面缓存

## 清理操作

### 清理缓存
点击"清理缓存"可以释放临时缓存空间，不会影响已下载的内容。

### 清理特定类型
点击各存储项的清理按钮，可以单独清理该类型的数据。

## 缓存配置

点击"缓存配置"可以设置：
- 内存缓存大小限制
- 磁盘缓存大小限制
- 自动清理策略

## 注意事项

- 清理永久缓存会删除已下载的漫画章节
- 清理应用数据会删除阅读进度和收藏
- 建议定期清理临时缓存以释放空间`;

    getHelpPanelManagerV2().showInlineHelp('存储管理帮助', helpContent);
  }
}
