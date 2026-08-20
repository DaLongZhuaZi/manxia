// 文件路径: entry/src/main/ets/Framework/Utils/ResponsiveLayout.ets
// 职责: 响应式布局工具类，提供基于断点的布局参数

import { DeviceAdaptationManager, Breakpoint, DeviceInfo } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'ResponsiveLayout';

/**
 * 响应式布局参数（名义类型）
 */
export class ResponsiveLayoutParams {
  public gridColumns: number;
  public gridGap: number;
  public contentPadding: number;
  public maxCardWidth: number;
  public useSidebarLayout: boolean;
  public sidebarWidth: number;
  public fontScale: number;

  constructor(gridColumns: number,
              gridGap: number,
              contentPadding: number,
              maxCardWidth: number,
              useSidebarLayout: boolean,
              sidebarWidth: number,
              fontScale: number) {
    this.gridColumns = gridColumns;
    this.gridGap = gridGap;
    this.contentPadding = contentPadding;
    this.maxCardWidth = maxCardWidth;
    this.useSidebarLayout = useSidebarLayout;
    this.sidebarWidth = sidebarWidth;
    this.fontScale = fontScale;
  }
}

/**
 * 漫画卡片尺寸（名义类型）
 */
export class MangaCardSize {
  public width: number;
  public height: number;

  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }
}

/**
 * 响应式布局工具类
 */
export class ResponsiveLayoutHelper {
  private static deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();

  /**
   * 获取当前布局参数
   */
  public static getLayoutParams(): ResponsiveLayoutParams {
    const deviceInfo = ResponsiveLayoutHelper.deviceManager.getDeviceInfo();
    const breakpoint = deviceInfo.breakpoint;

    switch (breakpoint) {
      case Breakpoint.XS:
        return ResponsiveLayoutHelper.getXSLayoutParams();
      case Breakpoint.SM:
        return ResponsiveLayoutHelper.getSMLayoutParams();
      case Breakpoint.MD:
        return ResponsiveLayoutHelper.getMDLayoutParams();
      case Breakpoint.LG:
        return ResponsiveLayoutHelper.getLGLayoutParams();
      default:
        return ResponsiveLayoutHelper.getXSLayoutParams();
    }
  }

  public static getLayoutParamsForBreakpoint(breakpoint: Breakpoint): ResponsiveLayoutParams {
    switch (breakpoint) {
      case Breakpoint.XS:
        return ResponsiveLayoutHelper.getXSLayoutParams();
      case Breakpoint.SM:
        return ResponsiveLayoutHelper.getSMLayoutParams();
      case Breakpoint.MD:
        return ResponsiveLayoutHelper.getMDLayoutParams();
      case Breakpoint.LG:
        return ResponsiveLayoutHelper.getLGLayoutParams();
      default:
        return ResponsiveLayoutHelper.getXSLayoutParams();
    }
  }

  /**
   * XS断点布局参数（手机竖屏）
   */
  private static getXSLayoutParams(): ResponsiveLayoutParams {
    return new ResponsiveLayoutParams(3, 12, 16, 600, false, 0, 1.0);
  }

  /**
   * SM断点布局参数（手机横屏/小平板）
   */
  private static getSMLayoutParams(): ResponsiveLayoutParams {
    return new ResponsiveLayoutParams(4, 16, 20, 700, false, 0, 1.0);
  }

  /**
   * MD断点布局参数（平板）
   */
  private static getMDLayoutParams(): ResponsiveLayoutParams {
    return new ResponsiveLayoutParams(5, 20, 24, 800, true, 240, 1.1);
  }

  /**
   * LG断点布局参数（大平板/折叠屏展开）
   */
  private static getLGLayoutParams(): ResponsiveLayoutParams {
    return new ResponsiveLayoutParams(6, 24, 32, 1000, true, 280, 1.15);
  }

  /**
   * 获取网格列数
   */
  public static getGridColumns(): number {
    return ResponsiveLayoutHelper.getLayoutParams().gridColumns;
  }

  /**
   * 获取网格间距
   */
  public static getGridGap(): number {
    return ResponsiveLayoutHelper.getLayoutParams().gridGap;
  }

  /**
   * 获取内容区域内边距
   */
  public static getContentPadding(): number {
    return ResponsiveLayoutHelper.getLayoutParams().contentPadding;
  }

