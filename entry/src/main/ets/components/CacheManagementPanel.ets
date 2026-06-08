// 文件路径: src/main/ets/components/CacheManagementPanel.ets
/**
 * 缓存管理面板组件
 * 提供缓存配置、磁盘缓存统计、智能预加载策略监控
 * 使用标签页样式，支持主题切换
 */

import { logger } from '../Utils/Logger';
import { CacheConfigManager, CacheConfig, MemoryCacheConfig, DiskCacheConfig, PreloadConfig } from '../Framework/Cache/CacheConfigManager';
import { SmartPreloadStrategy, PreloadStats } from '../Framework/Cache/SmartPreloadStrategy';
import { DiskCacheManager } from '../Framework/Cache/DiskCacheManager';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';

const TAG = 'CacheManagementPanel';

interface DiskCacheStatsInfo {
  count: number;
  totalSize: number;
  usagePercent: number;
}

interface ThemeState {
  currentTheme: ThemeType;
}

enum CacheTab {
  STATISTICS = 'STATISTICS',
  CONFIG = 'CONFIG',
  PRELOAD = 'PRELOAD'
}

@ComponentV2
export struct CacheManagementPanel {
  @Param @Require onClose: () => void;
  @Local cacheConfig: CacheConfig | null = null;
  @Local preloadStats: PreloadStats | null = null;
  @Local diskCacheStats: DiskCacheStatsInfo | null = null;
  @Local isLoading: boolean = true;
  @Local currentTab: CacheTab = CacheTab.STATISTICS;
  @Local themeState: ThemeState = { currentTheme: ThemeType.DARK };
  @Local fontState: FontAwareState = new FontAwareState();
  @Local appFontFamily: string = 'HarmonyOS Sans';
  
  private cacheConfigManager: CacheConfigManager = CacheConfigManager.getInstance();
  private smartPreloadStrategy: SmartPreloadStrategy = SmartPreloadStrategy.getInstance();
  private diskCacheManager: DiskCacheManager = DiskCacheManager.getInstance();
  private themeManager: ThemeManager = ThemeManager.getInstance();

