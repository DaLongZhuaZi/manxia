import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
// 文件路径: entry/src/main/ets/Framework/Managers/FontManager.ets
/**
 * 全局字体管理器
 * 管理APP内页面字体、小说字体、电子书字体
 * 支持系统字体和自定义字体文件
 */

import { UIContext } from '@kit.ArkUI';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { parseFontName, extractFileNameWithoutExt, FontNameInfo } from 'manxia_core/src/main/ets/Framework/Utils/FontNameParser';
import { uiContextManager } from './UIContextManager';

const TAG = 'FontManager';
const PREFERENCES_NAME = 'font_settings';
const FONTS_DIR = 'custom_fonts';

// 字体类型枚举
export enum FontType {
  SYSTEM = 'system',      // 系统字体
  CUSTOM = 'custom'       // 自定义字体
}

// 字体使用场景
export enum FontScene {
  APP_UI = 'app_ui',           // APP界面字体
  NOVEL = 'novel',             // 小说阅读字体
  EBOOK = 'ebook'              // 电子书阅读字体
}

// 系统预设字体
export interface SystemFont {
  id: string;
  name: string;
  displayName: string;
  isDefault: boolean;
}

// 自定义字体
export interface CustomFont {
  id: string;
  familyName: string;
  displayName: string;
  filePath: string;        // rawfile路径或沙箱路径
  isRegistered: boolean;
  addedTime: number;
}

// 字体设置
export interface FontSettings {
  // APP界面字体
  appFontType: FontType;
  appSystemFontId: string;
  appCustomFontId: string;
  appFontSize: number;           // 基础字体大小倍率 (0.8 - 1.5)
  
  // 小说阅读字体
  novelFontType: FontType;
  novelSystemFontId: string;
  novelCustomFontId: string;
  novelFontSize: number;         // 小说字体大小 (12 - 32)
  novelLineHeight: number;       // 行高倍率 (1.0 - 2.5)
  
  // 电子书阅读字体
  ebookFontType: FontType;
  ebookSystemFontId: string;
  ebookCustomFontId: string;
  ebookFontSize: number;         // 电子书字体大小 (12 - 32)
  ebookLineHeight: number;       // 行高倍率 (1.0 - 2.5)
}

// 默认字体设置
const DEFAULT_FONT_SETTINGS: FontSettings = {
  appFontType: FontType.SYSTEM,
  appSystemFontId: 'default',
  appCustomFontId: '',
  appFontSize: 1.0,
  
  novelFontType: FontType.SYSTEM,
  novelSystemFontId: 'default',
  novelCustomFontId: '',
  novelFontSize: 18,
  novelLineHeight: 1.8,
  
  ebookFontType: FontType.SYSTEM,
  ebookSystemFontId: 'default',
  ebookCustomFontId: '',
  ebookFontSize: 18,
  ebookLineHeight: 1.6
};

// 系统预设字体列表
const SYSTEM_FONTS: SystemFont[] = [
  { id: 'default', name: 'HarmonyOS Sans', displayName: '系统默认', isDefault: true },
  { id: 'sans_serif', name: 'sans-serif', displayName: '无衬线体', isDefault: false },
  { id: 'serif', name: 'serif', displayName: '衬线体', isDefault: false },
  { id: 'monospace', name: 'monospace', displayName: '等宽字体', isDefault: false }
];

// 字体变更回调
type FontChangeCallback = (scene: FontScene, fontFamily: string) => void;

/**
 * 字体管理器单例类
 */
export class FontManager {
  private static instance: FontManager | null = null;
  private settings: FontSettings = this.copyDefaultSettings();
  private customFonts: CustomFont[] = [];
  private isInitialized: boolean = false;
  private preferences: preferences.Preferences | null = null;
  private callbacks: Map<string, FontChangeCallback> = new Map();
  private context: common.UIAbilityContext | null = null;
  private fontsDirPath: string = '';

  private constructor() {}

