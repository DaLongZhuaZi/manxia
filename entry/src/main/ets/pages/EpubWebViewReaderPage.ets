import { logger } from '../Utils/Logger';
import { common } from '@kit.AbilityKit';
import { display, promptAction, UIContext } from '@kit.ArkUI';
import { WindowManager, DisplayMode } from '../Utils/WindowManager';
import { PageWindowCoordinator } from '../Utils/PageWindowCoordinator';
import { ReaderSafeAreaUtils } from '../Utils/ReaderSafeAreaUtils';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { EBookParserFactory } from '../Framework/Parsers/EBookParser';
import { convertMobiToExtractedDir } from '../Framework/Parsers/MobiParser';
import { KeyCode } from '@kit.InputKit';
import {
  EBook,
  EBookChapter,
  EBookContentMode,
  EBookFormat,
  EBookReaderEngine,
  EBookReadingProgress,
  EBookReadingSettings,
  DEFAULT_EBOOK_READING_SETTINGS
} from '../Models/EBookModels';
import {
  ReadingSettings as MangaReadingSettings,
  DEFAULT_READING_SETTINGS,
  ReadingMode,
  ReadingDirection,
  DoublePagePortraitLayout,
  PageTurnAnimationType
} from '../Models/MangaModels';
import {
  EpubWebViewReaderComponent,
  EpubWebViewReaderController,
  EpubSpineTransitionDirection,
  EpubWebViewReaderParams
} from '../Framework/Components/EpubWebViewReaderComponent';
import { EpubReaderSettingsPanel } from '../components/EpubReaderSettingsPanel';
import { EpubReaderChapterList } from '../components/EpubReaderChapterList';
import { MangaQuickSettings } from '../components/MangaQuickSettings';
import { MangaInteractionOverlay } from '../components/MangaInteractionOverlay';
import {
  setReaderReady,
  startBookCloseTransitionWithComponentId,
  cancelTransition
} from '../components/BookTransitionOverlay';
import { EBookReaderParams } from './EBookReaderPage';

const TAG = 'EpubWebViewReaderPage';

interface EpubSettingsPanelCallbacks {
  onSettingsChange: (settings: EBookReadingSettings) => void;
  onClose: () => void;
}

interface EpubChapterListCallbacks {
  onChapterSelect: (spineIndex: number) => void;
  onClose: () => void;
}

@Component
export struct EpubWebViewReaderPage {
  // ──── 导航 ────
  @State pathStack: NavPathStack = new NavPathStack();
  private uiContext: UIContext | null = null;
  private context: common.UIAbilityContext | null = null;
  private coverComponentId: string = '';

  // ──── 安全区 ────
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  // ──── 书籍数据 ────
  @State ebook: EBook | null = null;
  @State spineItems: EBookChapter[] = [];
  @State extractedRoot: string = '';
  @State currentSpineIndex: number = 0;
  @State currentPageWithinSpine: number = 0;
  @State totalPagesInSpine: number = 0;
  @State isFixedLayout: boolean = false;
  @State private canFallbackToReaderKit: boolean = false;
  private epubReaderController: EpubWebViewReaderController | null = null;
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

  // ──── 阅读设置 ────
  @State readingSettings: EBookReadingSettings = DEFAULT_EBOOK_READING_SETTINGS;
  @State pageReadingSettings: MangaReadingSettings = DEFAULT_READING_SETTINGS;

  // ──── UI 状态 ────
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State showTopToolbar: boolean = false;
  @State showBottomToolbar: boolean = false;
  @State toolbarOpacity: number = 0;
  @State showSettingsPanel: boolean = false;
  @State showQuickSettings: boolean = false;
  @State showChapterList: boolean = false;
  @State showPageTurnAnimationSettings: boolean = false;
  @State showAutoPageTurnSettings: boolean = false;
  @State showInteractionOverlay: boolean = false;
  @State componentWidth: number = 0;
  @State componentHeight: number = 0;
  @State isLandscapeMode: boolean = false;
  @State autoPageTurnEnabled: boolean = false;
  @State autoPageTurnIntervalSeconds: number = 5;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // ──── 工具栏自动隐藏 ────
  private static readonly TOOLBAR_AUTO_HIDE_MS: number = 3000;
  private static readonly PROGRESS_SAVE_INTERVAL_MS: number = 1500;
  private toolbarHideTimer: number = -1;
  private fullscreenRestoreTimer: number = -1;
  private autoPageTurnTimer: number = -1;
  private lastProgressSaveTime: number = 0;
  private sessionStartTimestamp: number = 0;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private hasNotifiedTransitionReaderReady: boolean = false;

  // ──── 生命周期 ────

  aboutToAppear(): void {
    this.themeManager = ThemeManager.getInstance();
    const info = display.getDefaultDisplaySync();
    this.isLandscapeMode = info.width > info.height;
  }

  aboutToDisappear(): void {
    this.clearToolbarTimer();
    this.clearFullscreenRestoreTimer();
    this.stopAutoPageTurn();
    void this.persistTextReadingSettings('about_to_disappear');
    void this.persistPageReadingSettings('about_to_disappear');
    void this.saveReadingProgress('about_to_disappear');
  }

  onPageShow(): void {
    WindowManager.reapplyCurrentDisplayMode(24);
    this.syncAutoPageTurnState();
  }

  onPageHide(): void {
    this.stopAutoPageTurn();
    void this.persistTextReadingSettings('page_hide');
    void this.saveReadingProgress('page_hide');
  }

  // ──── 初始化 ────

