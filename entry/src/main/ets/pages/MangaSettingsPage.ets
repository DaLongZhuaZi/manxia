import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
// 文件路径: entry/src/main/ets/pages/MangaSettingsPage.ets
/*
职责: 漫画设置页面，提供针对单部漫画的阅读设置配置（独立页面，不再复用阅读设置对话框）
*/

import { HdsNavDestination } from '@kit.UIDesignKit';
import { UIContext } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { PageLifecycleManager } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import {
  ReadingSettings,
  DEFAULT_READING_SETTINGS,
  ReadingDirection,
  ReadingMode,
  Manga,
  ImageSourceType,
  PageTurnAnimationType,
  DoublePagePortraitLayout
} from 'manxia_core/src/main/ets/Models/MangaModels';
import { DataManager, ComicInfo, ChapterInfo, PageInfo, ComicBasicInfoUpdate } from '../Framework/Data/DataManager';
import { DataService } from '../Framework/Services/DataService';
import { ComicConverter } from '../Framework/Utils/ComicConverter';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from 'manxia_theme/src/main/ets/Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from 'manxia_theme/src/main/ets/Framework/Utils/ResponsiveLayout';
import { eventBus, GameEvent, MangaDeletedPayload } from '../Framework/EventBus';
import { SandboxManager } from 'manxia_core/src/main/ets/Framework/Storage/SandboxManager';
import { ScraperDialog, ScraperDialogConfig, ScraperDialogResult } from '../Framework/Components/ScraperDialog';
import { ScraperContentType } from 'manxia_core/src/main/ets/Framework/Scraper/ScraperTypes';
import { getHelpPanelManagerV2 } from 'manxia_features_ui/src/main/ets/Framework/Components/HelpPanelV2';
import { getCoverImageManager } from '../Framework/Image/CoverImageManager';
import { image } from '@kit.ImageKit';
import { PageWindowCoordinator } from 'manxia_theme/src/main/ets/Utils/PageWindowCoordinator';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsImmersiveTitleActionItem, SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';
import { SourceDialogScaffold } from '../Framework/Components/SourceDialogScaffold';

const TAG: string = 'MangaSettingsPage';
const MAX_PRELOAD_PAGES: number = 50; // 最大预加载页数

// 页面导航参数
export interface MangaSettingsPageParams {
  mangaId: string;
  fromPage?: string;
}

// 导航路径接口（用于类型安全的 pushPath 调用）
interface NavigationPath {
  name: string;
  param: MangaSettingsPageParams;
}