  /**
   * 复制默认设置
   */
  private copyDefaultSettings(): FontSettings {
    return {
      appFontType: DEFAULT_FONT_SETTINGS.appFontType,
      appSystemFontId: DEFAULT_FONT_SETTINGS.appSystemFontId,
      appCustomFontId: DEFAULT_FONT_SETTINGS.appCustomFontId,
      appFontSize: DEFAULT_FONT_SETTINGS.appFontSize,
      novelFontType: DEFAULT_FONT_SETTINGS.novelFontType,
      novelSystemFontId: DEFAULT_FONT_SETTINGS.novelSystemFontId,
      novelCustomFontId: DEFAULT_FONT_SETTINGS.novelCustomFontId,
      novelFontSize: DEFAULT_FONT_SETTINGS.novelFontSize,
      novelLineHeight: DEFAULT_FONT_SETTINGS.novelLineHeight,
      ebookFontType: DEFAULT_FONT_SETTINGS.ebookFontType,
      ebookSystemFontId: DEFAULT_FONT_SETTINGS.ebookSystemFontId,
      ebookCustomFontId: DEFAULT_FONT_SETTINGS.ebookCustomFontId,
      ebookFontSize: DEFAULT_FONT_SETTINGS.ebookFontSize,
      ebookLineHeight: DEFAULT_FONT_SETTINGS.ebookLineHeight
    };
  }

  /**
   * 复制设置对象
   */
  private copySettings(source: FontSettings): FontSettings {
    return {
      appFontType: source.appFontType,
      appSystemFontId: source.appSystemFontId,
      appCustomFontId: source.appCustomFontId,
      appFontSize: source.appFontSize,
      novelFontType: source.novelFontType,
      novelSystemFontId: source.novelSystemFontId,
      novelCustomFontId: source.novelCustomFontId,
      novelFontSize: source.novelFontSize,
      novelLineHeight: source.novelLineHeight,
      ebookFontType: source.ebookFontType,
      ebookSystemFontId: source.ebookSystemFontId,
      ebookCustomFontId: source.ebookCustomFontId,
      ebookFontSize: source.ebookFontSize,
      ebookLineHeight: source.ebookLineHeight
    };
  }

  /**
   * 合并设置
   */
  private mergeSettings(saved: FontSettings): FontSettings {
    const defaults = this.copyDefaultSettings();
    return {
      appFontType: saved.appFontType || defaults.appFontType,
      appSystemFontId: saved.appSystemFontId || defaults.appSystemFontId,
      appCustomFontId: saved.appCustomFontId || defaults.appCustomFontId,
      appFontSize: saved.appFontSize || defaults.appFontSize,
      novelFontType: saved.novelFontType || defaults.novelFontType,
      novelSystemFontId: saved.novelSystemFontId || defaults.novelSystemFontId,
      novelCustomFontId: saved.novelCustomFontId || defaults.novelCustomFontId,
      novelFontSize: saved.novelFontSize || defaults.novelFontSize,
      novelLineHeight: saved.novelLineHeight || defaults.novelLineHeight,
      ebookFontType: saved.ebookFontType || defaults.ebookFontType,
      ebookSystemFontId: saved.ebookSystemFontId || defaults.ebookSystemFontId,
      ebookCustomFontId: saved.ebookCustomFontId || defaults.ebookCustomFontId,
      ebookFontSize: saved.ebookFontSize || defaults.ebookFontSize,
      ebookLineHeight: saved.ebookLineHeight || defaults.ebookLineHeight
    };
  }

  static getInstance(): FontManager {
    if (!FontManager.instance) {
      FontManager.instance = new FontManager();
    }
    return FontManager.instance;
  }

