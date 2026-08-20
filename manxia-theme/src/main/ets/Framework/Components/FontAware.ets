// 文件路径: entry/src/main/ets/Framework/Components/FontAware.ets
/**
 * 字体感知组件辅助类
 * 提供全局字体设置的接管功能，类似ThemeAwareHelper
 * 支持字体、字号倍率的全局应用
 */

import { getFontManager, FontScene, FontType } from '../Managers/FontManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'FontAware';

/**
 * 字体设置应用模式
 */
export enum FontApplyMode {
  FONT_ONLY = 'font_only',           // 只应用字体
  SCALE_ONLY = 'scale_only',         // 只应用倍率
  FONT_AND_SCALE = 'font_and_scale'  // 同时应用字体和倍率
}

/**
 * 字体感知状态类
 */
@Observed
export class FontAwareState {
  /** 当前APP字体族 */
  public appFontFamily: string = 'HarmonyOS Sans';
  /** 当前APP字号 */
  public appFontSize: number = 16;
  /** 当前小说字体族 */
  public novelFontFamily: string = 'HarmonyOS Sans';
  /** 当前小说字号 */
  public novelFontSize: number = 18;
  /** 当前小说行高 */
  public novelLineHeight: number = 1.8;
  /** 当前电子书字体族 */
  public ebookFontFamily: string = 'HarmonyOS Sans';
  /** 当前电子书字号 */
  public ebookFontSize: number = 18;
  /** 当前电子书行高 */
  public ebookLineHeight: number = 1.8;
  /** 字号缩放倍率 */
  public fontScale: number = 1.0;

  constructor() {
    this.syncFromFontManager();
  }

  /**
   * 从FontManager同步设置
   */
  public syncFromFontManager(): void {
    const fontManager = getFontManager();
    const settings = fontManager.getSettings();
    
    this.appFontFamily = fontManager.getFontFamily(FontScene.APP_UI);
    this.appFontSize = settings.appFontSize;
    this.novelFontFamily = fontManager.getFontFamily(FontScene.NOVEL);
    this.novelFontSize = settings.novelFontSize;
    this.novelLineHeight = settings.novelLineHeight;
    this.ebookFontFamily = fontManager.getFontFamily(FontScene.EBOOK);
    this.ebookFontSize = settings.ebookFontSize;
    this.ebookLineHeight = settings.ebookLineHeight;
  }

  /**
   * 获取缩放后的字号
   */
  public getScaledFontSize(baseFontSize: number): number {
    return Math.round(baseFontSize * this.fontScale);
  }
}

/**
 * 字体变化回调类型
 */
type FontChangeCallback = (state: FontAwareState) => void;

/**
 * 字体感知辅助类
 */
export class FontAwareHelper {
  private static fontChangeCallbacks: Map<string, FontChangeCallback> = new Map<string, FontChangeCallback>();
  private static globalState: FontAwareState = new FontAwareState();
  private static isInitialized: boolean = false;

  /**
   * 初始化全局字体感知
   */
  public static initialize(): void {
    if (FontAwareHelper.isInitialized) return;
    
    const fontManager = getFontManager();
    
    // 监听字体变化
    fontManager.addFontChangeListener('FontAwareHelper', (scene: FontScene, fontFamily: string) => {
      FontAwareHelper.globalState.syncFromFontManager();
      FontAwareHelper.notifyAllCallbacks();
    });
    
    FontAwareHelper.isInitialized = true;
    logger.info(TAG, '字体感知辅助类初始化完成');
  }