  /**
   * 是否使用分栏布局
   */
  public static useSidebarLayout(): boolean {
    return ResponsiveLayoutHelper.getLayoutParams().useSidebarLayout;
  }

  /**
   * 获取侧边栏宽度
   */
  public static getSidebarWidth(): number {
    return ResponsiveLayoutHelper.getLayoutParams().sidebarWidth;
  }

  /**
   * 获取字体缩放比例
   */
  public static getFontScale(): number {
    return ResponsiveLayoutHelper.getLayoutParams().fontScale;
  }

  /**
   * 根据基础字号计算响应式字号
   */
  public static getResponsiveFontSize(baseFontSize: number): number {
    return Math.round(baseFontSize * ResponsiveLayoutHelper.getFontScale());
  }

  /**
   * 获取列表布局模板
   * 返回Grid的columnsTemplate字符串
   */
  public static getGridColumnsTemplate(): string {
    const columns: number = ResponsiveLayoutHelper.getGridColumns();
    const template: string[] = [];
    let i: number = 0;
    while (i < columns) {
      template.push('1fr');
      i = i + 1;
    }
    return template.join(' ');
  }

  /**
   * 判断是否应该使用双页模式（用于漫画阅读器）
   */
  public static shouldUseDoublePage(): boolean {
    const deviceInfo = ResponsiveLayoutHelper.deviceManager.getDeviceInfo();
    // 横屏且屏幕宽度大于800vp时使用双页模式
    return deviceInfo.isLandscape && deviceInfo.screenWidth > 800;
  }

  /**
   * 获取最大内容宽度（用于限制超宽屏幕的内容宽度）
   */
  public static getMaxContentWidth(): number {
    return ResponsiveLayoutHelper.getLayoutParams().maxCardWidth;
  }

  /**
   * 判断是否是紧凑布局（手机竖屏）
   */
  public static isCompactLayout(): boolean {
    return ResponsiveLayoutHelper.deviceManager.getCurrentBreakpoint() === Breakpoint.XS;
  }

  /**
   * 判断是否是中等布局（手机横屏/小平板）
   */
  public static isMediumLayout(): boolean {
    return ResponsiveLayoutHelper.deviceManager.getCurrentBreakpoint() === Breakpoint.SM;
  }

  /**
   * 判断是否是扩展布局（平板及以上）
   */
  public static isExpandedLayout(): boolean {
    const breakpoint = ResponsiveLayoutHelper.deviceManager.getCurrentBreakpoint();
    return breakpoint === Breakpoint.MD || breakpoint === Breakpoint.LG;
  }

  /**
   * 获取漫画卡片尺寸
   */
  public static getMangaCardSize(): MangaCardSize {
    const breakpoint = ResponsiveLayoutHelper.deviceManager.getCurrentBreakpoint();
    
    switch (breakpoint) {
      case Breakpoint.XS:
        return new MangaCardSize(100, 140);
      case Breakpoint.SM:
        return new MangaCardSize(110, 154);
      case Breakpoint.MD:
        return new MangaCardSize(120, 168);
      case Breakpoint.LG:
        return new MangaCardSize(130, 182);
      default:
        return new MangaCardSize(100, 140);
    }
  }

  /**
   * 获取底部导航栏高度
   */
  public static getBottomTabBarHeight(): number {
    // 平板设备使用更高的底部栏
    return ResponsiveLayoutHelper.isExpandedLayout() ? 64 : 56;
  }

  /**
   * 获取标题栏高度
   */
  public static getTitleBarHeight(): number {
    return ResponsiveLayoutHelper.isExpandedLayout() ? 64 : 56;
  }

  /**
   * 日志输出当前布局参数
   */
  public static logCurrentLayout(): void {
    const params = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = ResponsiveLayoutHelper.deviceManager.getDeviceInfo();
    
    logger.info(TAG, `当前布局参数: ${JSON.stringify({
      breakpoint: deviceInfo.breakpoint,
      orientation: deviceInfo.orientation,
      deviceType: deviceInfo.deviceType,
      gridColumns: params.gridColumns,
      useSidebarLayout: params.useSidebarLayout,
      sidebarWidth: params.sidebarWidth
    })}`);
  }
}