  private async initializeWithParams(params: EBookReaderParams): Promise<void> {
    try {
      this.context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (_ignored) {}
    await this.loadEBook(params.bookId);
    this.coverComponentId = params.coverComponentId ?? '';
    this.sessionStartTimestamp = Date.now();
  }

  private async loadEBook(bookId: string): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    this.hasNotifiedTransitionReaderReady = false;
    this.epubReaderController = null;

    try {
      const ebook = await this.ebookDataManager.getEBookById(bookId);
      if (!ebook) {
        throw new Error('未找到电子书');
      }
      const isMobiFormat = ebook.format === EBookFormat.MOBI ||
        ebook.format === EBookFormat.AZW ||
        ebook.format === EBookFormat.AZW3;
      if (ebook.format !== EBookFormat.EPUB && !isMobiFormat) {
        throw new Error('当前文件格式不支持 WebView 渲染');
      }

      let extractedRoot = ebook.extractedRootPath ?? '';

      if (extractedRoot.length === 0 && ebook.format === EBookFormat.EPUB) {
        logger.info(TAG, `extractedRootPath 为空，尝试懒解压: ${ebook.filePath}`);
        extractedRoot = await EBookParserFactory.ensureEpubExtracted(ebook.filePath ?? '');
        if (extractedRoot.length > 0) {
          ebook.extractedRootPath = extractedRoot;
          for (const ch of ebook.chapters) {
            if ((ch.resourceFile ?? '').trim().length === 0) {
              const rh = (ch.resourceHref ?? '').trim().replace(/^\//, '');
              if (rh.length > 0) {
                ch.resourceFile = rh;
              }
            }
          }
          void this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
          logger.info(TAG, `懒解压成功: extractedRootPath=${extractedRoot}`);
        }
      }

      if (extractedRoot.length === 0 && isMobiFormat) {
        logger.info(TAG, `MOBI extractedRootPath 为空，触发懒转换: ${ebook.filePath}`);
        const convResult = await convertMobiToExtractedDir(ebook.filePath ?? '');
        if (convResult.success) {
          extractedRoot = convResult.extractedRootPath;
          ebook.extractedRootPath = extractedRoot;
          ebook.preferredReaderEngine = EBookReaderEngine.WEBVIEW;
          const newSpine = EBookParserFactory.parseEpubSpineItems(extractedRoot);
          if (newSpine.length > 0) {
            for (const ch of newSpine) {
              ch.bookId = ebook.id;
            }
            ebook.chapters = newSpine;
          }
          void this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
          logger.info(TAG, `MOBI 懒转换成功: ${extractedRoot}`);
        }
      }

      if (extractedRoot.length === 0) {
        this.canFallbackToReaderKit = ebook.contentMode !== EBookContentMode.FIXED_LAYOUT_HTML;
        throw new Error('EPUB 尚未解压，请重新导入文件，或使用 ReaderKit 打开');
      }

      let spineItems = ebook.chapters.filter((ch: EBookChapter) => {
        const rf = (ch.resourceFile ?? '').trim();
        const rh = (ch.resourceHref ?? '').trim();
        return rf.length > 0 || rh.length > 0;
      });

      if (spineItems.length === 0) {
        logger.info(TAG, `章节缺少资源路径，尝试直接解析 OPF: extractedRoot=${extractedRoot}`);
        const opfSpineItems = EBookParserFactory.parseEpubSpineItems(extractedRoot);
        if (opfSpineItems.length > 0) {
          for (const ch of opfSpineItems) {
            ch.bookId = ebook.id;
          }
          ebook.chapters = opfSpineItems;
          void this.ebookDataManager.saveEBook(ebook, { skipReadingSettings: true });
          spineItems = opfSpineItems;
          logger.info(TAG, `OPF 直接解析成功，获得 ${spineItems.length} 个 spine 项`);
        }
      }

      if (spineItems.length === 0) {
        this.canFallbackToReaderKit = ebook.contentMode !== EBookContentMode.FIXED_LAYOUT_HTML;
        throw new Error('EPUB 内容无法被 WebView 渲染（缺少 spine 资源路径），请使用 ReaderKit 打开');
      }

      this.ebook = ebook;
      this.extractedRoot = extractedRoot;
      this.spineItems = spineItems;
      this.isFixedLayout = ebook.contentMode === EBookContentMode.FIXED_LAYOUT_HTML;

      this.readingSettings = this.cloneTextReadingSettings(
        ebook.readingSettings ?? DEFAULT_EBOOK_READING_SETTINGS
      );
      ebook.readingSettings = this.cloneTextReadingSettings(this.readingSettings);
      const loadedPageSettings = await this.ebookDataManager.loadImageReaderSettings(ebook.id);
      const normalizedLoadedPageSettings = this.normalizePageReadingSettings(loadedPageSettings);
      this.pageReadingSettings = this.clonePageReadingSettings(normalizedLoadedPageSettings);
      if (!this.arePageReadingSettingsEqual(normalizedLoadedPageSettings, loadedPageSettings)) {
        void this.ebookDataManager.saveImageReaderSettings(ebook.id, normalizedLoadedPageSettings);
      }
      this.autoPageTurnEnabled = this.pageReadingSettings.autoPageTurnInterval > 0;
      this.autoPageTurnIntervalSeconds = this.autoPageTurnEnabled ?
        this.pageReadingSettings.autoPageTurnInterval : 5;
      logger.info(
        TAG,
        `恢复阅读设置: text(fontSize=${this.readingSettings.fontSize}, lineHeight=${this.readingSettings.lineHeight}, pageMargin=${this.readingSettings.pageMargin}, tapToTurn=${this.readingSettings.tapToTurn ?? true}), page(mode=${this.pageReadingSettings.readingMode}, direction=${this.pageReadingSettings.readingDirection}, animation=${this.pageReadingSettings.pageTurnAnimation}, volumeKey=${this.pageReadingSettings.volumeKeyNavigation}, autoPageTurn=${this.pageReadingSettings.autoPageTurnInterval})`
      );

      const progress = ebook.readingProgress;
      if (progress && progress.currentChapterIndex >= 0 && progress.currentChapterIndex < spineItems.length) {
        this.currentSpineIndex = progress.currentChapterIndex;
        this.currentPageWithinSpine = progress.currentPosition ?? 0;
      } else {
        this.currentSpineIndex = 0;
        this.currentPageWithinSpine = 0;
      }

      this.isLoading = false;
      this.syncAutoPageTurnState();
      logger.info(TAG, `EPUB 加载完成: bookId=${bookId}, spineItems=${spineItems.length}, spineIndex=${this.currentSpineIndex}`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `EPUB 加载失败: ${msg}`);
      this.errorMessage = msg;
      this.isLoading = false;
      cancelTransition();
    }
  }

  private notifyTransitionReaderReadyOnce(reason: string): void {
    if (this.hasNotifiedTransitionReaderReady) {
      logger.debug(TAG, `过渡动画就绪已通知，忽略重复触发: ${reason}`);
      return;
    }
    this.hasNotifiedTransitionReaderReady = true;
    setReaderReady();
    logger.info(TAG, `📖 已通知过渡动画阅读器就绪: ${reason}`);
  }

  // ──── Spine 路径解析 ────

  private resolveSpinePath(spineIndex: number): string {
    if (spineIndex < 0 || spineIndex >= this.spineItems.length) {
      return '';
    }
    const chapter = this.spineItems[spineIndex];
    const rf = (chapter.resourceFile ?? '').trim().replace(/^\//, '');
    const rh = (chapter.resourceHref ?? '').trim().replace(/^\//, '');
    const resourcePath = rf || rh;
    if (!resourcePath) {
      return '';
    }
    return `${this.extractedRoot}/${resourcePath}`;
  }

  // ──── 翻页 ────

  private cloneTextReadingSettings(settings: EBookReadingSettings): EBookReadingSettings {
    return {
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      fontPath: settings.fontPath,
      fontWeight: settings.fontWeight,
      lineHeight: settings.lineHeight,
      backgroundColor: settings.backgroundColor,
      textColor: settings.textColor,
      themeBgImage: settings.themeBgImage,
      nightMode: settings.nightMode,
      followSystemTheme: settings.followSystemTheme,
      pageMargin: settings.pageMargin,
      pageMode: settings.pageMode,
      brightness: settings.brightness,
      autoSave: settings.autoSave,
      saveInterval: settings.saveInterval,
      letterSpacing: settings.letterSpacing ?? 0,
      paragraphSpacing: settings.paragraphSpacing ?? 8,
      firstLineIndent: settings.firstLineIndent ?? 2,
      textAlignment: settings.textAlignment ?? 'JUSTIFY',
      pageTurnAnimation: settings.pageTurnAnimation ?? PageTurnAnimationType.SLIDE,
      tapToTurn: settings.tapToTurn ?? true,
      volumeKeyNavigation: settings.volumeKeyNavigation ?? true,
      keepScreenOn: settings.keepScreenOn ?? false,
      showPageNumber: settings.showPageNumber ?? true,
      showProgress: settings.showProgress ?? false,
      showTime: settings.showTime ?? true,
      showBattery: settings.showBattery ?? false,
      backgroundType: settings.backgroundType ?? 'COLOR',
      backgroundImagePath: settings.backgroundImagePath ?? '',
      backgroundImageOpacity: settings.backgroundImageOpacity ?? 0.3
    };
  }

  private mergeTextReadingSettings(settings: EBookReadingSettings): EBookReadingSettings {
    return {
      fontSize: settings.fontSize,
      fontFamily: settings.fontFamily,
      fontPath: settings.fontPath,
      fontWeight: settings.fontWeight,
      lineHeight: settings.lineHeight,
      backgroundColor: settings.backgroundColor,
      textColor: settings.textColor,
      themeBgImage: settings.themeBgImage,
      nightMode: settings.nightMode,
      followSystemTheme: settings.followSystemTheme,
      pageMargin: settings.pageMargin,
      pageMode: settings.pageMode,
      brightness: settings.brightness,
      autoSave: settings.autoSave,
      saveInterval: settings.saveInterval,
      letterSpacing: settings.letterSpacing ?? this.readingSettings.letterSpacing ?? 0,
      paragraphSpacing: settings.paragraphSpacing ?? this.readingSettings.paragraphSpacing ?? 8,
      firstLineIndent: settings.firstLineIndent ?? this.readingSettings.firstLineIndent ?? 2,
      textAlignment: settings.textAlignment ?? this.readingSettings.textAlignment ?? 'JUSTIFY',
      pageTurnAnimation: settings.pageTurnAnimation ?? this.readingSettings.pageTurnAnimation ?? PageTurnAnimationType.SLIDE,
      tapToTurn: settings.tapToTurn ?? this.readingSettings.tapToTurn ?? true,
      volumeKeyNavigation: settings.volumeKeyNavigation ?? this.readingSettings.volumeKeyNavigation ?? true,
      keepScreenOn: settings.keepScreenOn ?? this.readingSettings.keepScreenOn ?? false,
      showPageNumber: settings.showPageNumber ?? this.readingSettings.showPageNumber ?? true,
      showProgress: settings.showProgress ?? this.readingSettings.showProgress ?? false,
      showTime: settings.showTime ?? this.readingSettings.showTime ?? true,
      showBattery: settings.showBattery ?? this.readingSettings.showBattery ?? false,
      backgroundType: settings.backgroundType ?? this.readingSettings.backgroundType ?? 'COLOR',
      backgroundImagePath: settings.backgroundImagePath ?? this.readingSettings.backgroundImagePath ?? '',
      backgroundImageOpacity: settings.backgroundImageOpacity ?? this.readingSettings.backgroundImageOpacity ?? 0.3
    };
  }

  private arePageReadingSettingsEqual(left: MangaReadingSettings, right: MangaReadingSettings): boolean {
    return JSON.stringify(left) === JSON.stringify(right);
  }

  private clonePageReadingSettings(settings: MangaReadingSettings): MangaReadingSettings {
    return {
      readingMode: settings.readingMode,
      readingDirection: settings.readingDirection,
      brightness: settings.brightness,
      keepScreenOn: settings.keepScreenOn,
      pageSpacing: settings.pageSpacing,
      showPageInfo: settings.showPageInfo,
      showPageIndicator: settings.showPageIndicator,
      fitMode: settings.fitMode,
      autoPageTurnInterval: settings.autoPageTurnInterval,
      skipIntroPages: settings.skipIntroPages,
      pageTurnAnimation: settings.pageTurnAnimation,
      doublePagePortraitLayout: settings.doublePagePortraitLayout,
      filterSettings: {
        enabled: settings.filterSettings.enabled,
        brightness: settings.filterSettings.brightness,
        contrast: settings.filterSettings.contrast,
        saturation: settings.filterSettings.saturation,
        hue: settings.filterSettings.hue,
        gamma: settings.filterSettings.gamma,
        sepia: settings.filterSettings.sepia,
        invert: settings.filterSettings.invert,
        grayscale: settings.filterSettings.grayscale,
        blur: settings.filterSettings.blur
      },
      volumeKeyNavigation: settings.volumeKeyNavigation,
      curlBackOpacity: settings.curlBackOpacity ?? DEFAULT_READING_SETTINGS.curlBackOpacity,
      webtoonLeftMargin: settings.webtoonLeftMargin ?? DEFAULT_READING_SETTINGS.webtoonLeftMargin,
      webtoonRightMargin: settings.webtoonRightMargin ?? DEFAULT_READING_SETTINGS.webtoonRightMargin,
      webtoonMarginSync: settings.webtoonMarginSync ?? DEFAULT_READING_SETTINGS.webtoonMarginSync
    };
  }

  private normalizePageReadingSettings(
    settings: MangaReadingSettings,
    shouldNotify: boolean = false
  ): MangaReadingSettings {
    const normalized = this.clonePageReadingSettings(settings);
    let toastMessage: string = '';
    if (normalized.readingDirection === ReadingDirection.VERTICAL) {
      normalized.readingDirection = ReadingDirection.TOP_TO_BOTTOM;
    }
    if (normalized.readingMode === ReadingMode.CONTINUOUS_SCROLL) {
      normalized.readingMode = ReadingMode.SINGLE_PAGE;
      toastMessage = 'WebView EPUB 暂不支持连续横向滚动，已切换为单页模式';
    }
    if (normalized.readingMode === ReadingMode.WEBTOON ||
      normalized.readingMode === ReadingMode.WEBTOON_WITH_GAP ||
      normalized.readingMode === ReadingMode.CONTINUOUS_VERTICAL) {
      normalized.readingMode = ReadingMode.SINGLE_PAGE_TTB;
      normalized.readingDirection = ReadingDirection.TOP_TO_BOTTOM;
      toastMessage = 'WebView EPUB 暂不支持条漫滚动，已切换为纵向分页';
    }
    if (normalized.readingMode === ReadingMode.SINGLE_PAGE &&
      normalized.readingDirection === ReadingDirection.TOP_TO_BOTTOM) {
      normalized.readingMode = ReadingMode.SINGLE_PAGE_TTB;
    }
    if (normalized.readingMode === ReadingMode.SINGLE_PAGE_TTB) {
      normalized.readingDirection = ReadingDirection.TOP_TO_BOTTOM;
    }
    if (normalized.readingMode === ReadingMode.DOUBLE_PAGE &&
      normalized.readingDirection === ReadingDirection.TOP_TO_BOTTOM) {
      normalized.readingDirection = ReadingDirection.LEFT_TO_RIGHT;
    }
    if (normalized.readingMode === ReadingMode.DOUBLE_PAGE &&
      this.getDeviceOrientation() !== 'landscape' &&
      normalized.doublePagePortraitLayout === DoublePagePortraitLayout.VERTICAL) {
      normalized.doublePagePortraitLayout = DoublePagePortraitLayout.HORIZONTAL;
      toastMessage = 'WebView EPUB 暂不支持双页竖屏上下组合，已切换为左右组合';
    }
    if (shouldNotify && toastMessage.length > 0) {
      promptAction.showToast({ message: toastMessage, duration: 1400 });
    }
    return normalized;
  }

  private async persistPageReadingSettings(trigger: string): Promise<void> {
    if (!this.ebook) {
      return;
    }
    try {
      await this.ebookDataManager.saveImageReaderSettings(
        this.ebook.id,
        this.clonePageReadingSettings(this.pageReadingSettings)
      );
    } catch (error) {
      logger.error(TAG, `保存 WebView EPUB 翻页设置失败: 触发源=${trigger}, 错误=${String(error)}`);
    }
  }

  private async persistTextReadingSettings(trigger: string): Promise<void> {
    if (!this.ebook) {
      return;
    }
    const snapshot = this.cloneTextReadingSettings(this.readingSettings);
    this.ebook.readingSettings = snapshot;
    try {
      logger.info(
        TAG,
        `保存 WebView EPUB 文本阅读设置: 触发源=${trigger}, fontSize=${snapshot.fontSize}, lineHeight=${snapshot.lineHeight}, pageMargin=${snapshot.pageMargin}`
      );
      await this.ebookDataManager.saveReadingSettings(this.ebook.id, snapshot);
    } catch (error) {
      logger.error(TAG, `保存 WebView EPUB 文本阅读设置失败: 触发源=${trigger}, 错误=${String(error)}`);
    }
  }

  private applyPageReadingSettings(
    settings: MangaReadingSettings,
    trigger: string,
    shouldNotifyUnsupportedMode: boolean = false
  ): void {
    const normalized = this.normalizePageReadingSettings(settings, shouldNotifyUnsupportedMode);
    const readingModeChanged = this.pageReadingSettings.readingMode !== normalized.readingMode ||
      this.pageReadingSettings.readingDirection !== normalized.readingDirection;
    this.pageReadingSettings = this.clonePageReadingSettings(normalized);
    this.autoPageTurnEnabled = normalized.autoPageTurnInterval > 0;
    if (this.autoPageTurnEnabled) {
      this.autoPageTurnIntervalSeconds = normalized.autoPageTurnInterval;
    }
    this.epubReaderController?.applyPageSettings(normalized);
    void this.persistPageReadingSettings(trigger);
    if (readingModeChanged && !this.showQuickSettings) {
      this.showInteractionOverlay = true;
    }
    this.handleMenusVisibilityChange();
  }

  private getEffectiveComponentWidth(): number {
    if (this.componentWidth > 0) {
      return this.componentWidth;
    }
    const info = display.getDefaultDisplaySync();
    return px2vp(info.width);
  }

  private getEffectiveComponentHeight(): number {
    if (this.componentHeight > 0) {
      return this.componentHeight;
    }
    const info = display.getDefaultDisplaySync();
    return px2vp(info.height);
  }

  private getDeviceOrientation(): 'portrait' | 'landscape' | 'square' {
    const width = this.getEffectiveComponentWidth();
    const height = this.getEffectiveComponentHeight();
    if (Math.abs(width - height) < 1) {
      return 'square';
    }
    return width > height ? 'landscape' : 'portrait';
  }

  private isVerticalPagingMode(): boolean {
    return this.pageReadingSettings.readingMode === ReadingMode.SINGLE_PAGE_TTB ||
      this.pageReadingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM;
  }

  private isRtlPagingMode(): boolean {
    return this.pageReadingSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
  }

  private isDoublePageMode(): boolean {
    return this.pageReadingSettings.readingMode === ReadingMode.DOUBLE_PAGE &&
      this.getEffectiveComponentWidth() > this.getEffectiveComponentHeight();
  }

  private handlePageTap(event: ClickEvent): void {
    if (this.areMenusVisible()) {
      return;
    }
    if (!(this.readingSettings.tapToTurn ?? true)) {
      this.toggleToolbars();
      return;
    }
    this.processReaderTap(event.x, event.y);
  }

  private processReaderTap(clickX: number, clickY: number): void {
    const displayWidth = this.getEffectiveComponentWidth();
    const displayHeight = this.getEffectiveComponentHeight();
    if (this.isDoublePageMode()) {
      this.handleDoublePageTap(clickX, clickY, displayWidth, displayHeight);
      return;
    }
    if (this.isVerticalPagingMode()) {
      this.handleVerticalPageTap(clickY, displayHeight);
      return;
    }
    this.handleHorizontalPageTap(clickX, displayWidth);
  }

  private handleDoublePageTap(
    clickX: number,
    clickY: number,
    displayWidth: number,
    displayHeight: number
  ): void {
    const centerAreaRatio = 0.4;
    const sideAreaRatio = (1 - centerAreaRatio) / 2;
    if (this.pageReadingSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM) {
      const topZoneEnd = displayHeight * sideAreaRatio;
      const bottomZoneStart = displayHeight * (1 - sideAreaRatio);
      if (clickY < topZoneEnd) {
        this.flipPage(false);
      } else if (clickY > bottomZoneStart) {
        this.flipPage(true);
      } else {
        this.toggleToolbars();
      }
      return;
    }
    const leftZoneEnd = displayWidth * sideAreaRatio;
    const rightZoneStart = displayWidth * (1 - sideAreaRatio);
    if (clickX < leftZoneEnd) {
      if (this.isRtlPagingMode()) {
        this.flipPage(true);
      } else {
        this.flipPage(false);
      }
    } else if (clickX > rightZoneStart) {
      if (this.isRtlPagingMode()) {
        this.flipPage(false);
      } else {
        this.flipPage(true);
      }
    } else {
      this.toggleToolbars();
    }
  }

  private handleVerticalPageTap(clickY: number, displayHeight: number): void {
    const centerAreaRatio = 0.4;
    const sideAreaRatio = (1 - centerAreaRatio) / 2;
    const topZoneEnd = displayHeight * sideAreaRatio;
    const bottomZoneStart = displayHeight * (1 - sideAreaRatio);
    if (clickY < topZoneEnd) {
      this.flipPage(false);
    } else if (clickY > bottomZoneStart) {
      this.flipPage(true);
    } else {
      this.toggleToolbars();
    }
  }

  private handleHorizontalPageTap(clickX: number, displayWidth: number): void {
    const centerAreaRatio = 0.4;
    const sideAreaRatio = (1 - centerAreaRatio) / 2;
    const leftZoneEnd = displayWidth * sideAreaRatio;
    const rightZoneStart = displayWidth * (1 - sideAreaRatio);
    if (clickX < leftZoneEnd) {
      if (this.isRtlPagingMode()) {
        this.flipPage(true);
      } else {
        this.flipPage(false);
      }
    } else if (clickX > rightZoneStart) {
      if (this.isRtlPagingMode()) {
        this.flipPage(false);
      } else {
        this.flipPage(true);
      }
    } else {
      this.toggleToolbars();
    }
  }

  private handleSwipe(event: GestureEvent): void {
    if (this.areMenusVisible()) {
      return;
    }
    if (this.isVerticalPagingMode()) {
      if (Math.abs(event.offsetY) < Math.max(40, Math.abs(event.offsetX))) {
        return;
      }
      this.flipPage(event.offsetY < 0);
      return;
    }
    if (Math.abs(event.offsetX) < Math.max(40, Math.abs(event.offsetY))) {
      return;
    }
    const swipingLeft = event.offsetX < 0;
    const forward = this.isRtlPagingMode() ? !swipingLeft : swipingLeft;
    this.flipPage(forward);
  }

  private flipPage(forward: boolean): boolean {
    if (!this.epubReaderController) {
      return false;
    }
    const handled = this.epubReaderController.flipPage(forward);
    if (handled) {
      this.syncAutoPageTurnState();
      return true;
    }
    const chapterChanged = this.onSpineChangeRequested(forward ? 'next' : 'prev');
    if (!chapterChanged) {
      this.stopAutoPageTurn();
    }
    return chapterChanged;
  }

  private onSpineChangeRequested(direction: 'prev' | 'next'): boolean {
    if (direction === 'next') {
      if (this.currentSpineIndex < this.spineItems.length - 1) {
        this.loadSpineItem(this.currentSpineIndex + 1, 0, 'next');
        return true;
      }
      promptAction.showToast({ message: '已是最后一章', duration: 1200 });
      return false;
    }
    if (this.currentSpineIndex > 0) {
      this.loadSpineItem(this.currentSpineIndex - 1, 99999, 'prev');
      return true;
    }
    promptAction.showToast({ message: '已是第一章', duration: 1200 });
    return false;
  }

  private loadSpineItem(
    spineIndex: number,
    pageOffset: number,
    transitionDirection: EpubSpineTransitionDirection = 'none'
  ): void {
    const path = this.resolveSpinePath(spineIndex);
    if (path.length === 0) {
      return;
    }
    this.currentSpineIndex = spineIndex;
    this.currentPageWithinSpine = 0;
    this.totalPagesInSpine = 0;
    this.epubReaderController?.loadSpineItem(path, pageOffset, transitionDirection);
    logger.info(TAG, `切换 spine: index=${spineIndex}, pageOffset=${pageOffset}, direction=${transitionDirection}, path=${path}`);
  }

  private jumpToCurrentSpinePage(pageIndex: number): void {
    if (!this.epubReaderController || this.totalPagesInSpine <= 0) {
      return;
    }
    const safePageIndex = Math.max(0, Math.min(pageIndex, this.totalPagesInSpine - 1));
    const moved = this.epubReaderController.goToPage(safePageIndex);
    if (moved) {
      this.syncAutoPageTurnState();
      logger.info(TAG, `跳转章节页: spine=${this.currentSpineIndex}, page=${safePageIndex}/${this.totalPagesInSpine}`);
    }
  }

  private handleVolumeKey(keyCode: number): boolean {
    if (!this.pageReadingSettings.volumeKeyNavigation) {
      return false;
    }
    if (keyCode === KeyCode.KEYCODE_VOLUME_UP) {
      return this.flipPage(false);
    }
    if (keyCode === KeyCode.KEYCODE_VOLUME_DOWN) {
      return this.flipPage(true);
    }
    return false;
  }

  // ──── 工具栏图标颜色 ────

  private getToolbarIconColor(isActive: boolean = false): ResourceColor {
    if (this.themeManager.isDarkThemeSync()) {
      return Color.White;
    }
    return isActive ? $r('app.color.accent_primary') : $r('app.color.text_primary');
  }

  private getAutoPageTurnIconResource(): Resource {
    return this.autoPageTurnEnabled ? $r('sys.symbol.airplane_departure') : $r('sys.symbol.airplane_arrival');
  }

  // ──── 工具栏显隐 ────

  private areMenusVisible(): boolean {
    return this.showSettingsPanel ||
      this.showQuickSettings ||
      this.showChapterList ||
      this.showPageTurnAnimationSettings ||
      this.showAutoPageTurnSettings ||
      this.showInteractionOverlay;
  }

  private closeTransientPanels(): void {
    this.showSettingsPanel = false;
    this.showQuickSettings = false;
    this.showChapterList = false;
    this.showPageTurnAnimationSettings = false;
    this.showAutoPageTurnSettings = false;
    this.showInteractionOverlay = false;
    this.handleMenusVisibilityChange();
  }

  private toggleToolbars(): void {
    if (this.areMenusVisible()) {
      this.closeTransientPanels();
      return;
    }
    if (this.showTopToolbar || this.showBottomToolbar) {
      this.hideToolbars();
    } else {
      this.showToolbars();
    }
  }

  private showToolbars(): void {
    this.stopAutoPageTurn();
    this.showTopToolbar = true;
    this.showBottomToolbar = true;
    const ctx = this.uiContext;
    if (ctx) {
      ctx.animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
        this.toolbarOpacity = 1;
      });
    } else {
      this.toolbarOpacity = 1;
    }
    this.scheduleToolbarAutoHide();
  }

  private hideToolbars(): void {
    this.clearToolbarTimer();
    const ctx = this.uiContext;
    if (ctx) {
      ctx.animateTo({
        duration: 180,
        curve: Curve.EaseIn,
        onFinish: () => {
          this.showTopToolbar = false;
          this.showBottomToolbar = false;
          this.syncAutoPageTurnState();
        }
      }, () => {
        this.toolbarOpacity = 0;
      });
    } else {
      this.toolbarOpacity = 0;
      this.showTopToolbar = false;
      this.showBottomToolbar = false;
      this.syncAutoPageTurnState();
    }
    this.scheduleFullscreenRestore('hide_toolbars', 200);
  }

  private scheduleToolbarAutoHide(): void {
    if (!this.showTopToolbar && !this.showBottomToolbar) {
      return;
    }
    if (this.areMenusVisible()) {
      return;
    }
    this.clearToolbarTimer();
    this.toolbarHideTimer = setTimeout(() => {
      this.toolbarHideTimer = -1;
      if (!this.areMenusVisible()) {
        this.hideToolbars();
      }
    }, EpubWebViewReaderPage.TOOLBAR_AUTO_HIDE_MS);
  }

  private clearToolbarTimer(): void {
    if (this.toolbarHideTimer !== -1) {
      clearTimeout(this.toolbarHideTimer);
      this.toolbarHideTimer = -1;
    }
  }

  private handleMenusVisibilityChange(): void {
    if (this.areMenusVisible()) {
      this.clearToolbarTimer();
      this.stopAutoPageTurn();
      return;
    }
    this.scheduleToolbarAutoHide();
    this.scheduleFullscreenRestore('menus_closed', 80);
    this.syncAutoPageTurnState();
  }

  private startAutoPageTurn(): void {
    if (!this.autoPageTurnEnabled || this.autoPageTurnIntervalSeconds <= 0) {
      return;
    }
    this.stopAutoPageTurn();
    this.autoPageTurnTimer = setInterval(() => {
      const moved = this.flipPage(true);
      if (!moved) {
        this.stopAutoPageTurn();
      }
    }, this.autoPageTurnIntervalSeconds * 1000);
  }

  private stopAutoPageTurn(): void {
    if (this.autoPageTurnTimer !== -1) {
      clearInterval(this.autoPageTurnTimer);
      this.autoPageTurnTimer = -1;
    }
  }

  private syncAutoPageTurnState(): void {
    if (!this.autoPageTurnEnabled ||
      this.isLoading ||
      this.errorMessage.trim().length > 0 ||
      this.areMenusVisible() ||
      this.showTopToolbar ||
      this.showBottomToolbar ||
      !this.epubReaderController ||
      !this.epubReaderController.isReady()) {
      this.stopAutoPageTurn();
      return;
    }
    this.startAutoPageTurn();
  }

  private setAutoPageTurnEnabled(enabled: boolean): void {
    const nextSettings = this.clonePageReadingSettings(this.pageReadingSettings);
    nextSettings.autoPageTurnInterval = enabled ? this.autoPageTurnIntervalSeconds : 0;
    this.applyPageReadingSettings(nextSettings, 'toggle_auto_page_turn');
  }

  private setAutoPageTurnIntervalSeconds(value: number): void {
    const clamped = Math.max(1, Math.min(30, Math.round(value)));
    this.autoPageTurnIntervalSeconds = clamped;
    if (!this.autoPageTurnEnabled) {
      return;
    }
    const nextSettings = this.clonePageReadingSettings(this.pageReadingSettings);
    nextSettings.autoPageTurnInterval = clamped;
    this.applyPageReadingSettings(nextSettings, 'update_auto_page_turn_interval');
  }

  private isForcedProgressSave(trigger: string): boolean {
    return trigger === 'about_to_disappear' ||
      trigger === 'page_hide' ||
      trigger === 'go_back' ||
      trigger === 'chapter_list_jump' ||
      trigger === 'slider';
  }

  private getProgressSaveIntervalMs(): number {
    const seconds = Math.max(1, Math.round(this.readingSettings.saveInterval ?? 0));
    return seconds * 1000;
  }

  private scheduleFullscreenRestore(reason: string, delayMs: number = 120): void {
    this.clearFullscreenRestoreTimer();
    this.fullscreenRestoreTimer = setTimeout(() => {
      this.fullscreenRestoreTimer = -1;
      const ctx = this.uiContext ?? undefined;
      logger.debug(TAG, `重新应用沉浸模式: 原因=${reason}`);
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, ctx);
      WindowManager.reapplyCurrentDisplayMode(24);
    }, delayMs);
  }