  /**
   * 初始化组件的字体感知功能
   */
  public static initializeFontAware(
    componentId: string,
    state: FontAwareState,
    callback?: FontChangeCallback
  ): void {
    // 确保全局初始化
    FontAwareHelper.initialize();
    
    // 同步当前设置
    state.syncFromFontManager();
    
    // 注册回调
    if (callback) {
      const wrappedCallback: FontChangeCallback = (newState: FontAwareState) => {
        state.syncFromFontManager();
        callback(newState);
      };
      FontAwareHelper.fontChangeCallbacks.set(componentId, wrappedCallback);
    } else {
      FontAwareHelper.fontChangeCallbacks.set(componentId, (newState: FontAwareState) => {
        state.syncFromFontManager();
      });
    }
    
    logger.debug(TAG, `组件 ${componentId} 字体感知功能已初始化`);
  }

  /**
   * 清理组件的字体感知功能
   */
  public static cleanupFontAware(componentId: string): void {
    FontAwareHelper.fontChangeCallbacks.delete(componentId);
    logger.debug(TAG, `组件 ${componentId} 字体感知功能已清理`);
  }

  /**
   * 通知所有回调
   */
  private static notifyAllCallbacks(): void {
    FontAwareHelper.fontChangeCallbacks.forEach((callback) => {
      try {
        callback(FontAwareHelper.globalState);
      } catch (error) {
        logger.error(TAG, `字体变化回调执行失败: ${String(error)}`);
      }
    });
  }

  /**
   * 获取全局字体状态
   */
  public static getGlobalState(): FontAwareState {
    return FontAwareHelper.globalState;
  }

  // ==================== 字体应用接口 ====================

  /**
   * 获取APP界面字体族
   */
  public static getAppFontFamily(): string {
    return FontAwareHelper.globalState.appFontFamily;
  }

  /**
   * 获取APP界面字号
   */
  public static getAppFontSize(): number {
    return FontAwareHelper.globalState.appFontSize;
  }

  /**
   * 获取缩放后的APP界面字号
   */
  public static getScaledAppFontSize(scale?: number): number {
    const s = scale ?? FontAwareHelper.globalState.fontScale;
    return Math.round(FontAwareHelper.globalState.appFontSize * s);
  }

  /**
   * 获取小说字体族
   */
  public static getNovelFontFamily(): string {
    return FontAwareHelper.globalState.novelFontFamily;
  }

  /**
   * 获取小说字号
   */
  public static getNovelFontSize(): number {
    return FontAwareHelper.globalState.novelFontSize;
  }

  /**
   * 获取小说行高
   */
  public static getNovelLineHeight(): number {
    return FontAwareHelper.globalState.novelLineHeight;
  }

  /**
   * 获取电子书字体族
   */
  public static getEbookFontFamily(): string {
    return FontAwareHelper.globalState.ebookFontFamily;
  }

  /**
   * 获取电子书字号
   */
  public static getEbookFontSize(): number {
    return FontAwareHelper.globalState.ebookFontSize;
  }

  /**
   * 获取电子书行高
   */
  public static getEbookLineHeight(): number {
    return FontAwareHelper.globalState.ebookLineHeight;
  }

  // ==================== 通用字号计算接口 ====================

  /**
   * 根据基础字号和场景获取实际字号
   * @param baseFontSize 基础字号
   * @param scene 使用场景
   * @param applyScale 是否应用缩放
   */
  public static getFontSize(baseFontSize: number, scene: FontScene = FontScene.APP_UI, applyScale: boolean = true): number {
    if (!applyScale) {
      return baseFontSize;
    }
    return Math.round(baseFontSize * FontAwareHelper.globalState.fontScale);
  }

  /**
   * 根据场景获取字体族
   */
  public static getFontFamily(scene: FontScene = FontScene.APP_UI): string {
    switch (scene) {
      case FontScene.APP_UI:
        return FontAwareHelper.globalState.appFontFamily;
      case FontScene.NOVEL:
        return FontAwareHelper.globalState.novelFontFamily;
      case FontScene.EBOOK:
        return FontAwareHelper.globalState.ebookFontFamily;
      default:
        return FontAwareHelper.globalState.appFontFamily;
    }
  }

