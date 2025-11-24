// 文件路径: entry/src/main/ets/Framework/Managers/DeviceAdaptationManager.ets
// 职责: 设备适配管理器，处理多设备、多屏幕尺寸、多方向的适配逻辑

import { display } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { logger } from '../../Utils/Logger';

const TAG = 'DeviceAdaptationManager';

/**
 * 设备类型枚举
 */
export enum DeviceType {
  PHONE = 'phone',           // 手机
  TABLET = 'tablet',         // 平板
  FOLDABLE = 'foldable',     // 折叠屏
  TWO_IN_ONE = 'two_in_one'  // 2in1设备
}

/**
 * 屏幕方向枚举
 */
export enum ScreenOrientation {
  PORTRAIT = 'portrait',   // 竖屏
  LANDSCAPE = 'landscape'  // 横屏
}

/**
 * 断点枚举 - 基于屏幕宽度
 */
export enum Breakpoint {
  XS = 'xs',  // 超小屏 0-600vp (手机竖屏)
  SM = 'sm',  // 小屏 600-840vp (手机横屏/小平板)
  MD = 'md',  // 中屏 840-1024vp (平板)
  LG = 'lg'   // 大屏 1024+vp (大平板/折叠屏展开/2in1)
}

/**
 * 折叠状态枚举
 */
export enum FoldStatus {
  UNKNOWN = 0,      // 未知状态
  EXPANDED = 1,     // 展开状态
  FOLDED = 2,       // 折叠状态
  HALF_FOLDED = 3   // 半折叠（悬停）状态
}

/**
 * 设备信息接口 
 * 包含设备类型、屏幕方向、断点、屏幕尺寸、密度、是否是平板类、二合一类设备、是否是折叠屏、折叠状态、是否是横屏
 */
export interface DeviceInfo {
  deviceType: DeviceType;
  orientation: ScreenOrientation;
  breakpoint: Breakpoint;
  screenWidth: number;    // vp单位
  screenHeight: number;   // vp单位
  screenWidthPx: number;  // px单位
  screenHeightPx: number; // px单位
  density: number;        // 屏幕密度
  isTablet: boolean;      // 是否是平板类、二合一类设备
  isFoldable: boolean;    // 是否是折叠屏（通过API判断）
  foldStatus: FoldStatus; // 折叠状态
  isLandscape: boolean;   // 是否是横屏
}

/**
 * 设备变化监听器
 */
export type DeviceChangeListener = (deviceInfo: DeviceInfo) => void;

/**
 * 设备信息日志接口（用于日志输出）
 */
interface DeviceInfoLog {
  deviceType: string;
  orientation: string;
  breakpoint: string;
  screenWidth: string;
  screenHeight: string;
  isFoldable: boolean;
  foldStatus: string;
}

/**
 * 设备适配管理器
 * 单例模式，全局管理设备信息和适配逻辑
 */
export class DeviceAdaptationManager {
  private static instance: DeviceAdaptationManager;
  private currentDeviceInfo: DeviceInfo | null = null;
  private listeners: Set<DeviceChangeListener> = new Set();
  private displayObj: display.Display | null = null;
  private isFoldableDevice: boolean = false;
  private isTablet: boolean = false;
  private currentFoldStatus: FoldStatus = FoldStatus.UNKNOWN;

  private constructor() {
    this.initialize();
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): DeviceAdaptationManager {
    if (!DeviceAdaptationManager.instance) {
      DeviceAdaptationManager.instance = new DeviceAdaptationManager();
    }
    return DeviceAdaptationManager.instance;
  }

  /**
   * 初始化
   */
  private initialize(): void {
    try {
      // 获取默认显示对象
      this.displayObj = display.getDefaultDisplaySync();
      
      // 检测是否是折叠屏设备
      this.detectFoldableDevice();

      // 检测是否是平板、二合一类设备
      this.detectTabletDevice();
      
      // 更新设备信息
      this.updateDeviceInfo();
      
      // 监听屏幕变化
      this.registerDisplayListener();
      
      // 如果是折叠屏，监听折叠状态变化
      if (this.isFoldableDevice) {
        this.registerFoldStatusListener();
      }
      
      logger.info(TAG, '设备适配管理器初始化完成');
    } catch (error) {
      logger.error(TAG, '设备适配管理器初始化失败', String(error));
    }
  }
  