  private clearFullscreenRestoreTimer(): void {
    if (this.fullscreenRestoreTimer !== -1) {
      clearTimeout(this.fullscreenRestoreTimer);
      this.fullscreenRestoreTimer = -1;
    }
  }

  // ──── 进度保存 ────

  private async saveReadingProgress(trigger: string): Promise<void> {
    const ebook = this.ebook;
    if (!ebook) {
      return;
    }
    const forceSave = this.isForcedProgressSave(trigger);
    const now = Date.now();
    if (!forceSave && !(this.readingSettings.autoSave ?? true)) {
      return;
    }
    const intervalMs = Math.max(
      EpubWebViewReaderPage.PROGRESS_SAVE_INTERVAL_MS,
      this.getProgressSaveIntervalMs()
    );
    if (!forceSave && (now - this.lastProgressSaveTime) < intervalMs) {
      return;
    }
    const baseTotalReadingTime = ebook.readingProgress?.totalReadingTime ?? 0;
    const sessionSecs = this.sessionStartTimestamp > 0 ? (now - this.sessionStartTimestamp) / 1000 : 0;
    const totalSpines = this.spineItems.length;
    const progressPercent = totalSpines > 0
      ? Math.min(100, ((this.currentSpineIndex + 1) / totalSpines) * 100)
      : 0;
    const progress: EBookReadingProgress = {
      bookId: ebook.id,
      currentChapterId: this.spineItems[this.currentSpineIndex]?.id ?? '',
      currentChapterIndex: this.currentSpineIndex,
      currentPosition: this.currentPageWithinSpine,
      domPos: `webview-epub:${this.currentSpineIndex}:${this.currentPageWithinSpine}`,
      progress: progressPercent,
      lastReadTime: now,
      totalReadingTime: baseTotalReadingTime + sessionSecs
    };
    try {
      await this.ebookDataManager.saveReadingProgress(progress);
      ebook.readingProgress = progress;
      this.lastProgressSaveTime = now;
      this.sessionStartTimestamp = now;
      logger.debug(TAG, `[${trigger}] 进度已保存: spine=${this.currentSpineIndex}, page=${this.currentPageWithinSpine}`);
    } catch (e) {
      logger.warn(TAG, `保存进度失败: ${String(e)}`);
    }
  }

