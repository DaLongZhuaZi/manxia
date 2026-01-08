/**
 * 全局生命周期任务监控面板
 * 
 * 功能：
 * 1. 实时显示所有活跃页面的任务状态
 * 2. 显示定时器、Promise、资源、监听器统计
 * 3. 支持查看详细信息
 * 4. 支持紧急清理操作
 * 
 * 文件路径: entry/src/main/ets/components/LifecycleMonitorPanel.ets
 */

import { logger } from '../Utils/Logger';
import { GlobalTaskCoordinator, PageStats, GlobalStats } from '../Framework/Lifecycle';
import { ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';
import { promptAction } from '@kit.ArkUI';

const TAG = 'LifecycleMonitorPanel';
const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct LifecycleMonitorPanel {
  @Prop currentTheme: ThemeType = ThemeType.DARK;
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @State globalStats: GlobalStats = {
    totalPages: 0,
    totalTimers: 0,
    totalPromises: 0,
    totalResources: 0,
    totalListeners: 0
  };
  
  @State pageStatsList: PageStats[] = [];
  @State isExpanded: boolean = false;
  @State autoRefresh: boolean = true;
  @State lastUpdateTime: string = '';
  
  private refreshTimer: number = -1;
  private coordinator = GlobalTaskCoordinator.getInstance();
  
  aboutToAppear() {
    FontAwareHelper.initializeFontAware('LifecycleMonitorPanel', this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    this.refreshData();
    if (this.autoRefresh) {
      this.startAutoRefresh();
    }
  }
  
  aboutToDisappear() {
    this.stopAutoRefresh();
    FontAwareHelper.cleanupFontAware('LifecycleMonitorPanel');
  }
  
  /**
   * 刷新数据
   */
  private refreshData() {
    try {
      // 获取全局统计
      this.globalStats = this.coordinator.getGlobalStats();
      
      // 获取所有页面统计
      const dump = this.coordinator.dumpActiveTasks();
      this.pageStatsList = dump.pages;
      
      // 更新时间
      const now = new Date();
      this.lastUpdateTime = `${now.getHours().toString().padStart(2, '0')}:${now.getMinutes().toString().padStart(2, '0')}:${now.getSeconds().toString().padStart(2, '0')}`;
      
      logger.debug(TAG, `数据已刷新: ${this.globalStats.totalPages} 个页面, ${this.globalStats.totalTimers} 个定时器`);
    } catch (error) {
      logger.error(TAG, `刷新数据失败: ${error}`);
    }
  }
  
  /**
   * 启动自动刷新
   */
  private startAutoRefresh() {
    if (this.refreshTimer !== -1) {
      return;
    }
    
    this.refreshTimer = setInterval(() => {
      this.refreshData();
    }, 1000) as number;
    
    logger.info(TAG, '自动刷新已启动');
  }
  
  /**
   * 停止自动刷新
   */
  private stopAutoRefresh() {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
      logger.info(TAG, '自动刷新已停止');
    }
  }
  
  /**
   * 切换自动刷新
   */
  private toggleAutoRefresh() {
    this.autoRefresh = !this.autoRefresh;
    if (this.autoRefresh) {
      this.startAutoRefresh();
    } else {
      this.stopAutoRefresh();
    }
  }
  
  /**
   * 执行紧急清理
   */
  private async performEmergencyCleanup() {
    try {
      logger.warn(TAG, '用户触发紧急清理');
      await this.coordinator.emergencyCleanup();
      this.refreshData();
    } catch (error) {
      logger.error(TAG, `紧急清理失败: ${error}`);
    }
  }
  
  /**
   * 导出调试信息
   */
  private exportDebugInfo() {
    try {
      const debugInfo = this.coordinator.getDebugInfoString();
      logger.info(TAG, '调试信息已导出到日志');
      console.log(debugInfo);
      promptAction.showToast({ message: '调试信息已导出到日志' });
    } catch (error) {
      logger.error(TAG, `导出调试信息失败: ${error}`);
      promptAction.showToast({ message: '导出失败' });
    }
  }
  
  build() {
    Column() {
      // 标题栏顶部间隔
      Blank()
        .height(TITLE_BAR_HEIGHT_MINI)
      
      // 标题栏
      Row() {
        Text('生命周期监控面板')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .layoutWeight(1)
        
        // 自动刷新开关
        Row() {
          Text(this.autoRefresh ? '自动' : '手动')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
            .margin({ right: 4 })
          
          Toggle({ type: ToggleType.Switch, isOn: this.autoRefresh })
            .width(40)
            .height(20)
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
            .onChange((isOn: boolean) => {
              this.toggleAutoRefresh();
            })
        }
        .margin({ right: 8 })
        
        // 刷新按钮
        Button('刷新')
          .fontSize(12)
          .height(28)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .onClick(() => {
            this.refreshData();
          })
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.currentTheme))
      
      // 全局统计卡片
      Column() {
        Row() {
          Text('全局统计')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
            .layoutWeight(1)
          
          Text(`更新: ${this.lastUpdateTime}`)
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.currentTheme))
        }
        .width('100%')
        .margin({ bottom: 8 })
        
        // 统计数据网格
        Grid() {
          GridItem() {
            this.StatCard('活跃页面', this.globalStats.totalPages, '#4CAF50')
          }
          
          GridItem() {
            this.StatCard('定时器', this.globalStats.totalTimers, '#2196F3')
          }
          
          GridItem() {
            this.StatCard('Promise', this.globalStats.totalPromises, '#FF9800')
          }
          
          GridItem() {
            this.StatCard('资源', this.globalStats.totalResources, '#9C27B0')
          }
          
          GridItem() {
            this.StatCard('监听器', this.globalStats.totalListeners, '#F44336')
          }
          
          GridItem() {
            this.StatCard('总任务', 
              this.globalStats.totalTimers + this.globalStats.totalPromises + this.globalStats.totalResources,
              '#607D8B')
          }
        }
        .columnsTemplate('1fr 1fr 1fr')
        .rowsTemplate('1fr 1fr')
        .columnsGap(8)
        .rowsGap(8)
        .width('100%')
        .height(120)
      }
      .width('100%')
      .padding(12)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.currentTheme))
      .borderRadius(8)
      .margin({ top: 8, left: 12, right: 12 })
      
      // 页面列表
      if (this.pageStatsList.length > 0) {
        Column() {
          Row() {
            Text(`页面详情 (${this.pageStatsList.length})`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Medium)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
              .layoutWeight(1)
            
            Button(this.isExpanded ? '收起' : '展开')
              .fontSize(12)
              .height(24)
              .fontFamily(this.appFontFamily)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.currentTheme))
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
              .onClick(() => {
                this.isExpanded = !this.isExpanded;
              })
          }
          .width('100%')
          .margin({ bottom: 8 })
          
          if (this.isExpanded) {
            List({ space: 8 }) {
              ForEach(this.pageStatsList, (page: PageStats, index: number) => {
                ListItem() {
                  this.PageCard(page, index)
                }
              })
            }
            .width('100%')
            .layoutWeight(1)
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.currentTheme))
        .borderRadius(8)
        .margin({ top: 8, left: 12, right: 12 })
        .layoutWeight(this.isExpanded ? 1 : 0)
      } else {
        Column() {
          Text('暂无活跃页面')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.currentTheme))
            .margin({ top: 20, bottom: 20 })
        }
        .width('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.currentTheme))
        .borderRadius(8)
        .margin({ top: 8, left: 12, right: 12 })
      }
      
      // 操作按钮
      Row() {
        Button('导出日志')
          .fontSize(14)
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .onClick(() => {
            this.exportDebugInfo();
          })
        
        Button('紧急清理')
          .fontSize(14)
          .layoutWeight(1)
          .fontFamily(this.appFontFamily)
          .backgroundColor('#F44336')
          .fontColor('#FFFFFF')
          .margin({ left: 8 })
          .onClick(() => {
            this.performEmergencyCleanup();
          })
      }
      .width('100%')
      .padding(12)
      .margin({ top: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.currentTheme))
  }
  
  /**
   * 统计卡片
   */
  @Builder
  StatCard(label: string, value: number, color: string) {
    Column() {
      Text(value.toString())
        .fontSize(20)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)
      
      Text(label)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
        .margin({ top: 2 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.currentTheme))
    .borderRadius(4)
  }
  
  /**
   * 页面卡片
   */
  @Builder
  PageCard(page: PageStats, index: number) {
    Column() {
      // 页面名称
      Row() {
        Text(`${index + 1}. ${page.pageId}`)
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .layoutWeight(1)
        
        Text(this.formatUptime(page.uptime))
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.currentTheme))
      }
      .width('100%')
      .margin({ bottom: 6 })
      
      // 任务统计
      Row() {
        this.TaskBadge('定时器', page.timerCount, '#2196F3')
        this.TaskBadge('Promise', page.promiseCount, '#FF9800')
        this.TaskBadge('资源', page.resourceCount, '#9C27B0')
        this.TaskBadge('监听器', page.listenerCount, '#F44336')
      }
      .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.currentTheme))
    .borderRadius(6)
  }
  
  /**
   * 任务徽章
   */
  @Builder
  TaskBadge(label: string, count: number, color: string) {
    Row() {
      Text(label)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
        .margin({ right: 2 })
      
      Text(count.toString())
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor(color)
        .fontWeight(FontWeight.Bold)
    }
    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.currentTheme))
    .borderRadius(10)
    .margin({ right: 4 })
  }
  
  /**
   * 格式化运行时间
   */
  private formatUptime(ms: number): string {
    const seconds = Math.floor(ms / 1000);
    if (seconds < 60) {
      return `${seconds}秒`;
    }
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) {
      return `${minutes}分${seconds % 60}秒`;
    }
    const hours = Math.floor(minutes / 60);
    return `${hours}时${minutes % 60}分`;
  }
}