  /**
   * 检测是否是折叠屏设备
   */
  private detectFoldableDevice(): void {
    try {
      this.isFoldableDevice = display.isFoldable();
      if (this.isFoldableDevice) {
        this.currentFoldStatus = this.convertFoldStatus(display.getFoldStatus());
        logger.info(TAG, `✅ 检测到折叠屏设备，当前状态: ${this.getFoldStatusName(this.currentFoldStatus)}`);
      } else {
        logger.info(TAG, '📱 非折叠屏设备');
      }
    } catch (error) {
      logger.warn(TAG, '折叠屏检测失败，假定为非折叠屏设备', String(error));
      this.isFoldableDevice = false;
      this.currentFoldStatus = FoldStatus.UNKNOWN;
    }
  }

  /**
   * 检测是否是平板、二合一类设备
   */
  private detectTabletDevice(): void {
    try {
      const deviceTypeStr = deviceInfo.deviceType;
      this.isTablet = deviceTypeStr === 'tablet' || deviceTypeStr === '2in1';
      logger.info(TAG, `✅ 检测到平板类设备: ${this.isTablet}`);
    } catch (error) {
      logger.warn(TAG, '平板类设备检测失败', String(error));
      this.isTablet = false;
    }
  }
  
  /**
   * 转换折叠状态枚举
   */
  private convertFoldStatus(status: display.FoldStatus): FoldStatus {
    switch (status) {
      case display.FoldStatus.FOLD_STATUS_EXPANDED:
        return FoldStatus.EXPANDED;
      case display.FoldStatus.FOLD_STATUS_FOLDED:
        return FoldStatus.FOLDED;
      case display.FoldStatus.FOLD_STATUS_HALF_FOLDED:
        return FoldStatus.HALF_FOLDED;
      default:
        return FoldStatus.UNKNOWN;
    }
  }
  
  /**
   * 获取折叠状态名称
   */
  private getFoldStatusName(status: FoldStatus): string {
    switch (status) {
      case FoldStatus.EXPANDED:
        return '展开';
      case FoldStatus.FOLDED:
        return '折叠';
      case FoldStatus.HALF_FOLDED:
        return '半折叠/悬停';
      default:
        return '未知';
    }
  }
  
  /**
   * 注册折叠状态变化监听器
   */
  private registerFoldStatusListener(): void {
    try {
      display.on('foldStatusChange', (status: display.FoldStatus) => {
        this.currentFoldStatus = this.convertFoldStatus(status);
        logger.info(TAG, `🔄 折叠状态变化: ${this.getFoldStatusName(this.currentFoldStatus)}`);
        // 折叠状态变化时更新设备信息
        this.updateDeviceInfo();
      });
      logger.debug(TAG, '折叠状态监听器注册成功');
    } catch (error) {
      logger.warn(TAG, '注册折叠状态监听器失败', String(error));
    }
  }

  /**
   * 注册屏幕变化监听
   */
  private registerDisplayListener(): void {
    try {
      // 监听屏幕变化（包括旋转、分辨率改变等）
      display.on('change', (displayId: number) => {
        logger.info(TAG, `📱 屏幕发生变化: displayId=${displayId}`);
        this.updateDeviceInfo();
      });
      
      // 尝试监听折叠屏状态变化（如果API可用）
      // 注意：折叠屏API是扩展的、可选的，不是所有设备都支持
      // 使用动态属性访问来避免类型不兼容问题
      try {
        // 检查是否有折叠屏相关的监听方法
        // 由于折叠屏API可能不在标准Display类型中，我们无法直接使用类型断言
        // 因此使用静默处理，如果API不可用则不会影响正常功能
        logger.debug(TAG, '尝试注册折叠屏状态监听（可选功能）');
        // 折叠屏监听功能暂时禁用，等待官方API稳定后再启用
        // 当前通过display.on('change')事件已经可以监听到设备尺寸变化
      } catch (foldError) {
        // 非折叠屏设备或API不可用，静默忽略
        logger.debug(TAG, '折叠屏状态监听不可用（这是正常的，大多数设备不支持）');
      }
    } catch (error) {
      logger.error(TAG, '注册屏幕变化监听失败', String(error));
    }
  }

