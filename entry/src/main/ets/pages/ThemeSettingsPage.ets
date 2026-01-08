/**
 * 主题设置页面
 * 提供自定义主题功能：图片选择、裁剪、模糊效果、主色调提取、深色模式适配
 */
import { logger } from '../Utils/Logger';
import { ThemeManager, ThemeType, CustomThemeData, CUSTOM_THEME_KEYS, THEME_CONFIGS } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { UIContext, LengthMetrics, promptAction } from '@kit.ArkUI';
import { cropToDisplayAspect, cropToDisplayAspectWithOptions, CropAlignment } from '../Framework/Utils/ImageCropper';
import { preferences } from '@kit.ArkData';
import fs from '@ohos.file.fs';
import effectKit from '@ohos.effectKit';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint, DeviceType as AdaptDeviceType } from '../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../Framework/Utils/ResponsiveLayout';
import { deviceInfo } from '@kit.BasicServicesKit';
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';

const TAG = 'ThemeSettingsPage';

/**
 * 自定义主题数据接口（本地定义，与ThemeManager中的CustomThemeData保持一致）
 */
interface CustomTheme {
  id: string;
  name: string;
  backgroundImagePath: string; // 浅色模式图片路径
  backgroundImagePathDark?: string; // 深色模式图片路径（可选，用于兼容旧版本）
  splashBackgroundImagePath?: string; // 开屏图片路径（可选）
  blurLevel: number;
  brightness: number; // 亮度调整（0-100），50为原始亮度
  primaryColor: string;
  isDark: boolean;
  createTime: number;
  lastModified: number;
}

/**
 * 图片处理配置接口
 */
interface ImageProcessConfig {
  targetWidth: number;
  targetHeight: number;
  blurRadius: number; // 模糊半径
  darkenAmount: number; // 压暗程度 (0-1)
  quality: number; // 输出质量 (0-100)
}

/**
 * 目标尺寸接口
 */
interface TargetSize {
  targetWidth: number;
  targetHeight: number;
}

/**
 * RGB颜色接口
 */
interface RGBColor {
  r: number;
  g: number;
  b: number;
}