  /**
   * 初始化字体管理器
   */
  async initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.isInitialized) {
      logger.info(TAG, '字体管理器已初始化');
      return;
    }

    try {
      this.context = context;
      
      // 创建字体存储目录
      this.fontsDirPath = `${context.filesDir}/${FONTS_DIR}`;
      await this.ensureFontsDir();
      
      // 获取preferences实例
      this.preferences = await preferences.getPreferences(context, PREFERENCES_NAME);
      
      // 加载保存的设置
      await this.loadSettings();
      
      // 加载自定义字体列表
      await this.loadCustomFonts();
      
      // 注册已保存的自定义字体。冷启动早期可能还没有 UIContext，此时会延迟到页面可用后重试。
      await this.registerSavedCustomFonts();
      
      this.isInitialized = true;
      
      // 同步到AppStorage
      this.syncToAppStorage();
      
      const appFont = this.getFontFamily(FontScene.APP_UI);
      logger.info(TAG, `字体管理器初始化完成，字体目录: ${this.fontsDirPath}, APP字体: ${appFont}`);
    } catch (error) {
      logger.error(TAG, `字体管理器初始化失败: ${String(error)}`);
    }
  }

  /**
   * 确保字体目录存在
   */
  private async ensureFontsDir(): Promise<void> {
    try {
      const exists = SafeFileUtils.accessSync(this.fontsDirPath);
      if (!exists) {
        SafeFileUtils.mkdirSync(this.fontsDirPath);
        logger.info(TAG, `创建字体目录: ${this.fontsDirPath}`);
      }
    } catch (error) {
      // 目录不存在，创建它
      try {
        SafeFileUtils.mkdirSync(this.fontsDirPath);
        logger.info(TAG, `创建字体目录: ${this.fontsDirPath}`);
      } catch (mkdirError) {
        logger.error(TAG, `创建字体目录失败: ${String(mkdirError)}`);
      }
    }
  }

  /**
   * 加载字体设置
   */
  private async loadSettings(): Promise<void> {
    if (!this.preferences) return;

    try {
      const settingsJson = await this.preferences.get('settings', '') as string;
      logger.info(TAG, `加载字体设置JSON: ${settingsJson ? settingsJson.substring(0, 200) : '空'}`);
      if (settingsJson) {
        const saved = SafeUtils.parseObj(settingsJson) as FontSettings;
        this.settings = this.mergeSettings(saved);
        logger.info(TAG, `字体设置加载成功: appFontType=${this.settings.appFontType}, appSystemFontId=${this.settings.appSystemFontId}, appCustomFontId=${this.settings.appCustomFontId}`);
      } else {
        logger.info(TAG, '没有保存的字体设置，使用默认值');
      }
    } catch (error) {
      logger.error(TAG, `加载字体设置失败: ${String(error)}`);
    }
  }

  /**
   * 保存字体设置
   */
  private async saveSettings(): Promise<void> {
    if (!this.preferences) return;

    try {
      await this.preferences.put('settings', JSON.stringify(this.settings));
      await this.preferences.flush();
      logger.info(TAG, '字体设置保存成功');
    } catch (error) {
      logger.error(TAG, `保存字体设置失败: ${String(error)}`);
    }
  }

  /**
   * 加载自定义字体列表
   */
  private async loadCustomFonts(): Promise<void> {
    if (!this.preferences) return;

    try {
      const fontsJson = await this.preferences.get('custom_fonts', '') as string;
      if (fontsJson) {
        this.customFonts = SafeUtils.parseArr(fontsJson) as CustomFont[];
        logger.info(TAG, `加载了 ${this.customFonts.length} 个自定义字体`);
      }
    } catch (error) {
      logger.error(TAG, `加载自定义字体列表失败: ${String(error)}`);
    }
  }

  /**
   * 保存自定义字体列表
   */
  private async saveCustomFonts(): Promise<void> {
    if (!this.preferences) return;

    try {
      await this.preferences.put('custom_fonts', JSON.stringify(this.customFonts));
      await this.preferences.flush();
      logger.info(TAG, '自定义字体列表保存成功');
    } catch (error) {
      logger.error(TAG, `保存自定义字体列表失败: ${String(error)}`);
    }
  }

  /**
   * 注册已保存的自定义字体
   */
  private async registerSavedCustomFonts(uiContext?: UIContext | null): Promise<void> {
    const targetUIContext: UIContext | null = uiContext ?? uiContextManager.getUIContext();
    if (!targetUIContext) {
      this.customFonts.forEach((customFont: CustomFont) => {
        customFont.isRegistered = false;
      });
      logger.warn(TAG, 'UIContext 不可用，已延迟注册已保存的自定义字体');
      return;
    }

    for (const customFont of this.customFonts) {
      try {
        await this.registerFont(customFont, targetUIContext);
        customFont.isRegistered = true;
      } catch (error) {
        logger.warn(TAG, `注册字体 ${customFont.displayName} 失败: ${String(error)}`);
        customFont.isRegistered = false;
      }
    }
  }

  /**
   * 在当前 UIContext 中重新注册所有自定义字体。
   * API23 的字体注册绑定 UIContext，冷启动初始化早于页面创建时需要在页面出现后重放注册。
   */
  public async registerCustomFontsForCurrentUIContext(): Promise<void> {
    await this.registerCustomFontsForUIContext(uiContextManager.getUIContext());
  }

  /**
   * 在指定 UIContext 中重新注册所有自定义字体。
   */
  public async registerCustomFontsForUIContext(uiContext: UIContext | null): Promise<void> {
    await this.registerSavedCustomFonts(uiContext);
    this.syncToAppStorage();
  }

  /**
   * 注册字体到系统
   */
  private async registerFont(customFont: CustomFont, uiContext?: UIContext | null): Promise<void> {
    try {
      const targetUIContext: UIContext | null = uiContext ?? uiContextManager.getUIContext();
      if (!targetUIContext) {
        throw new Error('UIContext 不可用，无法注册字体');
      }
      // 使用file://协议的URI格式
      const fontUri = customFont.filePath.startsWith('file://') ? customFont.filePath : `file://${customFont.filePath}`;
      targetUIContext.getFont().registerFont({
        familyName: customFont.familyName,
        familySrc: fontUri
      });
      logger.info(TAG, `字体注册成功: ${customFont.familyName}, URI: ${fontUri}`);
    } catch (error) {
      throw new Error(`字体注册失败: ${String(error)}`);
    }
  }

  /**
   * 确保指定自定义字体已注册到当前或指定 UIContext。
   */
  private async ensureCustomFontRegistered(fontId: string, scene: FontScene, uiContext?: UIContext | null): Promise<void> {
    const customFont = this.customFonts.find((font: CustomFont) => font.id === fontId);
    if (!customFont) {
      throw new Error(`未找到${scene}自定义字体: ${fontId}`);
    }

    await this.registerFont(customFont, uiContext);
    customFont.isRegistered = true;
  }

  /**
   * 添加自定义字体
   * @param displayName 用户提供的显示名称（如果为空则自动解析）
   * @param sourceFilePath 源字体文件路径
   */
  async addCustomFont(displayName: string, sourceFilePath: string, uiContext?: UIContext | null): Promise<CustomFont> {
    const id = `custom_${Date.now()}`;
    
    // 获取文件扩展名
    const ext = this.getFileExtension(sourceFilePath);
    const localFileName = `${id}${ext}`;
    const localFilePath = `${this.fontsDirPath}/${localFileName}`;
    
    try {
      // 复制字体文件到应用沙箱
      await this.copyFontFile(sourceFilePath, localFilePath);
      logger.info(TAG, `字体文件复制成功: ${localFilePath}`);
      
      // 解析字体文件获取真实名称
      let fontNameInfo: FontNameInfo | null = null;
      let actualDisplayName = displayName;
      let actualFamilyName = `CustomFont_${id}`;
      
      try {
        fontNameInfo = await parseFontName(localFilePath);
        
        // 使用解析出的名称
        if (fontNameInfo) {
          // 显示名称优先使用本地化名称（中文等），其次使用完整名称，最后使用字体族名称
          actualDisplayName = fontNameInfo.displayName || fontNameInfo.fullName || fontNameInfo.familyName || '';
          
          // familyName使用PostScript名称或英文字体族名称（用于系统注册）
          // 注意：有些字体的PostScript名称可能包含特殊字符，需要清理
          actualFamilyName = this.sanitizeFamilyName(fontNameInfo.postScriptName || fontNameInfo.familyName || `CustomFont_${id}`);
          
          logger.info(TAG, `字体名称解析成功: displayName=${actualDisplayName}, familyName=${actualFamilyName}, ` +
            `localizedFamily=${fontNameInfo.localizedFamilyName || 'N/A'}, postScript=${fontNameInfo.postScriptName || 'N/A'}`);
        }
      } catch (parseError) {
        logger.warn(TAG, `字体名称解析失败，使用文件名: ${String(parseError)}`);
      }
      
      // 如果displayName仍为空，使用用户提供的名称或文件名
      if (!actualDisplayName) {
        actualDisplayName = displayName || extractFileNameWithoutExt(sourceFilePath);
      }
      
      const customFont: CustomFont = {
        id,
        familyName: actualFamilyName,
        displayName: actualDisplayName,
        filePath: localFilePath,
        isRegistered: false,
        addedTime: Date.now()
      };

      // 注册字体
      await this.registerFont(customFont, uiContext);
      customFont.isRegistered = true;
      
      // 添加到列表
      this.customFonts.push(customFont);
      await this.saveCustomFonts();
      
      logger.info(TAG, `自定义字体添加成功: ${actualDisplayName}, familyName=${actualFamilyName}, 路径: ${localFilePath}`);
      return customFont;
    } catch (error) {
      // 清理可能已复制的文件
      try {
        SafeFileUtils.unlinkSync(localFilePath);
      } catch (e) {
        // 忽略清理错误
      }
      logger.error(TAG, `添加自定义字体失败: ${String(error)}`);
      throw new Error(`添加自定义字体失败: ${String(error)}`);
    }
  }
  
  /**
   * 清理字体族名称，移除不支持的字符
   * 某些字体的PostScript名称可能包含特殊字符，需要清理以确保系统能正确注册
   */
  private sanitizeFamilyName(name: string): string {
    if (!name) return '';
    
    // 移除或替换不支持的字符
    // 保留字母、数字、中文、日文、韩文、连字符和下划线
    let sanitized = name
      .replace(/[\x00-\x1F\x7F]/g, '') // 移除控制字符
      .replace(/[<>:"\|?*]/g, '')      // 移除文件名不支持的字符
      .trim();
    
    // 如果清理后为空，返回原始名称
    return sanitized || name;
  }

  /**
   * 获取文件扩展名
   */
  private getFileExtension(filePath: string): string {
    const lastDot = filePath.lastIndexOf('.');
    if (lastDot === -1) {
      return '.ttf';
    }
    return filePath.substring(lastDot);
  }

  /**
   * 复制字体文件到应用沙箱
   */
  private async copyFontFile(sourcePath: string, destPath: string): Promise<void> {
    try {
      // 打开源文件
      const sourceFile = SafeFileUtils.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      
      // 创建目标文件
      const destFile = SafeFileUtils.openSync(destPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      
      // 读取并写入
      const stat = SafeFileUtils.statSync(sourceFile.fd);
      const buffer = new ArrayBuffer(stat.size);
      SafeFileUtils.readSync(sourceFile.fd, buffer);
      SafeFileUtils.writeSync(destFile.fd, buffer);
      
      // 关闭文件
      SafeFileUtils.closeSync(sourceFile);
      SafeFileUtils.closeSync(destFile);
      
      logger.info(TAG, `字体文件复制完成: ${stat.size} 字节`);
    } catch (error) {
      throw new Error(`复制字体文件失败: ${String(error)}`);
    }
  }

  /**
   * 删除自定义字体
   */
  async removeCustomFont(fontId: string): Promise<void> {
    const index = this.customFonts.findIndex(f => f.id === fontId);
    if (index === -1) {
      throw new Error('字体不存在');
    }

    const customFont = this.customFonts[index];
    
    // 检查是否正在使用
    const isAppUsing = this.settings.appFontType === FontType.CUSTOM && this.settings.appCustomFontId === fontId;
    const isNovelUsing = this.settings.novelFontType === FontType.CUSTOM && this.settings.novelCustomFontId === fontId;
    const isEbookUsing = this.settings.ebookFontType === FontType.CUSTOM && this.settings.ebookCustomFontId === fontId;
    
    logger.info(TAG, `删除字体检查: fontId=${fontId}, appType=${this.settings.appFontType}, appCustomId=${this.settings.appCustomFontId}, isAppUsing=${isAppUsing}`);
    
    if (isAppUsing || isNovelUsing || isEbookUsing) {
      throw new Error('字体正在使用中，请先切换到其他字体');
    }

    // 删除字体文件
    try {
      SafeFileUtils.unlinkSync(customFont.filePath);
      logger.info(TAG, `字体文件已删除: ${customFont.filePath}`);
    } catch (error) {
      logger.warn(TAG, `删除字体文件失败: ${String(error)}`);
    }

    this.customFonts.splice(index, 1);
    await this.saveCustomFonts();
    
    logger.info(TAG, `自定义字体删除成功: ${customFont.displayName}`);
  }

  /**
   * 获取系统字体列表
   */
  getSystemFonts(): SystemFont[] {
    return SYSTEM_FONTS.slice();
  }

  /**
   * 获取自定义字体列表
   */
  getCustomFonts(): CustomFont[] {
    return this.customFonts.slice();
  }

  /**
   * 获取当前字体设置
   */
  getSettings(): FontSettings {
    return this.copySettings(this.settings);
  }

  /**
   * 获取指定场景的字体族名称
   */
  getFontFamily(scene: FontScene): string {
    switch (scene) {
      case FontScene.APP_UI:
        if (this.settings.appFontType === FontType.CUSTOM && this.settings.appCustomFontId) {
          const customFont = this.customFonts.find(f => f.id === this.settings.appCustomFontId);
          return customFont?.familyName || 'HarmonyOS Sans';
        }
        return this.getSystemFontName(this.settings.appSystemFontId);
        
      case FontScene.NOVEL:
        if (this.settings.novelFontType === FontType.CUSTOM && this.settings.novelCustomFontId) {
          const customFont = this.customFonts.find(f => f.id === this.settings.novelCustomFontId);
          return customFont?.familyName || 'HarmonyOS Sans';
        }
        return this.getSystemFontName(this.settings.novelSystemFontId);
        
      case FontScene.EBOOK:
        if (this.settings.ebookFontType === FontType.CUSTOM && this.settings.ebookCustomFontId) {
          const customFont = this.customFonts.find(f => f.id === this.settings.ebookCustomFontId);
          return customFont?.familyName || 'HarmonyOS Sans';
        }
        return this.getSystemFontName(this.settings.ebookSystemFontId);
        
      default:
        return 'HarmonyOS Sans';
    }
  }

  /**
   * 获取系统字体名称
   */
  private getSystemFontName(fontId: string): string {
    const systemFont = SYSTEM_FONTS.find(f => f.id === fontId);
    return systemFont?.name || 'HarmonyOS Sans';
  }

  /**
   * 获取指定场景的字体大小
   */
  getFontSize(scene: FontScene): number {
    switch (scene) {
      case FontScene.APP_UI:
        return this.settings.appFontSize;
      case FontScene.NOVEL:
        return this.settings.novelFontSize;
      case FontScene.EBOOK:
        return this.settings.ebookFontSize;
      default:
        return 1.0;
    }
  }

  /**
   * 获取指定场景的行高
   */
  getLineHeight(scene: FontScene): number {
    switch (scene) {
      case FontScene.NOVEL:
        return this.settings.novelLineHeight;
      case FontScene.EBOOK:
        return this.settings.ebookLineHeight;
      default:
        return 1.5;
    }
  }

  /**
   * 设置APP界面字体
   */
  async setAppFont(fontType: FontType, fontId: string, uiContext?: UIContext | null): Promise<void> {
    if (fontType === FontType.CUSTOM) {
      await this.ensureCustomFontRegistered(fontId, FontScene.APP_UI, uiContext);
    }
    this.settings.appFontType = fontType;
    if (fontType === FontType.SYSTEM) {
      this.settings.appSystemFontId = fontId;
    } else {
      this.settings.appCustomFontId = fontId;
    }
    await this.saveSettings();
    this.notifyFontChange(FontScene.APP_UI);
  }

  /**
   * 设置APP界面字体大小倍率
   */
  async setAppFontSize(size: number): Promise<void> {
    this.settings.appFontSize = Math.max(0.8, Math.min(1.5, size));
    await this.saveSettings();
    this.notifyFontChange(FontScene.APP_UI);
  }

  /**
   * 设置小说阅读字体
   */
  async setNovelFont(fontType: FontType, fontId: string, uiContext?: UIContext | null): Promise<void> {
    if (fontType === FontType.CUSTOM) {
      await this.ensureCustomFontRegistered(fontId, FontScene.NOVEL, uiContext);
    }
    this.settings.novelFontType = fontType;
    if (fontType === FontType.SYSTEM) {
      this.settings.novelSystemFontId = fontId;
    } else {
      this.settings.novelCustomFontId = fontId;
    }
    await this.saveSettings();
    this.notifyFontChange(FontScene.NOVEL);
  }

  /**
   * 设置小说阅读字体大小
   */
  async setNovelFontSize(size: number): Promise<void> {
    this.settings.novelFontSize = Math.max(12, Math.min(32, size));
    await this.saveSettings();
    this.notifyFontChange(FontScene.NOVEL);
  }

  /**
   * 设置小说阅读行高
   */
  async setNovelLineHeight(height: number): Promise<void> {
    this.settings.novelLineHeight = Math.max(1.0, Math.min(2.5, height));
    await this.saveSettings();
    this.notifyFontChange(FontScene.NOVEL);
  }

  /**
   * 设置电子书阅读字体
   */
  async setEbookFont(fontType: FontType, fontId: string, uiContext?: UIContext | null): Promise<void> {
    if (fontType === FontType.CUSTOM) {
      await this.ensureCustomFontRegistered(fontId, FontScene.EBOOK, uiContext);
    }
    this.settings.ebookFontType = fontType;
    if (fontType === FontType.SYSTEM) {
      this.settings.ebookSystemFontId = fontId;
    } else {
      this.settings.ebookCustomFontId = fontId;
    }
    await this.saveSettings();
    this.notifyFontChange(FontScene.EBOOK);
  }

  /**
   * 设置电子书阅读字体大小
   */
  async setEbookFontSize(size: number): Promise<void> {
    this.settings.ebookFontSize = Math.max(12, Math.min(32, size));
    await this.saveSettings();
    this.notifyFontChange(FontScene.EBOOK);
  }

  /**
   * 设置电子书阅读行高
   */
  async setEbookLineHeight(height: number): Promise<void> {
    this.settings.ebookLineHeight = Math.max(1.0, Math.min(2.5, height));
    await this.saveSettings();
    this.notifyFontChange(FontScene.EBOOK);
  }

  /**
   * 注册字体变更回调
   */
  addFontChangeListener(id: string, callback: FontChangeCallback): void {
    this.callbacks.set(id, callback);
  }

  /**
   * 移除字体变更回调
   */
  removeFontChangeListener(id: string): void {
    this.callbacks.delete(id);
  }

  /**
   * 通知字体变更
   */
  private notifyFontChange(scene: FontScene): void {
    const fontFamily = this.getFontFamily(scene);
    
    // 同步到AppStorage
    this.syncToAppStorage();
    
    this.callbacks.forEach((callback) => {
      try {
        callback(scene, fontFamily);
      } catch (error) {
        logger.error(TAG, `字体变更回调执行失败: ${String(error)}`);
      }
    });
  }

  /**
   * 同步字体设置到AppStorage
   */
  syncToAppStorage(): void {
    try {
      const appFont = this.getFontFamily(FontScene.APP_UI);
      const novelFont = this.getFontFamily(FontScene.NOVEL);
      const ebookFont = this.getFontFamily(FontScene.EBOOK);
      
      // APP界面字体
      AppStorage.setOrCreate('appFontFamily', appFont);
      AppStorage.setOrCreate('appFontSize', this.settings.appFontSize);
      
      // 小说字体
      AppStorage.setOrCreate('novelFontFamily', novelFont);
      AppStorage.setOrCreate('novelFontSize', this.settings.novelFontSize);
      AppStorage.setOrCreate('novelLineHeight', this.settings.novelLineHeight);
      
      // 电子书字体
      AppStorage.setOrCreate('ebookFontFamily', ebookFont);
      AppStorage.setOrCreate('ebookFontSize', this.settings.ebookFontSize);
      AppStorage.setOrCreate('ebookLineHeight', this.settings.ebookLineHeight);
      
      logger.info(TAG, `字体设置已同步到AppStorage: APP=${appFont}, 小说=${novelFont}, 电子书=${ebookFont}`);
      
      // 检查自定义字体是否已注册
      if (this.settings.appFontType === FontType.CUSTOM) {
        const customFont = this.customFonts.find(f => f.id === this.settings.appCustomFontId);
        if (customFont) {
          logger.info(TAG, `当前APP自定义字体: id=${customFont.id}, familyName=${customFont.familyName}, isRegistered=${customFont.isRegistered}, filePath=${customFont.filePath}`);
        } else {
          logger.warn(TAG, `未找到APP自定义字体: ${this.settings.appCustomFontId}`);
        }
      }
    } catch (error) {
      logger.error(TAG, `同步字体设置到AppStorage失败: ${String(error)}`);
    }
  }

  /**
   * 重置为默认设置
   */
  async resetToDefault(): Promise<void> {
    this.settings = this.copyDefaultSettings();
    await this.saveSettings();
    
    // 通知所有场景
    this.notifyFontChange(FontScene.APP_UI);
    this.notifyFontChange(FontScene.NOVEL);
    this.notifyFontChange(FontScene.EBOOK);
    
    logger.info(TAG, '字体设置已重置为默认值');
  }

  /**
   * 获取字体显示名称
   */
  getFontDisplayName(scene: FontScene): string {
    let fontType: FontType;
    let systemFontId: string;
    let customFontId: string;

    switch (scene) {
      case FontScene.APP_UI:
        fontType = this.settings.appFontType;
        systemFontId = this.settings.appSystemFontId;
        customFontId = this.settings.appCustomFontId;
        break;
      case FontScene.NOVEL:
        fontType = this.settings.novelFontType;
        systemFontId = this.settings.novelSystemFontId;
        customFontId = this.settings.novelCustomFontId;
        break;
      case FontScene.EBOOK:
        fontType = this.settings.ebookFontType;
        systemFontId = this.settings.ebookSystemFontId;
        customFontId = this.settings.ebookCustomFontId;
        break;
      default:
        return '系统默认';
    }

    if (fontType === FontType.CUSTOM && customFontId) {
      const customFont = this.customFonts.find(f => f.id === customFontId);
      return customFont?.displayName || '自定义字体';
    }

    const systemFont = SYSTEM_FONTS.find(f => f.id === systemFontId);
    return systemFont?.displayName || '系统默认';
  }
  
  /**
   * 重新加载字体设置（用于备份恢复后）
   */
  async reloadSettings(): Promise<void> {
    if (!this.isInitialized || !this.preferences) {
      logger.warn(TAG, '字体管理器未初始化，无法重新加载设置');
      return;
    }
    
    try {
      logger.info(TAG, '开始重新加载字体设置...');
      
      // 重新加载设置
      await this.loadSettings();
      
      // 重新加载自定义字体列表
      await this.loadCustomFonts();
      
      // 重新注册自定义字体
      await this.registerSavedCustomFonts();
      
      // 同步到AppStorage
      this.syncToAppStorage();
      
      // 通知所有监听器
      this.notifyAllListeners();
      
      logger.info(TAG, '字体设置重新加载完成');
    } catch (error) {
      logger.error(TAG, `重新加载字体设置失败: ${String(error)}`);
    }
  }
  
  /**
   * 通知所有场景的监听器
   */
  private notifyAllListeners(): void {
    const scenes: FontScene[] = [FontScene.APP_UI, FontScene.NOVEL, FontScene.EBOOK];
    for (const scene of scenes) {
      this.notifyFontChange(scene);
    }
  }
}

// 导出单例获取函数
export function getFontManager(): FontManager {
  return FontManager.getInstance();
}