  // ──── 返回 ────

  private openWithReaderKit(): void {
    const bookId = this.ebook?.id ?? '';
    if (!bookId) {
      this.pathStack.pop();
      return;
    }
    this.pathStack.pop();
    this.pathStack.pushPath({
      name: 'EBookReaderPage',
      param: { bookId } as EBookReaderParams
    });
  }

  private async goBack(): Promise<void> {
    if (this.areMenusVisible()) {
      this.closeTransientPanels();
      return;
    }
    this.stopAutoPageTurn();
    await this.persistTextReadingSettings('go_back');
    await this.persistPageReadingSettings('go_back');
    await this.saveReadingProgress('go_back');
    const coverCmpId = this.coverComponentId;
    if (coverCmpId) {
      try {
        await startBookCloseTransitionWithComponentId('epub_webview_reader_root', coverCmpId);
      } catch (_ignored) {
        cancelTransition();
      }
    }
    this.pathStack.pop();
  }

  private openChapterList(): void {
    this.showQuickSettings = false;
    this.showSettingsPanel = false;
    this.showPageTurnAnimationSettings = false;
    this.showAutoPageTurnSettings = false;
    this.showInteractionOverlay = false;
    this.showChapterList = true;
    this.handleMenusVisibilityChange();
  }

  private openQuickSettings(): void {
    this.showSettingsPanel = false;
    this.showChapterList = false;
    this.showPageTurnAnimationSettings = false;
    this.showAutoPageTurnSettings = false;
    this.showInteractionOverlay = false;
    this.showQuickSettings = true;
    this.handleMenusVisibilityChange();
  }