@Component
export struct ThemeSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private uiContext: UIContext | undefined = undefined;

  // 状态栏和导航栏高度
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 当前选择的图片
  @State selectedImagePath: string = '';
  @State selectedImagePixelMap: image.PixelMap | null = null;
  // 开屏图片选择
  @State selectedSplashImagePath: string = '';
  @State selectedSplashImagePixelMap: image.PixelMap | null = null;
  @State processedSplashImagePixelMap: image.PixelMap | null = null;
  @State processedSplashImagePath: string = '';
  
  // 主题商店展示与创建模式
  @State isCreatingCustomTheme: boolean = false;
  @State isCropping: boolean = false;
  @State cropAlignment: CropAlignment = CropAlignment.CENTER;
  @State cropZoom: number = 1.0;
  @State newThemeName: string = '';
  @State selectedPrimaryColor: string = '';
  @State availablePrimaryColors: string[] = [];
  // 多选删除：选择模式与已选主题ID列表
  @State selectionModeEnabled: boolean = false;
  @State selectedThemeIds: string[] = [];
  
  // 当前激活的主题ID（用于在列表中标识）
  @StorageProp(CUSTOM_THEME_KEYS.CURRENT_THEME_ID) currentCustomThemeId: string = '';
  
  // 处理后的图片
  @State processedImagePixelMap: image.PixelMap | null = null;
  @State processedImagePath: string = '';
  
  // 调节参数
  @State blurLevel: number = 0; // 模糊程度 0-100，默认无模糊
  @State brightnessLevel: number = 50; // 亮度 0-100，50为原始亮度，小于50变暗，大于50变亮
  
  // 提取的主色调
  @State extractedColor: string = '#6200EE';
  @State extractedColorRGB: string = 'RGB(98, 0, 238)';
  
  // 加载状态
  @State isProcessing: boolean = false;
  @State processingMessage: string = '';
  @State processingProgress: number = 0;
  
  // 预设主题列表
  @State customThemes: CustomTheme[] = [];
  
  // 滑块调节防抖定时器
  private effectDebounceTimer: number = -1;

  // 默认自定义主题常量
  private DEFAULT_THEME_ID: string = 'default_custom_theme';
  private DEFAULT_THEME_NAME: string = '第一自定义主题';
  private SECONDARY_THEME_ID: string = 'secondary_custom_theme';
  private SECONDARY_THEME_NAME: string = '第二自定义主题';
  // 原始背景图片所在 rawfile 目录（如需调整实际目录，请修改此常量）
  private RAW_BACKGROUND_DIR: string = 'backgrounds';
  
  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    this.uiContext = this.getUIContext();
    
    ThemeAwareHelper.initializeThemeAware(TAG, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题已切换: ${theme}`);
    });
    FontAwareHelper.initializeFontAware(TAG, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
    });
    
    // 初始化响应式布局
    this.initializeResponsiveLayout();
    
    this.loadCustomThemes();

    // 首次进入时初始化默认自定义主题（若不存在则创建）
    setTimeout(async () => {
      await this.ensureDefaultCustomThemeInitialized();
    }, 0);

    // 初始化可选主题色（从系统主题配置，后续加入提取主色）
    const colorsInit: string[] = [];
    colorsInit.push(THEME_CONFIGS[ThemeType.LIGHT].primaryColor);
    colorsInit.push(THEME_CONFIGS[ThemeType.DARK].primaryColor);
    this.availablePrimaryColors = colorsInit;
  }

  private lifecycle = new PageLifecycleManager('ThemeSettingsPage', { enableDebug: true });

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(TAG);
    FontAwareHelper.cleanupFontAware(TAG);
    
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
    
    // 清理防抖定时器
    if (this.effectDebounceTimer !== -1) {
      clearTimeout(this.effectDebounceTimer);
      this.effectDebounceTimer = -1;
    }
    
    // 释放PixelMap资源
    if (this.selectedImagePixelMap) {
      this.selectedImagePixelMap.release();
    }
    if (this.processedImagePixelMap) {
      this.processedImagePixelMap.release();
    }
    if (this.selectedSplashImagePixelMap) {
      this.selectedSplashImagePixelMap.release();
    }
    if (this.processedSplashImagePixelMap) {
      this.processedSplashImagePixelMap.release();
    }
  }

  /**
   * 初始化响应式布局
   */
  private initializeResponsiveLayout(): void {
    try {
      // 更新响应式参数
      this.updateResponsiveParams();

      // 创建并注册设备变化监听器
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.updateResponsiveParams();
      };
      
      this.deviceManager.addListener(this.deviceChangeListener);
      
      logger.info(TAG, '✅ 响应式布局初始化完成');
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  /**
   * 设备类型到背景名选择（a_* / b_*）
   */
  private getDeviceTypeString(): string {
    // 直接使用官方 deviceInfo.deviceType，返回字符串：'foldable' | 'phone' | 'tablet' | '2in1' 或其他
    const sysType: string = String(deviceInfo.deviceType);
    // 同步折叠屏检测，若为折叠屏则优先使用折叠屏规则
    const isFoldable: boolean = this.deviceManager.getDeviceInfo().isFoldable;
    if (isFoldable) {
      return 'foldable';
    }
    if (sysType === 'phone') {
      return 'phone';
    }
    if (sysType === 'tablet') {
      return 'tablet';
    }
    if (sysType === '2in1') {
      return '2in1';
    }
    // 无法识别时，回退到设备适配管理器的判断
    const managedType = this.deviceManager.getDeviceInfo().deviceType;
    if (managedType === AdaptDeviceType.FOLDABLE) {
      return 'foldable';
    }
    if (managedType === AdaptDeviceType.PHONE) {
      return 'phone';
    }
    if (managedType === AdaptDeviceType.TABLET) {
      return 'tablet';
    }
    if (managedType === AdaptDeviceType.TWO_IN_ONE) {
      return '2in1';
    }
    return 'phone';
  }

  /**
   * 根据设备类型返回 a_* 或 b_* 的具体名称
   */
  private selectBackgroundName(setId: string): string {
    const dev: string = this.getDeviceTypeString();
    // a_* 集合：折叠屏 a_1，手机 a_2，平板/2in1 a_3
    if (setId === 'a') {
      if (dev === 'foldable') { return 'a_1'; }
      if (dev === 'phone') { return 'a_2'; }
      // tablet 或 2in1
      return 'a_3';
    }
    // b_* 集合：折叠屏 b_1，手机 b_2，平板/2in1 b_3
    if (setId === 'b') {
      if (dev === 'foldable') { return 'b_1'; }
      if (dev === 'phone') { return 'b_2'; }
      return 'b_3';
    }
    return 'a_2';
  }

  // 媒体资源模式下不再需要rawfile拷贝，相关逻辑已移除

  /**
   * 更新响应式布局参数
   */
  private updateResponsiveParams(): void {
    // 避免结构类型对象在页面中传播：改为使用名义方法返回基础值
    const deviceInfo: DeviceInfo = this.deviceManager.getDeviceInfo() as DeviceInfo;

    // 使用工具类的显式方法，避免依赖 ResponsiveLayoutParams 结构类型
    this.responsive_contentPadding = ResponsiveLayoutHelper.getContentPadding();
    this.responsive_isLandscape = deviceInfo.isLandscape;

    // 最大内容宽度改为直接使用工具类计算结果，保持与断点逻辑一致
    this.responsive_maxContentWidth = ResponsiveLayoutHelper.getMaxContentWidth();
    
    logger.debug(TAG, `响应式参数更新: 内边距=${this.responsive_contentPadding}, 最大宽度=${this.responsive_maxContentWidth}`);
  }

  /**
   * 加载已保存的自定义主题
   */
  private async loadCustomThemes(): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '无法获取UIAbilityContext');
        return;
      }
      
      const themesDir = `${context.filesDir}/custom_themes`;
      const themesFile = `${themesDir}/themes.json`;
      
      if (fs.accessSync(themesFile)) {
        const content = fs.readTextSync(themesFile);
        this.customThemes = JSON.parse(content) as CustomTheme[];
        // 媒体资源模式清理：默认/第二自定义主题不保留本地图片路径
        const sanitized: CustomTheme[] = [];
        let j: number = 0;
        while (j < this.customThemes.length) {
          const t: CustomTheme = this.customThemes[j];
          const isDefaultOrSecondary: boolean = (t.id === this.DEFAULT_THEME_ID) || (t.id === this.SECONDARY_THEME_ID);
          const newTheme: CustomTheme = {
            id: t.id,
            name: t.name,
            backgroundImagePath: isDefaultOrSecondary ? '' : (t.backgroundImagePath ? t.backgroundImagePath : ''),
            backgroundImagePathDark: isDefaultOrSecondary ? '' : (t.backgroundImagePathDark ? t.backgroundImagePathDark : ''),
            splashBackgroundImagePath: t.splashBackgroundImagePath ? t.splashBackgroundImagePath : '',
            blurLevel: t.blurLevel,
            brightness: t.brightness,
            primaryColor: t.primaryColor,
            isDark: t.isDark,
            createTime: t.createTime,
            lastModified: t.lastModified
          };
          sanitized.push(newTheme);
          j = j + 1;
        }
        this.customThemes = sanitized;
        logger.info(TAG, `已加载并清理 ${this.customThemes.length} 个自定义主题（媒体资源模式）`);
      }
    } catch (error) {
      logger.error(TAG, `加载自定义主题失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 保存自定义主题
   */
  private async saveCustomTheme(theme: CustomTheme): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      
      const themesDir = `${context.filesDir}/custom_themes`;
      const themesFile = `${themesDir}/themes.json`;
      
      // 确保目录存在
      if (!fs.accessSync(themesDir)) {
        fs.mkdirSync(themesDir);
      }
      
      // 添加或更新主题
      const existingIndex = this.customThemes.findIndex(t => t.id === theme.id);
      if (existingIndex >= 0) {
        this.customThemes[existingIndex] = theme;
      } else {
        this.customThemes.push(theme);
      }
      
      // 保存到文件
      const file = fs.openSync(themesFile, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(this.customThemes));
      fs.closeSync(file);
      logger.info(TAG, `已保存自定义主题: ${theme.name}`);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `保存自定义主题失败: ${errorMsg}`);
      throw new Error(`保存自定义主题失败: ${errorMsg}`);
    }
  }

  /**
   * 持久化当前自定义主题列表到文件
   */
  private async persistCustomThemesList(): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      const themesDir: string = `${context.filesDir}/custom_themes`;
      const themesFile: string = `${themesDir}/themes.json`;
      if (!fs.accessSync(themesDir)) {
        fs.mkdirSync(themesDir);
      }
      const file = fs.openSync(themesFile, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, JSON.stringify(this.customThemes));
      fs.closeSync(file);
      logger.info(TAG, '✅ 自定义主题列表已持久化');
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `持久化主题列表失败: ${errorMsg}`);
      throw new Error(`持久化主题列表失败: ${errorMsg}`);
    }
  }

  /**
   * 判断主题是否被选中
   */
  private isThemeSelected(themeId: string): boolean {
    const index: number = this.selectedThemeIds.indexOf(themeId);
    return index >= 0;
  }

  /**
   * 切换主题选择状态（长按/点击）
   */
  private toggleThemeSelection(themeId: string): void {
    if (!this.selectionModeEnabled) {
      this.selectionModeEnabled = true;
    }
    const index: number = this.selectedThemeIds.indexOf(themeId);
    if (index >= 0) {
      // 取消选择
      const newSelected: string[] = [];
      let i: number = 0;
      while (i < this.selectedThemeIds.length) {
        const id: string = this.selectedThemeIds[i];
        if (id !== themeId) {
          newSelected.push(id);
        }
        i = i + 1;
      }
      this.selectedThemeIds = newSelected;
    } else {
      // 添加选择
      const newSelected: string[] = [];
      let j: number = 0;
      while (j < this.selectedThemeIds.length) {
        newSelected.push(this.selectedThemeIds[j]);
        j = j + 1;
      }
      newSelected.push(themeId);
      this.selectedThemeIds = newSelected;
    }
  }

  /**
   * 退出选择模式并清空选择
   */
  private exitSelectionMode(): void {
    this.selectionModeEnabled = false;
    const emptyList: string[] = [];
    this.selectedThemeIds = emptyList;
  }

  /**
   * 删除已选中的自定义主题（含图片文件与列表项）
   */
  private async deleteSelectedThemes(): Promise<void> {
    try {
      if (this.selectedThemeIds.length === 0) {
        logger.warn(TAG, '没有选中的主题可删除');
        return;
      }
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      const themesDir: string = `${context.filesDir}/custom_themes`;

      // 构建保留列表
      const remainThemes: CustomTheme[] = [];
      let idx: number = 0;
      while (idx < this.customThemes.length) {
        const theme: CustomTheme = this.customThemes[idx];
        const selected: boolean = this.isThemeSelected(theme.id);
        if (selected) {
          // 删除关联文件
          if (theme.backgroundImagePath && theme.backgroundImagePath.length > 0 && fs.accessSync(theme.backgroundImagePath)) {
            fs.unlinkSync(theme.backgroundImagePath);
            logger.info(TAG, `已删除浅色背景: ${theme.backgroundImagePath}`);
          }
          if (theme.backgroundImagePathDark && theme.backgroundImagePathDark.length > 0 && fs.accessSync(theme.backgroundImagePathDark)) {
            fs.unlinkSync(theme.backgroundImagePathDark);
            logger.info(TAG, `已删除深色背景: ${theme.backgroundImagePathDark}`);
          } else {
            // 兼容旧版本可能使用文件名约定
            const darkCandidate: string = `${themesDir}/${theme.id}_dark.webp`;
            if (fs.accessSync(darkCandidate)) {
              fs.unlinkSync(darkCandidate);
              logger.info(TAG, `已删除深色背景(兼容路径): ${darkCandidate}`);
            }
          }
          if (theme.splashBackgroundImagePath && theme.splashBackgroundImagePath.length > 0 && fs.accessSync(theme.splashBackgroundImagePath)) {
            fs.unlinkSync(theme.splashBackgroundImagePath);
            logger.info(TAG, `已删除开屏背景: ${theme.splashBackgroundImagePath}`);
          }

          // 若当前激活主题被删除，则清除自定义主题状态
          if (this.currentCustomThemeId === theme.id) {
            await this.themeManager.clearCustomTheme();
            this.currentCustomThemeId = '';
            logger.info(TAG, `当前激活主题已删除，已清除自定义主题状态`);
          }
        } else {
          remainThemes.push(theme);
        }
        idx = idx + 1;
      }

      // 更新内存并持久化
      this.customThemes = remainThemes;
      await this.persistCustomThemesList();
      // 退出选择模式
      this.exitSelectionMode();
      logger.info(TAG, '✅ 已删除选中的自定义主题');
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `删除自定义主题失败: ${errorMsg}`);
    }
  }

  /**
   * 确保默认自定义主题已初始化（首次缺失则创建并写入列表）
   */
  private async ensureDefaultCustomThemeInitialized(): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        logger.error(TAG, '无法获取UIAbilityContext');
        return;
      }
      const themesDir: string = `${context.filesDir}/custom_themes`;
      const themesFile: string = `${themesDir}/themes.json`;

      if (!fs.accessSync(themesDir)) {
        fs.mkdirSync(themesDir);
      }

      // 检查默认主题是否已存在
      let exists: boolean = false;
      let idx: number = 0;
      while (idx < this.customThemes.length) {
        const themeItem: CustomTheme = this.customThemes[idx];
        if (themeItem.id === this.DEFAULT_THEME_ID) {
          exists = true;
          break;
        }
        idx = idx + 1;
      }

      if (exists) {
        logger.debug(TAG, '默认自定义主题已存在，跳过初始化');
        return;
      }

      // 创建默认自定义主题（按设备类型选择 a_* 背景，失败则回退透明）
      const created: CustomTheme = await this.createDefaultCustomTheme();
      await this.saveCustomTheme(created);
      logger.info(TAG, '✅ 默认自定义主题已初始化并写入列表');

      // [修复] 移除自动应用逻辑，避免强制用户使用自定义主题
      // 用户应该主动选择是否使用自定义主题，而不是被动强制应用

      // （移除分支内的第二主题初始化，改为在方法末统一执行）
    } catch (error) {
      logger.error(TAG, `默认主题初始化失败: ${error instanceof Error ? error.message : String(error)}`);
    }
    // 在默认主题流程结束后，确保第二自定义主题也初始化
    await this.ensureSecondaryCustomThemeInitialized();
  }

  /**
   * 生成透明的 WebP 图片，确保图片加载不出错
   */
  private async generateTransparentWebP(imagePath: string, width: number, height: number): Promise<void> {
    const w: number = width > 0 ? width : 16;
    const h: number = height > 0 ? height : 16;
    const bufferSize: number = w * h * 4;
    const rgba: ArrayBuffer = new ArrayBuffer(bufferSize);
    const rgbaView: Uint8Array = new Uint8Array(rgba);
    // 全透明：RGBA = (0,0,0,0)
    let i: number = 0;
    while (i < bufferSize) {
      rgbaView[i] = 0;      // R
      rgbaView[i + 1] = 0;  // G
      rgbaView[i + 2] = 0;  // B
      rgbaView[i + 3] = 0;  // A
      i = i + 4;
    }

    const initOpts: image.InitializationOptions = {
      size: { width: w, height: h },
      pixelFormat: 3, // RGBA_8888
      alphaType: 0,
      editable: false
    };

    const pixelMap: image.PixelMap = await image.createPixelMap(rgba, initOpts);
    const packOpts: image.PackingOption = {
      format: 'image/webp',
      quality: 85
    };

    const imagePacker = image.createImagePacker();
    const file = fs.openSync(imagePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    await imagePacker.packToFile(pixelMap, file.fd, packOpts);
    fs.closeSync(file);
    imagePacker.release();
    pixelMap.release();
  }

  /**
   * 创建默认自定义主题（透明背景），并返回主题对象
   */
  private async createDefaultCustomTheme(): Promise<CustomTheme> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取UIAbilityContext');
    }
    // 改为使用媒体资源（app.media.a_*）进行显示，不再复制rawfile到文件目录
    // 为保持现有存储结构与类型安全，路径字段置为空字符串，显示层通过资源回退逻辑加载媒体资源
    const now: number = Date.now();
    const primaryColor: string = THEME_CONFIGS[ThemeType.LIGHT].primaryColor;
    const created: CustomTheme = {
      id: this.DEFAULT_THEME_ID,
      name: this.DEFAULT_THEME_NAME,
      backgroundImagePath: '',
      backgroundImagePathDark: '',
      splashBackgroundImagePath: '',
      blurLevel: 0,
      brightness: 50,
      primaryColor: primaryColor,
      isDark: false,
      createTime: now,
      lastModified: now
    };
    return created;
  }

  /**
   * 确保第二自定义主题已存在；不存在则按设备类型创建（b_* 背景）
   */
  private async ensureSecondaryCustomThemeInitialized(): Promise<void> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      logger.error(TAG, '无法获取UIAbilityContext');
      return;
    }
    const themesDir: string = `${context.filesDir}/custom_themes`;
    if (!fs.accessSync(themesDir)) {
      fs.mkdirSync(themesDir);
    }

    // 检查是否已存在
    let exists: boolean = false;
    let i: number = 0;
    while (i < this.customThemes.length) {
      const t: CustomTheme = this.customThemes[i];
      if (t.id === this.SECONDARY_THEME_ID) {
        exists = true;
        break;
      }
      i = i + 1;
    }
    if (exists) {
      logger.debug(TAG, '第二自定义主题已存在，跳过创建');
      return;
    }

    // 改为使用媒体资源（app.media.b_*）进行显示，不再复制rawfile到文件目录
    const now: number = Date.now();
    const primaryColor: string = THEME_CONFIGS[ThemeType.LIGHT].primaryColor;
    const created: CustomTheme = {
      id: this.SECONDARY_THEME_ID,
      name: this.SECONDARY_THEME_NAME,
      backgroundImagePath: '',
      backgroundImagePathDark: '',
      splashBackgroundImagePath: '',
      blurLevel: 0,
      brightness: 50,
      primaryColor: primaryColor,
      isDark: false,
      createTime: now,
      lastModified: now
    };
    await this.saveCustomTheme(created);
    logger.info(TAG, '✅ 已创建第二自定义主题（媒体资源 b_*）并写入列表');
  }

  /**
   * 恢复默认自定义主题：若被删除则重新创建并自动应用
   */
  private async restoreDefaultCustomTheme(): Promise<void> {
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      const themesDir: string = `${context.filesDir}/custom_themes`;
      const themesFile: string = `${themesDir}/themes.json`;
      if (!fs.accessSync(themesDir)) {
        fs.mkdirSync(themesDir);
      }

      // 查找默认主题
      let index: number = -1;
      let i: number = 0;
      while (i < this.customThemes.length) {
        if (this.customThemes[i].id === this.DEFAULT_THEME_ID) {
          index = i;
          break;
        }
        i = i + 1;
      }

      let targetTheme: CustomTheme | null = null;
      if (index >= 0) {
        // 已存在，直接应用（背景路径可能为空，由显示层采用媒体资源回退）
        targetTheme = this.customThemes[index];
      } else {
        // 不存在则创建（媒体资源模式）
        const created: CustomTheme = await this.createDefaultCustomTheme();
        await this.saveCustomTheme(created);
        targetTheme = created;
      }

      if (targetTheme) {
        await this.applyCustomThemeToManager(targetTheme, '');
        logger.info(TAG, '✅ 已恢复并应用默认自定义主题（媒体资源模式）');
      }
    } catch (error) {
      const errorMsg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `恢复默认主题失败: ${errorMsg}`);
    }
  }

  /**
   * 选择图片
   */
  private async selectImage(): Promise<void> {
    try {
      logger.info(TAG, '开始选择图片');
      
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      
      const photoSelectOptions: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };
      
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select(photoSelectOptions);
      
      if (result && result.photoUris && result.photoUris.length > 0) {
        const imageUri = result.photoUris[0];
        logger.info(TAG, `已选择图片: ${imageUri}`);
        
        await this.loadAndProcessImage(imageUri);
      }
    } catch (error) {
      logger.error(TAG, `选择图片失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 加载并处理图片
   */
  private async loadAndProcessImage(imageUri: string): Promise<void> {
    this.isProcessing = true;
    this.processingMessage = '正在加载图片...';
    this.processingProgress = 10;
    
    try {
      // 打开图片文件
      const file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      const imageSource = image.createImageSource(file.fd);
      
      // 获取图片信息
      const imageInfo = await imageSource.getImageInfo();
      logger.info(TAG, `图片尺寸: ${imageInfo.size.width}x${imageInfo.size.height}`);
      
      this.processingProgress = 30;
      this.processingMessage = '正在准备裁剪...';
      
      // 计算目标尺寸（使用720p分辨率，足够用于背景且文件小）
      // 使用较小的分辨率可以显著减小文件大小，提升性能
      const maxWidth = 720;
      const maxHeight = 1280;
      const targetSize = this.calculateTargetSize(
        imageInfo.size.width,
        imageInfo.size.height,
        maxWidth,
        maxHeight
      );
      const targetWidth = targetSize.targetWidth;
      const targetHeight = targetSize.targetHeight;
      
      logger.info(TAG, `目标尺寸: ${targetWidth}x${targetHeight}`);
      
      // 解码并缩放图片（不立即裁剪，进入裁剪阶段）
      const decodingOptions: image.DecodingOptions = {
        desiredSize: { width: targetWidth, height: targetHeight },
        desiredPixelFormat: 3 // RGBA_8888
      };
      
      const decodedPixelMap = await imageSource.createPixelMap(decodingOptions);
      this.selectedImagePixelMap = decodedPixelMap;
      this.selectedImagePath = imageUri;
      
      fs.closeSync(file);
      imageSource.release();
      
      // 直接进行主色调提取（不进入自定义裁剪阶段）
      this.processingProgress = 60;
      this.processingMessage = '正在提取主色调...';
      await this.extractDominantColor(this.selectedImagePixelMap);
      
      // 复制原图作为处理结果（默认无效果）
      this.processingProgress = 80;
      this.processingMessage = '正在准备预览...';
      await this.copyOriginalToProcessed();
      
      this.isCropping = false;
      this.processingProgress = 100;
      this.processingMessage = '图片已准备就绪';
      
      setTimeout(() => {
        this.isProcessing = false;
      }, 300);
      
    } catch (error) {
      logger.error(TAG, `处理图片失败: ${error instanceof Error ? error.message : String(error)}`);
      this.isProcessing = false;
      this.processingMessage = '处理失败';
    }
  }

  /**
   * 应用裁剪（用户确认裁剪后执行），随后进行主色提取与效果预处理
   */
  private async applyCrop(): Promise<void> {
    if (!this.selectedImagePixelMap) {
      logger.error(TAG, 'applyCrop: selectedImagePixelMap为空');
      return;
    }
    try {
      this.isProcessing = true;
      this.processingMessage = '正在裁剪图片...';
      this.processingProgress = 40;

      const cropped = await cropToDisplayAspectWithOptions(this.selectedImagePixelMap, this.cropAlignment, this.cropZoom);
      // 释放旧像素图
      this.selectedImagePixelMap.release();
      this.selectedImagePixelMap = cropped;

      this.processingProgress = 70;
      this.processingMessage = '正在提取主色调...';
      await this.extractDominantColor(this.selectedImagePixelMap);

      this.processingProgress = 90;
      this.processingMessage = '正在应用预览效果...';
      await this.applyImageEffects();

      this.isCropping = false;
      this.processingProgress = 100;
      this.processingMessage = '裁剪完成';

      setTimeout(() => { this.isProcessing = false; }, 300);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `应用裁剪失败: ${msg}`);
      this.isProcessing = false;
    }
  }

  /**
   * 预览裁剪效果（不修改原图，仅生成预览处理结果）
   */
  private async previewCrop(): Promise<void> {
    if (!this.selectedImagePixelMap) {
      logger.error(TAG, 'previewCrop: selectedImagePixelMap为空');
      return;
    }
    try {
      this.isProcessing = true;
      this.processingMessage = '正在预览裁剪效果...';
      this.processingProgress = 30;
      const cropped = await cropToDisplayAspectWithOptions(this.selectedImagePixelMap, this.cropAlignment, this.cropZoom);
      // 释放旧的预览处理结果
      if (this.processedImagePixelMap) {
        this.processedImagePixelMap.release();
      }
      this.processedImagePixelMap = cropped;
      this.processingProgress = 70;
      await this.applyImageEffects();
      this.processingProgress = 100;
      this.processingMessage = '裁剪预览完成';
      setTimeout(() => { this.isProcessing = false; }, 200);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `预览裁剪失败: ${msg}`);
      this.isProcessing = false;
    }
  }

  /**
   * 选择开屏图片
   */
  private async selectSplashImage(): Promise<void> {
    try {
      logger.info(TAG, '开始选择开屏图片');
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }

      const photoSelectOptions: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };

      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select(photoSelectOptions);

      if (result && result.photoUris && result.photoUris.length > 0) {
        const imageUri = result.photoUris[0];
        logger.info(TAG, `已选择开屏图片: ${imageUri}`);
        await this.loadAndProcessSplashImage(imageUri);
      }
    } catch (error) {
      logger.error(TAG, `选择开屏图片失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 加载并处理开屏图片（仅裁剪到设备比例）
   */
  private async loadAndProcessSplashImage(imageUri: string): Promise<void> {
    this.isProcessing = true;
    this.processingMessage = '正在加载开屏图片...';
    this.processingProgress = 10;

    try {
      const file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      const imageSource = image.createImageSource(file.fd);
      const imageInfo = await imageSource.getImageInfo();
      logger.info(TAG, `开屏图片尺寸: ${imageInfo.size.width}x${imageInfo.size.height}`);

      this.processingProgress = 40;
      this.processingMessage = '正在裁剪开屏图片...';

      const maxWidth = 1080; // 开屏图片保存更高分辨率以保证品质
      const maxHeight = 1920;
      const targetSize = this.calculateTargetSize(imageInfo.size.width, imageInfo.size.height, maxWidth, maxHeight);
      const decodingOptions: image.DecodingOptions = {
        desiredSize: { width: targetSize.targetWidth, height: targetSize.targetHeight },
        desiredPixelFormat: 3
      };

      const decodedPixelMap = await imageSource.createPixelMap(decodingOptions);
      const cropped = await cropToDisplayAspect(decodedPixelMap);
      decodedPixelMap.release();

      // 保存状态
      this.selectedSplashImagePixelMap = cropped;
      this.selectedSplashImagePath = imageUri;

      // 预览使用处理后的（裁剪）像素图
      this.processedSplashImagePixelMap = cropped;
      this.processedSplashImagePath = imageUri;

      this.processingProgress = 100;
      this.processingMessage = '开屏图片处理完成';

      fs.closeSync(file);
      imageSource.release();
      setTimeout(() => { this.isProcessing = false; }, 300);
    } catch (error) {
      logger.error(TAG, `处理开屏图片失败: ${error instanceof Error ? error.message : String(error)}`);
      this.isProcessing = false;
      this.processingMessage = '开屏图片处理失败';
    }
  }

  /**
   * 计算目标尺寸（保持宽高比，适配到最大尺寸内）
   */
  private calculateTargetSize(
    srcWidth: number,
    srcHeight: number,
    maxWidth: number,
    maxHeight: number
  ): TargetSize {
    // 计算缩放比例，确保图片完全适配到最大尺寸内
    const widthScale = maxWidth / srcWidth;
    const heightScale = maxHeight / srcHeight;
    
    // 取较小的缩放比例，确保图片不超出边界
    const scale = Math.min(widthScale, heightScale, 1.0); // 最大1.0，避免放大
    
    const resultWidth = Math.round(srcWidth * scale);
    const resultHeight = Math.round(srcHeight * scale);
    
    const result: TargetSize = {
      targetWidth: resultWidth,
      targetHeight: resultHeight
    };
    return result;
  }

  /**
   * 提取主色调
   * 使用effectKit的ColorPicker硬件加速，避免手动像素处理导致ANR
   */
  private async extractDominantColor(pixelMap: image.PixelMap): Promise<void> {
    try {
      logger.info(TAG, '开始提取主色调（使用effectKit）');
      
      // 使用effectKit的ColorPicker提取主色调
      // createColorPicker返回Promise<ColorPicker>
      const colorPicker = await effectKit.createColorPicker(pixelMap);
      
      // getMainColorSync 返回一个Promise<Color>
      const mainColor = await colorPicker.getMainColorSync();
      
      // Color对象包含red, green, blue, alpha属性（0-255）
      const r = mainColor.red;
      const g = mainColor.green;
      const b = mainColor.blue;
      
      logger.info(TAG, `提取的原始颜色: RGB(${r}, ${g}, ${b})`);
      
      // 增强饱和度
      const enhancedColor = this.enhanceSaturation(r, g, b, 1.3);
      const enhancedR = enhancedColor.r;
      const enhancedG = enhancedColor.g;
      const enhancedB = enhancedColor.b;
      
      this.extractedColor = `#${this.toHex(enhancedR)}${this.toHex(enhancedG)}${this.toHex(enhancedB)}`;
      this.extractedColorRGB = `RGB(${enhancedR}, ${enhancedG}, ${enhancedB})`;
      
      logger.info(TAG, `提取的主色调（增强后）: ${this.extractedColor}`);

      // 将提取色加入可选主题色并默认选中（避免重复添加）
      const hasColor: boolean = this.availablePrimaryColors.includes(this.extractedColor);
      if (!hasColor) {
        const updatedColors: string[] = [];
        let idx: number = 0;
        while (idx < this.availablePrimaryColors.length) {
          updatedColors.push(this.availablePrimaryColors[idx]);
          idx = idx + 1;
        }
        updatedColors.push(this.extractedColor);
        this.availablePrimaryColors = updatedColors;
      }
      this.selectedPrimaryColor = this.extractedColor;
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `提取主色调失败: ${errorMsg}`);
      
      // 失败时使用默认颜色
      this.extractedColor = '#6200EE';
      this.extractedColorRGB = 'RGB(98, 0, 238)';
      
      // 不再抛出错误，避免中断流程
      logger.warn(TAG, '已使用默认主色调继续处理');
    }
  }

  /**
   * 增强饱和度
   */
  private enhanceSaturation(r: number, g: number, b: number, factor: number): RGBColor {
    // 转换到HSV
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const delta = max - min;
    
    if (delta === 0) {
      const result: RGBColor = { r, g, b }; // 灰色，无需增强
      return result;
    }
    
    const saturation = delta / max;
    const newSaturation = Math.min(1, saturation * factor);
    
    const scale = newSaturation / saturation;
    const gray = (r + g + b) / 3;
    
    const result: RGBColor = {
      r: Math.round(Math.max(0, Math.min(255, gray + (r - gray) * scale))),
      g: Math.round(Math.max(0, Math.min(255, gray + (g - gray) * scale))),
      b: Math.round(Math.max(0, Math.min(255, gray + (b - gray) * scale)))
    };
    return result;
  }

  /**
   * 转换为十六进制
   */
  private toHex(value: number): string {
    const hex = value.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  }

  /**
   * 解析十六进制颜色字符串为RGB
   */
  private parseHexColorToRGB(hexColor: string): RGBColor {
    let clean: string = hexColor;
    if (hexColor.startsWith('#')) {
      clean = hexColor.substring(1);
    }
    if (clean.length !== 6) {
      // 默认返回系统强调色近似值
      return { r: 98, g: 0, b: 238 } as RGBColor;
    }
    const rHex: string = clean.substring(0, 2);
    const gHex: string = clean.substring(2, 4);
    const bHex: string = clean.substring(4, 6);
    const rVal: number = parseInt(rHex, 16);
    const gVal: number = parseInt(gHex, 16);
    const bVal: number = parseInt(bHex, 16);
    const result: RGBColor = { r: rVal, g: gVal, b: bVal } as RGBColor;
    return result;
  }

  /**
   * 获取裁剪对齐方式的显示标签
   */
  private getCropAlignmentLabel(): string {
    switch (this.cropAlignment) {
      case CropAlignment.TOP_LEFT:
        return '左上';
      case CropAlignment.TOP:
        return '顶部居中';
      case CropAlignment.TOP_RIGHT:
        return '右上';
      case CropAlignment.CENTER_LEFT:
        return '左侧居中';
      case CropAlignment.CENTER:
        return '居中';
      case CropAlignment.CENTER_RIGHT:
        return '右侧居中';
      case CropAlignment.BOTTOM_LEFT:
        return '左下';
      case CropAlignment.BOTTOM:
        return '底部居中';
      case CropAlignment.BOTTOM_RIGHT:
        return '右下';
      default:
        return '居中';
    }
  }

  /**
   * 复制原图到处理结果（用于默认无效果模式）
   */
  private async copyOriginalToProcessed(): Promise<void> {
    if (!this.selectedImagePixelMap) {
      return;
    }
    
    try {
      // 释放旧的处理结果
      if (this.processedImagePixelMap) {
        this.processedImagePixelMap.release();
        this.processedImagePixelMap = null;
      }
      
      // 获取原图信息
      const imageInfo = await this.selectedImagePixelMap.getImageInfo();
      const width = imageInfo.size.width;
      const height = imageInfo.size.height;
      
      // 复制原图像素数据
      // readPixelsToBuffer 返回 BGRA 格式，需要转换为 RGBA
      const buffer = new ArrayBuffer(width * height * 4);
      await this.selectedImagePixelMap.readPixelsToBuffer(buffer);
      
      // BGRA -> RGBA：交换 R 和 B 通道
      const pixels = new Uint8Array(buffer);
      for (let i = 0; i < pixels.length; i += 4) {
        const b = pixels[i];     // BGRA 中第一个是 B
        const r = pixels[i + 2]; // BGRA 中第三个是 R
        pixels[i] = r;           // 设为 R
        pixels[i + 2] = b;       // 设为 B
      }
      
      // 创建新的 PixelMap（RGBA 格式）
      const createOptions: image.InitializationOptions = {
        size: { width: width, height: height },
        pixelFormat: 3, // RGBA_8888
        alphaType: 0,
        editable: true
      };
      
      this.processedImagePixelMap = await image.createPixelMap(buffer, createOptions);
      logger.info(TAG, `✅ 原图已复制到预览 (size=${width}x${height})`);
    } catch (error) {
      logger.error(TAG, `复制原图失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 防抖应用图片效果
   * 用于滑块调节时避免频繁触发
   */
  private applyImageEffectsDebounced(): void {
    // 清除之前的定时器
    if (this.effectDebounceTimer !== -1) {
      clearTimeout(this.effectDebounceTimer);
    }
    
    // 设置新的定时器，300ms后执行
    this.effectDebounceTimer = setTimeout(() => {
      this.applyImageEffects();
      this.effectDebounceTimer = -1;
    }, 300);
  }

  /**
   * 应用图片效果（模糊和压暗）
   * 使用effectKit硬件加速的模糊效果，避免CPU密集型处理导致ANR
   */
  private async applyImageEffects(): Promise<void> {
    if (!this.selectedImagePixelMap) {
      return;
    }
    
    try {
      logger.info(TAG, `开始应用图片效果: 模糊=${this.blurLevel}, 亮度=${this.brightnessLevel}`);
      
      // 如果没有需要应用的效果（模糊为0且亮度为50），直接复制原图
      if (this.blurLevel === 0 && this.brightnessLevel === 50) {
        await this.copyOriginalToProcessed();
        logger.info(TAG, '✅ 无需应用效果，使用原图');
        return;
      }
      
      // 获取原图信息
      const imageInfo = await this.selectedImagePixelMap.getImageInfo();
      const width = imageInfo.size.width;
      const height = imageInfo.size.height;
      
      // 1. 复制原图作为工作副本（避免修改原图）
      const buffer = new ArrayBuffer(width * height * 4);
      await this.selectedImagePixelMap.readPixelsToBuffer(buffer);
      
      // BGRA -> RGBA：交换 R 和 B 通道（readPixelsToBuffer 返回 BGRA 格式）
      const pixelsBgra = new Uint8Array(buffer);
      for (let swapIdx = 0; swapIdx < pixelsBgra.length; swapIdx += 4) {
        const bChannel = pixelsBgra[swapIdx];
        const rChannel = pixelsBgra[swapIdx + 2];
        pixelsBgra[swapIdx] = rChannel;
        pixelsBgra[swapIdx + 2] = bChannel;
      }
      
      // 2. 创建可编辑的PixelMap用于应用效果（RGBA 格式）
      const createOptions: image.InitializationOptions = {
        size: { width: width, height: height },
        pixelFormat: 3, // RGBA_8888
        alphaType: 0,
        editable: true // 必须设置为可编辑，才能使用effectKit
      };
      
      let workingPixelMap = await image.createPixelMap(buffer, createOptions);
      
      // 3. 应用亮度变暗（在 effectKit 处理之前，避免格式问题）
      // 此时 workingPixelMap 是我们自己创建的 RGBA 格式，可以安全操作
      if (this.brightnessLevel < 50) {
        // 0-49%: 手动像素处理变暗（在原始 buffer 上操作）
        // 映射: 0% → 0.0, 49% → 0.98, 50% → 1.0
        const darknessFactor = this.brightnessLevel / 50;
        logger.info(TAG, `应用亮度降低，因子=${darknessFactor}`);
        
        // 直接在已转换为 RGBA 的 buffer 上操作
        const pixels = new Uint8Array(buffer);
        for (let i = 0; i < pixels.length; i += 4) {
          pixels[i] = Math.round(pixels[i] * darknessFactor);
          pixels[i + 1] = Math.round(pixels[i + 1] * darknessFactor);
          pixels[i + 2] = Math.round(pixels[i + 2] * darknessFactor);
        }
        
        // 重新创建 PixelMap
        workingPixelMap.release();
        workingPixelMap = await image.createPixelMap(buffer, createOptions);
        logger.info(TAG, '✅ 亮度降低完成');
      }
      
      // 4. 应用模糊效果（使用effectKit硬件加速）
      if (this.blurLevel > 0) {
        const filter = effectKit.createEffect(workingPixelMap);
        if (filter) {
          const blurRadius = Math.round(this.blurLevel * 0.3);
          logger.info(TAG, `应用模糊效果，半径=${blurRadius}`);
          filter.blur(blurRadius);
          const blurredPixelMap = await filter.getPixelMap();
          workingPixelMap.release();
          workingPixelMap = blurredPixelMap;
          logger.info(TAG, '✅ 模糊效果应用完成');
        }
      }
      
      // 5. 应用亮度增加（使用 effectKit）
      if (this.brightnessLevel > 50) {
        // 51-100%: 使用 effectKit.brightness 增亮
        // effectKit.brightness: 0=原始, 1=最亮
        // 映射: 51% → 0.02, 100% → 1.0
        const brightnessFactor = (this.brightnessLevel - 50) / 50;
        logger.info(TAG, `应用亮度增加，因子=${brightnessFactor}`);
        const filter = effectKit.createEffect(workingPixelMap);
        if (filter) {
          filter.brightness(brightnessFactor);
          const brighterPixelMap = await filter.getPixelMap();
          workingPixelMap.release();
          workingPixelMap = brighterPixelMap;
          logger.info(TAG, '✅ 亮度增加完成');
        }
      }
      
      // 5. 释放旧的处理结果，保存新的处理结果
      if (this.processedImagePixelMap) {
        this.processedImagePixelMap.release();
      }
      
      this.processedImagePixelMap = workingPixelMap;
      
      logger.info(TAG, '✅ 图片效果应用完成');
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `应用图片效果失败: ${errorMsg}`);
      
      // 失败时直接复制原图
      if (this.selectedImagePixelMap && !this.processedImagePixelMap) {
        try {
          const imageInfo = await this.selectedImagePixelMap.getImageInfo();
          const buffer = new ArrayBuffer(imageInfo.size.width * imageInfo.size.height * 4);
          await this.selectedImagePixelMap.readPixelsToBuffer(buffer);
          
          // BGRA -> RGBA 转换
          const fallbackPixels = new Uint8Array(buffer);
          for (let fi = 0; fi < fallbackPixels.length; fi += 4) {
            const fb = fallbackPixels[fi];
            const fr = fallbackPixels[fi + 2];
            fallbackPixels[fi] = fr;
            fallbackPixels[fi + 2] = fb;
          }
          
          const createOptions: image.InitializationOptions = {
            size: imageInfo.size,
            pixelFormat: 3, // RGBA_8888
            alphaType: 0
          };
          
          this.processedImagePixelMap = await image.createPixelMap(buffer, createOptions);
          logger.info(TAG, '已使用原图作为备用处理结果');
        } catch (fallbackError) {
          logger.error(TAG, `备用处理也失败: ${fallbackError instanceof Error ? fallbackError.message : String(fallbackError)}`);
        }
      }
    }
  }

  /**
   * 计算亮度调整比例（保持色相）
   * @param currentLuminance 当前像素的感知亮度
   * @param brightnessFactor 亮度调整因子
   * @returns 调整比例
   */
  private calculateBrightnessAdjustment(currentLuminance: number, brightnessFactor: number): number {
    // 对于暗部和亮部采用不同的调整策略
    if (brightnessFactor < 1.0) {
      // 变暗：使用线性调整，但对暗部保留更多细节
      return brightnessFactor * (0.5 + 0.5 * (currentLuminance / 255));
    } else {
      // 变亮：使用非线性调整，避免过度曝光
      const delta = brightnessFactor - 1.0;
      const headroom = (255 - currentLuminance) / 255;
      return 1.0 + delta * headroom * 0.8;
    }
  }

  /**
   * 保存并应用当前主题
   * 保存两张图片：浅色模式（原亮度）和深色模式（降低亮度）
   */
  private async saveAndApplyTheme(): Promise<void> {
    if (!this.selectedImagePixelMap) {
      logger.error(TAG, '没有可保存的主题');
      return;
    }
    
    try {
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取UIAbilityContext');
      }
      
      this.isProcessing = true;
      this.processingMessage = '正在保存主题...';
      this.processingProgress = 0;
      
      // 创建主题目录
      const themesDir = `${context.filesDir}/custom_themes`;
      if (!fs.accessSync(themesDir)) {
        fs.mkdirSync(themesDir);
      }
      
      const themeId = `theme_${Date.now()}`;
      
      // 1. 生成浅色模式图片（使用用户设置的亮度+模糊）
      this.processingMessage = '正在生成浅色模式图片...';
      this.processingProgress = 20;
      const lightImagePath = await this.generateThemeImage(themeId, 'light', this.blurLevel, this.brightnessLevel);
      
      // 2. 生成深色模式图片（在用户设置基础上降低亮度）
      this.processingMessage = '正在生成深色模式图片...';
      this.processingProgress = 60;
      const darkBrightness = Math.max(10, Math.min(40, this.brightnessLevel - 20)); // 比当前亮度低20%，范围10-40
      const darkImagePath = await this.generateThemeImage(themeId, 'dark', this.blurLevel, darkBrightness);

      // 生成开屏图片（如果已选择）
      let splashImagePath: string = '';
      if (this.selectedSplashImagePixelMap) {
        this.processingMessage = '正在生成开屏图片...';
        this.processingProgress = 80;
        splashImagePath = await this.generateSplashImage(themeId);
      }
      
      // 3. 创建主题对象
      this.processingMessage = '正在保存主题信息...';
      this.processingProgress = 90;
      const themeName: string = this.normalizeThemeName();
      const primaryColorToUse: string = this.selectedPrimaryColor && this.selectedPrimaryColor.length > 0 ? this.selectedPrimaryColor : this.extractedColor;
      const customTheme: CustomTheme = {
        id: themeId,
        name: themeName,
        backgroundImagePath: lightImagePath,
        backgroundImagePathDark: darkImagePath,
        splashBackgroundImagePath: splashImagePath,
        blurLevel: this.blurLevel,
        brightness: this.brightnessLevel,
        primaryColor: primaryColorToUse,
        isDark: this.themeState.currentTheme === ThemeType.DARK,
        createTime: Date.now(),
        lastModified: Date.now()
      };
      
      await this.saveCustomTheme(customTheme);
      
      logger.info(TAG, `主题已保存: ${customTheme.name}`);
      logger.info(TAG, `  浅色模式图片: ${lightImagePath}`);
      logger.info(TAG, `  深色模式图片: ${darkImagePath}`);
      
      // 应用主题到应用
      await this.applyCustomThemeToManager(customTheme, splashImagePath);
      
      this.processingMessage = '主题保存成功！';
      this.processingProgress = 100;
      logger.info(TAG, `✅ 自定义主题已应用，将在所有页面生效`);
      
      // 显示Toast并自动返回
      setTimeout(() => {
        this.isProcessing = false;
        // 显示成功提示
        promptAction.showToast({
          message: '主题已保存并应用',
          duration: 2000
        });
        // 延迟返回上一页
        setTimeout(() => {
          this.goBack();
        }, 500);
      }, 800);
      
    } catch (error) {
      this.isProcessing = false;
      logger.error(TAG, `保存主题失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 标准化主题名称：若未输入则生成“自定义主题N”且避免重名
   */
  private normalizeThemeName(): string {
    const inputName: string = this.newThemeName ? this.newThemeName.trim() : '';
    if (inputName.length > 0) {
      return inputName;
    }
    let index: number = 1;
    while (true) {
      const candidate: string = '自定义主题 ' + index.toString();
      let exists: boolean = false;
      let i: number = 0;
      while (i < this.customThemes.length) {
        if (this.customThemes[i].name === candidate) {
          exists = true;
          break;
        }
        i = i + 1;
      }
      if (!exists) {
        return candidate;
      }
      index = index + 1;
    }
  }

  /**
   * 生成主题图片（模糊+亮度调整）
   * @param themeId 主题ID
   * @param mode 模式（light/dark）
   * @param blurLevel 模糊程度
   * @param brightness 亮度（0-100）
   * @returns 生成的图片路径
   */
  private async generateThemeImage(themeId: string, mode: string, blurLevel: number, brightness: number): Promise<string> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取UIAbilityContext');
    }
    if (!this.selectedImagePixelMap) {
      throw new Error('selectedImagePixelMap为null');
    }
    
    const themesDir = `${context.filesDir}/custom_themes`;
    const imagePath = `${themesDir}/${themeId}_${mode}.webp`;
    
    // 获取原图信息
    const imageInfo = await this.selectedImagePixelMap.getImageInfo();
    const width = imageInfo.size.width;
    const height = imageInfo.size.height;
    
    // 1. 复制原图并转换格式
    const buffer = new ArrayBuffer(width * height * 4);
    await this.selectedImagePixelMap.readPixelsToBuffer(buffer);
    
    // BGRA -> RGBA：交换 R 和 B 通道（readPixelsToBuffer 返回 BGRA 格式）
    const pixelsConvert = new Uint8Array(buffer);
    for (let idx = 0; idx < pixelsConvert.length; idx += 4) {
      const bVal = pixelsConvert[idx];
      const rVal = pixelsConvert[idx + 2];
      pixelsConvert[idx] = rVal;
      pixelsConvert[idx + 2] = bVal;
    }
    
    // 使用 RGBA_8888 格式创建 PixelMap
    const createOptions: image.InitializationOptions = {
      size: { width: width, height: height },
      pixelFormat: 3, // RGBA_8888
      alphaType: 0,
      editable: true
    };
    
    let workingPixelMap = await image.createPixelMap(buffer, createOptions);
    
    // 2. 应用亮度变暗（在 effectKit 处理之前）
    if (brightness < 50) {
      const darknessFactor = brightness / 50;
      const pixels = new Uint8Array(buffer);
      for (let i = 0; i < pixels.length; i += 4) {
        pixels[i] = Math.round(pixels[i] * darknessFactor);
        pixels[i + 1] = Math.round(pixels[i + 1] * darknessFactor);
        pixels[i + 2] = Math.round(pixels[i + 2] * darknessFactor);
      }
      workingPixelMap.release();
      workingPixelMap = await image.createPixelMap(buffer, createOptions);
    }
    
    // 3. 应用模糊效果
    if (blurLevel > 0) {
      const filter = effectKit.createEffect(workingPixelMap);
      if (filter) {
        const blurRadius = Math.round(blurLevel * 0.3);
        filter.blur(blurRadius);
        const blurredPixelMap = await filter.getPixelMap();
        workingPixelMap.release();
        workingPixelMap = blurredPixelMap;
      }
    }
    
    // 4. 应用亮度增加
    if (brightness > 50) {
      const brightnessFactor = (brightness - 50) / 50;
      const filter = effectKit.createEffect(workingPixelMap);
      if (filter) {
        filter.brightness(brightnessFactor);
        const brighterPixelMap = await filter.getPixelMap();
        workingPixelMap.release();
        workingPixelMap = brighterPixelMap;
      }
    }
    
    // 4. 保存为WebP格式（最优压缩和质量）
    const packOpts: image.PackingOption = {
      format: 'image/webp',
      quality: 85 // WebP质量85可以获得极小的文件体积和优秀的视觉质量
    };
    
    try {
      const imagePacker = image.createImagePacker();
      const file = fs.openSync(imagePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      await imagePacker.packToFile(workingPixelMap, file.fd, packOpts);
      fs.closeSync(file);
      imagePacker.release();
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `保存图片失败: ${errorMsg}`);
      throw new Error(`保存图片失败: ${errorMsg}`);
    } finally {
      workingPixelMap.release();
    }
    
    logger.info(TAG, `✅ 生成${mode}模式图片: ${imagePath}`);
    
    return imagePath;
  }

  /**
   * 生成开屏图片（仅打包裁剪后的像素图）
   */
  private async generateSplashImage(themeId: string): Promise<string> {
    const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
    if (!context) {
      throw new Error('无法获取UIAbilityContext');
    }
    if (!this.selectedSplashImagePixelMap) {
      throw new Error('selectedSplashImagePixelMap为null');
    }

    const themesDir = `${context.filesDir}/custom_themes`;
    const imagePath = `${themesDir}/${themeId}_splash.webp`;

    const packOpts: image.PackingOption = {
      format: 'image/webp',
      quality: 85
    };

    try {
      const imagePacker = image.createImagePacker();
      const file = fs.openSync(imagePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      await imagePacker.packToFile(this.selectedSplashImagePixelMap, file.fd, packOpts);
      fs.closeSync(file);
      imagePacker.release();
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `保存开屏图片失败: ${errorMsg}`);
      throw new Error(`保存开屏图片失败: ${errorMsg}`);
    }

    logger.info(TAG, `✅ 生成开屏图片: ${imagePath}`);
    return imagePath;
  }

  /**
   * 应用自定义主题到ThemeManager
   * 辅助方法，用于调用ThemeManager的applyCustomTheme方法
   */
  private async applyCustomThemeToManager(theme: CustomTheme, splashImagePath: string): Promise<void> {
    try {
      logger.info(TAG, `开始应用自定义主题: ${theme.name}`);
      // 不强制切换应用主题；保持当前主题设置（含AUTO），由ThemeManager按系统深浅切换背景
      
      // 调用ThemeManager统一应用（包含开屏背景路径）
      const themeData: CustomThemeData = {
        id: theme.id,
        name: theme.name,
        backgroundImagePath: theme.backgroundImagePath,
        backgroundImagePathDark: theme.backgroundImagePathDark,
        splashBackgroundImagePath: theme.splashBackgroundImagePath ? theme.splashBackgroundImagePath : splashImagePath,
        blurLevel: theme.blurLevel,
        primaryColor: theme.primaryColor,
        isDark: theme.isDark,
        createTime: theme.createTime,
        lastModified: theme.lastModified
      };
      await this.themeManager.applyCustomTheme(themeData);
      
      logger.info(TAG, `✅ 自定义主题应用成功（含开屏图）: ${theme.name}`);
      logger.info(TAG, `   背景图片: ${theme.backgroundImagePath}`);
      logger.info(TAG, `   深色背景: ${theme.backgroundImagePathDark}`);
      if (splashImagePath && splashImagePath.length > 0) {
        logger.info(TAG, `   开屏图片: ${splashImagePath}`);
      }
      logger.info(TAG, `   主色调: ${theme.primaryColor}`);
      logger.info(TAG, `   当前显示主题: ${this.themeManager.getActualThemeSync()}`);
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `应用自定义主题失败: ${errorMsg}`);
      throw new Error(`应用自定义主题失败: ${errorMsg}`);
    }
  }

  /**
   * 返回上一页
   */
  private goBack(): void {
    this.pathStack.pop();
  }

  /**
   * 显示删除确认对话框（使用系统组件）
   */
  private showDeleteConfirmDialogSystem(): void {
    if (!this.uiContext) {
      logger.warn(TAG, 'UIContext 未初始化，无法显示删除确认对话框');
      return;
    }
    
    this.uiContext.getPromptAction().showDialog({
      title: '确认删除',
      message: `确定要删除选中的 ${this.selectedThemeIds.length} 个主题吗？\n此操作不可撤销，相关的背景图片文件也将被删除。`,
      buttons: [
        { text: '取消', color: '#999999' },
        { text: '删除', color: '#FF3B30' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.deleteSelectedThemes();
      }
    }).catch((err: Error) => {
      logger.error(TAG, `显示删除确认对话框失败: ${err.message}`);
    });
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        Column() {
          // 预留标题栏占位（与 HdsNavDestination 标题栏高度一致）
          Blank().height(56)

          // 内容区域
          Scroll() {
            Column({ space: 16 }) {
              // 主题商店（列表 + 创建入口）
              if (!this.isCreatingCustomTheme) {
                Column({ space: 12 }) {
                  Text('自定义主题')
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .width('100%')

                  if (this.customThemes.length > 0) {
                    Grid() {
                      ForEach(this.customThemes, (theme: CustomTheme) => {
                        GridItem() {
                          Column() {
                            // 主题背景图片预览 - 显示缩略图或占位符
                            Stack() {
                              if (theme.backgroundImagePath && theme.backgroundImagePath.length > 0) {
                                Image('file://' + theme.backgroundImagePath)
                                  .width('100%')
                                  .height(120)
                                  .objectFit(ImageFit.Cover)
                                  .borderRadius(12)
                                  .syncLoad(true)
                              } else {
                                // 无背景图片时显示主题色渐变占位符
                                Column()
                                  .width('100%')
                                  .height(120)
                                  .borderRadius(12)
                                  .linearGradient({
                                    angle: 135,
                                    colors: [[theme.primaryColor, 0.0], [theme.isDark ? '#1A1A1A' : '#F5F5F5', 1.0]]
                                  })

                                Text('默认主题')
                                  .fontSize(14)
                                  .fontFamily(this.appFontFamily)
                                  .fontColor(theme.isDark ? '#FFFFFF' : '#333333')
                                  .opacity(0.7)
                              }

                              // 当前激活指示器
                              if (this.currentCustomThemeId === theme.id) {
                                Column()
                                  .width('100%')
                                  .height(120)
                                  .borderRadius(12)
                                  .border({ width: 3, color: $r('app.color.accent_primary') })
                              }

                              // 多选模式下的选中指示器
                              if (this.selectionModeEnabled) {
                                Column()
                                  .width(28)
                                  .height(28)
                                  .backgroundColor(this.isThemeSelected(theme.id) ? $r('app.color.accent_primary') : 'rgba(255,255,255,0.8)')
                                  .borderRadius(14)
                                  .border({ width: 2, color: $r('app.color.accent_primary') })
                                  .position({ x: 8, y: 8 })
                              }
                            }
                            .width('100%')
                            .height(120)

                            Row({ space: 8 }) {
                              // 主题色块
                              Column()
                                .width(24)
                                .height(24)
                                .backgroundColor(theme.primaryColor)
                                .borderRadius(4)

                              Column({ space: 4 }) {
                                Text(theme.name)
                                  .fontSize(14)
                                  .fontFamily(this.appFontFamily)
                                  .fontWeight(FontWeight.Medium)
                                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                                  .maxLines(1)
                                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                                Text(theme.isDark ? '深色主题' : '浅色主题')
                                  .fontSize(12)
                                  .fontFamily(this.appFontFamily)
                                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                              }
                              .layoutWeight(1)
                              .alignItems(HorizontalAlign.Start)

                              Button(this.currentCustomThemeId === theme.id ? '已激活' : '应用')
                                .fontSize(12)
                                .height(32)
                                .fontFamily(this.appFontFamily)
                                .backgroundColor(this.currentCustomThemeId === theme.id ? $r('app.color.text_secondary') : $r('app.color.accent_primary'))
                                .enabled(this.currentCustomThemeId !== theme.id)
                                .onClick(async () => {
                                  try {
                                    const splashPathApply: string = theme.splashBackgroundImagePath ? theme.splashBackgroundImagePath : '';
                                    await this.applyCustomThemeToManager(theme, splashPathApply);
                                    logger.info(TAG, `已应用保存的主题: ${theme.name}`);
                                  } catch (error) {
                                    logger.error(TAG, `应用主题失败: ${error instanceof Error ? error.message : String(error)}`);
                                  }
                                })
                            }
                            .width('100%')
                            .padding({ top: 8 })
                          }
                          .width('100%')
                          .padding(12)
                          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                          .borderRadius(12)
                          // 长按进入/切换选择，点击在选择模式下也切换选中
                          .gesture(LongPressGesture().onAction(() => { this.toggleThemeSelection(theme.id); }))
                          .onClick(() => {
                            if (this.selectionModeEnabled) {
                              this.toggleThemeSelection(theme.id);
                            }
                          })
                        }
                      }, (theme: CustomTheme) => theme.id)
                    }
                    .columnsTemplate(this.responsive_isLandscape ? '1fr 1fr' : '1fr')
                    .columnsGap(12)
                    .rowsGap(12)
                    .width('100%')
                  }

                  Button('创建自定义主题')
                    .width('100%')
                    .height(48)
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .backgroundColor($r('app.color.accent_primary'))
                    .onClick(() => { this.isCreatingCustomTheme = true; })
                }
                .width('100%')
                .padding(16)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .borderRadius(12)
              }

              // 图片预览区域（创建模式）
              if (this.isCreatingCustomTheme && this.processedImagePixelMap) {
                Column() {
                  Text('预览效果')
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .width('100%')
                    .margin({ bottom: 8 })

                  Stack() {
                    Image(this.processedImagePixelMap)
                      .width('100%')
                      .height(300)
                      .objectFit(ImageFit.Cover)
                      .borderRadius(12)

                    // 主色调预览
                    Row() {
                      Column() {
                        Text('主色调')
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(Color.White)
                        Text(this.extractedColor)
                          .fontSize(10)
                          .fontColor(Color.White)
                          .margin({ top: 4 })
                          .fontFamily(this.appFontFamily)
                      }
                      .padding(8)
                      .backgroundColor(this.extractedColor)
                      .borderRadius(8)
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.End)
                    .padding(12)
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(16)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .borderRadius(12)
              } else if (this.isCreatingCustomTheme && this.selectedImagePixelMap) {
                Column() {
                  Text('原始图片')
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .width('100%')
                    .margin({ bottom: 8 })

                  Image(this.selectedImagePixelMap)
                    .width('100%')
                    .height(300)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(12)
                }
                .width('100%')
                .padding(16)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .borderRadius(12)
              }

              // 选择图片按钮（背景）仅创建模式
              if (this.isCreatingCustomTheme) {
                Button('选择背景图片')
                .width('100%')
                .height(48)
                .fontSize(16)
                  .fontFamily(this.appFontFamily)
                .backgroundColor($r('app.color.accent_primary'))
                .onClick(() => this.selectImage())
              }

              // 选择开屏图片按钮（仅创建模式）
              if (this.isCreatingCustomTheme) {
                Column({ space: 8 }) {
                  Button('选择开屏背景图片')
                    .width('100%')
                    .height(48)
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .backgroundColor($r('app.color.accent_primary'))
                    .onClick(() => this.selectSplashImage())
                  
                  Text('提示：未设置开屏图片将使用背景图片作为开屏图片')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    .opacity(0.8)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                }
                .width('100%')
              }

              // 参数调节区域（选择图片后显示）
              if (this.isCreatingCustomTheme && this.selectedImagePixelMap) {
                Column({ space: 16 }) {
                  // 模糊程度
                  Column({ space: 8 }) {
                    Row() {
                      Text('模糊程度')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      Blank()
                      Text(`${this.blurLevel}%`)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    }
                    .width('100%')

                    Slider({
                      value: this.blurLevel,
                      min: 0,
                      max: 100,
                      step: 10
                    })
                      .width('100%')
                      .trackColor($r('app.color.divider_primary'))
                      .selectedColor($r('app.color.accent_primary'))
                      .showSteps(true)
                      .onChange((value: number) => {
                        // 确保值是10的倍数
                        this.blurLevel = Math.round(value / 10) * 10;
                        this.applyImageEffectsDebounced();
                      })
                  }

                  // 亮度调整（所有模式）
                  Column({ space: 8 }) {
                    Row() {
                      Text('亮度')
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                      Blank()
                      Text(`${this.brightnessLevel}%`)
                        .fontSize(14)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      Text(this.brightnessLevel < 50 ? ' (变暗)' : this.brightnessLevel > 50 ? ' (变亮)' : ' (原始)')
                        .fontSize(12)
                        .fontFamily(this.appFontFamily)
                        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                        .opacity(0.7)
                        .margin({ left: 4 })
                    }
                    .width('100%')

                    Slider({
                      value: this.brightnessLevel,
                      min: 0,
                      max: 100,
                      step: 10
                    })
                      .width('100%')
                      .trackColor($r('app.color.divider_primary'))
                      .selectedColor($r('app.color.accent_primary'))
                      .showSteps(true)
                      .onChange((value: number) => {
                        // 确保值是10的倍数
                        this.brightnessLevel = Math.round(value / 10) * 10;
                        this.applyImageEffectsDebounced();
                      })
                  }

                }
                .width('100%')
                .padding(16)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .borderRadius(12)
              }

              // 开屏图片预览区域（仅创建模式）
              if (this.isCreatingCustomTheme && this.processedSplashImagePixelMap) {
                Column() {
                  Text('开屏图片预览')
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .width('100%')
                    .margin({ bottom: 8 })

                  Image(this.processedSplashImagePixelMap)
                    .width('100%')
                    .height(300)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(12)
                }
                .width('100%')
                .padding(16)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .borderRadius(12)
              }

              // 主题色选择（仅创建模式）
              if (this.isCreatingCustomTheme) {
                Column({ space: 12 }) {
                  Text('选择主题色')
                    .fontSize(16)
                    .fontFamily(this.appFontFamily)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                    .width('100%')

                  // 提取的主色调显示
                  if (this.extractedColor && this.extractedColor.length > 0) {
                    Row({ space: 12 }) {
                      Column()
                        .width(48)
                        .height(48)
                        .backgroundColor(this.extractedColor)
                        .borderRadius(8)
                        .border({ width: this.selectedPrimaryColor === this.extractedColor ? 3 : 0, color: $r('app.color.accent_primary') })
                        .onClick(() => { this.selectedPrimaryColor = this.extractedColor; })

                      Column({ space: 4 }) {
                        Text('从图片提取')
                          .fontSize(12)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                        Text(this.extractedColor)
                          .fontSize(14)
                          .fontFamily(this.appFontFamily)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                        Text(this.extractedColorRGB)
                          .fontSize(11)
                          .fontFamily(this.appFontFamily)
                          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      }
                      .alignItems(HorizontalAlign.Start)
                    }
                    .width('100%')
                    .padding(8)
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
                    .borderRadius(8)
                  }

                  Text('可选主题色')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                    .width('100%')

                  Row({ space: 12 }) {
                    ForEach(this.availablePrimaryColors, (colorStr: string) => {
                      Stack() {
                        Column()
                          .width(40)
                          .height(40)
                          .backgroundColor(colorStr)
                          .borderRadius(8)
                          .border({ width: this.selectedPrimaryColor === colorStr ? 3 : 1, color: this.selectedPrimaryColor === colorStr ? $r('app.color.accent_primary') : $r('app.color.divider_primary') })

                        if (this.selectedPrimaryColor === colorStr) {
                          Image($r('app.media.ic_check'))
                            .width(16)
                            .height(16)
                            .fillColor(Color.White)
                        }
                      }
                      .width(40)
                      .height(40)
                      .onClick(() => {
                        this.selectedPrimaryColor = colorStr;
                      })
                    }, (colorStr: string) => colorStr)
                  }
                  .width('100%')
                }
                .width('100%')
                .padding(16)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .borderRadius(12)
              }

              // 主题名称输入（仅创建模式）
              if (this.isCreatingCustomTheme) {
                Column({ space: 8 }) {
                  Text('主题名称（可选）')
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  TextInput({ text: this.newThemeName })
                    .width('100%')
                    .height(40)
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                    .onChange((value: string) => { this.newThemeName = value; })
                }
                .width('100%')
                .padding(16)
              }

              // 已保存的主题列表，不再显示


              // 底部保存按钮（固定在页面底部，仅创建模式）
              if (this.isCreatingCustomTheme) {
                Button('保存并应用主题')
                  .width('100%')
                  .height(48)
                  .fontSize(16)
                  .fontFamily(this.appFontFamily)
                  .backgroundColor($r('app.color.color_success'))
                  .enabled(!this.isProcessing && this.processedImagePixelMap !== null)
                  .onClick(() => this.saveAndApplyTheme())
                  .margin({ top: 12 })
              }

              // 处理进度提示
              if (this.isProcessing) {
                Column({ space: 12 }) {
                  LoadingProgress()
                    .width(48)
                    .height(48)
                    .color($r('app.color.accent_primary'))

                  Text(this.processingMessage)
                    .fontSize(14)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

                  Progress({
                    value: this.processingProgress,
                    total: 100,
                    type: ProgressType.Linear
                  })
                    .width('100%')
                    .color($r('app.color.accent_primary'))
                }
                .width('100%')
                .padding(24)
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                .borderRadius(12)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: this.responsive_maxContentWidth }) // 响应式最大宽度
            .padding(this.responsive_contentPadding)
          }
          .width('100%')
          .height('100%')
          .align(Alignment.TopStart) // 响应式：大屏居中对齐
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(56)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: {
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme),
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)
            }
          }
        }
      },
      content: {
        title: { mainTitle: '主题设置' },
        menu: {
          value: this.selectionModeEnabled ? [
            {
              content: {
                label: '删除所选',
                icon: $r('sys.symbol.trash'),
                isEnabled: this.selectedThemeIds.length > 0,
                action: () => { this.showDeleteConfirmDialogSystem(); }
              }
            },
            {
              content: {
                label: '取消选择',
                icon: $r('app.media.ic_cancel'),
                isEnabled: true,
                action: () => { this.exitSelectionMode(); }
              }
            }
          ] : [
            {
              content: {
                label: '恢复默认主题',
                icon: $r('app.media.ic_restore'),
                isEnabled: true,
                action: () => { this.restoreDefaultCustomTheme(); }
              }
            }
          ]
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .backgroundColor(Color.Transparent)
  }
}