  /**
   * 设置全局字号缩放倍率
   */
  public static setFontScale(scale: number): void {
    FontAwareHelper.globalState.fontScale = Math.max(0.5, Math.min(2.0, scale));
    FontAwareHelper.notifyAllCallbacks();
    logger.info(TAG, `字号缩放倍率设置为: ${FontAwareHelper.globalState.fontScale}`);
  }

  /**
   * 获取当前字号缩放倍率
   */
  public static getFontScale(): number {
    return FontAwareHelper.globalState.fontScale;
  }

  // ==================== 便捷样式应用接口 ====================

  /**
   * 获取标题文字样式参数
   * @param mode 应用模式
   */
  public static getTitleStyle(mode: FontApplyMode = FontApplyMode.FONT_AND_SCALE): TextStyleParams {
    const baseFontSize = 18;
    return FontAwareHelper.buildTextStyle(baseFontSize, FontScene.APP_UI, mode);
  }

  /**
   * 获取正文文字样式参数
   * @param mode 应用模式
   */
  public static getBodyStyle(mode: FontApplyMode = FontApplyMode.FONT_AND_SCALE): TextStyleParams {
    const baseFontSize = 14;
    return FontAwareHelper.buildTextStyle(baseFontSize, FontScene.APP_UI, mode);
  }

  /**
   * 获取次要文字样式参数
   * @param mode 应用模式
   */
  public static getSecondaryStyle(mode: FontApplyMode = FontApplyMode.FONT_AND_SCALE): TextStyleParams {
    const baseFontSize = 12;
    return FontAwareHelper.buildTextStyle(baseFontSize, FontScene.APP_UI, mode);
  }

  /**
   * 获取小说阅读文字样式参数
   */
  public static getNovelReadingStyle(): TextStyleParams {
    return {
      fontFamily: FontAwareHelper.globalState.novelFontFamily,
      fontSize: FontAwareHelper.globalState.novelFontSize,
      lineHeight: FontAwareHelper.globalState.novelLineHeight
    };
  }

  /**
   * 获取电子书阅读文字样式参数
   */
  public static getEbookReadingStyle(): TextStyleParams {
    return {
      fontFamily: FontAwareHelper.globalState.ebookFontFamily,
      fontSize: FontAwareHelper.globalState.ebookFontSize,
      lineHeight: FontAwareHelper.globalState.ebookLineHeight
    };
  }

  /**
   * 构建文字样式参数
   */
  private static buildTextStyle(baseFontSize: number, scene: FontScene, mode: FontApplyMode): TextStyleParams {
    const result: TextStyleParams = {};
    
    switch (mode) {
      case FontApplyMode.FONT_ONLY:
        result.fontFamily = FontAwareHelper.getFontFamily(scene);
        result.fontSize = baseFontSize;
        break;
      case FontApplyMode.SCALE_ONLY:
        result.fontSize = FontAwareHelper.getFontSize(baseFontSize, scene, true);
        break;
      case FontApplyMode.FONT_AND_SCALE:
        result.fontFamily = FontAwareHelper.getFontFamily(scene);
        result.fontSize = FontAwareHelper.getFontSize(baseFontSize, scene, true);
        break;
    }
    
    return result;
  }
}

/**
 * 文字样式参数接口
 */
export interface TextStyleParams {
  fontFamily?: string;
  fontSize?: number;
  lineHeight?: number;
}

/**
 * 导出便捷函数
 */
export function getAppFontFamily(): string {
  return FontAwareHelper.getAppFontFamily();
}

export function getAppFontSize(): number {
  return FontAwareHelper.getAppFontSize();
}

export function getNovelFontFamily(): string {
  return FontAwareHelper.getNovelFontFamily();
}

export function getEbookFontFamily(): string {
  return FontAwareHelper.getEbookFontFamily();
}

export function getFontScale(): number {
  return FontAwareHelper.getFontScale();
}

export function setFontScale(scale: number): void {
  FontAwareHelper.setFontScale(scale);
}