  private openTextSettings(): void {
    this.showQuickSettings = false;
    this.showChapterList = false;
    this.showPageTurnAnimationSettings = false;
    this.showAutoPageTurnSettings = false;
    this.showInteractionOverlay = false;
    this.showSettingsPanel = true;
    this.handleMenusVisibilityChange();
  }

  private openPageTurnAnimationSettings(): void {
    this.showQuickSettings = false;
    this.showChapterList = false;
    this.showSettingsPanel = false;
    this.showAutoPageTurnSettings = false;
    this.showInteractionOverlay = false;
    this.showPageTurnAnimationSettings = true;
    this.handleMenusVisibilityChange();
  }

  private openAutoPageTurnSettings(): void {
    this.showQuickSettings = false;
    this.showChapterList = false;
    this.showSettingsPanel = false;
    this.showPageTurnAnimationSettings = false;
    this.showInteractionOverlay = false;
    this.showAutoPageTurnSettings = true;
    this.handleMenusVisibilityChange();
  }

  // ──── 标题辅助 ────

  private getBookTitle(): string {
    return this.ebook?.metadata.title ?? 'EPUB 阅读器';
  }

  private getCurrentChapterTitle(): string {
    if (this.spineItems.length === 0) {
      return '';
    }
    const ch = this.spineItems[this.currentSpineIndex];
    const t = (ch?.title ?? '').trim();
    return t.length > 0 ? t : `第 ${this.currentSpineIndex + 1} 章`;
  }

