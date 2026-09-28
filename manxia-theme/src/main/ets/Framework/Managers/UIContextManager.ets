// 文件路径: src/main/ets/Framework/Managers/UIContextManager.ets
/**
 * UI上下文管理器
 * 负责管理应用中的UI上下文，提供统一的UI操作接口
 * 采用单例模式，支持路由导航、动画执行、弹窗管理等功能
 */

import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

// 屏幕尺寸接口
interface ScreenSize {
  width: number;
  height: number;
}

// 安全区域接口
interface SafeAreaInsets {
  top: number;
  bottom: number;
  left: number;
  right: number;
}


const TAG = 'UIContextManager';

/**
 * 路由选项接口
 */
export interface RouteOptions {
  /** 路由URL */
  url: string;
  /** 路由参数 */
  params?: Record<string, Object>;
  /** 是否替换当前页面 */
  replace?: boolean;
  /** 动画配置 */
  animationConfig?: AnimationConfig;
}

/**
 * 动画配置接口
 */
export interface AnimationConfig {
  /** 动画持续时间（毫秒） */
  duration?: number;
  /** 动画延迟时间（毫秒） */
  delay?: number;
  /** 动画曲线 */
  curve?: Curve;
  /** 动画完成回调 */
  onFinish?: () => void;
}

/**
 * 弹窗配置接口
 */
export interface DialogConfig {
  /** 弹窗标题 */
  title?: string;
  /** 弹窗内容 */
  message: string;
  /** 确认按钮文本 */
  confirmText?: string;
  /** 取消按钮文本 */
  cancelText?: string;
  /** 确认回调 */
  onConfirm?: () => void;
  /** 取消回调 */
  onCancel?: () => void;
}

/**
 * Toast配置接口
 */
export interface ToastConfig {
  /** Toast消息 */
  message: string;
  /** 显示时长（毫秒） */
  duration?: number;
  /** Toast位置 */
  alignment?: Alignment;
}

/**
 * UI上下文管理器类
 */
export class UIContextManager {
  private static instance: UIContextManager | null = null;
  private uiContext: UIContext | null = null;
  private abilityContext: common.UIAbilityContext | null = null;

  /**
   * 私有构造函数
   */
  private constructor() {
    logger.info(TAG, 'UI上下文管理器初始化');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): UIContextManager {
    if (!UIContextManager.instance) {
      UIContextManager.instance = new UIContextManager();
    }
    return UIContextManager.instance;
  }

  /**
   * 设置UI上下文
   */
  public setUIContext(uiContext: UIContext): void {
    this.uiContext = uiContext;
    logger.debug(TAG, 'UI上下文已设置');
  }

  /**
   * 设置Ability上下文
   */
  public setAbilityContext(abilityContext: common.UIAbilityContext): void {
    this.abilityContext = abilityContext;
    logger.debug(TAG, 'Ability上下文已设置');
  }

  /**
   * 获取UI上下文
   */
  public getUIContext(): UIContext | null {
    return this.uiContext;
  }

  /**
   * 获取Ability上下文
   */
  public getAbilityContext(): common.UIAbilityContext | null {
    return this.abilityContext;
  }

  /**
   * 执行动画
   */
  public animateTo(config: AnimationConfig, callback: () => void): void {
    if (!this.uiContext) {
      logger.warn(TAG, 'UI上下文未设置，无法执行动画');
      callback();
      return;
    }

    try {
      const animateOptions: AnimateParam = {
        duration: config.duration || 300,
        delay: config.delay || 0,
        curve: config.curve || Curve.EaseInOut,
        onFinish: config.onFinish
      };

      this.uiContext.animateTo(animateOptions, callback);
      logger.debug(TAG, '动画执行成功');
    } catch (error) {
      logger.error(TAG, '动画执行失败', error);
      callback();
    }
  }