  aboutToAppear(): void {
    // 初始化主题
    this.themeManager.getActualTheme().then((theme: ThemeType) => {
      this.themeState.currentTheme = theme;
    });
    // 监听主题变化
    this.themeManager.onThemeChange((theme: ThemeType) => {
      this.themeState = { currentTheme: theme };
    });
    FontAwareHelper.initializeFontAware('CacheManagementPanel', this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
      this.appFontFamily = newState.appFontFamily;
    });
    this.loadAllData();
  }

  /**
   * 加载所有数据
   */
  private async loadAllData(): Promise<void> {
    try {
      this.isLoading = true;
      
      // 加载缓存配置
      this.cacheConfig = this.cacheConfigManager.getConfig();
      
      // 加载预加载统计
      this.preloadStats = this.smartPreloadStrategy.getStats();
      
      // 加载磁盘缓存统计
      const stats = this.diskCacheManager.getStats();
      this.diskCacheStats = {
        count: stats.count,
        totalSize: stats.totalSize,
        usagePercent: stats.usagePercent
      };
      
      logger.info(TAG, '数据加载完成');
    } catch (error) {
      logger.error(TAG, `加载数据失败: ${String(error)}`);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 刷新数据
   */
  private async refreshData(): Promise<void> {
    await this.loadAllData();
  }

  /**
   * 更新内存缓存配置
   */
  private async updateMemoryCacheSize(value: number): Promise<void> {
    try {
      const currentConfig = this.cacheConfigManager.getMemoryCacheConfig();
      const newConfig: MemoryCacheConfig = {
        maxCount: currentConfig.maxCount,
        maxSize: value * 1024 * 1024,
        enabled: currentConfig.enabled
      };
      await this.cacheConfigManager.updateMemoryCacheConfig(newConfig);
      this.cacheConfig = this.cacheConfigManager.getConfig();
      logger.info(TAG, `内存缓存大小已更新: ${value}MB`);
    } catch (error) {
      logger.error(TAG, `更新失败: ${String(error)}`);
    }
  }

  /**
   * 更新磁盘缓存配置
   */
  private async updateDiskCacheSize(value: number): Promise<void> {
    try {
      const currentConfig = this.cacheConfigManager.getDiskCacheConfig();
      const newConfig: DiskCacheConfig = {
        maxSize: value * 1024 * 1024,
        maxAge: currentConfig.maxAge,
        enabled: currentConfig.enabled,
        compressionQuality: currentConfig.compressionQuality
      };
      await this.cacheConfigManager.updateDiskCacheConfig(newConfig);
      this.cacheConfig = this.cacheConfigManager.getConfig();
      logger.info(TAG, `磁盘缓存大小已更新: ${value}MB`);
    } catch (error) {
      logger.error(TAG, `更新失败: ${String(error)}`);
    }
  }

  /**
   * 更新预加载范围
   */
  private async updatePreloadRange(normal: number, webtoon: number): Promise<void> {
    try {
      const currentConfig = this.cacheConfigManager.getPreloadConfig();
      const newConfig: PreloadConfig = {
        enabled: currentConfig.enabled,
        rangeNormal: normal,
        rangeWebtoon: webtoon,
        maxConcurrent: currentConfig.maxConcurrent
      };
      await this.cacheConfigManager.updatePreloadConfig(newConfig);
      this.cacheConfig = this.cacheConfigManager.getConfig();
      logger.info(TAG, `预加载范围已更新: 普通=${normal}, 条漫=${webtoon}`);
    } catch (error) {
      logger.error(TAG, `更新失败: ${String(error)}`);
    }
  }

  /**
   * 切换预加载开关
   */
  private async togglePreload(enabled: boolean): Promise<void> {
    try {
      const currentConfig = this.cacheConfigManager.getPreloadConfig();
      const newConfig: PreloadConfig = {
        enabled: enabled,
        rangeNormal: currentConfig.rangeNormal,
        rangeWebtoon: currentConfig.rangeWebtoon,
        maxConcurrent: currentConfig.maxConcurrent
      };
      await this.cacheConfigManager.updatePreloadConfig(newConfig);
      this.cacheConfig = this.cacheConfigManager.getConfig();
      logger.info(TAG, `预加载已${enabled ? '启用' : '禁用'}`);
    } catch (error) {
      logger.error(TAG, `更新失败: ${String(error)}`);
    }
  }

  /**
   * 重置配置
   */
  private async resetConfig(): Promise<void> {
    try {
      await this.cacheConfigManager.resetToDefault();
      this.cacheConfig = this.cacheConfigManager.getConfig();
      logger.info(TAG, '配置已重置为默认值');
    } catch (error) {
      logger.error(TAG, `重置失败: ${String(error)}`);
    }
  }

  /**
   * 清空磁盘缓存
   */
  private async clearDiskCache(): Promise<void> {
    try {
      await this.diskCacheManager.clear();
      await this.refreshData();
      logger.info(TAG, '磁盘缓存已清空');
    } catch (error) {
      logger.error(TAG, `清空失败: ${String(error)}`);
    }
  }

  /**
   * 重置预加载统计
   */
  private async resetPreloadStats(): Promise<void> {
    try {
      this.smartPreloadStrategy.resetStats();
      this.preloadStats = this.smartPreloadStrategy.getStats();
      logger.info(TAG, '预加载统计已重置');
    } catch (error) {
      logger.error(TAG, `重置失败: ${String(error)}`);
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('缓存管理')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text('刷新')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
        }
        .height(32)
        .padding({ left: 12, right: 12 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(16)
        .onClick(() => this.refreshData())
        
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
        }
        .width(32)
        .height(32)
        .margin({ left: 8 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(16)
        .stateStyles({
          pressed: {
            .scale({ x: 0.9, y: 0.9 })
            .opacity(0.7)
          }
        })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
          if (this.onClose) {
            this.onClose();
          }
        })
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      
      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
      
      // 标签页导航
      Row({ space: 0 }) {
        this.buildTabButtonWithSymbol($r('sys.symbol.histogram_fill'), '统计', CacheTab.STATISTICS)
        this.buildTabButtonWithSymbol($r('sys.symbol.gearshape'), '配置', CacheTab.CONFIG)
        this.buildTabButtonWithSymbol($r('sys.symbol.bolt'), '预加载', CacheTab.PRELOAD)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      
      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

      if (this.isLoading) {
        Column({ space: 20 }) {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          Text('加载中...')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
      } else {
        Scroll() {
          Column({ space: 0 }) {
            if (this.currentTab === CacheTab.STATISTICS) {
              this.buildStatisticsTab()
            } else if (this.currentTab === CacheTab.CONFIG) {
              this.buildConfigTab()
            } else if (this.currentTab === CacheTab.PRELOAD) {
              this.buildPreloadTab()
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
  }
  
  @Builder
  buildTabButtonWithSymbol(iconRes: Resource, label: string, tab: CacheTab) {
    Column({ space: 4 }) {
      SymbolGlyph(iconRes)
        .fontSize(20)
        .fontColor([this.currentTab === tab ? 
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
          ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.currentTab === tab ?
          ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) : 
          ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .fontWeight(this.currentTab === tab ? FontWeight.Medium : FontWeight.Normal)
    }
    .layoutWeight(1)
    .padding({ top: 8, bottom: 8 })
    .backgroundColor(this.currentTab === tab ? 
      ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme) : 
      Color.Transparent)
    .borderRadius(8)
    .animation({ duration: 200, curve: Curve.EaseInOut })
    .stateStyles({
      pressed: {
        .scale({ x: 0.95, y: 0.95 })
        .opacity(0.8)
      }
    })
    .onClick(() => {
      this.currentTab = tab;
    })
  }

  @Builder
  buildStatisticsTab() {
    Column({ space: 16 }) {
      this.buildDiskCacheStats()
    }
    .width('100%')
    .padding(16)
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }).combine(TransitionEffect.translate({ x: 10 })))
  }
  
  @Builder
  buildConfigTab() {
    Column({ space: 16 }) {
      this.buildCacheConfig()
    }
    .width('100%')
    .padding(16)
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }).combine(TransitionEffect.translate({ x: 10 })))
  }
  
  @Builder
  buildPreloadTab() {
    Column({ space: 16 }) {
      this.buildPreloadStrategy()
    }
    .width('100%')
    .padding(16)
    .transition(TransitionEffect.OPACITY.animation({ duration: 200 }).combine(TransitionEffect.translate({ x: 10 })))
  }
  
  @Builder
  buildDiskCacheStats() {
    Column({ space: 12 }) {
      Row() {
        Text('磁盘缓存统计')
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(14)
              .fontColor([Color.White])
            Text('清空')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(Color.White)
          }
        }
        .height(28)
        .padding({ left: 12, right: 12 })
        .backgroundColor('#FF5252')
        .borderRadius(14)
        .stateStyles({
          pressed: {
            .scale({ x: 0.95, y: 0.95 })
            .opacity(0.8)
          }
        })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => {
            this.getUIContext().showAlertDialog({
              title: '确认清空',
              message: '确定要清空所有磁盘缓存吗？',
              primaryButton: {
                value: '取消',
                action: () => {}
              },
              secondaryButton: {
                value: '确认',
                action: () => this.clearDiskCache()
              }
            });
          })
      }
      .width('100%')

      if (this.diskCacheStats) {
        Column({ space: 10 }) {
          Row() {
            Text('缓存数量')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Blank()
            Text(`${this.diskCacheStats.count} 张`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
          .width('100%')

          Row() {
            Text('总大小')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Blank()
            Text(`${(this.diskCacheStats.totalSize / 1024 / 1024).toFixed(2)} MB`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          .width('100%')

          Row() {
            Text('使用率')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Blank()
            Text(`${this.diskCacheStats.usagePercent.toFixed(1)}%`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.diskCacheStats.usagePercent > 80 ? '#FF5252' : 
                ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
          .width('100%')

          Progress({ value: this.diskCacheStats.usagePercent, total: 100 })
            .width('100%')
            .height(6)
            .color(this.diskCacheStats.usagePercent > 80 ? '#FF5252' : 
              ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  @Builder
  buildCacheConfig() {
    Column({ space: 16 }) {
      Text('缓存配置')
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      if (this.cacheConfig) {
        Column({ space: 20 }) {
          // 内存缓存
          Column({ space: 10 }) {
            Row() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.memory_module'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                Text('内存缓存大小')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              }
              Blank()
              Text(`${(this.cacheConfig.memoryCache.maxSize / 1024 / 1024).toFixed(0)} MB`)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .width('100%')

            Slider({
              value: this.cacheConfig.memoryCache.maxSize / 1024 / 1024,
              min: 10,
              max: 200,
              step: 10
            })
              .width('100%')
              .onChange((value: number) => {
                this.updateMemoryCacheSize(value);
              })
          }

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          
          // 磁盘缓存
          Column({ space: 10 }) {
            Row() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.externaldrive'))
                  .fontSize(16)
                  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
                Text('磁盘缓存大小')
                  .fontSize(14)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              }
              Blank()
              Text(`${(this.cacheConfig.diskCache.maxSize / 1024 / 1024).toFixed(0)} MB`)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .width('100%')

            Slider({
              value: this.cacheConfig.diskCache.maxSize / 1024 / 1024,
              min: 100,
              max: 2000,
              step: 100
            })
              .width('100%')
              .onChange((value: number) => {
                this.updateDiskCacheSize(value);
              })
          }

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          
          // 预加载开关
          Row() {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.bolt'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text('启用预加载')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.cacheConfig.preload.enabled })
              .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              .onChange((isOn: boolean) => {
                this.togglePreload(isOn);
              })
          }
          .width('100%')

          // 预加载范围
          if (this.cacheConfig.preload.enabled) {
            Column({ space: 12 }) {
              Row() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.book'))
                    .fontSize(14)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                  Text('普通模式预加载')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                }
                Blank()
                Text(`${this.cacheConfig.preload.rangeNormal} 页`)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              }
              .width('100%')

              Slider({
                value: this.cacheConfig.preload.rangeNormal,
                min: 0,
                max: 10,
                step: 1
              })
                .width('100%')
                .onChange((value: number) => {
                  this.updatePreloadRange(value, this.cacheConfig!.preload.rangeWebtoon);
                })

              Row() {
                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.scroll_vertical'))
                    .fontSize(14)
                    .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
                  Text('条漫模式预加载')
                    .fontSize(13)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                }
                Blank()
                Text(`${this.cacheConfig.preload.rangeWebtoon} 页`)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
              }
              .width('100%')

              Slider({
                value: this.cacheConfig.preload.rangeWebtoon,
                min: 0,
                max: 10,
                step: 1
              })
                .width('100%')
                .onChange((value: number) => {
                  this.updatePreloadRange(this.cacheConfig!.preload.rangeNormal, value);
                })
            }
          }

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))
          
          // 重置按钮
          Button({ type: ButtonType.Normal }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text('重置为默认配置')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
          }
          .width('100%')
          .height(40)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
          .borderRadius(8)
          .stateStyles({
            pressed: {
              .scale({ x: 0.98, y: 0.98 })
              .opacity(0.8)
            }
          })
          .animation({ duration: 150, curve: Curve.EaseOut })
          .onClick(() => {
              this.getUIContext().showAlertDialog({
                title: '确认重置',
                message: '确定要重置为默认配置吗？',
                primaryButton: {
                  value: '取消',
                  action: () => {}
                },
                secondaryButton: {
                  value: '确认',
                  action: () => this.resetConfig()
                }
              });
            })
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }

  @Builder
  buildPreloadStrategy() {
    Column({ space: 12 }) {
      Row() {
        Text('智能预加载策略')
          .fontSize(15)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        
        Blank()
        
        Button({ type: ButtonType.Normal }) {
          Row({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
              .fontSize(14)
              .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            Text('重置')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          }
        }
        .height(28)
        .padding({ left: 12, right: 12 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
        .borderRadius(14)
        .stateStyles({
          pressed: {
            .scale({ x: 0.95, y: 0.95 })
            .opacity(0.8)
          }
        })
        .animation({ duration: 150, curve: Curve.EaseOut })
        .onClick(() => this.resetPreloadStats())
      }
      .width('100%')

      if (this.preloadStats) {
        Column({ space: 16 }) {
          // 阅读统计
          Column({ space: 10 }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.service_management'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text('阅读统计')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }

            Row() {
              Text('总页数')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              Blank()
              Text(`${this.preloadStats.totalPages}`)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
            .width('100%')

            Row() {
              Text('向前翻页')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
              Blank()
              Text(`${this.preloadStats.forwardPages} (${(this.preloadStats.forwardRatio * 100).toFixed(1)}%)`)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
            }
            .width('100%')

            Row() {
              Text('向后翻页')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
              Blank()
              Text(`${this.preloadStats.backwardPages}`)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
            }
            .width('100%')

            Row() {
              Text('平均停留时间')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
              Blank()
              Text(`${(this.preloadStats.avgPageDuration / 1000).toFixed(1)}秒`)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
            }
            .width('100%')

            Row() {
              Text('阅读速度')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
              Blank()
              Text(this.preloadStats.readingSpeed === 'fast' ? '快速' : 
                   this.preloadStats.readingSpeed === 'slow' ? '慢速' : '正常')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')

            Row() {
              Text('网络类型')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
              Blank()
              Text(this.preloadStats.networkType)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
            }
            .width('100%')
          }

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.themeState.currentTheme))

          // 当前策略
          Column({ space: 10 }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.scope'))
                .fontSize(16)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
              Text('当前策略')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }

            Row() {
              Text('向前预加载')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              Blank()
              Text(`${this.preloadStats.currentStrategy.forwardRange} 页`)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .width('100%')

            Row() {
              Text('向后预加载')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
              Blank()
              Text(`${this.preloadStats.currentStrategy.backwardRange} 页`)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.Blue)
            }
            .width('100%')

            Row() {
              Text('优先级')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
              Blank()
              Text(`${this.preloadStats.currentStrategy.priority}/10`)
                .fontSize(13)
                .fontFamily(this.appFontFamily)
            }
            .width('100%')

            Row() {
              Text('策略原因')
                .fontSize(13)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              Blank()
              Text(this.preloadStats.currentStrategy.reason)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(2)
                .textAlign(TextAlign.End)
            }
            .width('100%')
          }
        }
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
  }
}