  /**
   * 更新设备信息
   */
  private updateDeviceInfo(): void {
    try {
      // 重要：每次都重新获取 display 对象，因为旋转后属性会变化
      // 不能复用旧的 displayObj，否则 orientation 等属性不会更新
      this.displayObj = display.getDefaultDisplaySync();

      const widthPx = this.displayObj.width;
      const heightPx = this.displayObj.height;
      const density = this.displayObj.densityDPI / 160; // 计算密度比例

      // 转换为vp单位
      const widthVp = widthPx / density;
      const heightVp = heightPx / density;

      // 判断屏幕方向 - 使用官方API的orientation属性
      // display.Orientation.PORTRAIT: 0
      // display.Orientation.LANDSCAPE: 1
      // display.Orientation.PORTRAIT_INVERTED: 2
      // display.Orientation.LANDSCAPE_INVERTED: 3
      const displayOrientation = this.displayObj.orientation;
      const isLandscape = (displayOrientation === display.Orientation.LANDSCAPE || 
                          displayOrientation === display.Orientation.LANDSCAPE_INVERTED);
      const orientation = isLandscape ? ScreenOrientation.LANDSCAPE : ScreenOrientation.PORTRAIT;
      
      logger.debug(TAG, `🔄 方向检测: displayOrientation=${displayOrientation}, isLandscape=${isLandscape}, 宽=${widthVp.toFixed(2)}, 高=${heightVp.toFixed(2)}`);

      // 判断断点（基于宽度）
      const breakpoint = this.calculateBreakpoint(widthVp);

      // 获取设备类型（使用官方API）
      const deviceType = this.getDeviceTypeFromAPI();

      // 构建设备信息
      const newDeviceInfo: DeviceInfo = {
        deviceType,
        orientation,
        breakpoint,
        screenWidth: widthVp,
        screenHeight: heightVp,
        screenWidthPx: widthPx,
        screenHeightPx: heightPx,
        density,
        isTablet: deviceType === DeviceType.TABLET || deviceType === DeviceType.TWO_IN_ONE,
        isFoldable: this.isFoldableDevice,
        foldStatus: this.currentFoldStatus,
        isLandscape
      };

      // 检查是否有变化
      const hasChanged = this.hasDeviceInfoChanged(newDeviceInfo);
      
      this.currentDeviceInfo = newDeviceInfo;

      const logInfo: DeviceInfoLog = {
        deviceType: newDeviceInfo.deviceType,
        orientation: newDeviceInfo.orientation,
        breakpoint: newDeviceInfo.breakpoint,
        screenWidth: newDeviceInfo.screenWidth.toFixed(2),
        screenHeight: newDeviceInfo.screenHeight.toFixed(2),
        isFoldable: newDeviceInfo.isFoldable,
        foldStatus: this.getFoldStatusName(newDeviceInfo.foldStatus)
      };

      logger.info(TAG, `设备信息: ${JSON.stringify(logInfo)}`);

      // 如果有变化，通知监听器
      if (hasChanged) {
        this.notifyListeners(newDeviceInfo);
      }
    } catch (error) {
      logger.error(TAG, '更新设备信息失败', String(error));
    }
  }
  
  /**
   * 从官方API获取设备类型
   */
  private getDeviceTypeFromAPI(): DeviceType {
    try {
      const systemDeviceType = deviceInfo.deviceType;
      
      // 如果是折叠屏，优先返回折叠屏类型
      if (this.isFoldableDevice) {
        logger.debug(TAG, `设备类型: ${systemDeviceType} (折叠屏)`);
        return DeviceType.FOLDABLE;
      }
      
      // 根据系统返回的设备类型映射
      switch (systemDeviceType) {
        case 'phone':
          return DeviceType.PHONE;
        case 'tablet':
          return DeviceType.TABLET;
        case '2in1':
          return DeviceType.TWO_IN_ONE;
        default:
          // 如果无法识别，根据屏幕尺寸判断
          logger.warn(TAG, `未知设备类型: ${systemDeviceType}，使用屏幕尺寸判断`);
          return this.fallbackDeviceTypeDetection();
      }
    } catch (error) {
      logger.error(TAG, '获取设备类型失败，使用备用方案', String(error));
      return this.fallbackDeviceTypeDetection();
    }
  }
  
