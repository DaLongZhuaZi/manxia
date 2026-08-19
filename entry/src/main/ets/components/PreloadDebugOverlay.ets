// 文件路径: entry/src/main/ets/components/PreloadDebugOverlay.ets
// 职责: 显示漫画阅读器的预加载调试信息

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';

const TAG = 'PreloadDebugOverlay';

/**
 * 预加载项状态
 */
export enum PreloadItemStatus {
  PENDING = 'pending',          // 等待加载
  LOADING = 'loading',          // 加载中
  COMPLETED = 'completed',      // 已完成（网络加载）
  MEM_CACHE_HIT = 'mem_cache',  // 内存缓存命中
  DISK_CACHE_HIT = 'disk_cache',// 磁盘缓存命中
  FAILED = 'failed'             // 加载失败
}

/**
 * 预加载项信息
 */
export interface PreloadItemInfo {
  pageIndex: number;        // 页面索引
  pageId: string;           // 页面ID
  status: PreloadItemStatus; // 状态
  url?: string;             // 图片URL（可选）
  startTime?: number;       // 开始时间
  endTime?: number;         // 结束时间
  error?: string;           // 错误信息
}

/**
 * 预加载调试信息
 */
export interface PreloadDebugInfo {
  currentPage: number;      // 当前页码
  totalPages: number;       // 总页数
  preloadRange: number;     // 预加载范围
  queueItems: PreloadItemInfo[]; // 队列中的项
  completedCount: number;   // 已完成数量
  failedCount: number;      // 失败数量
  memCacheHits: number;     // 内存缓存命中
  diskCacheHits: number;    // 磁盘缓存命中
  networkLoads: number;     // 网络加载
}

/**
 * 预加载调试 Overlay 组件
 */
@Component
export struct PreloadDebugOverlay {
  @Link debugInfo: PreloadDebugInfo;
  @Prop visible: boolean;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  
  // 自动刷新定时器
  private refreshTimer: number = -1;
  private readonly REFRESH_INTERVAL: number = 500; // 500ms刷新一次
  
  // 滚动控制器
  private scroller: Scroller = new Scroller();
  
  // 上次的当前页，用于检测页面变化
  private lastCurrentPage: number = -1;
  
  // 强制刷新标记
  @State private forceRefreshKey: number = 0;

  aboutToAppear() {
    // 启动自动刷新定时器
    this.startAutoRefresh();
    logger.debug(TAG, '预加载调试面板已启动自动刷新');
  }
  
  aboutToDisappear() {
    // 清理定时器
    this.stopAutoRefresh();
    logger.debug(TAG, '预加载调试面板已停止自动刷新');
  }
  
  /**
   * 启动自动刷新
   */
  private startAutoRefresh() {
    if (this.refreshTimer !== -1) {
      return;
    }
    
    this.refreshTimer = setInterval(() => {
      // 检查当前页是否变化
      if (this.debugInfo.currentPage !== this.lastCurrentPage) {
        this.lastCurrentPage = this.debugInfo.currentPage;
        // 自动滚动到当前页
        this.scrollToCurrentPage();
      }
      
      // 触发UI刷新（通过修改key）
      this.forceRefreshKey++;
    }, this.REFRESH_INTERVAL);
  }
  
  /**
   * 停止自动刷新
   */
  private stopAutoRefresh() {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }
  
  /**
   * 获取当前页周围的页面列表（显示当前页前后各5页）
   */
  private getVisibleItems(): PreloadItemInfo[] {
    const currentPage = this.debugInfo.currentPage;
    const range = 5; // 前后各显示5页
    
    // 过滤出当前页附近的项
    const visibleItems = this.debugInfo.queueItems.filter(item => {
      const distance = Math.abs(item.pageIndex - currentPage);
      return distance <= range;
    });
    
    // 按页码排序
    visibleItems.sort((a, b) => a.pageIndex - b.pageIndex);
    
    return visibleItems;
  }
  
  /**
   * 滚动到当前页
   */
  private scrollToCurrentPage() {
    try {
      const visibleItems = this.getVisibleItems();
      
      // 查找当前页在可见列表中的索引
      const currentPageIndex = visibleItems.findIndex(
        item => item.pageIndex === this.debugInfo.currentPage
      );
      
      if (currentPageIndex >= 0) {
        // 计算滚动位置（每项高度28px）
        const scrollPosition = currentPageIndex * 28;
        this.scroller.scrollTo({ xOffset: 0, yOffset: scrollPosition, animation: true });
        logger.debug(TAG, `自动滚动到当前页: P${this.debugInfo.currentPage + 1}, 索引=${currentPageIndex}`);
      }
    } catch (error) {
      logger.warn(TAG, `自动滚动失败: ${error}`);
    }
  }