  // ──── Build ────

  @Builder
  private buildLoadingView() {
    Column() {
      LoadingProgress().width(48).height(48).color($r('app.color.accent_primary'))
      Text('正在加载 EPUB…')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 12 })
        .fontFamily(this.appFontFamily)
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Black)
  }

  @Builder
  private buildErrorView() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
        .fontSize(48)
        .fontColor([$r('app.color.text_secondary')])
      Text(this.errorMessage)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 12 })
        .fontFamily(this.appFontFamily)
        .padding({ left: 24, right: 24 })
        .textAlign(TextAlign.Center)
      if (this.canFallbackToReaderKit) {
        Button('使用 ReaderKit 打开')
          .margin({ top: 24 })
          .onClick(() => { this.openWithReaderKit(); })
      }
      Button('返回')
        .margin({ top: 12 })
        .buttonStyle(ButtonStyleMode.NORMAL)
        .onClick(() => { this.pathStack.pop(); })
    }
    .width('100%').height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.Black)
  }

  @Builder
  private buildTopToolbar() {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.arrow_left'))
          .fontSize(22)
          .fontColor([this.getToolbarIconColor()])
      }
      .width(48).height(48)
      .backgroundColor(Color.Transparent)
      .onClick(() => { void this.goBack(); })

      Column() {
        Text(this.getBookTitle())
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .fontFamily(this.appFontFamily)
        if (this.getCurrentChapterTitle().length > 0) {
          Text(this.getCurrentChapterTitle())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontFamily(this.appFontFamily)
            .margin({ top: 1 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8, right: 8 })
    }
    .width('100%')
    .height(ReaderSafeAreaUtils.getTopToolbarHeight(this.statusBarHeight))
    .padding({ left: 4, right: 8, top: ReaderSafeAreaUtils.getStatusBarInset(this.statusBarHeight) })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.18)', offsetX: 0, offsetY: 4 })
    .opacity(this.toolbarOpacity)
  }

  @Builder
  private buildBottomToolbar() {
    Column() {
      // 进度条行
      Row() {
        Text(`${this.currentSpineIndex + 1}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width(36)
          .textAlign(TextAlign.Center)
          .fontFamily(this.appFontFamily)

        Slider({
          value: this.currentSpineIndex,
          min: 0,
          max: Math.max(0, this.spineItems.length - 1),
          step: 1
        })
          .layoutWeight(1)
          .trackColor($r('app.color.divider_primary'))
          .selectedColor($r('app.color.accent_primary'))
          .onChange((value: number) => {
            const idx = Math.round(value);
            if (idx !== this.currentSpineIndex) {
              this.loadSpineItem(idx, 0);
              void this.saveReadingProgress('slider');
            }
          })

        Text(`${this.spineItems.length}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width(36)
          .textAlign(TextAlign.Center)
          .fontFamily(this.appFontFamily)
      }
      .width('100%')
      .padding({ left: 8, right: 8 })

      // 页内进度（仅在多页时显示）
      if (this.totalPagesInSpine > 1) {
        Column() {
          Text(`本章 ${this.currentPageWithinSpine + 1} / ${this.totalPagesInSpine} 页`)
            .fontSize(11)
            .fontColor($r('app.color.text_muted'))
            .margin({ bottom: 4 })
            .fontFamily(this.appFontFamily)

          Row() {
            Text('1')
              .fontSize(10)
              .fontColor($r('app.color.text_muted'))
              .width(24)
              .textAlign(TextAlign.Center)
              .fontFamily(this.appFontFamily)

            Slider({
              value: this.currentPageWithinSpine,
              min: 0,
              max: Math.max(0, this.totalPagesInSpine - 1),
              step: 1
            })
              .layoutWeight(1)
              .trackColor($r('app.color.divider_primary'))
              .selectedColor($r('app.color.accent_primary'))
              .onChange((value: number) => {
                const nextPage = Math.round(value);
                if (nextPage !== this.currentPageWithinSpine) {
                  this.jumpToCurrentSpinePage(nextPage);
                }
              })

            Text(`${this.totalPagesInSpine}`)
              .fontSize(10)
              .fontColor($r('app.color.text_muted'))
              .width(24)
              .textAlign(TextAlign.Center)
              .fontFamily(this.appFontFamily)
          }
          .width('100%')
          .padding({ left: 8, right: 8 })
        }
        .width('100%')
        .margin({ bottom: 4 })
      }

      // 功能按钮行
      Row() {
        Button() {
          SymbolGlyph($r('sys.symbol.list_bullet'))
            .fontSize(22)
            .fontColor([this.getToolbarIconColor()])
        }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openChapterList();
        })

        Blank()

        Button() {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(22)
            .fontColor([this.getToolbarIconColor()])
        }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openQuickSettings();
        })

        Blank()

        Button() {
          SymbolGlyph($r('sys.symbol.circle_on_circle'))
            .fontSize(22)
            .fontColor([this.getToolbarIconColor()])
        }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openPageTurnAnimationSettings();
        })

        Blank()

        Button() {
          SymbolGlyph($r('sys.symbol.eye'))
            .fontSize(22)
            .fontColor([this.getToolbarIconColor()])
        }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openTextSettings();
        })

        Blank()

        Button() {
          SymbolGlyph(this.getAutoPageTurnIconResource())
            .fontSize(22)
            .fontColor([this.getToolbarIconColor(this.autoPageTurnEnabled)])
        }
        .width(48).height(48).backgroundColor(Color.Transparent)
        .onClick(() => {
          this.openAutoPageTurnSettings();
        })
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: this.navigationBarHeight })
    }
    .width('100%')
    .backgroundColor(this.themeManager.getGlassBackgroundResource())
    .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.18)', offsetX: 0, offsetY: -2 })
    .opacity(this.toolbarOpacity)
  }

  @Builder
  private buildAnimButton(label: string, type: PageTurnAnimationType) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontColor(this.pageReadingSettings.pageTurnAnimation === type ?
          $r('app.color.accent_primary') : $r('app.color.text_secondary'))
    }
    .width('31%')
    .padding(10)
    .backgroundColor(this.pageReadingSettings.pageTurnAnimation === type ?
      $r('app.color.accent_background') : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      const nextSettings = this.clonePageReadingSettings(this.pageReadingSettings);
      nextSettings.pageTurnAnimation = type;
      this.applyPageReadingSettings(nextSettings, 'page_turn_animation_select');
    })
  }

  @Builder
  private buildPageTurnAnimationSettings() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5)
        .onClick(() => {
          this.showPageTurnAnimationSettings = false;
          this.handleMenusVisibilityChange();
        })

      if (this.isLandscapeMode) {
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.showPageTurnAnimationSettings = false;
              this.handleMenusVisibilityChange();
            })

          Column() {
            Row() {
              Text('翻页动画设置')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .fontFamily(this.appFontFamily)

              Button() {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(18)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width(36)
              .height(36)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.showPageTurnAnimationSettings = false;
                this.handleMenusVisibilityChange();
              })
            }
            .width('100%')
            .margin({ bottom: 16 })

            Column() {
              Row() {
                this.buildAnimButton('无', PageTurnAnimationType.NONE)
                this.buildAnimButton('滑动', PageTurnAnimationType.SLIDE)
                this.buildAnimButton('淡入淡出', PageTurnAnimationType.FADE)
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
              .margin({ bottom: 8 })

              Row() {
                this.buildAnimButton('立方体', PageTurnAnimationType.CUBE)
                this.buildAnimButton('覆盖', PageTurnAnimationType.COVER)
                this.buildAnimButton('景深', PageTurnAnimationType.DEPTH)
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
            }
            .width('100%')
          }
          .width(320)
          .height('100%')
          .padding(16)
          .backgroundColor(this.themeManager.getGlassBackgroundResource())
          .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
          .borderRadius({ topLeft: 16, bottomLeft: 16 })
        }
        .width('100%')
        .height('100%')
      } else {
        Column() {
          Row() {
            Text('翻页动画设置')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .fontFamily(this.appFontFamily)

            Button() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([$r('app.color.text_secondary')])
            }
            .width(36)
            .height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.showPageTurnAnimationSettings = false;
              this.handleMenusVisibilityChange();
            })
          }
          .width('100%')
          .margin({ bottom: 16 })

          Row() {
            this.buildAnimButton('无', PageTurnAnimationType.NONE)
            this.buildAnimButton('滑动', PageTurnAnimationType.SLIDE)
            this.buildAnimButton('淡入淡出', PageTurnAnimationType.FADE)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
          .margin({ bottom: 8 })

          Row() {
            this.buildAnimButton('立方体', PageTurnAnimationType.CUBE)
            this.buildAnimButton('覆盖', PageTurnAnimationType.COVER)
            this.buildAnimButton('景深', PageTurnAnimationType.DEPTH)
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('90%')
        .constraintSize({ maxWidth: 400 })
        .padding(20)
        .backgroundColor(this.themeManager.getGlassBackgroundResource())
        .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
        .borderRadius(16)
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(240)
  }

  @Builder
  private buildAutoPageTurnSettings() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_overlay'))
        .opacity(0.5)
        .onClick(() => {
          this.showAutoPageTurnSettings = false;
          this.handleMenusVisibilityChange();
        })

      if (this.isLandscapeMode) {
        Row() {
          Column()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.showAutoPageTurnSettings = false;
              this.handleMenusVisibilityChange();
            })

          Column() {
            Row() {
              Text('自动翻页设置')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .fontFamily(this.appFontFamily)

              Button() {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(18)
                  .fontColor([$r('app.color.text_secondary')])
              }
              .width(36)
              .height(36)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.showAutoPageTurnSettings = false;
                this.handleMenusVisibilityChange();
              })
            }
            .width('100%')
            .margin({ bottom: 16 })

            Text('翻页间隔')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .width('100%')
              .margin({ bottom: 8 })
              .fontFamily(this.appFontFamily)

            Row() {
              Text(`${this.autoPageTurnIntervalSeconds}s`)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.accent_primary'))
                .width(50)
                .fontFamily(this.appFontFamily)

              Slider({
                value: this.autoPageTurnIntervalSeconds,
                min: 1,
                max: 30,
                step: 1
              })
                .layoutWeight(1)
                .trackColor($r('app.color.divider_primary'))
                .selectedColor($r('app.color.accent_primary'))
                .onChange((value: number) => {
                  this.setAutoPageTurnIntervalSeconds(value);
                })
            }
            .width('100%')
            .margin({ bottom: 16 })

            Row() {
              Text('启用自动翻页')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .fontFamily(this.appFontFamily)

              Toggle({ type: ToggleType.Switch, isOn: this.autoPageTurnEnabled })
                .selectedColor($r('app.color.accent_primary'))
                .onChange((isOn: boolean) => {
                  this.setAutoPageTurnEnabled(isOn);
                })
            }
            .width('100%')
          }
          .width(320)
          .height('100%')
          .padding(16)
          .backgroundColor(this.themeManager.getGlassBackgroundResource())
          .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
          .borderRadius({ topLeft: 16, bottomLeft: 16 })
        }
        .width('100%')
        .height('100%')
      } else {
        Column() {
          Row() {
            Text('自动翻页设置')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .fontFamily(this.appFontFamily)

            Button() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([$r('app.color.text_secondary')])
            }
            .width(36)
            .height(36)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.showAutoPageTurnSettings = false;
              this.handleMenusVisibilityChange();
            })
          }
          .width('100%')
          .margin({ bottom: 16 })

          Text('翻页间隔')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ bottom: 8 })
            .fontFamily(this.appFontFamily)

          Row() {
            Text(`${this.autoPageTurnIntervalSeconds}s`)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.accent_primary'))
              .width(50)
              .fontFamily(this.appFontFamily)

            Slider({
              value: this.autoPageTurnIntervalSeconds,
              min: 1,
              max: 30,
              step: 1
            })
              .layoutWeight(1)
              .trackColor($r('app.color.divider_primary'))
              .selectedColor($r('app.color.accent_primary'))
              .onChange((value: number) => {
                this.setAutoPageTurnIntervalSeconds(value);
              })
          }
          .width('100%')
          .margin({ bottom: 16 })

          Row() {
            Text('启用自动翻页')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
              .fontFamily(this.appFontFamily)

            Toggle({ type: ToggleType.Switch, isOn: this.autoPageTurnEnabled })
              .selectedColor($r('app.color.accent_primary'))
              .onChange((isOn: boolean) => {
                this.setAutoPageTurnEnabled(isOn);
              })
          }
          .width('100%')
        }
        .width('90%')
        .constraintSize({ maxWidth: 400 })
        .padding(20)
        .backgroundColor(this.themeManager.getGlassBackgroundResource())
        .backgroundBlurStyle(this.themeManager.getGlassBlurStyle())
        .borderRadius(16)
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(240)
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // ── 内容层 ──
        if (this.isLoading) {
          this.buildLoadingView()
        } else if (this.errorMessage.trim().length > 0) {
          this.buildErrorView()
        } else {
          Column() {
            EpubWebViewReaderComponent({
              params: {
                initialSpineFilePath: this.resolveSpinePath(this.currentSpineIndex),
                initialPageOffset: this.currentPageWithinSpine,
                textSettings: this.readingSettings,
                pageSettings: this.pageReadingSettings,
                isFixedLayout: this.isFixedLayout,
                callbacks: {
                  onPageChange: (page: number, totalPages: number) => {
                    this.currentPageWithinSpine = page;
                    this.totalPagesInSpine = totalPages;
                    this.syncAutoPageTurnState();
                    void this.saveReadingProgress('page_change');
                  },
                  onSpineChangeRequested: (direction: 'prev' | 'next') => {
                    this.onSpineChangeRequested(direction);
                  },
                  onReady: (controller: EpubWebViewReaderController) => {
                    this.epubReaderController = controller;
                    this.syncAutoPageTurnState();
                    this.notifyTransitionReaderReadyOnce('webview_layout_ready');
                    logger.info(TAG, 'EpubWebView 控制器就绪');
                  },
                  onError: (msg: string) => {
                    logger.warn(TAG, `WebView 错误: ${msg}`);
                    if (!this.hasNotifiedTransitionReaderReady) {
                      logger.warn(TAG, 'WebView 初始加载失败，取消翻开过渡遮罩');
                      cancelTransition();
                    }
                  }
                }
              } as EpubWebViewReaderParams
            })
              .width('100%')
              .height('100%')
          }
          .width('100%')
          .height('100%')
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const widthVp = Number(newArea.width);
            const heightVp = Number(newArea.height);
            if (widthVp > 0 && heightVp > 0) {
              const widthChanged = Math.abs(widthVp - this.componentWidth) > 1;
              const heightChanged = Math.abs(heightVp - this.componentHeight) > 1;
              this.componentWidth = widthVp;
              this.componentHeight = heightVp;
              this.isLandscapeMode = widthVp > heightVp;
              if (widthChanged || heightChanged) {
                const normalizedSettings = this.normalizePageReadingSettings(this.pageReadingSettings);
                if (!this.arePageReadingSettingsEqual(normalizedSettings, this.pageReadingSettings)) {
                  this.pageReadingSettings = this.clonePageReadingSettings(normalizedSettings);
                  this.autoPageTurnEnabled = normalizedSettings.autoPageTurnInterval > 0;
                  if (this.autoPageTurnEnabled) {
                    this.autoPageTurnIntervalSeconds = normalizedSettings.autoPageTurnInterval;
                  }
                  void this.persistPageReadingSettings('component_area_change');
                }
                this.epubReaderController?.applyPageSettings(normalizedSettings);
              }
            }
          })
        }

        // ── 手势截取层 ──
        if (!this.isLoading && this.errorMessage.trim().length === 0) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(Color.Transparent)
            .hitTestBehavior(HitTestMode.Block)
            .onClick((event: ClickEvent) => { this.handlePageTap(event); })
            .gesture(
              PanGesture({ direction: PanDirection.All, distance: 40 })
                .onActionEnd((event: GestureEvent) => {
                  this.handleSwipe(event);
                })
            )
        }

        // ── 顶部工具栏 ──
        if (this.showTopToolbar) {
          Column() {
            this.buildTopToolbar()
          }
          .width('100%')
          .align(Alignment.TopStart)
          .position({ x: 0, y: 0 })
          .zIndex(100)
        }

        // ── 底部工具栏 ──
        if (this.showBottomToolbar) {
          Column() {
            this.buildBottomToolbar()
          }
          .width('100%')
          .position({ x: 0, y: '100%' })
          .translate({ x: 0, y: '-100%' })
          .zIndex(100)
        }

        // ── 快捷设置面板 ──
        if (this.showQuickSettings) {
          MangaQuickSettings({
            readingSettings: this.pageReadingSettings,
            isVisible: this.showQuickSettings,
            callbacks: {
              onSettingsChange: (settings: MangaReadingSettings) => {
                this.applyPageReadingSettings(settings, 'quick_settings_change', true);
              },
              onClose: () => {
                this.showQuickSettings = false;
                this.handleMenusVisibilityChange();
              },
              onOpenFullSettings: () => {
                this.showQuickSettings = false;
                this.openTextSettings();
              }
            }
          })
          .zIndex(210)
        }

        // ── 文字/主题设置面板 ──
        if (this.showSettingsPanel) {
          EpubReaderSettingsPanel({
            settings: this.readingSettings,
            isVisible: this.showSettingsPanel,
            callbacks: {
              onSettingsChange: (newSettings: EBookReadingSettings) => {
                const mergedSettings = this.mergeTextReadingSettings(newSettings);
                this.readingSettings = mergedSettings;
                if (this.ebook) {
                  this.ebook.readingSettings = this.cloneTextReadingSettings(mergedSettings);
                }
                this.epubReaderController?.applyReadingSettings(mergedSettings);
                const bookId = this.ebook?.id ?? '';
                if (bookId.length > 0) {
                  void this.ebookDataManager.saveReadingSettings(bookId, mergedSettings);
                }
              },
              onClose: () => {
                this.showSettingsPanel = false;
                this.handleMenusVisibilityChange();
                this.scheduleFullscreenRestore('settings_closed', 80);
              }
            } as EpubSettingsPanelCallbacks
          })
          .zIndex(220)
        }

        // ── 章节列表（自带遮罩与动画）──
        if (this.showChapterList) {
          EpubReaderChapterList({
            chapters: this.spineItems,
            currentIndex: this.currentSpineIndex,
            isVisible: this.showChapterList,
            callbacks: {
              onChapterSelect: (spineIndex: number) => {
                this.loadSpineItem(spineIndex, 0);
                this.showChapterList = false;
                this.handleMenusVisibilityChange();
                void this.saveReadingProgress('chapter_list_jump');
              },
              onClose: () => {
                this.showChapterList = false;
                this.handleMenusVisibilityChange();
                this.scheduleFullscreenRestore('chapter_list_closed', 80);
              }
            } as EpubChapterListCallbacks
          })
          .zIndex(220)
        }

        if (this.showPageTurnAnimationSettings) {
          this.buildPageTurnAnimationSettings()
        }

        if (this.showAutoPageTurnSettings) {
          this.buildAutoPageTurnSettings()
        }

        if (this.showInteractionOverlay) {
          MangaInteractionOverlay({
            params: {
              readingMode: this.pageReadingSettings.readingMode,
              readingDirection: this.pageReadingSettings.readingDirection,
              componentWidth: this.getEffectiveComponentWidth(),
              componentHeight: this.getEffectiveComponentHeight(),
              deviceOrientation: this.getDeviceOrientation(),
              statusBarHeight: this.statusBarHeight,
              navigationBarHeight: this.navigationBarHeight,
              onDismiss: () => {
                this.showInteractionOverlay = false;
                this.handleMenusVisibilityChange();
              }
            }
          })
          .zIndex(230)
        }
      }
      .width('100%')
      .height('100%')
      .id('epub_webview_reader_root')
      .backgroundColor(Color.Black)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onKeyEvent((event: KeyEvent) => {
        if (event.type === KeyType.Up) {
          if (this.handleVolumeKey(event.keyCode)) {
            event.stopPropagation();
          }
        }
      })
    }
    .hideTitleBar(true)
    .onBackPressed(() => {
      if (this.areMenusVisible()) {
        this.closeTransientPanels();
        return true;
      }
      void this.goBack();
      return true;
    })
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      this.uiContext = this.getUIContext();
      PageWindowCoordinator.applyPagePolicy('EpubWebViewReaderPage', this.uiContext);
      WindowManager.setDisplayMode(DisplayMode.FULL_IMMERSIVE, this.uiContext);
      const params = ctx.pathInfo.param as EBookReaderParams;
      if (params?.bookId) {
        void this.initializeWithParams(params);
      } else {
        this.errorMessage = '缺少书籍参数';
        this.isLoading = false;
      }
    })
  }
}