  /**
   * 页面导航
   */
  public navigateTo(options: RouteOptions): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.uiContext) {
        const error = new Error('UI上下文未设置，无法进行页面导航');
        logger.error(TAG, error.message);
        reject(error);
        return;
      }

      try {
        const router = this.uiContext.getRouter();
        
        if (options.replace) {
          router.replaceUrl({
            url: options.url,
            params: options.params
          }).then(() => {
            logger.debug(TAG, `页面替换成功: ${options.url}`);
            resolve();
          }).catch((error: Error) => {
            logger.error(TAG, `页面替换失败: ${options.url}`, error.toString());
            reject(error);
          });
        } else {
          router.pushUrl({
            url: options.url,
            params: options.params
          }).then(() => {
            logger.debug(TAG, `页面跳转成功: ${options.url}`);
            resolve();
          }).catch((error: Error) => {
            logger.error(TAG, `页面跳转失败: ${options.url}`, error.toString());
            reject(error);
          });
        }
      } catch (error) {
        logger.error(TAG, '页面导航异常', error.toString());
        reject(error);
      }
    });
  }

  /**
   * 返回上一页
   */
  public goBack(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.uiContext) {
        const error = new Error('UI上下文未设置，无法返回上一页');
        logger.error(TAG, error.message);
        reject(error);
        return;
      }

      try {
        const router = this.uiContext.getRouter();
        router.back();
        logger.debug(TAG, '返回上一页成功');
        resolve();
      } catch (error) {
        logger.error(TAG, '返回上一页异常', error.toString());
        reject(error);
      }
    });
  }

  /**
   * 显示Toast
   */
  public showToast(config: ToastConfig): void {
    if (!this.uiContext) {
      logger.warn(TAG, 'UI上下文未设置，无法显示Toast');
      return;
    }

    try {
      // 注意：实际的Toast实现可能需要根据HarmonyOS的具体API调整
      logger.info(TAG, `显示Toast: ${config.message}`);
      // 这里应该调用实际的Toast API
    } catch (error) {
      logger.error(TAG, 'Toast显示失败', error.toString());
    }
  }

  /**
   * 显示确认对话框
   */
  public showConfirmDialog(config: DialogConfig): Promise<boolean> {
    return new Promise((resolve) => {
      if (!this.uiContext) {
        logger.warn(TAG, 'UI上下文未设置，无法显示对话框');
        resolve(false);
        return;
      }

      try {
        // 注意：实际的Dialog实现可能需要根据HarmonyOS的具体API调整
        logger.info(TAG, `显示确认对话框: ${config.message}`);
        // 这里应该调用实际的Dialog API
        resolve(true);
      } catch (error) {
        logger.error(TAG, '对话框显示失败', error.toString());
        resolve(false);
      }
    });
  }

  /**
   * 获取屏幕尺寸
   */
  public getScreenSize(): ScreenSize | null {
    if (!this.uiContext) {
      logger.warn(TAG, 'UI上下文未设置，无法获取屏幕尺寸');
      return null;
    }

    try {
      // 注意：实际的屏幕尺寸获取可能需要根据HarmonyOS的具体API调整
      logger.debug(TAG, '获取屏幕尺寸');
      const screenSize: ScreenSize = { width: 0, height: 0 };
      return screenSize;
    } catch (error) {
      logger.error(TAG, '获取屏幕尺寸失败', error.toString());
      return null;
    }
  }

  /**
   * 获取安全区域信息
   */
  public getSafeAreaInsets(): SafeAreaInsets | null {
    if (!this.uiContext) {
      logger.warn(TAG, 'UI上下文未设置，无法获取安全区域信息');
      return null;
    }

    try {
      // 注意：实际的安全区域获取可能需要根据HarmonyOS的具体API调整
      logger.debug(TAG, '获取安全区域信息');
      const safeAreaInsets: SafeAreaInsets = { top: 0, bottom: 0, left: 0, right: 0 };
      return safeAreaInsets;
    } catch (error) {
      logger.error(TAG, '获取安全区域信息失败', error.toString());
      return null;
    }
  }

  /**
   * 退出应用
   */
  public terminateApp(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!this.abilityContext) {
        const error = new Error('Ability上下文未设置，无法退出应用');
        logger.error(TAG, error.message);
        reject(error);
        return;
      }

      try {
        this.abilityContext.terminateSelf().then(() => {
          logger.info(TAG, '应用退出成功');
          resolve();
        }).catch((error: Error) => {
          logger.error(TAG, '应用退出失败', error.toString());
          reject(error);
        });
      } catch (error) {
        logger.error(TAG, '应用退出异常', error.toString());
        reject(error);
      }
    });
  }

  /**
   * 检查UI上下文是否可用
   */
  public isUIContextAvailable(): boolean {
    return this.uiContext !== null;
  }

  /**
   * 检查Ability上下文是否可用
   */
  public isAbilityContextAvailable(): boolean {
    return this.abilityContext !== null;
  }

  /**
   * 清理资源
   */
  public destroy(): void {
    this.uiContext = null;
    this.abilityContext = null;
    UIContextManager.instance = null;
    logger.info(TAG, 'UI上下文管理器已销毁');
  }
}

/**
 * 导出默认实例
 */
export const uiContextManager = UIContextManager.getInstance();