  /**
   * 备用设备类型检测（基于屏幕尺寸）
   */
  private fallbackDeviceTypeDetection(): DeviceType {
    if (!this.displayObj) {
      return DeviceType.PHONE;
    }
    
    const density = this.displayObj.densityDPI / 160;
    const widthVp = this.displayObj.width / density;
    
    if (widthVp >= 1024) {
      return DeviceType.TWO_IN_ONE;
    } else if (widthVp >= 600) {
      return DeviceType.TABLET;
    } else {
      return DeviceType.PHONE;
    }
  }

  /**
   * 计算断点
   */
  private calculateBreakpoint(widthVp: number): Breakpoint {
    if (widthVp < 600) {
      return Breakpoint.XS;
    } else if (widthVp < 840) {
      return Breakpoint.SM;
    } else if (widthVp < 1024) {
      return Breakpoint.MD;
    } else {
      return Breakpoint.LG;
    }
  }


  /**
   * 检查设备信息是否有变化
   */
  private hasDeviceInfoChanged(newInfo: DeviceInfo): boolean {
    if (!this.currentDeviceInfo) {
      return true;
    }

    return this.currentDeviceInfo.deviceType !== newInfo.deviceType ||
           this.currentDeviceInfo.orientation !== newInfo.orientation ||
           this.currentDeviceInfo.breakpoint !== newInfo.breakpoint ||
           this.currentDeviceInfo.foldStatus !== newInfo.foldStatus;
  }

  /**
   * 通知所有监听器
   */
  private notifyListeners(deviceInfo: DeviceInfo): void {
    this.listeners.forEach((listener: DeviceChangeListener) => {
      try {
        listener(deviceInfo);
      } catch (error) {
        logger.error(TAG, '监听器回调执行失败', String(error));
      }
    });
  }

  /**
   * 获取当前设备信息
   */
  public getDeviceInfo(): DeviceInfo {
    if (!this.currentDeviceInfo) {
      this.updateDeviceInfo();
    }
    return this.currentDeviceInfo as DeviceInfo;
  }

  /**
   * 添加设备变化监听器
   */
  public addListener(listener: DeviceChangeListener): void {
    this.listeners.add(listener);
    logger.debug(TAG, `添加监听器，当前监听器数量: ${this.listeners.size}`);
  }

  /**
   * 移除设备变化监听器
   */
  public removeListener(listener: DeviceChangeListener): void {
    this.listeners.delete(listener);
    logger.debug(TAG, `移除监听器，当前监听器数量: ${this.listeners.size}`);
  }

  /**
   * 判断是否是手机竖屏
   */
  public isPhonePortrait(): boolean {
    const info = this.getDeviceInfo();
    return info.deviceType === DeviceType.PHONE && info.orientation === ScreenOrientation.PORTRAIT;
  }

  /**
   * 判断是否是平板、二合一或更大的设备
   */
  public isTabletOrLarger(): boolean {
    const info = this.getDeviceInfo();
    return info.isTablet || info.isFoldable;
  }

  /**
   * 判断是否是横屏
   */
  public isLandscape(): boolean {
    return this.getDeviceInfo().isLandscape;
  }

  /**
   * 获取当前断点
   */
  public getCurrentBreakpoint(): Breakpoint {
    return this.getDeviceInfo().breakpoint;
  }

  /**
   * 判断是否大于等于指定断点
   */
  public isBreakpointGreaterOrEqual(targetBreakpoint: Breakpoint): boolean {
    const breakpointOrder: Breakpoint[] = [Breakpoint.XS, Breakpoint.SM, Breakpoint.MD, Breakpoint.LG];
    const currentIndex = breakpointOrder.indexOf(this.getCurrentBreakpoint());
    const targetIndex = breakpointOrder.indexOf(targetBreakpoint);
    return currentIndex >= targetIndex;
  }

  /**
   * 销毁管理器
   */
  public destroy(): void {
    try {
      display.off('change');
      this.listeners.clear();
      this.currentDeviceInfo = null;
      this.displayObj = null;
      logger.info(TAG, '设备适配管理器已销毁');
    } catch (error) {
      logger.error(TAG, '销毁设备适配管理器失败', String(error));
    }
  }
}