@Component
struct MangaSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  private scroller: Scroller = new Scroller();
  private uiContext: UIContext | undefined = undefined;

  // 主题相关
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private componentId: string = 'MangaSettingsPage';

  // 响应式布局相关状态
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 读取和编辑的设置状态（针对当前漫画）
  @State readingSettings: ReadingSettings = DEFAULT_READING_SETTINGS;
  
  // 漫画信息
  @State currentManga: Manga | null = null;
  @State coverImagePath: string = '';
  @State isLoadingManga: boolean = true;

  // 漫画基础信息编辑状态
  @State editingTitle: string = '';
  @State editingDescription: string = '';
  @State editingAuthors: string = '';
  @State editingGenres: string = '';
  @State editingStatus: string = '';
  @State isEditingBasicInfo: boolean = false;
  @State basicInfoExpanded: boolean = true;

  // 预加载页数设置
  @State preloadPagesCount: number = 3;
  @State preloadAllPages: boolean = false;


  // 高级设置展开状态
  @State advancedSettingsExpanded: boolean = true;

  // 删除确认对话框状态
  @State showDeleteConfirmDialog: boolean = false;
  @State isDeleting: boolean = false;
  @State showCoverSelectDialog: boolean = false;
  @State coverSelectDialogVisible: boolean = false;
  @State coverSelectDialogCandidates: string[] = [];
  @State coverSelectDialogDisplayCandidates: string[] = [];
  @State coverSelectDialogImageLoadFailed: boolean[] = [];
  @State coverSelectDialogSelectedIndex: number = 0;
  @State coverSelectDialogTitle: string = '';
  @State isApplyingCoverSelection: boolean = false;
  private coverSelectDialogAnimationToken: number = 0;
  private readonly coverSelectDialogAnimationDuration: number = 220;
  
  // 保存状态
  @State isSavingBasicInfo: boolean = false;

  // 刮削对话框控制器
  private scraperDialogController: CustomDialogController | null = null;

  // 当前页面参数
  private pageParams: MangaSettingsPageParams = { mangaId: '', fromPage: 'Unknown' } as MangaSettingsPageParams;

  // DataManager和DataService实例
  private dataManager: DataManager = DataManager.getInstance();
  private dataService: DataService = DataService.getInstance();
  /**
   * 页面出现时声明本页窗口策略，确保沉浸式布局稳定。
   */
  aboutToAppear(): void {
    PageWindowCoordinator.applyPagePolicy('MangaSettingsPage', this.getUIContext());
  }

  onPageShow(): void {
    PageWindowCoordinator.reapplyPagePolicy('MangaSettingsPage', this.getUIContext());
    logger.lifecycle(TAG, '漫画设置页面开始显示');
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
        logger.debug(TAG, '✅ 成功获取GlobalNavStack');

        const paramList = this.pathStack.getParamByName('MangaSettingsPage') as MangaSettingsPageParams[];
        logger.debug(TAG, `📋 获取到参数数组，长度: ${paramList ? paramList.length : 0}`);

        if (paramList && paramList.length > 0) {
          const latestParam = paramList[paramList.length - 1] as MangaSettingsPageParams;
          if (latestParam && typeof latestParam === 'object' &&
              (Object.keys(latestParam).includes('mangaId'))) {
            this.pageParams = latestParam;
            logger.info(TAG, `📖 参数解析成功: mangaId=${latestParam.mangaId}, fromPage=${latestParam.fromPage || '未指定'}`);
          } else {
            logger.error(TAG, '❌ 参数格式不正确或缺少必需的 mangaId 属性');
          }
        } else {
          logger.error(TAG, '❌ 未找到页面参数，参数数组为空或不存在');
        }
      } else {
        logger.error(TAG, '❌ 无法从 AppStorage 获取 GlobalNavStack!');
      }
    } catch (err) {
      const errorMessage: string = err instanceof Error ? err.message : String(err);
      logger.error(TAG, '❌ AppStorage.get 异常', errorMessage);
    }
    logger.lifecycle(TAG, '漫画设置页面显示完成');
  }

  onReady(context: NavDestinationContext): void {
    logger.info(TAG, 'HdsNavDestination.onReady 已触发');
    
    // 获取UIContext
    this.uiContext = this.getUIContext();
    
    // 初始化响应式布局
    this.initResponsiveLayout();
    
    // 保持与全局栈一致：若 onPageShow 已绑定全局栈，则此处仅作为兜底兼容
    this.pathStack = context.pathStack;
    const params = context.pathInfo.param as MangaSettingsPageParams;
    if (params && typeof params === 'object' && Object.keys(params).includes('mangaId')) {
      this.pageParams = params;
      logger.info(TAG, `接收到页面参数: mangaId=${params.mangaId}, fromPage=${params.fromPage || '未指定'}`);
    } else {
      logger.warn(TAG, '未接收到有效的页面参数，使用默认设置');
    }

    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题切换到: ${newTheme}`);
      }
    );
    
    // 初始化字体感知
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    // 加载当前漫画的阅读设置
    this.loadMangaAndSettings();

  }

  private lifecycle = new PageLifecycleManager('MangaSettingsPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    // 清理主题感知
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    
    // 移除设备变化监听器
    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }

  }

  private showMangaSettingsHelp(): void {
    const helpContent = `# 漫画设置帮助

## 功能介绍

漫画设置页面允许您为单部漫画配置个性化的阅读设置，这些设置会覆盖全局默认设置。

## 基本信息编辑

### 修改封面
点击封面图片可以更换漫画封面：
- 从漫画页面中选择
- 从相册选择图片

### 修改标题和作者
点击对应字段可以编辑漫画的标题和作者信息。

## 阅读方向设置

| 选项 | 说明 |
|------|------|
| 从左到右 | 适合国漫、欧美漫画 |
| 从右到左 | 适合日漫 |
| 垂直滚动 | 条漫模式 |

## 阅读模式设置

- **单页模式**: 每次显示一页
- **双页模式**: 同时显示两页（适合平板）
- **条漫模式**: 垂直连续滚动

## 翻页动画

- **无动画**: 直接切换
- **滑动**: 左右滑动效果
- **卷页**: 仿真翻书效果
- **淡入淡出**: 渐变切换

## 预加载设置

设置预加载的页数，可以提升阅读流畅度，但会占用更多内存和流量。

## 高级设置

- **图片缩放**: 设置默认缩放比例
- **亮度调节**: 单独设置阅读亮度
- **背景颜色**: 自定义阅读背景

## 操作按钮

- **保存设置**: 保存当前设置
- **重置为默认**: 恢复全局默认设置
- **删除漫画**: 从书架移除此漫画`;

    getHelpPanelManagerV2().showInlineHelp('漫画设置帮助', helpContent);
  }

  /**
   * 初始化响应式布局
   */
  private initResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}`);
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
      logger.info(TAG, '✅ 响应式布局初始化完成');
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  /**
   * 更新响应式布局参数
   */
  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 600;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        break;
    }
  }

  /**
   * 加载漫画信息和设置
   */
  private async loadMangaAndSettings(): Promise<void> {
    this.isLoadingManga = true;
    try {
      logger.info(TAG, `开始加载漫画信息: ${this.pageParams.mangaId}`);
      
      // 加载漫画信息（使用异步转换方法，自动从数据库加载阅读设置和进度）
      const comicInfo = await this.dataManager.getComicById(this.pageParams.mangaId);
      if (comicInfo) {
        this.currentManga = await ComicConverter.convertComicInfoToMangaAsync(comicInfo);
        this.coverImagePath = this.currentManga.coverImagePath;
        
        // 使用从数据库加载的阅读设置
        this.readingSettings = this.currentManga.readingSettings;
        this.normalizeCurrentPageTurnAnimation();
        logger.info(TAG, `从数据库加载的阅读设置: mode=${this.readingSettings.readingMode}`);
        
        // 初始化编辑状态
        this.initEditingState();
        
        // 加载预加载设置（从数据库优先，回退到AppStorage）
        try {
          const preloadCountJson = await this.dataManager.getUserSetting('default_user', `preload_count_${this.pageParams.mangaId}`);
          if (preloadCountJson) {
            this.preloadPagesCount = parseInt(preloadCountJson);
          }
          
          const preloadAllJson = await this.dataManager.getUserSetting('default_user', `preload_all_${this.pageParams.mangaId}`);
          if (preloadAllJson) {
            this.preloadAllPages = preloadAllJson === 'true';
          }
        } catch (err) {
          logger.warn(TAG, `从数据库加载预加载设置失败，尝试从AppStorage加载: ${String(err)}`);
          // 回退到AppStorage
          const savedPreloadCount = AppStorage.get<number>(`preload_count_${this.pageParams.mangaId}`);
          if (savedPreloadCount !== undefined) {
            this.preloadPagesCount = savedPreloadCount;
          }
          
          const savedPreloadAll = AppStorage.get<boolean>(`preload_all_${this.pageParams.mangaId}`);
          if (savedPreloadAll !== undefined) {
            this.preloadAllPages = savedPreloadAll;
          }
        }
        
        logger.info(TAG, `漫画信息加载完成: ${this.currentManga.title}`);
      } else {
        logger.error(TAG, '未找到漫画信息');
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `加载漫画信息失败: ${errorMessage}`);
    } finally {
      this.isLoadingManga = false;
    }
  }

  /**
   * 判断图片路径来源类型（与 MangaDetailPage 一致）
   */
  private detectImageSourceType(path: string): ImageSourceType {
    const src: string = path;
    if (src.indexOf('http://') === 0 || src.indexOf('https://') === 0) {
      return ImageSourceType.NETWORK;
    }
    if (src.indexOf('$rawfile(') === 0) {
      return ImageSourceType.RAWFILE;
    }
    return ImageSourceType.LOCAL;
  }

  /**
   * 规范化用于 UI 显示的图片路径：本地文件补充 file:// 前缀，并记录详细诊断日志
   */
  private normalizeDisplayPath(rawPath: string, sourceType: ImageSourceType): string {
    if (!rawPath || rawPath.length === 0) {
      return '';
    }
    let displayPath: string = rawPath;
    if (sourceType === ImageSourceType.LOCAL) {
      const hasScheme: boolean = rawPath.indexOf('file://') === 0;
      if (!hasScheme) {
        displayPath = 'file://' + rawPath;
      }

      try {
        const actualPath: string = hasScheme ? rawPath.substring(7) : rawPath;
        const stat: fs.Stat = SafeFileUtils.statSync(actualPath);
        logger.debug(TAG, `设置页封面路径规范化成功: raw='${rawPath}', display='${displayPath}', size=${stat.size}`);
      } catch (statErr) {
        logger.warn(TAG, `设置页封面路径规范化检查失败: raw='${rawPath}', display='${displayPath}', 原始错误=${String(statErr)}`);
      }
    } else {
      logger.debug(TAG, `设置页封面来源类型=${sourceType}, 原样使用路径: '${rawPath}'`);
    }
    return displayPath;
  }

  /**
   * 提供设置页封面图片的 UI 渲染源：返回规范化后的路径、PixelMap或资源占位图
   * 支持AVIF格式：优先使用预加载的PixelMap
   */
  private getCoverImageSourceForUI(): string | ResourceStr | image.PixelMap {
    const raw: string = this.coverImagePath;
    if (raw && raw.length > 0) {
      // 检查是否有预加载的PixelMap（用于AVIF等特殊格式）
      if (raw.startsWith('http://') || raw.startsWith('https://')) {
        const coverManager = getCoverImageManager();
        const cachedPixelMap = coverManager.getCachedPixelMap(raw);
        if (cachedPixelMap) {
          return cachedPixelMap;
        }
      }
      
      const srcType: ImageSourceType = this.currentManga && this.currentManga.coverSourceType !== undefined
        ? (this.currentManga.coverSourceType as ImageSourceType)
        : this.detectImageSourceType(raw);
      const normalized: string = this.normalizeDisplayPath(raw, srcType);
      if (normalized.length > 0) {
        return normalized;
      }
    }
    return $r('app.media.mangabook');
  }

  /**
   * 用于日志的设置页封面显示路径（规范化后的字符串），若使用资源占位返回空字符串
   */
  private getCoverDisplayPathForLog(): string {
    const raw: string = this.coverImagePath;
    if (raw && raw.length > 0) {
      const srcType: ImageSourceType = this.currentManga && this.currentManga.coverSourceType !== undefined
        ? (this.currentManga.coverSourceType as ImageSourceType)
        : this.detectImageSourceType(raw);
      return this.normalizeDisplayPath(raw, srcType);
    }
    return '';
  }

  /**
   * 返回上一页
   */
  private goBack(): void {
    try {
      // 统一使用全局栈回退逻辑
      const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (globalStack) {
        globalStack.pop();
      } else {
        // 兜底使用本地栈
        this.pathStack.pop();
      }
    } catch (error) {
      const errorMessage: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `返回失败: ${errorMessage}`);
    }
  }

  /**
   * 显示删除确认对话框
   */
  private showMangaDeleteConfirmDialog(): void {
    this.showDeleteConfirmDialog = true;
  }

  /**
   * 删除漫画
   */
  private async deleteManga(): Promise<void> {
    if (!this.currentManga) {
      logger.warn(TAG, '当前漫画信息为空，无法删除');
      return;
    }

    this.isDeleting = true;
    try {
      logger.info(TAG, `开始删除漫画: ${this.currentManga.title} (${this.pageParams.mangaId})`);
      
      // 调用DataManager的deleteComic方法
      await this.dataManager.deleteComic(this.pageParams.mangaId);
      
      logger.info(TAG, `漫画删除成功: ${this.currentManga.title}`);
      
      // 关闭对话框
      this.showDeleteConfirmDialog = false;
      
      // 显示成功提示
      this.showToast('漫画已删除');
      
      // 发布漫画删除事件，通知书库刷新
      eventBus.publish(GameEvent.MANGA_DELETED, new MangaDeletedPayload(this.pageParams.mangaId));
      
      // 延迟返回到书库，让用户看到提示
      setTimeout(() => {
        // 返回到书库页面
        try {
          const globalStack = AppStorage.get<NavPathStack>('GlobalNavStack');
          if (globalStack) {
            // 清空导航栈，回到主页面（书库标签）
            globalStack.clear();
            logger.info(TAG, '已返回书库页面');
          } else {
            // 兜底逻辑
            this.goBack();
          }
        } catch (error) {
          logger.error(TAG, `返回书库失败: ${String(error)}`);
          this.goBack();
        }
      }, 1000);
      
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `删除漫画失败: ${errorMessage}`);
      this.showToast('删除失败，请稍后重试');
      this.showDeleteConfirmDialog = false;
    } finally {
      this.isDeleting = false;
    }
  }

  /**
   * 显示Toast提示
   */
  private showToast(message: string, duration: number = 2000): void {
    try {
      if (this.uiContext) {
        this.uiContext.getPromptAction().showToast({
          message: message,
          duration: duration,
          bottom: 100
        });
      }
    } catch (error) {
      logger.warn(TAG, `Toast显示失败: ${message}`);
    }
  }

  /**
   * 选择封面图片
   */
  private async selectCoverImage(): Promise<void> {
    try {
      logger.info(TAG, '开始选择封面图片');
      
      // 获取UIAbilityContext
      const context = this.uiContext?.getHostContext() as common.UIAbilityContext;
      if (!context) {
        throw new Error('无法获取应用上下文');
      }

      // 创建图片选择器
      const photoSelectOptions: photoAccessHelper.PhotoSelectOptions = {
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      };

      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const selectResult = await photoPicker.select(photoSelectOptions);
      
      if (!selectResult || selectResult.photoUris.length === 0) {
        logger.info(TAG, '未选择图片');
        return;
      }

      const selectedUri: string = selectResult.photoUris[0] as string;
      logger.info(TAG, `选择了图片: ${selectedUri}`);
      await this.applyCoverBySourcePath(selectedUri);
      logger.info(TAG, '封面图片更新成功');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `选择封面图片失败: ${errorMessage}`);
      this.showToast('选择封面失败');
    }
  }

  /**
   * 从当前漫画的页面中选取前三张图片，弹窗选择并设置为封面
   */
  private async selectCoverFromMangaPages(): Promise<void> {
    try {
      if (!this.pageParams || !this.pageParams.mangaId) {
        this.showToast('缺少漫画ID');
        return;
      }
      const mangaId: string = this.pageParams.mangaId;
      // 获取章节列表，取第一章
      const chapters: ChapterInfo[] = await this.dataManager.getComicChapters(mangaId);
      if (!chapters || chapters.length === 0) {
        this.showToast('未找到章节，无法设置封面');
        return;
      }
      const firstChapterId: string = chapters[0].id;
      const pages: PageInfo[] = await this.dataManager.getPageInfoList(firstChapterId);
      if (!pages || pages.length === 0) {
        this.showToast('章节内无图片，无法设置封面');
        return;
      }

      // 取前三张图片的路径（优先本地路径），并预处理为可直接显示的路径
      const candidates: string[] = [];
      const displayCandidates: string[] = [];
      const maxCount: number = pages.length > 3 ? 3 : pages.length;
      for (let i = 0; i < maxCount; i++) {
        const p: PageInfo = pages[i];
        const path: string = (p.localPath && p.localPath.length > 0) ? (p.localPath as string) : p.imageUrl;
        if (path && path.length > 0) {
          const displayPath: string = this.normalizeCoverCandidateDisplayPath(path);
          candidates.push(path);
          displayCandidates.push(displayPath);
        }
      }
      if (candidates.length === 0) {
        this.showToast('未找到可用图片');
        return;
      }

      this.openCoverSelectDialog(
        candidates,
        displayCandidates,
        this.currentManga ? this.currentManga.title : mangaId
      );
      logger.info(TAG, `打开封面选择对话框: candidates=${candidates.length}, mangaId=${mangaId}, chapterId=${firstChapterId}`);
    } catch (error) {
      const errMsg: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `从漫画页面设置封面失败: ${errMsg}`);
      this.showToast('设置封面失败');
    }
  }

  private normalizeCoverCandidateDisplayPath(rawPath: string): string {
    if (!rawPath || rawPath.length === 0) {
      return '';
    }
    const lowerRawPath: string = rawPath.toLowerCase();
    const hasUriScheme: boolean = rawPath.indexOf('://') > 0;
    if (hasUriScheme &&
      lowerRawPath.indexOf('http://') !== 0 &&
      lowerRawPath.indexOf('https://') !== 0 &&
      lowerRawPath.indexOf('file://') !== 0 &&
      lowerRawPath.indexOf('$rawfile(') !== 0) {
      return rawPath;
    }
    const sourceType: ImageSourceType = this.detectImageSourceType(rawPath);
    return this.normalizeDisplayPath(rawPath, sourceType);
  }

  private buildCoverCandidateLoadFlags(length: number): boolean[] {
    const flags: boolean[] = [];
    for (let i = 0; i < length; i++) {
      flags.push(false);
    }
    return flags;
  }

  private openCoverSelectDialog(candidates: string[], displayCandidates: string[], title: string): void {
    this.coverSelectDialogAnimationToken += 1;
    const token: number = this.coverSelectDialogAnimationToken;
    this.coverSelectDialogCandidates = candidates;
    this.coverSelectDialogDisplayCandidates = displayCandidates;
    this.coverSelectDialogImageLoadFailed = this.buildCoverCandidateLoadFlags(displayCandidates.length);
    this.coverSelectDialogSelectedIndex = 0;
    this.coverSelectDialogTitle = title;
    this.showCoverSelectDialog = true;
    this.coverSelectDialogVisible = false;
    setTimeout(() => {
      if (this.coverSelectDialogAnimationToken === token && this.showCoverSelectDialog) {
        this.coverSelectDialogVisible = true;
      }
    }, 0);
  }

  private closeCoverSelectDialog(forceClose: boolean = false): void {
    if (this.isApplyingCoverSelection && !forceClose) {
      return;
    }
    if (!this.showCoverSelectDialog) {
      return;
    }
    this.coverSelectDialogAnimationToken += 1;
    const token: number = this.coverSelectDialogAnimationToken;
    this.coverSelectDialogVisible = false;
    setTimeout(() => {
      if (this.coverSelectDialogAnimationToken !== token) {
        return;
      }
      this.showCoverSelectDialog = false;
      this.coverSelectDialogCandidates = [];
      this.coverSelectDialogDisplayCandidates = [];
      this.coverSelectDialogImageLoadFailed = [];
      this.coverSelectDialogSelectedIndex = 0;
      this.coverSelectDialogTitle = '';
    }, this.coverSelectDialogAnimationDuration);
  }

  private getCoverSelectCandidateDisplaySource(index: number): string | ResourceStr {
    if (index < 0 || index >= this.coverSelectDialogDisplayCandidates.length) {
      return $r('app.media.mangabook');
    }
    if (index < this.coverSelectDialogImageLoadFailed.length && this.coverSelectDialogImageLoadFailed[index]) {
      return $r('app.media.mangabook');
    }
    const displayPath: string = this.coverSelectDialogDisplayCandidates[index];
    if (displayPath && displayPath.length > 0) {
      return displayPath;
    }
    return $r('app.media.mangabook');
  }

  private markCoverSelectCandidateLoadFailed(index: number): void {
    if (index < 0 || index >= this.coverSelectDialogImageLoadFailed.length) {
      return;
    }
    if (this.coverSelectDialogImageLoadFailed[index]) {
      return;
    }
    const nextFlags: boolean[] = [];
    for (let i = 0; i < this.coverSelectDialogImageLoadFailed.length; i++) {
      nextFlags.push(this.coverSelectDialogImageLoadFailed[i]);
    }
    nextFlags[index] = true;
    this.coverSelectDialogImageLoadFailed = nextFlags;
    const rawPath: string = index < this.coverSelectDialogCandidates.length ? this.coverSelectDialogCandidates[index] : '';
    const displayPath: string = index < this.coverSelectDialogDisplayCandidates.length ? this.coverSelectDialogDisplayCandidates[index] : '';
    logger.warn(TAG, `封面候选图加载失败: index=${index}, raw='${rawPath}', display='${displayPath}'`);
  }

  private async confirmCoverSelectDialog(): Promise<void> {
    if (this.coverSelectDialogSelectedIndex < 0 || this.coverSelectDialogSelectedIndex >= this.coverSelectDialogCandidates.length) {
      this.showToast('请选择封面图片');
      return;
    }
    const selectedPath: string = this.coverSelectDialogCandidates[this.coverSelectDialogSelectedIndex];
    this.isApplyingCoverSelection = true;
    try {
      await this.applyCoverBySourcePath(selectedPath);
      this.closeCoverSelectDialog(true);
    } catch (error) {
      const errorMessage: string = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `应用封面选择失败: ${errorMessage}`);
      this.showToast('设置封面失败');
    } finally {
      this.isApplyingCoverSelection = false;
    }
  }

  private async applyCoverBySourcePath(sourcePath: string): Promise<void> {
    if (!this.pageParams || !this.pageParams.mangaId) {
      throw new Error('缺少漫画ID');
    }
    const mangaId: string = this.pageParams.mangaId;
    const sandbox: SandboxManager = SandboxManager.getInstance();
    const comicsDir: string = sandbox.getDirectory('comics');
    const sourceId: string = (this.currentManga && this.currentManga.sourceInfo && this.currentManga.sourceInfo.sourceId)
      ? (this.currentManga.sourceInfo.sourceId as string)
      : 'local_import';
    const safeSource: string = this.sanitizeFileName(sourceId);
    const comicTitle: string = this.currentManga ? this.currentManga.title : mangaId;
    const safeTitle: string = this.sanitizeFileName(comicTitle);
    const comicRoot: string = `${comicsDir}/${safeSource}/${safeTitle}`;
    await sandbox.createDirectory(comicRoot);

    const ext: string = this.getFileExtension(sourcePath);
    const coverTarget: string = `${comicRoot}/cover${ext.length > 0 ? '.' + ext : ''}`;
    if (await sandbox.exists(coverTarget)) {
      await sandbox.deleteFile(coverTarget);
    }
    await sandbox.copyFile(sourcePath, coverTarget);
    await this.dataManager.updateComicCoverUrl(mangaId, coverTarget);
    this.coverImagePath = coverTarget;
    this.showToast('封面已更新');
    logger.info(TAG, `封面路径已更新: ${coverTarget}`);
  }

  // 与导入页一致的文件名清理
  private sanitizeFileName(fileName: string): string {
    return fileName
      .replace(/\s+/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_+|_+$/g, '')
      .substring(0, 100);
  }

  private getFileExtension(path: string): string {
    const idx: number = path.lastIndexOf('.');
    if (idx < 0 || idx >= path.length - 1) {
      return '';
    }
    const ext: string = path.substring(idx + 1).toLowerCase();
    const allowed: string[] = ['jpg', 'jpeg', 'png', 'webp', 'avif'];
    for (let i = 0; i < allowed.length; i++) {
      if (ext === allowed[i]) {
        return ext;
      }
    }
    return '';
  }

  // 显式更新方法 - 修改后立即保存到数据库
  private setReadingDirection(direction: ReadingDirection): void {
    if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
      this.readingSettings.doublePagePortraitLayout = direction === ReadingDirection.TOP_TO_BOTTOM
        ? DoublePagePortraitLayout.VERTICAL
        : DoublePagePortraitLayout.HORIZONTAL;
    }
    this.readingSettings.readingDirection = this.normalizeReadingDirectionForMode(
      this.readingSettings.readingMode,
      direction,
      this.readingSettings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL
    );
    this.normalizeCurrentPageTurnAnimation();
    this.saveSettingsImmediately();
  }

  private setReadingMode(mode: ReadingMode): void {
    this.readingSettings.readingMode = mode;
    this.readingSettings.readingDirection = this.normalizeReadingDirectionForMode(
      mode,
      this.readingSettings.readingDirection,
      this.readingSettings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL
    );
    this.normalizeCurrentPageTurnAnimation();
    this.saveSettingsImmediately();
  }

  private normalizeReadingDirectionForMode(
    mode: ReadingMode,
    direction: ReadingDirection,
    doublePagePortraitLayout: DoublePagePortraitLayout
  ): ReadingDirection {
    const normalizedDirection = direction === ReadingDirection.VERTICAL
      ? ReadingDirection.TOP_TO_BOTTOM
      : direction;
    if (mode === ReadingMode.DOUBLE_PAGE && doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL) {
      return ReadingDirection.TOP_TO_BOTTOM;
    }
    if (mode === ReadingMode.DOUBLE_PAGE && normalizedDirection === ReadingDirection.TOP_TO_BOTTOM) {
      return ReadingDirection.LEFT_TO_RIGHT;
    }
    if ((mode === ReadingMode.WEBTOON || mode === ReadingMode.CONTINUOUS_VERTICAL) &&
      normalizedDirection !== ReadingDirection.TOP_TO_BOTTOM) {
      return ReadingDirection.TOP_TO_BOTTOM;
    }
    if (mode === ReadingMode.CONTINUOUS_SCROLL && normalizedDirection === ReadingDirection.TOP_TO_BOTTOM) {
      return ReadingDirection.LEFT_TO_RIGHT;
    }
    return normalizedDirection;
  }

  private setShowPageInfo(isOn: boolean): void {
    this.readingSettings.showPageInfo = isOn;
    this.saveSettingsImmediately();
  }

  private setShowPageIndicator(isOn: boolean): void {
    this.readingSettings.showPageIndicator = isOn;
    this.saveSettingsImmediately();
  }

  private setKeepScreenOn(isOn: boolean): void {
    this.readingSettings.keepScreenOn = isOn;
    this.saveSettingsImmediately();
  }

  private setLockMode(isOn: boolean): void {
    this.readingSettings.lockMode = isOn;
    this.readingSettings.lockOrientation = isOn;
    this.saveSettingsImmediately();
  }

  private setLockDeviceOrientation(isOn: boolean): void {
    this.readingSettings.lockDeviceOrientation = isOn;
    this.saveSettingsImmediately();
  }

  private setVolumeKeyNavigation(isOn: boolean): void {
    this.readingSettings.volumeKeyNavigation = isOn;
    this.saveSettingsImmediately();
  }

  private isSinglePageReadingMode(): boolean {
    return this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE ||
      this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_LTR ||
      this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_RTL ||
      this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB;
  }

  private isModeLocked(): boolean {
    return this.readingSettings.lockMode ?? this.readingSettings.lockOrientation ?? false;
  }

  private getModeLockHint(): string {
    if (this.isModeLocked()) {
      return '已锁定，旋转设备时保持当前阅读模式';
    }
    if (this.isSinglePageReadingMode()) {
      return '未锁定，横屏会临时切换为左右双页';
    }
    return '锁定后旋转设备不会触发临时布局切换';
  }

  private getDeviceOrientationLockHint(): string {
    if (this.readingSettings.lockDeviceOrientation ?? false) {
      return '已锁定，阅读时保持当前横竖屏方向';
    }
    return '开启后会锁住当前设备方向，避免阅读时误旋转';
  }

  private setBrightness(value: number): void {
    this.readingSettings.brightness = Math.max(0, Math.min(100, value));
    this.saveSettingsImmediately();
  }

  private setPageSpacing(value: number): void {
    this.readingSettings.pageSpacing = Math.max(0, Math.min(50, value));
    this.saveSettingsImmediately();
  }

  private setAutoPageTurnInterval(value: number): void {
    this.readingSettings.autoPageTurnInterval = Math.max(0, Math.min(60, value));
    this.saveSettingsImmediately();
  }

  private setPageTurnAnimation(animationType: PageTurnAnimationType): void {
    const normalizedAnimation: PageTurnAnimationType = this.normalizePageTurnAnimationForCurrentMode(animationType);
    this.readingSettings.pageTurnAnimation = normalizedAnimation;
    logger.info(TAG, `翻页动画设置更新为: ${normalizedAnimation}`);
    this.saveSettingsImmediately();
  }

  /**
   * 立即保存设置到数据库（静默保存，不显示Toast）
   */
  private saveSettingsImmediately(): void {
    try {
      // 保存阅读设置到数据库
      ComicConverter.saveReadingSettings(this.pageParams.mangaId, this.readingSettings).then(() => {
        logger.debug(TAG, `阅读设置已自动保存`);
      }).catch((error: Error) => {
        logger.error(TAG, `自动保存阅读设置失败: ${error.message}`);
      });
      
      // 同时保存到AppStorage作为缓存
      AppStorage.setOrCreate(`manga_settings_${this.pageParams.mangaId}`, JSON.stringify(this.readingSettings));
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `自动保存设置失败: ${errorMessage}`);
    }
  }
  
  /**
   * 判断当前阅读模式是否支持卷页动画
   * 卷页动画支持：
   * - 单页模式 + 从左到右/从右到左阅读方向
   * - 双页模式（设置页面允许选择，实际效果由阅读器根据横屏状态决定）
   */
  private isCurlAnimationSupported(): boolean {
    const mode = this.readingSettings.readingMode;
    const direction = this.readingSettings.readingDirection;
    
    // 单页从右到左模式
    if (mode === ReadingMode.SINGLE_PAGE_RTL) {
      return true;
    }
    
    // 单页模式 + 从左到右或从右到左方向
    if (mode === ReadingMode.SINGLE_PAGE) {
      return direction === ReadingDirection.LEFT_TO_RIGHT || 
             direction === ReadingDirection.RIGHT_TO_LEFT;
    }
    
    // 双页模式（在设置页面允许选择，实际运行时会根据横屏状态决定）
    if (mode === ReadingMode.DOUBLE_PAGE) {
      return true;
    }
    
    return false;
  }

  private setPreloadPagesCount(value: number): void {
    this.preloadPagesCount = Math.max(1, Math.min(MAX_PRELOAD_PAGES, value));
    this.savePreloadSettingsImmediately();
  }

  private setPreloadAllPages(isOn: boolean): void {
    this.preloadAllPages = isOn;
    this.savePreloadSettingsImmediately();
  }

  /**
   * 立即保存预加载设置到数据库
   */
  private savePreloadSettingsImmediately(): void {
    try {
      this.dataManager.saveUserSetting('default_user', `preload_count_${this.pageParams.mangaId}`, String(this.preloadPagesCount))
        .catch((error: Error) => {
          logger.error(TAG, `保存预加载页数失败: ${error.message}`);
        });
      
      this.dataManager.saveUserSetting('default_user', `preload_all_${this.pageParams.mangaId}`, String(this.preloadAllPages))
        .catch((error: Error) => {
          logger.error(TAG, `保存预加载全部设置失败: ${error.message}`);
        });
      
      // 同时保存到AppStorage作为缓存
      AppStorage.setOrCreate(`preload_count_${this.pageParams.mangaId}`, this.preloadPagesCount);
      AppStorage.setOrCreate(`preload_all_${this.pageParams.mangaId}`, this.preloadAllPages);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `自动保存预加载设置失败: ${errorMessage}`);
    }
  }

  /**
   * 初始化编辑状态
   */
  private initEditingState(): void {
    if (this.currentManga) {
      this.editingTitle = this.currentManga.title;
      this.editingDescription = this.currentManga.description || '';
      this.editingAuthors = this.currentManga.metadata.authors.join(', ');
      this.editingGenres = this.currentManga.metadata.genres.join(', ');
      this.editingStatus = this.currentManga.status;
    }
  }

  /**
   * 开始编辑基础信息
   */
  private startEditingBasicInfo(): void {
    this.initEditingState();
    this.isEditingBasicInfo = true;
  }

  /**
   * 取消编辑基础信息
   */
  private cancelEditingBasicInfo(): void {
    this.initEditingState();
    this.isEditingBasicInfo = false;
  }

  /**
   * 保存基础信息
   */
  private async saveBasicInfo(): Promise<void> {
    if (!this.currentManga) {
      return;
    }
    
    this.isSavingBasicInfo = true;
    try {
      // 更新漫画对象
      this.currentManga.title = this.editingTitle.trim();
      this.currentManga.description = this.editingDescription.trim();
      this.currentManga.metadata.authors = this.editingAuthors.split(',').map(s => s.trim()).filter(s => s.length > 0);
      this.currentManga.metadata.genres = this.editingGenres.split(',').map(s => s.trim()).filter(s => s.length > 0);
      
      // 保存到数据库
      const updateInfo: ComicBasicInfoUpdate = {
        title: this.currentManga.title,
        description: this.currentManga.description,
        authors: this.currentManga.metadata.authors,
        genres: this.currentManga.metadata.genres
      };
      await this.dataManager.updateComicBasicInfo(this.pageParams.mangaId, updateInfo);
      
      logger.info(TAG, `漫画基础信息保存成功: ${this.currentManga.title}`);
      this.isEditingBasicInfo = false;
    } catch (error) {
      logger.error(TAG, `保存漫画基础信息失败: ${String(error)}`);
    } finally {
      this.isSavingBasicInfo = false;
    }
  }

  /**
   * 打开刮削对话框
   */
  private openScraperDialog(): void {
    const config: ScraperDialogConfig = {
      initialKeyword: this.editingTitle || (this.currentManga ? this.currentManga.title : ''),
      contentType: ScraperContentType.MANGA,
      title: '搜索漫画信息'
    };

    this.scraperDialogController = new CustomDialogController({
      builder: ScraperDialog({
        themeState: this.themeState,
        config: config,
        onConfirm: (result: ScraperDialogResult) => {
          this.applyScraperResult(result);
        },
        onCancel: () => {
          logger.info(TAG, '用户取消刮削');
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      customStyle: true
    });

    this.scraperDialogController.open();
  }

  /**
   * 应用刮削结果
   */
  private applyScraperResult(result: ScraperDialogResult): void {
    const metadata = result.metadata;
    logger.info(TAG, `应用刮削结果: ${metadata.title}`);

    // 应用标题
    if (metadata.title) {
      this.editingTitle = metadata.title;
    }

    // 应用作者
    if (result.applyAuthor && metadata.author) {
      this.editingAuthors = metadata.author;
    } else if (result.applyAuthor && metadata.authors && metadata.authors.length > 0) {
      this.editingAuthors = metadata.authors.join(', ');
    }

    // 应用描述
    if (result.applyDescription && metadata.description) {
      this.editingDescription = metadata.description;
    }

    // 应用标签/分类
    if (result.applyTags) {
      const tags: string[] = [];
      if (metadata.genres && metadata.genres.length > 0) {
        tags.push(...metadata.genres);
      }
      if (metadata.tags && metadata.tags.length > 0) {
        tags.push(...metadata.tags.slice(0, 5)); // 只取前5个标签
      }
      if (tags.length > 0) {
        this.editingGenres = tags.join(', ');
      }
    }

    // 展开编辑区域以显示结果
    this.basicInfoExpanded = true;

    logger.info(TAG, '刮削结果已应用到编辑字段');
    this.showToast('刮削信息已填入，请确认后保存');
  }

  /**
   * 判断是否禁用从上到下阅读方向
   */
  private isTTBDisabled(): boolean {
    return this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL;
  }

  private isHorizontalDirectionDisabled(): boolean {
    return this.readingSettings.readingMode === ReadingMode.WEBTOON ||
      this.readingSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL;
  }

  private isDoublePageVerticalLayoutSelected(): boolean {
    return this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE &&
      (this.readingSettings.doublePagePortraitLayout ?? DoublePagePortraitLayout.VERTICAL) ===
        DoublePagePortraitLayout.VERTICAL;
  }

  private normalizePageTurnAnimationForCurrentMode(animationType: PageTurnAnimationType): PageTurnAnimationType {
    if (this.isDoublePageVerticalLayoutSelected()) {
      return PageTurnAnimationType.SLIDE;
    }
    return animationType;
  }

  private normalizeCurrentPageTurnAnimation(): void {
    this.readingSettings.pageTurnAnimation = this.normalizePageTurnAnimationForCurrentMode(
      this.readingSettings.pageTurnAnimation
    );
  }

  @Builder
  private buildVerticalDoublePageAnimationLockCard() {
    Column({ space: 8 }) {
      Text('上下专属')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding(10)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme))
        .borderRadius(8)
      Text('上下双页通过触顶/触底翻页，只使用专属上下滑动动画。')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .width('100%')
    }
    .width('100%')
  }

  /**
   * 处理阅读模式变更时的逻辑
   */
  private handleReadingModeChange(mode: ReadingMode): void {
    const oldMode = this.readingSettings.readingMode;
    this.setReadingMode(mode);
    logger.info(TAG, `阅读模式切换: ${oldMode} -> ${mode}, direction=${this.readingSettings.readingDirection}, layout=${this.readingSettings.doublePagePortraitLayout}`);
  }

  // 构建封面和基本信息区域
  @Builder
  buildMangaInfoSection() {
    Column({ space: 16 }) {
      Text('漫画信息')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      if (this.isLoadingManga) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          
          Text('加载中...')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .margin({ top: 8 })
        }
        .width('100%')
        .height(200)
        .justifyContent(FlexAlign.Center)
      } else if (this.currentManga) {
        if (this.responsive_isLandscape) {
          Row({ space: 16 }) {
            Stack() {
              Image(this.getCoverImageSourceForUI())
                .width('100%')
                .height('100%')
                .borderRadius(8)
                .objectFit(ImageFit.Contain)
                .backgroundColor(Color.Transparent)
                .key(`cover_landscape_${this.coverImagePath}`)
                .onError(() => {
                  const srcType = this.currentManga ? this.currentManga.coverSourceType : undefined;
                  logger.warn(TAG, `设置页封面加载失败: raw='${this.coverImagePath}', display='${this.getCoverDisplayPathForLog()}', source=${srcType}`);
                })
            }
            .width(180)
            .height(260)
            .padding(8)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
            .borderRadius(12)

            Column({ space: 10 }) {
              Text(this.currentManga.title)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              if (this.currentManga.metadata.authors.length > 0) {
                Text(`作者: ${this.currentManga.metadata.authors.join(', ')}`)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }

              if (this.currentManga.metadata.genres.length > 0) {
                Text(`标签: ${this.currentManga.metadata.genres.slice(0, 3).join(', ')}`)
                  .fontSize(13)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }

              Text(`章节: ${this.currentManga.chapters.length} | 状态: ${this.currentManga.status}`)
                .fontSize(12)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))

              Blank()

              Row({ space: 10 }) {
                Button('从漫画页面选择封面')
                  .type(ButtonType.ROUNDED_RECTANGLE)
                  .layoutWeight(1)
                  .height(40)
                  .fontFamily(this.appFontFamily)
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
                  .borderRadius(10)
                  .onClick(() => { this.selectCoverFromMangaPages(); })

                Button('从相册选择封面')
                  .type(ButtonType.ROUNDED_RECTANGLE)
                  .layoutWeight(1)
                  .height(40)
                  .fontFamily(this.appFontFamily)
                  .fontSize(14)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
                  .borderRadius(10)
                  .onClick(() => { this.selectCoverImage(); })
              }
              .width('100%')
            }
            .layoutWeight(1)
            .height(260)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
        } else {
          Column({ space: 12 }) {
            Row({ space: 12 }) {
              Stack() {
                Image(this.getCoverImageSourceForUI())
                  .width('100%')
                  .height('100%')
                  .borderRadius(8)
                  .objectFit(ImageFit.Contain)
                  .backgroundColor(Color.Transparent)
                  .key(`cover_portrait_${this.coverImagePath}`)
                  .onError(() => {
                    const srcType = this.currentManga ? this.currentManga.coverSourceType : undefined;
                    logger.warn(TAG, `设置页封面加载失败: raw='${this.coverImagePath}', display='${this.getCoverDisplayPathForLog()}', source=${srcType}`);
                  })
              }
              .width(136)
              .height(194)
              .padding(8)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(12)

              Column({ space: 8 }) {
                Text(this.currentManga.title)
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                if (this.currentManga.metadata.authors.length > 0) {
                  Row({ space: 4 }) {
                    Text('作者:')
                      .fontSize(13)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    
                    Text(this.currentManga.metadata.authors.join(', '))
                      .fontSize(13)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  .width('100%')
                }

                if (this.currentManga.metadata.genres.length > 0) {
                  Row({ space: 4 }) {
                    Text('标签:')
                      .fontSize(13)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                    
                    Text(this.currentManga.metadata.genres.slice(0, 3).join(', '))
                      .fontSize(13)
                      .fontFamily(this.appFontFamily)
                      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                  }
                  .width('100%')
                }

                Text(`章节: ${this.currentManga.chapters.length} | 状态: ${this.currentManga.status}`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')

            Column({ space: 8 }) {
              Button('从漫画页面选择封面')
                .type(ButtonType.ROUNDED_RECTANGLE)
                .width('100%')
                .height(40)
                .fontFamily(this.appFontFamily)
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
                .borderRadius(10)
                .onClick(() => { this.selectCoverFromMangaPages(); })

              Button('从相册选择封面')
                .type(ButtonType.ROUNDED_RECTANGLE)
                .width('100%')
                .height(40)
                .fontFamily(this.appFontFamily)
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
                .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
                .borderRadius(10)
                .onClick(() => { this.selectCoverImage(); })
            }
            .width('100%')
          }
          .width('100%')
        }

        // 描述
        if (this.currentManga.description && this.currentManga.description.length > 0) {
          Column({ space: 8 }) {
            Text('简介')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .alignSelf(ItemAlign.Start)
            
            Text(this.currentManga.description)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .lineHeight(20)
          }
          .width('100%')
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  /**
   * 构建基础信息编辑区域
   */
  @Builder
  buildBasicInfoEditSection() {
    Column({ space: 16 }) {
      // 标题行
      Row() {
        Text('编辑基础信息')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Blank()

        // 刮削按钮
        Row({ space: 4 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(14)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])

          Text('刮削')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        }
        .padding({ left: 8, right: 10, top: 4, bottom: 4 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme) + '15')
        .borderRadius(14)
        .onClick(() => {
          this.openScraperDialog();
        })
        .margin({ right: 8 })
        
        // 展开/收起按钮
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(18)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme)])
            .rotate({ angle: this.basicInfoExpanded ? 180 : 0 })
            .animation({ duration: 220, curve: Curve.EaseOut })
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.basicInfoExpanded = !this.basicInfoExpanded;
        })
      }
      .width('100%')

      if (this.basicInfoExpanded && this.currentManga) {
        Column({ space: 12 }) {
          // 标题编辑
          Column({ space: 4 }) {
            Text('漫画标题')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .alignSelf(ItemAlign.Start)
            
            TextInput({ text: this.editingTitle, placeholder: '请输入漫画标题' })
              .width('100%')
              .height(44)
              .fontSize(14)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .onChange((value: string) => {
                this.editingTitle = value;
              })
          }
          .width('100%')

          // 作者编辑
          Column({ space: 4 }) {
            Text('作者（多个用逗号分隔）')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .alignSelf(ItemAlign.Start)
            
            TextInput({ text: this.editingAuthors, placeholder: '例如: 作者A, 作者B' })
              .width('100%')
              .height(44)
              .fontSize(14)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .onChange((value: string) => {
                this.editingAuthors = value;
              })
          }
          .width('100%')

          // 标签编辑
          Column({ space: 4 }) {
            Text('标签（多个用逗号分隔）')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .alignSelf(ItemAlign.Start)
            
            TextInput({ text: this.editingGenres, placeholder: '例如: 冒险, 奇幻, 热血' })
              .width('100%')
              .height(44)
              .fontSize(14)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .onChange((value: string) => {
                this.editingGenres = value;
              })
          }
          .width('100%')

          // 简介编辑
          Column({ space: 4 }) {
            Text('漫画简介')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .alignSelf(ItemAlign.Start)
            
            TextArea({ text: this.editingDescription, placeholder: '请输入漫画简介...' })
              .width('100%')
              .height(100)
              .fontSize(14)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .onChange((value: string) => {
                this.editingDescription = value;
              })
          }
          .width('100%')

          // 操作按钮
          Row({ space: 12 }) {
            Button('重置')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
              .onClick(() => {
                this.initEditingState();
              })

            Button(this.isSavingBasicInfo ? '保存中...' : '保存修改')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .enabled(!this.isSavingBasicInfo)
              .onClick(() => {
                this.saveBasicInfo();
              })
          }
          .width('100%')
          .margin({ top: 8 })
        }
        .width('100%')
        .transition(
          TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
            .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }).animation({ duration: 220, curve: Curve.EaseOut }))
        )
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  // 构建设置项：阅读方向
  @Builder
  buildReadingDirectionSettings() {
    Column({ space: 12 }) {
      Row() {
        Text('阅读方向')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        if (this.isHorizontalDirectionDisabled()) {
          Text('条漫模式仅支持从上到下')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        } else if (this.isDoublePageVerticalLayoutSelected()) {
          Text('当前双页为上下组合；选择左右方向会切换为左右组合')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        } else if (this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE) {
          Text('当前双页为左右组合；选择从上到下将切换为上下组合')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
      }
      .width('100%')

      Row({ space: 8 }) {
        Column() {
          Button({ stateEffect: !this.isTTBDisabled() }) {
            Text('从上到下')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(
                this.isTTBDisabled() 
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
              )
          }
            .width('100%')
            .height(36)
            .backgroundColor(
              this.readingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(8)
            .enabled(!this.isTTBDisabled())
            .opacity(this.isTTBDisabled() ? 0.5 : 1.0)
            .onClick(() => {
              if (!this.isTTBDisabled()) {
                this.setReadingDirection(ReadingDirection.TOP_TO_BOTTOM)
              }
            })
        }.layoutWeight(1)

        Column() {
          Button({ stateEffect: !this.isHorizontalDirectionDisabled() }) {
            Text('从左到右')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(
                this.isHorizontalDirectionDisabled()
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
              )
          }
            .width('100%')
            .height(36)
            .backgroundColor(
              this.readingSettings.readingDirection === ReadingDirection.LEFT_TO_RIGHT
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(8)
            .enabled(!this.isHorizontalDirectionDisabled())
            .opacity(this.isHorizontalDirectionDisabled() ? 0.5 : 1.0)
            .onClick(() => {
              if (!this.isHorizontalDirectionDisabled()) {
                this.setReadingDirection(ReadingDirection.LEFT_TO_RIGHT)
              }
            })
        }.layoutWeight(1)

        Column() {
          Button({ stateEffect: !this.isHorizontalDirectionDisabled() }) {
            Text('从右到左')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(
                this.isHorizontalDirectionDisabled()
                  ? ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme)
              )
          }
            .width('100%')
            .height(36)
            .backgroundColor(
              this.readingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(8)
            .enabled(!this.isHorizontalDirectionDisabled())
            .opacity(this.isHorizontalDirectionDisabled() ? 0.5 : 1.0)
            .onClick(() => {
              if (!this.isHorizontalDirectionDisabled()) {
                this.setReadingDirection(ReadingDirection.RIGHT_TO_LEFT)
              }
            })
        }.layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  // 构建设置项：阅读模式
  @Builder
  buildReadingModeSettings() {
    Column({ space: 12 }) {
      Text('阅读模式')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 第一行：单页模式
      Row({ space: 8 }) {
        Column() {
          Button({ stateEffect: true }) {
            Text('单页')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width('100%')
            .height(36)
            .backgroundColor(
              this.readingSettings.readingMode === ReadingMode.SINGLE_PAGE
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(8)
            .onClick(() => this.handleReadingModeChange(ReadingMode.SINGLE_PAGE))
        }.layoutWeight(1)

        Column() {
          Button({ stateEffect: true }) {
            Text('双页')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width('100%')
            .height(36)
            .backgroundColor(
              this.readingSettings.readingMode === ReadingMode.DOUBLE_PAGE
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(8)
            .onClick(() => this.handleReadingModeChange(ReadingMode.DOUBLE_PAGE))
        }.layoutWeight(1)

        Column() {
          Button({ stateEffect: true }) {
            Text('连续滚动')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width('100%')
            .height(36)
            .backgroundColor(
              this.readingSettings.readingMode === ReadingMode.CONTINUOUS_SCROLL
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(8)
            .onClick(() => this.handleReadingModeChange(ReadingMode.CONTINUOUS_SCROLL))
        }.layoutWeight(1)
      }
      .width('100%')

      // 第二行：条漫模式
      Row({ space: 8 }) {
        Column() {
          Button({ stateEffect: true }) {
            Text('条漫')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width('100%')
            .height(36)
            .backgroundColor(
              this.readingSettings.readingMode === ReadingMode.WEBTOON
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(8)
            .onClick(() => this.handleReadingModeChange(ReadingMode.WEBTOON))
        }.layoutWeight(1)

        Column() {
          Button({ stateEffect: true }) {
            Text('垂直滚动')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
          }
            .width('100%')
            .height(36)
            .backgroundColor(
              this.readingSettings.readingMode === ReadingMode.CONTINUOUS_VERTICAL
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme)
            )
            .borderRadius(8)
            .onClick(() => this.handleReadingModeChange(ReadingMode.CONTINUOUS_VERTICAL))
        }.layoutWeight(1)

        Blank().layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  // 构建设置项：基础开关
  @Builder
  buildBasicSettings() {
    Column({ space: 16 }) {
      Text('基础设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Row() {
        Text('显示页码信息')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.readingSettings.showPageInfo })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .switchPointColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            this.setShowPageInfo(isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Text('显示页面指示器')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.readingSettings.showPageIndicator })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .switchPointColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            this.setShowPageIndicator(isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Text('保持屏幕常亮')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.readingSettings.keepScreenOn })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .switchPointColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            this.setKeepScreenOn(isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Column() {
          Text('锁定方向')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text(this.getDeviceOrientationLockHint())
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.readingSettings.lockDeviceOrientation ?? false })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .switchPointColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            this.setLockDeviceOrientation(isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Column() {
          Text('锁定模式')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text(this.getModeLockHint())
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.isModeLocked() })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .switchPointColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            this.setLockMode(isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      Row() {
        Text('音量键翻页')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.readingSettings.volumeKeyNavigation })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .switchPointColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            this.setVolumeKeyNavigation(isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  // 构建设置项：预加载设置
  @Builder
  buildPreloadSettings() {
    Column({ space: 16 }) {
      Text('预加载设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Row() {
        Text('预加载当前章所有页')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        Toggle({ type: ToggleType.Switch, isOn: this.preloadAllPages })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .switchPointColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
          .onChange((isOn: boolean) => {
            this.setPreloadAllPages(isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      if (!this.preloadAllPages) {
        Column({ space: 8 }) {
          Row() {
            Text('预加载页数')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Text(`${this.preloadPagesCount}`)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)

          Slider({
            value: this.preloadPagesCount,
            min: 1,
            max: MAX_PRELOAD_PAGES,
            step: 1,
            style: SliderStyle.InSet
          })
            .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .trackThickness(4)
            .onChange((value: number) => {
              this.setPreloadPagesCount(Math.round(value));
            })

          Text(`当前设置: 提前加载 ${this.preloadPagesCount} 页 (最大${MAX_PRELOAD_PAGES}页)`)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  // 构建设置项：高级设置（可展开）
  @Builder
  buildAdvancedSettings() {
    Column({ space: 16 }) {
      Row() {
        Text('高级设置')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .layoutWeight(1)
        
        Row({ space: 4 }) {
          Text(this.advancedSettingsExpanded ? '收起' : '展开')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          SymbolGlyph($r('sys.symbol.chevron_down'))
            .fontSize(16)
            .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)])
            .rotate({ angle: this.advancedSettingsExpanded ? 180 : 0 })
            .animation({ duration: 220, curve: Curve.EaseOut })
        }
          .onClick(() => {
            this.advancedSettingsExpanded = !this.advancedSettingsExpanded;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16 })

      if (this.advancedSettingsExpanded) {
        Column({ space: 16 }) {
          // 页面间距
          Column({ space: 8 }) {
            Row() {
              Text('页面间距')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text(`${this.readingSettings.pageSpacing}px`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            Slider({
              value: this.readingSettings.pageSpacing,
              min: 0,
              max: 50,
              step: 1,
              style: SliderStyle.InSet
            })
              .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
              .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .trackThickness(4)
              .onChange((value: number) => {
                this.setPageSpacing(Math.round(value));
              })
          }
          .width('100%')

          // 自动翻页间隔
          Column({ space: 8 }) {
            Row() {
              Text('自动翻页间隔')
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              Text(this.readingSettings.autoPageTurnInterval === 0 ? '禁用' : `${this.readingSettings.autoPageTurnInterval}秒`)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            Slider({
              value: this.readingSettings.autoPageTurnInterval,
              min: 0,
              max: 60,
              step: 1,
              style: SliderStyle.InSet
            })
              .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
              .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .trackThickness(4)
              .onChange((value: number) => {
                this.setAutoPageTurnInterval(Math.round(value));
              })
            
            Text('设置为0将禁用自动翻页')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
              .width('100%')
          }
          .width('100%')

          // 翻页动画
          Column({ space: 8 }) {
            Text('翻页动画')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .width('100%')

            if (this.isDoublePageVerticalLayoutSelected()) {
              this.buildVerticalDoublePageAnimationLockCard()
            } else {
            Row() {
              // 无动画
              Column() {
                Text('无')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.NONE ? 
                    ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) : 
                    ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .layoutWeight(1)
              .padding(10)
              .backgroundColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.NONE ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) : Color.Transparent)
              .borderRadius(8)
              .onClick(() => this.setPageTurnAnimation(PageTurnAnimationType.NONE))

              // 滑动
              Column() {
                Text('滑动')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.SLIDE ? 
                    ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) : 
                    ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .layoutWeight(1)
              .padding(10)
              .backgroundColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.SLIDE ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) : Color.Transparent)
              .borderRadius(8)
              .onClick(() => this.setPageTurnAnimation(PageTurnAnimationType.SLIDE))

              // 淡入淡出
              Column() {
                Text('淡入淡出')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.FADE ? 
                    ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) : 
                    ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .layoutWeight(1)
              .padding(10)
              .backgroundColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.FADE ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) : Color.Transparent)
              .borderRadius(8)
              .onClick(() => this.setPageTurnAnimation(PageTurnAnimationType.FADE))
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)

            Row() {
              // 立方体
              Column() {
                Text('立方体')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.CUBE ? 
                    ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) : 
                    ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .layoutWeight(1)
              .padding(10)
              .backgroundColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.CUBE ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) : Color.Transparent)
              .borderRadius(8)
              .onClick(() => this.setPageTurnAnimation(PageTurnAnimationType.CUBE))

              // 覆盖
              Column() {
                Text('覆盖')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.COVER ? 
                    ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) : 
                    ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .layoutWeight(1)
              .padding(10)
              .backgroundColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.COVER ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) : Color.Transparent)
              .borderRadius(8)
              .onClick(() => this.setPageTurnAnimation(PageTurnAnimationType.COVER))

              // 景深
              Column() {
                Text('景深')
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.DEPTH ? 
                    ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) : 
                    ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .layoutWeight(1)
              .padding(10)
              .backgroundColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.DEPTH ? 
                ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) : Color.Transparent)
              .borderRadius(8)
              .onClick(() => this.setPageTurnAnimation(PageTurnAnimationType.DEPTH))
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .margin({ top: 8 })

            Row() {
              // 卷页（只有单页LTR/RTL模式可用）
              if (this.isCurlAnimationSupported()) {
                Column() {
                  Text('卷页')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.CURL ? 
                      ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme) : 
                      ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                }
                .layoutWeight(1)
                .padding(10)
                .backgroundColor(this.readingSettings.pageTurnAnimation === PageTurnAnimationType.CURL ? 
                  ThemeAwareHelper.getTestManagementThemedColor('accent_primary_dimmed', this.themeState.currentTheme) : Color.Transparent)
                .borderRadius(8)
                .onClick(() => this.setPageTurnAnimation(PageTurnAnimationType.CURL))
              } else {
                // 禁用状态的卷页按钮
                Column() {
                  Text('卷页')
                    .fontSize(12)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                  Text('(单页/双页横屏)')
                    .fontSize(9)
                    .fontFamily(this.appFontFamily)
                    .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
                }
                .layoutWeight(1)
                .padding(10)
                .backgroundColor(Color.Transparent)
                .borderRadius(8)
                .opacity(0.5)
              }
              
              // 占位
              Column()
                .layoutWeight(1)
              Column()
                .layoutWeight(1)
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
            .margin({ top: 8 })
            }
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 16 })
        .transition(
          TransitionEffect.OPACITY.animation({ duration: 220, curve: Curve.EaseOut })
            .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }).animation({ duration: 220, curve: Curve.EaseOut }))
        )
      }
    }
    .width('100%')
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  // 构建操作按钮区域
  @Builder
  buildActionButtons() {
    Column({ space: 12 }) {
      // 重置默认设置按钮
      Row() {
        Button({ stateEffect: true }) {
          Text('重置为默认设置')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_inactive', this.themeState.currentTheme))
          .borderRadius(12)
          .onClick(() => {
            this.readingSettings = DEFAULT_READING_SETTINGS;
            this.preloadPagesCount = 3;
            this.preloadAllPages = false;
            // 立即保存重置后的设置
            this.saveSettingsImmediately();
            this.savePreloadSettingsImmediately();
            this.showToast('已重置为默认设置');
            logger.info(TAG, '已重置为默认设置');
          })
      }
      .width('100%')

      // 删除漫画按钮
      Row() {
        Button({ stateEffect: true }) {
          Text('删除漫画')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        }
          .width('100%')
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
          .borderRadius(12)
          .onClick(() => this.showMangaDeleteConfirmDialog())
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .clip(true)
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 8
    })
  }

  @Builder
  private buildCoverSelectDialog() {
    SourceDialogScaffold({
      themeState: this.themeState,
      closeOnMaskTap: !this.isApplyingCoverSelection,
      dialogWidth: '92%',
      maxWidth: 580,
      maxHeight: '84%',
      contentPadding: 18,
      zIndexValue: 2600,
      onMaskTap: () => {
        this.closeCoverSelectDialog();
      }
    }) {
      Column({ space: 14 }) {
        Text('选择封面图片')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Start)

        if (this.coverSelectDialogTitle.length > 0) {
          Text(`漫画：${this.coverSelectDialogTitle}`)
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        if (this.coverSelectDialogCandidates.length > 0) {
          Row({ space: 10 }) {
            ForEach(this.coverSelectDialogCandidates, (path: string, index: number) => {
              Column({ space: 8 }) {
                Stack({ alignContent: Alignment.Bottom }) {
                  Image(this.getCoverSelectCandidateDisplaySource(index))
                    .width('100%')
                    .height('100%')
                    .objectFit(ImageFit.Cover)
                    .borderRadius(12)
                    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
                    .onError(() => {
                      this.markCoverSelectCandidateLoadFailed(index);
                    })
                    .onClick(() => {
                      this.coverSelectDialogSelectedIndex = index;
                    })
                  if (this.coverSelectDialogSelectedIndex === index) {
                    Column()
                      .width('100%')
                      .height('100%')
                      .border({
                        width: 2,
                        color: ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                      })
                      .borderRadius(12)
                      .backgroundColor('rgba(39, 124, 255, 0.08)')
                  }
                }
                .width('100%')
                .aspectRatio(0.72)
                .clip(true)

                Text(`第${index + 1}张`)
                  .fontSize(12)
                  .fontFamily(this.appFontFamily)
                  .fontColor(this.coverSelectDialogSelectedIndex === index
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              }
              .layoutWeight(1)
            }, (item: string) => item)
          }
          .width('100%')
        }

        Row({ space: 12 }) {
          Button('取消')
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
            .borderRadius(10)
            .enabled(!this.isApplyingCoverSelection)
            .onClick(() => {
              this.closeCoverSelectDialog();
            })

          Button(this.isApplyingCoverSelection ? '应用中...' : '设为封面')
            .layoutWeight(1)
            .height(42)
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .borderRadius(10)
            .enabled(!this.isApplyingCoverSelection)
            .onClick(() => {
              void this.confirmCoverSelectDialog();
            })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  // 构建删除确认对话框
  @Builder
  buildDeleteConfirmDialog() {
    Stack({ alignContent: Alignment.Center }) {
      // 半透明遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(14, 20, 31, 0.24)')
        .onClick(() => {
          if (!this.isDeleting) {
            this.showDeleteConfirmDialog = false;
          }
        })

      // 确认对话框
      Column({ space: 20 }) {
        Text('确认删除')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

        Column({ space: 12 }) {
          Text('您确定要删除这部漫画吗？')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          
          if (this.currentManga) {
            Text(this.currentManga.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          
          Text('此操作将删除漫画的所有数据和文件，包括阅读进度、书签等，且不可恢复。')
            .fontSize(13)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .lineHeight(20)
        }
        .width('100%')

        Row({ space: 12 }) {
          Column() {
            Button({ stateEffect: true }) {
              Text('取消')
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            }
              .width('100%')
              .height(44)
              .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
              .borderRadius(8)
              .enabled(!this.isDeleting)
              .onClick(() => {
                if (!this.isDeleting) {
                  this.showDeleteConfirmDialog = false;
                }
              })
          }.layoutWeight(1)

          Column() {
            Button({ stateEffect: true }) {
              Text(this.isDeleting ? '删除中...' : '确认删除')
                .fontSize(16)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            }
            .width('100%')
            .height(44)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_danger', this.themeState.currentTheme))
            .borderRadius(8)
            .enabled(!this.isDeleting)
            .onClick(() => {
              if (!this.isDeleting) {
                this.deleteManga();
              }
            })
          }.layoutWeight(1)
        }
        .width('100%')
      }
      .width('85%')
      .padding(24)
      .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
      .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
      .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
      .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
      .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4)
      .clip(true)
      .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
      .shadow({
        radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 8,
        color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
        offsetX: 0,
        offsetY: 10
      })
    }
    .width('100%')
    .height('100%')
    .zIndex(2000)
  }

  private buildImmersiveTitleActions(): SettingsImmersiveTitleActionItem[] {
    const actions: SettingsImmersiveTitleActionItem[] = [{
      id: 'help',
      symbol: $r('sys.symbol.questionmark_circle'),
      label: '帮助',
      onClick: (): void => {
        this.showMangaSettingsHelp();
      }
    }];
    return actions;
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 内容层
        if (this.responsive_isLandscape) {
          // 横屏布局：左边40%漫画信息，右边60%设置选项
          Row() {
            // 左侧：漫画封面和基本信息（添加滚动支持）
            Scroll() {
              Column() {
                Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
                this.buildMangaInfoSection()
                Blank().height(40)
              }
              .width('100%')
            }
            .width('40%')
            .height('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .padding({ left: this.responsive_contentPadding, right: 8 })
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
            
            // 右侧：各种设置选项
            Scroll(this.scroller) {
              Column({ space: 16 }) {
                Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
                
                this.buildBasicInfoEditSection()
                this.buildReadingDirectionSettings()
                this.buildReadingModeSettings()
                this.buildBasicSettings()
                this.buildPreloadSettings()
                this.buildAdvancedSettings()
                this.buildActionButtons()
                Blank().height(40)
              }
              .width('100%')
            }
            .width('60%')
            .height('100%')
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .padding({ left: 8, right: this.responsive_contentPadding })
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        } else {
          // 竖屏布局：原有布局
          Scroll(this.scroller) {
            Column({ space: 16 }) {
              Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

              this.buildMangaInfoSection()
              this.buildBasicInfoEditSection()
              this.buildReadingDirectionSettings()
              this.buildReadingModeSettings()
              this.buildBasicSettings()
              this.buildPreloadSettings()
              this.buildAdvancedSettings()
              this.buildActionButtons()
              Blank().height(40)
            }
            .width('100%')
            .constraintSize({ maxWidth: this.responsive_maxContentWidth })
            .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding })
          }
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .align(Alignment.TopStart)
          .edgeEffect(EdgeEffect.Spring)
          .scrollBar(BarState.Auto)
        }

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '漫画设置',
          appFontFamily: this.appFontFamily,
          contentPadding: this.responsive_contentPadding,
          maxContentWidth: this.responsive_maxContentWidth,
          pathStack: this.pathStack,
          actions: this.buildImmersiveTitleActions()
        })

        if (this.showCoverSelectDialog) {
          Stack() {
            this.buildCoverSelectDialog()
          }
            .width('100%')
            .height('100%')
            .opacity(this.coverSelectDialogVisible ? 1 : 0)
            .scale({ x: this.coverSelectDialogVisible ? 1 : 0.96, y: this.coverSelectDialogVisible ? 1 : 0.96 })
            .animation({ duration: this.coverSelectDialogAnimationDuration, curve: Curve.EaseOut })
        }

        // 删除确认对话框
        if (this.showDeleteConfirmDialog) {
          this.buildDeleteConfirmDialog()
        }
      }
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.onReady(context);
    })
    .backgroundColor(Color.Transparent)
  }
}

export { MangaSettingsPage }