  build() {
    if (this.visible) {
      Column() {
        // 标题栏
        Row() {
          Text('预加载调试信息')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
          
          Blank()
          
          Text(`${this.debugInfo.currentPage + 1}/${this.debugInfo.totalPages}`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor('#AAAAAA')
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor('#CC000000')

        // 统计信息
        Row() {
          this.StatItem('范围', `±${this.debugInfo.preloadRange}`)
          Divider().vertical(true).height(20).color('#444444')
          this.StatItem('完成', `${this.debugInfo.completedCount}`, '#4CAF50')
          Divider().vertical(true).height(20).color('#444444')
          this.StatItem('失败', `${this.debugInfo.failedCount}`, '#F44336')
          Divider().vertical(true).height(20).color('#444444')
          this.StatItem('队列', `${this.debugInfo.queueItems.length}`)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor('#BB000000')
        .justifyContent(FlexAlign.SpaceAround)

        // 缓存统计
        Row() {
          this.CacheStatItem('内存', this.debugInfo.memCacheHits, '#2196F3')
          this.CacheStatItem('磁盘', this.debugInfo.diskCacheHits, '#FF9800')
          this.CacheStatItem('网络', this.debugInfo.networkLoads, '#9C27B0')
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .backgroundColor('#AA000000')
        .justifyContent(FlexAlign.SpaceAround)

        // 队列详情（显示当前页周围的页面，带自动滚动）
        if (this.debugInfo.queueItems.length > 0) {
          Divider().color('#333333')
          
          List({ scroller: this.scroller }) {
            ForEach(this.getVisibleItems(), (item: PreloadItemInfo) => {
              ListItem() {
                this.QueueItem(item, item.pageIndex === this.debugInfo.currentPage)
              }
            }, (item: PreloadItemInfo) => `${item.pageId}_${this.forceRefreshKey}`)
          }
          .width('100%')
          .height(Math.min(this.getVisibleItems().length * 32, 320))
          .backgroundColor('#99000000')
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .borderRadius(8)
      .clip(true)
      .shadow({ radius: 8, color: '#40000000', offsetY: 2 })
    }
  }

  @Builder
  StatItem(label: string, value: string, color: string = '#FFFFFF') {
    Column() {
      Text(label)
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor('#AAAAAA')
      Text(value)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(color)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 2 })
    }
  }

  @Builder
  CacheStatItem(label: string, count: number, color: string) {
    Row({ space: 4 }) {
      Circle({ width: 8, height: 8 })
        .fill(color)
      Text(`${label}: ${count}`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor('#CCCCCC')
    }
  }

  @Builder
  QueueItem(item: PreloadItemInfo, isCurrentPage: boolean = false) {
    Row() {
      // 状态指示器
      Circle({ width: 6, height: 6 })
        .fill(this.getStatusColor(item.status))
        .margin({ right: 6 })

      // 页码
      Text(`P${item.pageIndex + 1}`)
        .fontSize(11)
        .fontFamily(this.appFontFamily)
        .fontColor('#FFFFFF')
        .width(35)

      // 状态文本
      Text(this.getStatusText(item.status))
        .fontSize(10)
        .fontFamily(this.appFontFamily)
        .fontColor(this.getStatusColor(item.status))
        .width(50)

      // 耗时（如果已完成）
      if (item.status === PreloadItemStatus.COMPLETED && item.startTime && item.endTime) {
        Text(`${item.endTime - item.startTime}ms`)
          .fontSize(9)
          .fontFamily(this.appFontFamily)
          .fontColor('#888888')
          .margin({ left: 4 })
      }

      // 错误信息（如果失败）
      if (item.status === PreloadItemStatus.FAILED && item.error) {
        Text(item.error.substring(0, 20))
          .fontSize(9)
          .fontFamily(this.appFontFamily)
          .fontColor('#FF5252')
          .margin({ left: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      Blank()

      // URL缩略（最后20个字符）
      if (item.url) {
        Text(item.url.substring(Math.max(0, item.url.length - 20)))
          .fontSize(9)
          .fontFamily(this.appFontFamily)
          .fontColor('#666666')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .height(28)
    .padding({ left: 12, right: 12 })
    .backgroundColor(isCurrentPage ? '#33FFFFFF' : Color.Transparent)
    .borderRadius(4)
  }

  private getStatusColor(status: PreloadItemStatus): ResourceColor {
    switch (status) {
      case PreloadItemStatus.PENDING:
        return '#FFC107';
      case PreloadItemStatus.LOADING:
        return '#2196F3';
      case PreloadItemStatus.COMPLETED:
        return '#4CAF50';
      case PreloadItemStatus.MEM_CACHE_HIT:
        return '#00BCD4';
      case PreloadItemStatus.DISK_CACHE_HIT:
        return '#FF9800';
      case PreloadItemStatus.FAILED:
        return '#F44336';
      default:
        return '#999999';
    }
  }

  private getStatusText(status: PreloadItemStatus): string {
    switch (status) {
      case PreloadItemStatus.PENDING:
        return '等待';
      case PreloadItemStatus.LOADING:
        return '加载中';
      case PreloadItemStatus.COMPLETED:
        return '网络';
      case PreloadItemStatus.MEM_CACHE_HIT:
        return '内存';
      case PreloadItemStatus.DISK_CACHE_HIT:
        return '磁盘';
      case PreloadItemStatus.FAILED:
        return '失败';
      default:
        return '未知';
    }
  }
}
