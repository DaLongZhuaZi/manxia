import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import {
  curves,
  display,
  matrix4,
  UIContext
} from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import {
  EBookReadingSettings,
  DEFAULT_EBOOK_READING_SETTINGS
} from '../../Models/EBookModels';
import {
  ReadingSettings as MangaReadingSettings,
  ReadingMode,
  ReadingDirection,
  DoublePagePortraitLayout,
  DEFAULT_READING_SETTINGS,
  PageTurnAnimationType
} from '../../Models/MangaModels';

const TAG = 'EpubWebViewReaderComponent';
const SETTINGS_APPLY_DELAY_MS = 80;
const REFLOW_SETTLE_DELAY_MS = 260;
const INITIAL_LAYOUT_RECONCILE_DELAY_MS = 480;

interface FixedLayoutDimension {
  w: number;
  h: number;
}

interface ViewportDims {
  w: number;
  h: number;
  visualW: number;
  visualH: number;
  visualScale: number;
}

type EpubPageLayoutKind =
  'horizontal_paged' |
  'vertical_paged' |
  'double_page' |
  'continuous_horizontal' |
  'continuous_vertical';
export type EpubSpineTransitionDirection = 'prev' | 'next' | 'none';

interface ViewportAnimationState {
  opacity: number;
  matrix: matrix4.Matrix4Transit;
}

interface PageTurnAnimationProfile {
  outgoing: ViewportAnimationState;
  incoming: ViewportAnimationState;
  outDuration: number;
  inDuration: number;
  outCurve: Curve;
  inCurve: Curve;
}

interface PaginationMetrics {
  pageCount: number;
  currentPage: number;
  currentOffset: number;
  pageExtent: number;
  maxOffset: number;
  innerWidth: number;
  innerHeight: number;
  visualViewportWidth: number;
  visualViewportHeight: number;
  visualViewportScale: number;
  scrollWidth: number;
  scrollHeight: number;
  rootFontSize: string;
  bodyFontSize: string;
  bodyLineHeight: string;
  sampleTagName: string;
  sampleFontSize: string;
  sampleLineHeight: string;
  sampleTextAlign: string;
  styleTagParent: string;
  isStyleTagLastChild: boolean;
  rootTagName: string;
}

interface PageCommandResult {
  pageIndex: number;
  offset: number;
  pageCount: number;
  pageExtent: number;
  maxOffset: number;
}

interface PaginationUpdatePayload {
  source: string;
  layoutKind: string;
  pageCount: number;
  currentPage: number;
  currentOffset: number;
  pageExtent: number;
  maxOffset: number;
  atStart: boolean;
  atEnd: boolean;
}

interface ReaderTapPayload {
  xRatio: number;
  yRatio: number;
}

interface EpubReaderJsProxy {
  onPaginationChanged: (payloadJson: string) => void;
  onReaderTap: (payloadJson: string) => void;
}

interface PendingSpineTransitionState {
  incoming: ViewportAnimationState;
  inDuration: number;
  inCurve: Curve;
}

export interface EpubWebViewReaderController {
  loadSpineItem(
    spineFilePath: string,
    pageOffset: number,
    transitionDirection?: EpubSpineTransitionDirection
  ): void;
  flipPage(forward: boolean): boolean;
  goToPage(pageIndex: number): boolean;
  getPageCount(): number;
  getCurrentPage(): number;
  applyReadingSettings(settings: EBookReadingSettings): void;
  applyPageSettings(settings: MangaReadingSettings): void;
  isReady(): boolean;
}

export interface EpubWebViewReaderCallbacks {
  onPageChange: (page: number, totalPages: number) => void;
  onSpineChangeRequested: (direction: 'prev' | 'next') => void;
  onReady: (controller: EpubWebViewReaderController) => void;
  onError: (msg: string) => void;
  onReaderTap?: (xRatio: number, yRatio: number) => void;
}

export interface EpubWebViewReaderParams {
  initialSpineFilePath: string;
  initialPageOffset: number;
  textSettings: EBookReadingSettings;
  pageSettings: MangaReadingSettings;
  isFixedLayout: boolean;
  callbacks: EpubWebViewReaderCallbacks;
}

class EpubWebViewReaderControllerImpl implements EpubWebViewReaderController {
  private fnLoad: (
    path: string,
    offset: number,
    transitionDirection: EpubSpineTransitionDirection
  ) => void;
  private fnFlip: (forward: boolean) => boolean;
  private fnGoToPage: (pageIndex: number) => boolean;
  private fnGetCount: () => number;
  private fnGetCurrent: () => number;
  private fnApplySettings: (s: EBookReadingSettings) => void;
  private fnApplyPageSettings: (s: MangaReadingSettings) => void;
  private fnIsReady: () => boolean;

  constructor(
    fnLoad: (
      path: string,
      offset: number,
      transitionDirection: EpubSpineTransitionDirection
    ) => void,
    fnFlip: (forward: boolean) => boolean,
    fnGoToPage: (pageIndex: number) => boolean,
    fnGetCount: () => number,
    fnGetCurrent: () => number,
    fnApplySettings: (s: EBookReadingSettings) => void,
    fnApplyPageSettings: (s: MangaReadingSettings) => void,
    fnIsReady: () => boolean
  ) {
    this.fnLoad = fnLoad;
    this.fnFlip = fnFlip;
    this.fnGoToPage = fnGoToPage;
    this.fnGetCount = fnGetCount;
    this.fnGetCurrent = fnGetCurrent;
    this.fnApplySettings = fnApplySettings;
    this.fnApplyPageSettings = fnApplyPageSettings;
    this.fnIsReady = fnIsReady;
  }

  loadSpineItem(
    spineFilePath: string,
    pageOffset: number,
    transitionDirection: EpubSpineTransitionDirection = 'none'
  ): void {
    this.fnLoad(spineFilePath, pageOffset, transitionDirection);
  }

  flipPage(forward: boolean): boolean {
    return this.fnFlip(forward);
  }

  goToPage(pageIndex: number): boolean {
    return this.fnGoToPage(pageIndex);
  }

  getPageCount(): number {
    return this.fnGetCount();
  }

  getCurrentPage(): number {
    return this.fnGetCurrent();
  }

  applyReadingSettings(settings: EBookReadingSettings): void {
    this.fnApplySettings(settings);
  }

  applyPageSettings(settings: MangaReadingSettings): void {
    this.fnApplyPageSettings(settings);
  }

  isReady(): boolean {
    return this.fnIsReady();
  }
}

@Component
export struct EpubWebViewReaderComponent {
  @Prop params: EpubWebViewReaderParams;

  private uiContext: UIContext | null = null;
  private webviewController: webview.WebviewController = new webview.WebviewController();
  private currentPageCount: number = 0;
  private currentPage: number = 0;
  private ready: boolean = false;
  private isPageTurnAnimating: boolean = false;
  private pendingPageOffset: number = 0;
  private pendingSpinePath: string = '';
  private applySettingsTimer: number = -1;
  private pageTurnPhaseTimer: number = -1;
  private pendingSpineTransition: PendingSpineTransitionState | null = null;
  private boundarySwitchTimer: number = -1;
  private currentLayoutKind: EpubPageLayoutKind = 'horizontal_paged';
  private lastPaginationOffset: number = 0;
  private lastPaginationMaxOffset: number = 0;
  private lastPaginationPageExtent: number = 0;
  private lastProgressRatio: number = 0;
  private lastBoundarySwitchTime: number = 0;
  private boundarySuppressionUntil: number = 0;
  private activeTextSettings: EBookReadingSettings = {
    fontSize: DEFAULT_EBOOK_READING_SETTINGS.fontSize,
    fontFamily: DEFAULT_EBOOK_READING_SETTINGS.fontFamily,
    fontPath: DEFAULT_EBOOK_READING_SETTINGS.fontPath,
    fontWeight: DEFAULT_EBOOK_READING_SETTINGS.fontWeight,
    lineHeight: DEFAULT_EBOOK_READING_SETTINGS.lineHeight,
    backgroundColor: DEFAULT_EBOOK_READING_SETTINGS.backgroundColor,
    textColor: DEFAULT_EBOOK_READING_SETTINGS.textColor,
    themeBgImage: DEFAULT_EBOOK_READING_SETTINGS.themeBgImage,
    nightMode: DEFAULT_EBOOK_READING_SETTINGS.nightMode,
    followSystemTheme: DEFAULT_EBOOK_READING_SETTINGS.followSystemTheme,
    pageMargin: DEFAULT_EBOOK_READING_SETTINGS.pageMargin,
    pageMode: DEFAULT_EBOOK_READING_SETTINGS.pageMode,
    brightness: DEFAULT_EBOOK_READING_SETTINGS.brightness,
    autoSave: DEFAULT_EBOOK_READING_SETTINGS.autoSave,
    saveInterval: DEFAULT_EBOOK_READING_SETTINGS.saveInterval
  };
  private activePageSettings: MangaReadingSettings = DEFAULT_READING_SETTINGS;
  private hostWidthVp: number = 0;
  private hostHeightVp: number = 0;
  private fallbackVpW: number = 0;
  private fallbackVpH: number = 0;
  private lastVpW: number = 0;
  private lastVpH: number = 0;
  private lastVisualVpW: number = 0;
  private lastVisualVpH: number = 0;
  private lastVisualVpScale: number = 1;
  private jsProxy: EpubReaderJsProxy = {
    onPaginationChanged: (payloadJson: string): void => {
      this.handlePaginationChanged(payloadJson);
    },
    onReaderTap: (payloadJson: string): void => {
      this.handleReaderTap(payloadJson);
    }
  };

  @State private viewportOpacity: number = 1;
  @State private viewportMatrix: matrix4.Matrix4Transit = matrix4.identity();
  @State private viewportBackgroundColor: string = DEFAULT_EBOOK_READING_SETTINGS.backgroundColor;

  aboutToAppear(): void {
    this.uiContext = this.resolveUiContext();
    const dm = display.getDefaultDisplaySync();
    this.fallbackVpW = px2vp(dm.width);
    this.fallbackVpH = px2vp(dm.height);
    this.pendingSpinePath = this.params.initialSpineFilePath;
    this.pendingPageOffset = this.params.initialPageOffset;
    this.activeTextSettings = this.cloneTextSettings(this.params.textSettings);
    this.activePageSettings = this.clonePageSettings(this.params.pageSettings);
    this.viewportBackgroundColor = this.activeTextSettings.backgroundColor;
    this.resetViewportTransform();
    logger.info(
      TAG,
      `组件初始化: spine=${this.pendingSpinePath}, pageOffset=${this.pendingPageOffset}, fixed=${this.params.isFixedLayout}, text(${this.describeTextSettings(this.activeTextSettings)}), page(${this.describePageSettings(this.activePageSettings)})`
    );
  }

  aboutToDisappear(): void {
    this.clearDeferredWork();
    this.resetViewportTransform();
    this.pendingSpineTransition = null;
    this.uiContext = null;
  }

  private clearApplySettingsTimer(): void {
    if (this.applySettingsTimer !== -1) {
      clearTimeout(this.applySettingsTimer);
      this.applySettingsTimer = -1;
    }
  }

  private clearPageTurnPhaseTimer(): void {
    if (this.pageTurnPhaseTimer !== -1) {
      clearTimeout(this.pageTurnPhaseTimer);
      this.pageTurnPhaseTimer = -1;
    }
  }

  private clearDeferredWork(): void {
    this.clearApplySettingsTimer();
    this.clearPageTurnPhaseTimer();
    this.clearBoundarySwitchTimer();
  }

  private clearBoundarySwitchTimer(): void {
    if (this.boundarySwitchTimer !== -1) {
      clearTimeout(this.boundarySwitchTimer);
      this.boundarySwitchTimer = -1;
    }
  }

  private resolveUiContext(): UIContext | null {
    if (this.uiContext) {
      return this.uiContext;
    }
    try {
      this.uiContext = this.getUIContext();
      return this.uiContext;
    } catch (_error) {
      return null;
    }
  }

  private runJs(code: string, onResult?: (result: string) => void): void {
    try {
      this.webviewController.runJavaScript(code, (error: BusinessError | null, result: string) => {
        if (error) {
          logger.warn(TAG, `runJavaScript failed: ${error.message}`);
          return;
        }
        if (onResult) {
          onResult(result);
        }
      });
    } catch (error) {
      logger.warn(TAG, `runJavaScript threw: ${String(error)}`);
    }
  }

  private parseWebViewJson(raw: string): string {
    if (raw.startsWith('"') && raw.endsWith('"')) {
      try {
        return JSON.parse(raw) as string;
      } catch (_error) {
        return raw;
      }
    }
    return raw;
  }

  private queryViewportThenInject(pageOffset: number, source: string): void {
    this.runJs(
      '(function(){return JSON.stringify({w:window.innerWidth,h:window.innerHeight,visualW:window.visualViewport?(window.visualViewport.width||0):0,visualH:window.visualViewport?(window.visualViewport.height||0):0,visualScale:window.visualViewport?(window.visualViewport.scale||0):0});})();',
      (raw: string) => {
        let vpW = this.fallbackVpW;
        let vpH = this.fallbackVpH;
        let visualW = this.fallbackVpW;
        let visualH = this.fallbackVpH;
        let visualScale = 1;
        try {
          const clean = this.parseWebViewJson(raw);
          const dims = JSON.parse(clean) as ViewportDims;
          if (dims.w > 0) {
            vpW = dims.w;
          }
          if (dims.h > 0) {
            vpH = dims.h;
          }
          if (dims.visualW > 0) {
            visualW = dims.visualW;
          }
          if (dims.visualH > 0) {
            visualH = dims.visualH;
          }
          if (dims.visualScale > 0) {
            visualScale = dims.visualScale;
          }
        } catch (_error) {
          logger.warn(TAG, 'Viewport JSON parse failed, fallback to display metrics');
        }
        this.lastVpW = vpW;
        this.lastVpH = vpH;
        this.lastVisualVpW = visualW;
        this.lastVisualVpH = visualH;
        this.lastVisualVpScale = visualScale;
        this.applyInjectedLayout(
          vpW,
          vpH,
          pageOffset,
          this.activeTextSettings,
          this.activePageSettings,
          true,
          source
        );
      }
    );
  }

  private cloneTextSettings(settings: EBookReadingSettings): EBookReadingSettings {
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
      letterSpacing: settings.letterSpacing,
      paragraphSpacing: settings.paragraphSpacing,
      firstLineIndent: settings.firstLineIndent,
      textAlignment: settings.textAlignment,
      pageTurnAnimation: settings.pageTurnAnimation,
      tapToTurn: settings.tapToTurn,
      volumeKeyNavigation: settings.volumeKeyNavigation,
      keepScreenOn: settings.keepScreenOn,
      showPageNumber: settings.showPageNumber,
      showProgress: settings.showProgress,
      showTime: settings.showTime,
      showBattery: settings.showBattery,
      backgroundType: settings.backgroundType,
      backgroundImagePath: settings.backgroundImagePath,
      backgroundImageOpacity: settings.backgroundImageOpacity
    };
  }

  private clonePageSettings(settings: MangaReadingSettings): MangaReadingSettings {
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

  private clamp(value: number, min: number, max: number): number {
    const normalized = isNaN(value) ? min : value;
    return Math.max(min, Math.min(max, normalized));
  }

  private describeTextSettings(settings: EBookReadingSettings): string {
    return `fontSize=${settings.fontSize}, lineHeight=${settings.lineHeight}, pageMargin=${settings.pageMargin}, bg=${settings.backgroundColor}, text=${settings.textColor}, align=${settings.textAlignment ?? 'JUSTIFY'}, bgType=${settings.backgroundType ?? 'COLOR'}`;
  }

  private describePageSettings(settings: MangaReadingSettings): string {
    return `mode=${settings.readingMode}, direction=${settings.readingDirection}, animation=${settings.pageTurnAnimation}, doublePagePortrait=${settings.doublePagePortraitLayout}`;
  }

  private getViewportScale(vpW: number, vpH: number): number {
    const baseW = this.lastVisualVpW > 0 ? this.lastVisualVpW : (this.fallbackVpW > 0 ? this.fallbackVpW : vpW);
    const baseH = this.lastVisualVpH > 0 ? this.lastVisualVpH : (this.fallbackVpH > 0 ? this.fallbackVpH : vpH);
    const scaleW = baseW > 0 ? vpW / baseW : 1;
    const scaleH = baseH > 0 ? vpH / baseH : 1;
    const safeScaleW = isNaN(scaleW) || scaleW <= 0 ? 1 : scaleW;
    const safeScaleH = isNaN(scaleH) || scaleH <= 0 ? 1 : scaleH;
    return this.clamp(Math.min(safeScaleW, safeScaleH), 1, 4);
  }

  private getLayoutKind(settings: MangaReadingSettings, vpW: number, vpH: number): EpubPageLayoutKind {
    if (this.isContinuousVerticalMode(settings)) {
      return 'continuous_vertical';
    }
    if (this.isContinuousHorizontalMode(settings)) {
      return 'continuous_horizontal';
    }
    if (settings.readingMode === ReadingMode.SINGLE_PAGE_TTB) {
      return 'vertical_paged';
    }
    if (settings.readingMode === ReadingMode.DOUBLE_PAGE &&
      (vpW > vpH || settings.doublePagePortraitLayout === DoublePagePortraitLayout.HORIZONTAL)) {
      return 'double_page';
    }
    return 'horizontal_paged';
  }

  private isContinuousVerticalMode(settings: MangaReadingSettings = this.activePageSettings): boolean {
    return settings.readingMode === ReadingMode.WEBTOON ||
      settings.readingMode === ReadingMode.WEBTOON_WITH_GAP ||
      settings.readingMode === ReadingMode.CONTINUOUS_VERTICAL;
  }

  private isContinuousHorizontalMode(settings: MangaReadingSettings = this.activePageSettings): boolean {
    return settings.readingMode === ReadingMode.CONTINUOUS_SCROLL;
  }

  private isContinuousMode(settings: MangaReadingSettings = this.activePageSettings): boolean {
    return this.isContinuousVerticalMode(settings) || this.isContinuousHorizontalMode(settings);
  }

  private computeProgressRatio(
    pageIndex: number,
    pageCount: number,
    currentOffset: number,
    maxOffset: number
  ): number {
    if (maxOffset > 0) {
      return this.clamp(currentOffset / maxOffset, 0, 1);
    }
    if (pageCount > 1) {
      return this.clamp(pageIndex / Math.max(1, pageCount - 1), 0, 1);
    }
    return 0;
  }

  private normalizeAnimationType(animationType: PageTurnAnimationType): PageTurnAnimationType {
    if (animationType === PageTurnAnimationType.FLIP) {
      return PageTurnAnimationType.CUBE;
    }
    if (animationType === PageTurnAnimationType.ZOOM) {
      return PageTurnAnimationType.DEPTH;
    }
    if (animationType === PageTurnAnimationType.CURL) {
      return PageTurnAnimationType.COVER;
    }
    return animationType;
  }

  private buildMatrix(
    translateX: number,
    translateY: number,
    translateZ: number,
    scaleX: number,
    scaleY: number,
    rotateX: number,
    rotateY: number
  ): matrix4.Matrix4Transit {
    let matrix = matrix4.identity();
    matrix = matrix.translate({ x: translateX, y: translateY, z: translateZ });
    if (rotateX !== 0) {
      matrix = matrix.rotate({ x: 1, y: 0, z: 0, angle: rotateX });
    }
    if (rotateY !== 0) {
      matrix = matrix.rotate({ x: 0, y: 1, z: 0, angle: rotateY });
    }
    matrix = matrix.scale({ x: scaleX, y: scaleY, z: 1 });
    return matrix;
  }

  private resetViewportTransform(): void {
    this.viewportOpacity = 1;
    this.viewportMatrix = matrix4.identity();
  }

  private applyViewportState(state: ViewportAnimationState): void {
    this.viewportOpacity = state.opacity;
    this.viewportMatrix = state.matrix;
  }

  private getAnimationDirectionSign(layoutKind: EpubPageLayoutKind, forward: boolean): number {
    if (layoutKind === 'vertical_paged' || layoutKind === 'continuous_vertical') {
      return forward ? -1 : 1;
    }
    if (this.activePageSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT) {
      return forward ? 1 : -1;
    }
    return forward ? -1 : 1;
  }

  private getAnimationViewportWidthVp(): number {
    if (this.hostWidthVp > 1) {
      return this.hostWidthVp;
    }
    if (this.fallbackVpW > 1) {
      return this.fallbackVpW;
    }
    const dm = display.getDefaultDisplaySync();
    return px2vp(dm.width);
  }

  private getAnimationViewportHeightVp(): number {
    if (this.hostHeightVp > 1) {
      return this.hostHeightVp;
    }
    if (this.fallbackVpH > 1) {
      return this.fallbackVpH;
    }
    const dm = display.getDefaultDisplaySync();
    return px2vp(dm.height);
  }

  private shouldUseTextSafeAnimationProfile(): boolean {
    return !this.params.isFixedLayout;
  }

  private createTextSafeAnimationProfile(
    layoutKind: EpubPageLayoutKind,
    forward: boolean,
    animationType: PageTurnAnimationType
  ): PageTurnAnimationProfile {
    const viewportW = this.getAnimationViewportWidthVp();
    const viewportH = this.getAnimationViewportHeightVp();
    const isVertical = layoutKind === 'vertical_paged' || layoutKind === 'continuous_vertical';
    const extent = isVertical ? viewportH : viewportW;
    const sign = this.getAnimationDirectionSign(layoutKind, forward);
    const axisX = isVertical ? 0 : extent * sign;
    const axisY = isVertical ? extent * sign : 0;
    const incomingX = -axisX;
    const incomingY = -axisY;

    switch (animationType) {
      case PageTurnAnimationType.SLIDE:
        return {
          outgoing: {
            opacity: 0.82,
            matrix: this.buildMatrix(axisX * 0.08, axisY * 0.08, 0, 1, 1, 0, 0)
          },
          incoming: {
            opacity: 1,
            matrix: this.buildMatrix(incomingX * 0.16, incomingY * 0.16, 0, 1, 1, 0, 0)
          },
          outDuration: 90,
          inDuration: 170,
          outCurve: Curve.EaseIn,
          inCurve: Curve.FastOutSlowIn
        };
      case PageTurnAnimationType.FADE:
        return {
          outgoing: {
            opacity: 0.06,
            matrix: this.buildMatrix(0, 0, 0, 1, 1, 0, 0)
          },
          incoming: {
            opacity: 0.18,
            matrix: this.buildMatrix(0, 0, 0, 1, 1, 0, 0)
          },
          outDuration: 100,
          inDuration: 160,
          outCurve: Curve.EaseOut,
          inCurve: Curve.EaseIn
        };
      case PageTurnAnimationType.COVER:
        return {
          outgoing: {
            opacity: 0.92,
            matrix: this.buildMatrix(axisX * 0.03, axisY * 0.03, 0, 1, 1, 0, 0)
          },
          incoming: {
            opacity: 1,
            matrix: this.buildMatrix(incomingX * 0.20, incomingY * 0.20, 0, 1, 1, 0, 0)
          },
          outDuration: 85,
          inDuration: 180,
          outCurve: Curve.EaseOut,
          inCurve: Curve.FastOutSlowIn
        };
      case PageTurnAnimationType.CUBE:
        return {
          outgoing: {
            opacity: 0.54,
            matrix: this.buildMatrix(axisX * 0.05, axisY * 0.05, 0, 0.995, 0.995, 0, 0)
          },
          incoming: {
            opacity: 0.74,
            matrix: this.buildMatrix(incomingX * 0.12, incomingY * 0.12, 0, 1, 1, 0, 0)
          },
          outDuration: 95,
          inDuration: 185,
          outCurve: Curve.EaseInOut,
          inCurve: Curve.FastOutSlowIn
        };
      case PageTurnAnimationType.DEPTH:
        return {
          outgoing: {
            opacity: 0.38,
            matrix: this.buildMatrix(axisX * 0.02, axisY * 0.02, 0, 0.985, 0.985, 0, 0)
          },
          incoming: {
            opacity: 0.68,
            matrix: this.buildMatrix(-axisX * 0.03, -axisY * 0.03, 0, 1.015, 1.015, 0, 0)
          },
          outDuration: 90,
          inDuration: 190,
          outCurve: Curve.EaseIn,
          inCurve: Curve.FastOutSlowIn
        };
      default:
        return {
          outgoing: {
            opacity: 0.12,
            matrix: this.buildMatrix(0, 0, 0, 1, 1, 0, 0)
          },
          incoming: {
            opacity: 0.22,
            matrix: this.buildMatrix(0, 0, 0, 1, 1, 0, 0)
          },
          outDuration: 90,
          inDuration: 160,
          outCurve: Curve.EaseOut,
          inCurve: Curve.EaseIn
        };
    }
  }

  private createAnimationProfile(
    layoutKind: EpubPageLayoutKind,
    forward: boolean,
    animationType: PageTurnAnimationType
  ): PageTurnAnimationProfile {
    const normalizedAnimation = this.normalizeAnimationType(animationType);
    if (this.shouldUseTextSafeAnimationProfile()) {
      return this.createTextSafeAnimationProfile(layoutKind, forward, normalizedAnimation);
    }
    const viewportW = this.getAnimationViewportWidthVp();
    const viewportH = this.getAnimationViewportHeightVp();
    const isVertical = layoutKind === 'vertical_paged' || layoutKind === 'continuous_vertical';
    const extent = isVertical ? viewportH : viewportW;
    const sign = this.getAnimationDirectionSign(layoutKind, forward);
    const axisX = isVertical ? 0 : extent * sign;
    const axisY = isVertical ? extent * sign : 0;
    const incomingX = -axisX;
    const incomingY = -axisY;

    switch (normalizedAnimation) {
      case PageTurnAnimationType.SLIDE:
        return {
          outgoing: {
            opacity: 0.18,
            matrix: this.buildMatrix(axisX * 0.28, axisY * 0.28, 0, 0.96, 0.96, 0, 0)
          },
          incoming: {
            opacity: 0.32,
            matrix: this.buildMatrix(incomingX * 0.72, incomingY * 0.72, -40, 0.96, 0.96, 0, 0)
          },
          outDuration: 120,
          inDuration: 190,
          outCurve: Curve.EaseIn,
          inCurve: Curve.FastOutSlowIn
        };
      case PageTurnAnimationType.FADE:
        return {
          outgoing: {
            opacity: 0.08,
            matrix: this.buildMatrix(0, 0, 0, 0.97, 0.97, 0, 0)
          },
          incoming: {
            opacity: 0.14,
            matrix: this.buildMatrix(0, 0, 0, 1.03, 1.03, 0, 0)
          },
          outDuration: 100,
          inDuration: 180,
          outCurve: Curve.EaseIn,
          inCurve: Curve.EaseOut
        };
      case PageTurnAnimationType.CUBE:
        return {
          outgoing: {
            opacity: 0.28,
            matrix: this.buildMatrix(
              axisX * 0.22,
              axisY * 0.22,
              -viewportW * 0.2,
              0.92,
              0.92,
              isVertical ? -sign * 42 : 0,
              isVertical ? 0 : -sign * 54
            )
          },
          incoming: {
            opacity: 0.44,
            matrix: this.buildMatrix(
              incomingX * 0.18,
              incomingY * 0.18,
              -viewportW * 0.2,
              0.92,
              0.92,
              isVertical ? sign * 54 : 0,
              isVertical ? 0 : sign * 54
            )
          },
          outDuration: 135,
          inDuration: 215,
          outCurve: Curve.EaseInOut,
          inCurve: Curve.EaseInOut
        };
      case PageTurnAnimationType.COVER:
        return {
          outgoing: {
            opacity: 0.9,
            matrix: this.buildMatrix(axisX * 0.04, axisY * 0.04, 0, 0.985, 0.985, 0, 0)
          },
          incoming: {
            opacity: 1,
            matrix: this.buildMatrix(
              incomingX * 0.98,
              incomingY * 0.98,
              40,
              1.02,
              1.02,
              isVertical ? sign * 4 : 0,
              isVertical ? 0 : sign * 4
            )
          },
          outDuration: 70,
          inDuration: 220,
          outCurve: Curve.EaseOut,
          inCurve: Curve.FastOutSlowIn
        };
      case PageTurnAnimationType.DEPTH:
        return {
          outgoing: {
            opacity: 0.16,
            matrix: this.buildMatrix(axisX * 0.08, axisY * 0.08, -180, 0.84, 0.84, 0, 0)
          },
          incoming: {
            opacity: 0.38,
            matrix: this.buildMatrix(
              -axisX * 0.06,
              -axisY * 0.06,
              -260,
              0.62,
              0.62,
              isVertical ? sign * 10 : -6,
              isVertical ? 0 : sign * 10
            )
          },
          outDuration: 110,
          inDuration: 240,
          outCurve: Curve.EaseIn,
          inCurve: Curve.FastOutSlowIn
        };
      default:
        return {
          outgoing: {
            opacity: 0.14,
            matrix: this.buildMatrix(axisX * 0.24, axisY * 0.24, 0, 0.96, 0.96, 0, 0)
          },
          incoming: {
            opacity: 0.24,
            matrix: this.buildMatrix(incomingX * 0.58, incomingY * 0.58, 0, 0.96, 0.96, 0, 0)
          },
          outDuration: 110,
          inDuration: 180,
          outCurve: Curve.EaseIn,
          inCurve: Curve.FastOutSlowIn
        };
    }
  }

  private escapeJsTemplate(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/`/g, '\\`');
  }

  private normalizeFileUrl(rawPath: string): string {
    const trimmed = rawPath.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    if (trimmed.startsWith('file://')) {
      return trimmed;
    }
    const normalized = trimmed.replace(/\\/g, '/');
    const escaped = normalized.replace(/'/g, '%27');
    if (/^[A-Za-z]:\//.test(escaped)) {
      return `file:///${escaped}`;
    }
    if (escaped.startsWith('/')) {
      return `file://${escaped}`;
    }
    return escaped;
  }

  private toRgba(color: string, alpha: number): string {
    const normalizedAlpha = this.clamp(alpha, 0, 1);
    const trimmed = color.trim();
    let hex = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
    if (hex.length === 3) {
      hex = `${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}`;
    }
    if (!/^[0-9a-fA-F]{6}$/.test(hex)) {
      return `rgba(255,255,255,${normalizedAlpha})`;
    }
    const red = parseInt(hex.substring(0, 2), 16);
    const green = parseInt(hex.substring(2, 4), 16);
    const blue = parseInt(hex.substring(4, 6), 16);
    return `rgba(${red},${green},${blue},${normalizedAlpha})`;
  }

  private resolveTextAlignment(value: string | undefined): string {
    const normalized = (value ?? 'JUSTIFY').trim().toUpperCase();
    if (normalized === 'LEFT') {
      return 'left';
    }
    if (normalized === 'CENTER') {
      return 'center';
    }
    if (normalized === 'RIGHT') {
      return 'right';
    }
    return 'justify';
  }

  private buildFontCss(textSettings: EBookReadingSettings): string {
    const fontPath = (textSettings.fontPath ?? '').trim();
    if (fontPath.length <= 0) {
      return '';
    }
    const fontUrl = this.normalizeFileUrl(fontPath);
    if (fontUrl.length <= 0) {
      return '';
    }
    return `
      @font-face {
        font-family: '__mnx_custom_font';
        src: url('${fontUrl}');
        font-display: swap;
      }
    `;
  }

  private resolveFontFamily(textSettings: EBookReadingSettings): string {
    const fontPath = (textSettings.fontPath ?? '').trim();
    const fontFamily = (textSettings.fontFamily ?? 'HarmonyOS Sans').trim();
    const escapedFamily = (fontFamily.length > 0 ? fontFamily : 'HarmonyOS Sans').replace(/'/g, "\\'");
    if (fontPath.length > 0) {
      return `'__mnx_custom_font', '${escapedFamily}', sans-serif`;
    }
    if (fontFamily.length <= 0) {
      return `'HarmonyOS Sans', sans-serif`;
    }
    return `'${escapedFamily}', sans-serif`;
  }

  private buildBackgroundCss(textSettings: EBookReadingSettings): string {
    const backgroundType = (textSettings.backgroundType ?? 'COLOR').trim().toUpperCase();
    const backgroundImagePath = (textSettings.backgroundImagePath ?? '').trim();
    if (backgroundType !== 'IMAGE' || backgroundImagePath.length <= 0) {
      return '';
    }
    const backgroundUrl = this.normalizeFileUrl(backgroundImagePath);
    if (backgroundUrl.length <= 0) {
      return '';
    }
    const opacity = this.clamp(textSettings.backgroundImageOpacity ?? 0.3, 0, 1);
    return `
      html::before {
        content: '';
        position: fixed;
        inset: 0;
        background-image: url('${backgroundUrl}');
        background-position: center;
        background-repeat: no-repeat;
        background-size: cover;
        opacity: ${opacity};
        pointer-events: none;
        z-index: 0;
      }
    `;
  }

  private buildReflowCss(
    vpW: number,
    vpH: number,
    textSettings: EBookReadingSettings,
    pageSettings: MangaReadingSettings
  ): string {
    const layoutKind = this.getLayoutKind(pageSettings, vpW, vpH);
    const viewportScale = this.getViewportScale(vpW, vpH);
    const margin = this.clamp((textSettings.pageMargin ?? 16) * viewportScale, 0, 240);
    const fontSize = this.clamp((textSettings.fontSize ?? 18) * viewportScale, 10, 160);
    const lineHeight = this.clamp(textSettings.lineHeight ?? 1.8, 1.0, 3.2);
    const fontWeight = this.clamp(textSettings.fontWeight ?? 400, 100, 900);
    const letterSpacing = this.clamp((textSettings.letterSpacing ?? 0) * viewportScale, -8, 24);
    const paragraphSpacing = this.clamp((textSettings.paragraphSpacing ?? 8) * viewportScale, 0, 120);
    const firstLineIndent = this.clamp(textSettings.firstLineIndent ?? 0, 0, 8);
    const backgroundColor = textSettings.backgroundColor ?? '#FFFFFF';
    const textColor = textSettings.textColor ?? '#000000';
    const bodyOverlayColor = (textSettings.backgroundType ?? 'COLOR').trim().toUpperCase() === 'IMAGE'
      ? this.toRgba(backgroundColor, 0.9)
      : backgroundColor;
    const webtoonLeftMargin = this.isContinuousVerticalMode(pageSettings)
      ? this.clamp(pageSettings.webtoonLeftMargin ?? 0, 0, 50)
      : 0;
    const webtoonRightMargin = this.isContinuousVerticalMode(pageSettings)
      ? this.clamp(pageSettings.webtoonRightMargin ?? 0, 0, 50)
      : 0;
    const leftPadding = margin + (this.isContinuousVerticalMode(pageSettings) ? (vpW * webtoonLeftMargin / 100) : 0);
    const rightPadding = margin + (this.isContinuousVerticalMode(pageSettings) ? (vpW * webtoonRightMargin / 100) : 0);
    const contentW = Math.max(1, vpW - leftPadding - rightPadding);
    const contentH = Math.max(1, vpH - margin * 2);
    const columnCount = layoutKind === 'double_page' ? 2 : 1;
    const columnWidth = Math.max(1, Math.floor(contentW / columnCount));
    const fontCss = this.buildFontCss(textSettings);
    const fontFamily = this.resolveFontFamily(textSettings);
    const backgroundCss = this.buildBackgroundCss(textSettings);
    const textAlign = this.resolveTextAlignment(textSettings.textAlignment);
    const rootTextCss = `
      font-size: ${fontSize}px !important;
      line-height: ${lineHeight} !important;
      font-family: ${fontFamily} !important;
      font-weight: ${fontWeight} !important;
      letter-spacing: ${letterSpacing}px !important;
      text-align: ${textAlign} !important;
      -webkit-text-size-adjust: 100% !important;
      text-size-adjust: 100% !important;
    `;

    const commonTextCss = `
      color: ${textColor} !important;
      font-size: 1rem !important;
      line-height: ${lineHeight} !important;
      font-family: ${fontFamily} !important;
      font-weight: ${fontWeight} !important;
      letter-spacing: ${letterSpacing}px !important;
      text-align: ${textAlign} !important;
      word-break: break-word !important;
      overflow-wrap: break-word !important;
      -webkit-font-smoothing: antialiased !important;
    `;

    const paragraphCss = `
      p, li, blockquote {
        margin-top: 0 !important;
        margin-bottom: ${paragraphSpacing}px !important;
        text-indent: ${firstLineIndent}em !important;
      }
      p:last-child, li:last-child, blockquote:last-child {
        margin-bottom: 0 !important;
      }
    `;

    if (layoutKind === 'continuous_vertical') {
      const imageGap = pageSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP
        ? this.clamp(pageSettings.pageSpacing ?? 12, 0, 80)
        : 0;
      return `
        ${fontCss}
        ${backgroundCss}
        :root {
          ${rootTextCss}
        }
        html {
          margin: 0 !important;
          padding: 0 !important;
          width: 100% !important;
          min-height: 100% !important;
          overflow-x: hidden !important;
          overflow-y: auto !important;
          overscroll-behavior: contain !important;
          scroll-behavior: auto !important;
          scroll-snap-type: none !important;
          background-color: ${backgroundColor} !important;
          ${rootTextCss}
        }
        body {
          position: relative !important;
          z-index: 1 !important;
          margin: 0 !important;
          padding-top: ${margin}px !important;
          padding-right: ${rightPadding}px !important;
          padding-bottom: ${margin}px !important;
          padding-left: ${leftPadding}px !important;
          box-sizing: border-box !important;
          min-height: ${contentH}px !important;
          overflow-x: hidden !important;
          overflow-y: visible !important;
          background-color: ${bodyOverlayColor} !important;
          ${commonTextCss}
        }
        body * {
          color: inherit !important;
          line-height: inherit !important;
          font-family: inherit !important;
          font-weight: inherit !important;
          letter-spacing: inherit !important;
          text-align: inherit !important;
        }
        p, li, div, span, article, section, blockquote, td, th, a, pre, code, dd, dt, figcaption, caption {
          font-size: inherit !important;
        }
        body [style*='font-size'] {
          font-size: inherit !important;
        }
        ${paragraphCss}
        img, svg, video {
          max-width: ${contentW}px !important;
          max-height: none !important;
          height: auto !important;
          display: block !important;
          object-fit: contain !important;
          margin-left: auto !important;
          margin-right: auto !important;
          margin-bottom: ${imageGap}px !important;
          break-inside: avoid !important;
        }
        * {
          -webkit-tap-highlight-color: transparent !important;
        }
        ::-webkit-scrollbar {
          display: none !important;
        }
      `;
    }

    if (layoutKind === 'vertical_paged') {
      return `
        ${fontCss}
        ${backgroundCss}
        :root {
          ${rootTextCss}
        }
        html {
          margin: 0 !important;
          padding: 0 !important;
          width: 100% !important;
          min-height: 100% !important;
          overflow-x: hidden !important;
          overflow-y: auto !important;
          overscroll-behavior: contain !important;
          scroll-behavior: auto !important;
          scroll-snap-type: y mandatory !important;
          background-color: ${backgroundColor} !important;
          ${rootTextCss}
        }
        body {
          position: relative !important;
          z-index: 1 !important;
          margin: 0 !important;
          padding-top: ${margin}px !important;
          padding-right: ${rightPadding}px !important;
          padding-bottom: ${margin}px !important;
          padding-left: ${leftPadding}px !important;
          box-sizing: border-box !important;
          min-height: ${contentH}px !important;
          overflow-x: hidden !important;
          overflow-y: visible !important;
          background-color: ${bodyOverlayColor} !important;
          ${commonTextCss}
        }
        body * {
          color: inherit !important;
          line-height: inherit !important;
          font-family: inherit !important;
          font-weight: inherit !important;
          letter-spacing: inherit !important;
          text-align: inherit !important;
        }
        p, li, div, span, article, section, blockquote, td, th, a, pre, code, dd, dt, figcaption, caption {
          font-size: inherit !important;
        }
        body [style*='font-size'] {
          font-size: inherit !important;
        }
        ${paragraphCss}
        img, svg, video {
          max-width: ${contentW}px !important;
          max-height: ${contentH}px !important;
          height: auto !important;
          display: block !important;
          object-fit: contain !important;
          break-inside: avoid !important;
        }
        * {
          -webkit-tap-highlight-color: transparent !important;
        }
        ::-webkit-scrollbar {
          display: none !important;
        }
      `;
    }

    return `
      ${fontCss}
      ${backgroundCss}
      :root {
        ${rootTextCss}
      }
      html {
        margin: 0 !important;
        padding: 0 !important;
        width: 100% !important;
        min-height: 100% !important;
        overflow-x: auto !important;
        overflow-y: hidden !important;
        overscroll-behavior: contain !important;
        scroll-behavior: auto !important;
        scroll-snap-type: ${layoutKind === 'continuous_horizontal' ? 'none' : 'x mandatory'} !important;
        background-color: ${backgroundColor} !important;
        ${rootTextCss}
      }
      body {
        position: relative !important;
        z-index: 1 !important;
        margin: 0 !important;
        padding-top: ${margin}px !important;
        padding-right: ${rightPadding}px !important;
        padding-bottom: ${margin}px !important;
        padding-left: ${leftPadding}px !important;
        box-sizing: border-box !important;
        column-width: ${columnWidth}px !important;
        column-gap: 0px !important;
        column-fill: auto !important;
        min-width: 100% !important;
        width: auto !important;
        height: ${contentH}px !important;
        overflow-y: visible !important;
        overflow-x: visible !important;
        background-color: ${bodyOverlayColor} !important;
        ${commonTextCss}
      }
      body * {
        color: inherit !important;
        line-height: inherit !important;
        font-family: inherit !important;
        font-weight: inherit !important;
        letter-spacing: inherit !important;
        text-align: inherit !important;
      }
      p, li, div, span, article, section, blockquote, td, th, a, pre, code, dd, dt, figcaption, caption {
        font-size: inherit !important;
      }
      body [style*='font-size'] {
        font-size: inherit !important;
      }
      ${paragraphCss}
      img, svg, video {
        max-width: ${columnWidth}px !important;
        max-height: ${contentH}px !important;
        height: auto !important;
        display: block !important;
        object-fit: contain !important;
        break-inside: avoid-column !important;
      }
      * {
        -webkit-tap-highlight-color: transparent !important;
      }
      ::-webkit-scrollbar {
        display: none !important;
      }
    `;
  }

  private buildFixedCss(vpW: number, vpH: number, textSettings: EBookReadingSettings): string {
    const backgroundColor = textSettings.backgroundColor ?? '#FFFFFF';
    const backgroundCss = this.buildBackgroundCss(textSettings);
    return `
      ${backgroundCss}
      html, body {
        margin: 0 !important;
        padding: 0 !important;
        width: ${vpW}px !important;
        height: ${vpH}px !important;
        overflow: hidden !important;
        background-color: ${backgroundColor} !important;
      }
      body {
        position: relative !important;
        z-index: 1 !important;
        transform-origin: top left !important;
      }
      * {
        -webkit-tap-highlight-color: transparent !important;
      }
    `;
  }

  private buildBridgeJs(layoutKind: EpubPageLayoutKind): string {
    return `
      window.__mnxLayoutKind = '${layoutKind}';
      window.__mnxResolveScrollRoot = function() {
        return document.scrollingElement || document.documentElement || document.body;
      };
      window.__mnxGetViewportExtent = function() {
        var width = window.innerWidth || (document.documentElement ? document.documentElement.clientWidth : 0) || (document.body ? document.body.clientWidth : 0) || 0;
        var height = window.innerHeight || (document.documentElement ? document.documentElement.clientHeight : 0) || (document.body ? document.body.clientHeight : 0) || 0;
        return { width: Math.max(1, Math.round(width)), height: Math.max(1, Math.round(height)) };
      };
      window.__mnxRefreshPagination = function() {
        var root = window.__mnxResolveScrollRoot();
        var viewport = window.__mnxGetViewportExtent();
        var isVertical = window.__mnxLayoutKind === 'vertical_paged' || window.__mnxLayoutKind === 'continuous_vertical';
        var pageExtent = isVertical ? viewport.height : viewport.width;
        var totalExtent = Math.max(
          root ? (isVertical ? (root.scrollHeight || 0) : (root.scrollWidth || 0)) : 0,
          document.documentElement ? (isVertical ? (document.documentElement.scrollHeight || 0) : (document.documentElement.scrollWidth || 0)) : 0,
          document.body ? (isVertical ? (document.body.scrollHeight || 0) : (document.body.scrollWidth || 0)) : 0
        );
        var currentOffset = Math.max(
          0,
          Math.round(
            root ? (isVertical ? (root.scrollTop || 0) : (root.scrollLeft || 0)) : 0
          )
        );
        var maxOffset = Math.max(0, totalExtent - pageExtent);
        var offsets = [];
        if (maxOffset <= 0 || pageExtent <= 0) {
          offsets.push(0);
        } else {
          var probe = 0;
          while (probe < maxOffset) {
            offsets.push(Math.max(0, Math.round(probe)));
            probe += pageExtent;
          }
          if (offsets.length === 0 || offsets[offsets.length - 1] !== Math.round(maxOffset)) {
            offsets.push(Math.round(maxOffset));
          }
        }
        var currentPage = 0;
        var bestDistance = Number.MAX_SAFE_INTEGER;
        for (var i = 0; i < offsets.length; i++) {
          var distance = Math.abs(offsets[i] - currentOffset);
          if (distance < bestDistance) {
            bestDistance = distance;
            currentPage = i;
          }
        }
        window.__mnxPageOffsets = offsets;
        window.__mnxPaginationState = {
          pageCount: offsets.length,
          currentPage: currentPage,
          currentOffset: currentOffset,
          pageExtent: pageExtent,
          maxOffset: Math.round(maxOffset),
          rootTagName: root && root.tagName ? root.tagName : ''
        };
        return window.__mnxPaginationState;
      };
      window.__mnxNotifyPagination = function(source) {
        if (!window.arkts || typeof window.arkts.onPaginationChanged !== 'function') {
          return;
        }
        var state = window.__mnxRefreshPagination();
        window.arkts.onPaginationChanged(JSON.stringify({
          source: source || 'manual',
          layoutKind: window.__mnxLayoutKind || '',
          pageCount: state.pageCount,
          currentPage: state.currentPage,
          currentOffset: state.currentOffset,
          pageExtent: state.pageExtent,
          maxOffset: state.maxOffset,
          atStart: state.currentOffset <= 2,
          atEnd: state.currentOffset >= Math.max(0, state.maxOffset - 2)
        }));
      };
      window.__mnxSchedulePaginationNotify = function(source) {
        if (window.__mnxNotifyTimer) {
          clearTimeout(window.__mnxNotifyTimer);
        }
        window.__mnxNotifyTimer = setTimeout(function() {
          window.__mnxNotifyTimer = 0;
          window.__mnxNotifyPagination(source || 'deferred');
        }, 56);
      };
      window.__mnxInstallArkBridge = function() {
        var root = window.__mnxResolveScrollRoot();
        if (window.__mnxScrollRoot && window.__mnxScrollHandler && window.__mnxScrollRoot.removeEventListener) {
          window.__mnxScrollRoot.removeEventListener('scroll', window.__mnxScrollHandler);
        }
        if (window.__mnxWindowScrollHandler) {
          window.removeEventListener('scroll', window.__mnxWindowScrollHandler);
        }
        if (window.__mnxResizeHandler) {
          window.removeEventListener('resize', window.__mnxResizeHandler);
        }
        if (window.__mnxClickHandler) {
          document.removeEventListener('click', window.__mnxClickHandler, true);
        }
        window.__mnxScrollRoot = root;
        window.__mnxScrollHandler = function() {
          window.__mnxSchedulePaginationNotify('scroll');
        };
        window.__mnxWindowScrollHandler = function() {
          window.__mnxSchedulePaginationNotify('window_scroll');
        };
        window.__mnxResizeHandler = function() {
          window.__mnxSchedulePaginationNotify('resize');
        };
        window.__mnxClickHandler = function(event) {
          if (!window.arkts || typeof window.arkts.onReaderTap !== 'function') {
            return;
          }
          var viewport = window.__mnxGetViewportExtent();
          var safeWidth = Math.max(1, viewport.width);
          var safeHeight = Math.max(1, viewport.height);
          var clientX = event && typeof event.clientX === 'number' ? event.clientX : 0;
          var clientY = event && typeof event.clientY === 'number' ? event.clientY : 0;
          window.arkts.onReaderTap(JSON.stringify({
            xRatio: Math.max(0, Math.min(1, clientX / safeWidth)),
            yRatio: Math.max(0, Math.min(1, clientY / safeHeight))
          }));
        };
        if (root && root.addEventListener) {
          root.addEventListener('scroll', window.__mnxScrollHandler, { passive: true });
        }
        window.addEventListener('scroll', window.__mnxWindowScrollHandler, { passive: true });
        window.addEventListener('resize', window.__mnxResizeHandler, { passive: true });
        document.addEventListener('click', window.__mnxClickHandler, true);
      };
      window.__mnxGetPageCount = function() {
        return window.__mnxRefreshPagination().pageCount;
      };
      window.__mnxGoToPageImmediate = function(pageIndex) {
        var state = window.__mnxRefreshPagination();
        var root = window.__mnxResolveScrollRoot();
        var normalizedIndex = Math.max(0, Math.min(state.pageCount - 1, Math.floor(pageIndex || 0)));
        var targetOffset = state.pageCount > 0 ? (window.__mnxPageOffsets[normalizedIndex] || 0) : 0;
        if (root && typeof root.scrollTo === 'function') {
          if (window.__mnxLayoutKind === 'vertical_paged' || window.__mnxLayoutKind === 'continuous_vertical') {
            root.scrollTo({ left: 0, top: targetOffset, behavior: 'auto' });
          } else {
            root.scrollTo({ left: targetOffset, top: 0, behavior: 'auto' });
          }
        } else if (root) {
          if (window.__mnxLayoutKind === 'vertical_paged' || window.__mnxLayoutKind === 'continuous_vertical') {
            root.scrollTop = targetOffset;
          } else {
            root.scrollLeft = targetOffset;
          }
        } else if (window.__mnxLayoutKind === 'vertical_paged' || window.__mnxLayoutKind === 'continuous_vertical') {
          window.scrollTo(0, targetOffset);
        } else {
          window.scrollTo(targetOffset, 0);
        }
        state = window.__mnxRefreshPagination();
        window.__mnxPaginationState = state;
        window.__mnxSchedulePaginationNotify('programmatic');
        return JSON.stringify({
          pageIndex: state.currentPage,
          offset: state.currentOffset,
          pageCount: state.pageCount,
          pageExtent: state.pageExtent,
          maxOffset: state.maxOffset
        });
      };
      window.__mnxGoToPage = window.__mnxGoToPageImmediate;
      window.__mnxGetCurrentPage = function() {
        return window.__mnxRefreshPagination().currentPage;
      };
    `;
  }

  private parsePageCommandResult(raw: string, fallbackPage: number): PageCommandResult {
    try {
      const clean = this.parseWebViewJson(raw);
      const parsed = JSON.parse(clean) as PageCommandResult;
      const pageIndex = Number(parsed.pageIndex);
      const offset = Number(parsed.offset);
      const pageCount = Number(parsed.pageCount);
      const pageExtent = Number(parsed.pageExtent);
      const maxOffset = Number(parsed.maxOffset);
      return {
        pageIndex: !isNaN(pageIndex) ? pageIndex : fallbackPage,
        offset: !isNaN(offset) ? offset : 0,
        pageCount: !isNaN(pageCount) && pageCount > 0 ? Math.floor(pageCount) : Math.max(1, this.currentPageCount),
        pageExtent: !isNaN(pageExtent) ? Math.max(0, pageExtent) : this.lastPaginationPageExtent,
        maxOffset: !isNaN(maxOffset) ? Math.max(0, maxOffset) : this.lastPaginationMaxOffset
      };
    } catch (_error) {
      return {
        pageIndex: fallbackPage,
        offset: 0,
        pageCount: Math.max(1, this.currentPageCount),
        pageExtent: this.lastPaginationPageExtent,
        maxOffset: this.lastPaginationMaxOffset
      };
    }
  }

  private applyInjectedLayout(
    vpW: number,
    vpH: number,
    pageOffset: number,
    textSettings: EBookReadingSettings,
    pageSettings: MangaReadingSettings,
    notifyReady: boolean,
    source: string,
    anchorRatio: number = -1
  ): void {
    this.ready = false;
    this.viewportBackgroundColor = textSettings.backgroundColor ?? DEFAULT_EBOOK_READING_SETTINGS.backgroundColor;
    const css = this.params.isFixedLayout
      ? this.buildFixedCss(vpW, vpH, textSettings)
      : this.buildReflowCss(vpW, vpH, textSettings, pageSettings);
    const escapedCss = this.escapeJsTemplate(css);
    const layoutKind = this.params.isFixedLayout
      ? 'horizontal_paged'
      : this.getLayoutKind(pageSettings, vpW, vpH);
    this.currentLayoutKind = layoutKind;
    const bridge = this.buildBridgeJs(layoutKind);
    logger.info(
      TAG,
      `应用排版注入: source=${source}, notifyReady=${notifyReady}, fixed=${this.params.isFixedLayout}, pageOffset=${pageOffset}, vp=${vpW}x${vpH}, scale=${this.getViewportScale(vpW, vpH)}, text(${this.describeTextSettings(textSettings)}), page(${this.describePageSettings(pageSettings)})`
    );

    const injectScript = `
      (function() {
        var head = document.head || document.getElementsByTagName('head')[0] || document.documentElement;
        var viewportMeta = document.querySelector('meta[name="viewport"]');
        if (!viewportMeta) {
          viewportMeta = document.createElement('meta');
          viewportMeta.setAttribute('name', 'viewport');
          head.appendChild(viewportMeta);
        }
        viewportMeta.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, viewport-fit=cover');
        var styleTag = document.getElementById('__mnx_epub_style');
        if (styleTag) {
          styleTag.remove();
        }
        styleTag = document.createElement('style');
        styleTag.id = '__mnx_epub_style';
        styleTag.textContent = \`${escapedCss}\`;
        head.appendChild(styleTag);
        if (head.lastElementChild !== styleTag) {
          head.appendChild(styleTag);
        }
        // Remove body inline styles that would override !important CSS rules for column layout
        if (document.body) {
          var blockProps = ['height','max-height','min-height','overflow','overflow-x','overflow-y',
                           'width','max-width','column-width','column-gap','column-fill','column-count'];
          for (var pi = 0; pi < blockProps.length; pi++) {
            document.body.style.removeProperty(blockProps[pi]);
          }
          document.body.style.removeProperty('font-size');
          document.body.style.removeProperty('-webkit-text-size-adjust');
          document.body.style.removeProperty('text-size-adjust');
          // Force synchronous reflow so column layout is computed before we measure
          void document.body.offsetWidth;
        }
        if (document.documentElement) {
          document.documentElement.style.removeProperty('font-size');
          document.documentElement.style.removeProperty('-webkit-text-size-adjust');
          document.documentElement.style.removeProperty('text-size-adjust');
        }
        ${bridge}
        window.__mnxInstallArkBridge();
        return 'ok';
      })();
    `;

    this.runJs(injectScript, (_ok: string) => {
      setTimeout(() => {
        if (this.params.isFixedLayout) {
          this.applyFixedLayoutScale(vpW, vpH);
          this.completeReaderReady('horizontal_paged', 0, 1, notifyReady);
          return;
        }

        this.runJs(
          `(function() {
            var paginationState = window.__mnxRefreshPagination();
            return JSON.stringify({
              pageCount: paginationState.pageCount,
              currentPage: paginationState.currentPage,
              currentOffset: paginationState.currentOffset,
              pageExtent: paginationState.pageExtent,
              maxOffset: paginationState.maxOffset,
              innerWidth: window.innerWidth || 0,
              innerHeight: window.innerHeight || 0,
              visualViewportWidth: window.visualViewport ? (window.visualViewport.width || 0) : 0,
              visualViewportHeight: window.visualViewport ? (window.visualViewport.height || 0) : 0,
              visualViewportScale: window.visualViewport ? (window.visualViewport.scale || 0) : 0,
              rootFontSize: document.documentElement ? window.getComputedStyle(document.documentElement).fontSize || '' : '',
              bodyFontSize: document.body ? window.getComputedStyle(document.body).fontSize || '' : '',
              bodyLineHeight: document.body ? window.getComputedStyle(document.body).lineHeight || '' : '',
              sampleTagName: (function() {
                var sample = document.body ? document.body.querySelector('p, div, span, li, article, section, blockquote, td, th, a') : null;
                return sample ? sample.tagName : '';
              })(),
              sampleFontSize: (function() {
                var sample = document.body ? document.body.querySelector('p, div, span, li, article, section, blockquote, td, th, a') : null;
                return sample ? (window.getComputedStyle(sample).fontSize || '') : '';
              })(),
              sampleLineHeight: (function() {
                var sample = document.body ? document.body.querySelector('p, div, span, li, article, section, blockquote, td, th, a') : null;
                return sample ? (window.getComputedStyle(sample).lineHeight || '') : '';
              })(),
              sampleTextAlign: (function() {
                var sample = document.body ? document.body.querySelector('p, div, span, li, article, section, blockquote, td, th, a') : null;
                return sample ? (window.getComputedStyle(sample).textAlign || '') : '';
              })(),
              styleTagParent: (function() {
                var styleTag = document.getElementById('__mnx_epub_style');
                return styleTag && styleTag.parentElement ? styleTag.parentElement.tagName : '';
              })(),
              isStyleTagLastChild: (function() {
                var styleTag = document.getElementById('__mnx_epub_style');
                return !!(styleTag && styleTag.parentElement && styleTag.parentElement.lastElementChild === styleTag);
              })(),
              rootTagName: paginationState.rootTagName || '',
              scrollWidth: Math.max(
                document.documentElement.scrollWidth || 0,
                document.body ? document.body.scrollWidth : 0
              ),
              scrollHeight: Math.max(
                document.documentElement.scrollHeight || 0,
                document.body ? document.body.scrollHeight : 0
              )
            });
          })();`,
          (metricsRaw: string) => {
            let pageCount = 1;
            try {
              const cleanMetrics = this.parseWebViewJson(metricsRaw);
              const metrics = JSON.parse(cleanMetrics) as PaginationMetrics;
              const parsedCount = Math.floor(Number(metrics.pageCount));
              if (!isNaN(parsedCount) && parsedCount > 0) {
                pageCount = parsedCount;
              }
              logger.debug(
                TAG,
                `Pagination metrics: source=${source}, inner=${metrics.innerWidth}x${metrics.innerHeight}, visual=${metrics.visualViewportWidth}x${metrics.visualViewportHeight}@${metrics.visualViewportScale}, scroll=${metrics.scrollWidth}x${metrics.scrollHeight}, root=${metrics.rootTagName}, offset=${metrics.currentOffset}/${metrics.maxOffset}, extent=${metrics.pageExtent}, pages=${pageCount}, current=${metrics.currentPage}, rootFont=${metrics.rootFontSize}, bodyFont=${metrics.bodyFontSize}/${metrics.bodyLineHeight}, sample=${metrics.sampleTagName}:${metrics.sampleFontSize}/${metrics.sampleLineHeight}, align=${metrics.sampleTextAlign}, styleParent=${metrics.styleTagParent}, styleLast=${metrics.isStyleTagLastChild}`
              );
            } catch (error) {
              const fallbackCount = parseInt(this.parseWebViewJson(metricsRaw), 10);
              if (!isNaN(fallbackCount) && fallbackCount > 0) {
                pageCount = fallbackCount;
              } else {
                logger.warn(TAG, `Pagination metrics parse failed, fallback to single page: ${String(error)}`);
              }
            }

            this.currentPageCount = pageCount;
            const targetPage = anchorRatio >= 0 && this.currentPageCount > 1
              ? Math.max(
                  0,
                  Math.min(
                    Math.round(anchorRatio * Math.max(0, this.currentPageCount - 1)),
                    this.currentPageCount - 1
                  )
                )
              : Math.max(0, Math.min(pageOffset, this.currentPageCount - 1));
            let finished = false;
            const finalize = () => {
              if (finished) {
                return;
              }
              finished = true;
              this.completeReaderReady(layoutKind, targetPage, this.currentPageCount, notifyReady);
            };
            const fallbackTimer = setTimeout(() => {
              finalize();
            }, 60);
            this.runJs(`window.__mnxGoToPageImmediate(${targetPage});`, (resultRaw: string) => {
              const result = this.parsePageCommandResult(resultRaw, targetPage);
              this.currentPage = result.pageIndex;
              this.currentPageCount = result.pageCount;
              this.lastPaginationOffset = result.offset;
              this.lastPaginationPageExtent = result.pageExtent;
              this.lastPaginationMaxOffset = result.maxOffset;
              this.lastProgressRatio = this.computeProgressRatio(
                this.currentPage,
                this.currentPageCount,
                this.lastPaginationOffset,
                this.lastPaginationMaxOffset
              );
              clearTimeout(fallbackTimer);
              finalize();
            });
          }
        );
      }, REFLOW_SETTLE_DELAY_MS);
    });
  }

  private applyFixedLayoutScale(vpW: number, vpH: number): void {
    const detectScript = `
      (function() {
        var viewportMeta = document.querySelector('meta[name="viewport"]');
        var width = 0;
        var height = 0;
        if (viewportMeta) {
          var content = viewportMeta.getAttribute('content') || '';
          var widthMatch = content.match(/width\\s*=\\s*(\\d+)/);
          var heightMatch = content.match(/height\\s*=\\s*(\\d+)/);
          if (widthMatch) {
            width = parseInt(widthMatch[1]);
          }
          if (heightMatch) {
            height = parseInt(heightMatch[1]);
          }
        }
        if (!width) {
          width = document.documentElement.scrollWidth || ${vpW};
        }
        if (!height) {
          height = document.documentElement.scrollHeight || ${vpH};
        }
        return JSON.stringify({ w: width, h: height });
      })();
    `;
    this.runJs(detectScript, (result: string) => {
      try {
        const clean = this.parseWebViewJson(result);
        const dimension = JSON.parse(clean) as FixedLayoutDimension;
        const scaleX = vpW / (dimension.w || vpW);
        const scaleY = vpH / (dimension.h || vpH);
        const scale = Math.min(scaleX, scaleY);
        this.runJs(`document.body.style.transform = 'scale(${scale})';`);
      } catch (error) {
        logger.warn(TAG, `Fixed-layout dimension parse failed: ${String(error)}`);
      }
    });
  }

  private commitPageChange(targetPage: number, afterCommit?: () => void): void {
    let finished = false;
    let resolvedPage = targetPage;
    let resolvedPageCount = Math.max(1, this.currentPageCount);
    this.boundarySuppressionUntil = Date.now() + 260;
    const finalize = () => {
      if (finished) {
        return;
      }
      finished = true;
      this.currentPage = resolvedPage;
      this.currentPageCount = resolvedPageCount;
      this.lastProgressRatio = this.computeProgressRatio(
        this.currentPage,
        this.currentPageCount,
        this.lastPaginationOffset,
        this.lastPaginationMaxOffset
      );
      this.params.callbacks.onPageChange(this.currentPage, this.currentPageCount);
      if (afterCommit) {
        afterCommit();
      }
    };

    const fallbackTimer = setTimeout(() => {
      finalize();
    }, 60);

    this.runJs(`window.__mnxGoToPageImmediate(${targetPage});`, (resultRaw: string) => {
      const result = this.parsePageCommandResult(resultRaw, targetPage);
      resolvedPage = result.pageIndex;
      resolvedPageCount = result.pageCount;
      this.lastPaginationOffset = result.offset;
      this.lastPaginationPageExtent = result.pageExtent;
      this.lastPaginationMaxOffset = result.maxOffset;
      clearTimeout(fallbackTimer);
      finalize();
    });
  }

  private goToPageImmediate(targetPage: number): boolean {
    if (!this.ready || this.isPageTurnAnimating || this.currentPageCount <= 0) {
      return false;
    }
    const safeTargetPage = Math.max(0, Math.min(targetPage, this.currentPageCount - 1));
    this.commitPageChange(safeTargetPage);
    return true;
  }

  private finishPageTurnAnimation(): void {
    this.clearDeferredWork();
    this.isPageTurnAnimating = false;
    this.resetViewportTransform();
  }

  private loadSpineItemImmediate(spineFilePath: string, pageOffset: number): void {
    this.clearDeferredWork();
    this.pendingPageOffset = pageOffset;
    this.pendingSpinePath = spineFilePath;
    this.ready = false;
    this.currentPageCount = 0;
    this.currentPage = 0;
    this.lastPaginationOffset = 0;
    this.lastPaginationPageExtent = 0;
    this.lastPaginationMaxOffset = 0;
    this.boundarySuppressionUntil = 0;
    try {
      this.webviewController.loadUrl(`file://${spineFilePath}`);
    } catch (error) {
      const msg = String(error);
      this.pendingSpineTransition = null;
      this.finishPageTurnAnimation();
      logger.error(TAG, `loadUrl failed: ${msg}`);
      this.params.callbacks.onError(`加载失败: ${msg}`);
    }
  }

  private performAnimatedSpineTransition(
    spineFilePath: string,
    pageOffset: number,
    forward: boolean
  ): void {
    const animationType = this.normalizeAnimationType(
      this.activePageSettings.pageTurnAnimation ?? PageTurnAnimationType.SLIDE
    );
    const ctx = this.resolveUiContext();
    if (animationType === PageTurnAnimationType.NONE || !ctx) {
      this.pendingSpineTransition = null;
      this.finishPageTurnAnimation();
      this.loadSpineItemImmediate(spineFilePath, pageOffset);
      return;
    }

    const layoutKind = this.params.isFixedLayout
      ? 'horizontal_paged'
      : this.getLayoutKind(
        this.activePageSettings,
        this.lastVpW > 0 ? this.lastVpW : this.fallbackVpW,
        this.lastVpH > 0 ? this.lastVpH : this.fallbackVpH
      );
    const profile = this.createAnimationProfile(layoutKind, forward, animationType);
    this.pendingSpineTransition = {
      incoming: profile.incoming,
      inDuration: profile.inDuration,
      inCurve: profile.inCurve
    };
    this.isPageTurnAnimating = true;

    ctx.animateTo({
      duration: profile.outDuration,
      curve: curves.initCurve(profile.outCurve),
      onFinish: () => {
        this.loadSpineItemImmediate(spineFilePath, pageOffset);
      }
    }, () => {
      this.applyViewportState(profile.outgoing);
    });
  }

  private completeReaderReady(
    layoutKind: EpubPageLayoutKind,
    targetPage: number,
    totalPages: number,
    notifyReady: boolean
  ): void {
    this.currentLayoutKind = layoutKind;
    const finalizeReady = () => {
      this.ready = true;
      if (notifyReady) {
        this.params.callbacks.onReady(this.buildController());
      }
      logger.info(
        TAG,
        `Reader layout applied: layout=${layoutKind}, pages=${totalPages}, current=${targetPage}`
      );
      if (notifyReady && !this.params.isFixedLayout) {
        this.scheduleSettingsReapply('post_ready_reconcile', INITIAL_LAYOUT_RECONCILE_DELAY_MS);
      }
    };

    this.currentPageCount = totalPages;
    this.currentPage = targetPage;
    this.lastProgressRatio = this.computeProgressRatio(
      this.currentPage,
      this.currentPageCount,
      this.lastPaginationOffset,
      this.lastPaginationMaxOffset
    );
    this.params.callbacks.onPageChange(this.currentPage, this.currentPageCount);

    const pendingTransition = this.pendingSpineTransition;
    if (!pendingTransition) {
      finalizeReady();
      return;
    }

    this.applyViewportState(pendingTransition.incoming);
    const ctx = this.resolveUiContext();
    if (!ctx) {
      this.pendingSpineTransition = null;
      this.finishPageTurnAnimation();
      finalizeReady();
      return;
    }

    ctx.animateTo({
      duration: pendingTransition.inDuration,
      curve: curves.initCurve(pendingTransition.inCurve),
      onFinish: () => {
        this.pendingSpineTransition = null;
        this.finishPageTurnAnimation();
        finalizeReady();
      }
    }, () => {
      this.resetViewportTransform();
    });
  }

  private performAnimatedPageTurn(targetPage: number, forward: boolean): void {
    const layoutKind = this.getLayoutKind(
      this.activePageSettings,
      this.lastVpW > 0 ? this.lastVpW : this.fallbackVpW,
      this.lastVpH > 0 ? this.lastVpH : this.fallbackVpH
    );
    const animationType = this.normalizeAnimationType(
      this.activePageSettings.pageTurnAnimation ?? PageTurnAnimationType.SLIDE
    );

    if (animationType === PageTurnAnimationType.NONE) {
      this.commitPageChange(targetPage);
      return;
    }

    const ctx = this.resolveUiContext();
    if (!ctx) {
      this.commitPageChange(targetPage);
      return;
    }

    this.isPageTurnAnimating = true;
    const profile = this.createAnimationProfile(layoutKind, forward, animationType);

    ctx.animateTo({
      duration: profile.outDuration,
      curve: curves.initCurve(profile.outCurve),
      onFinish: () => {
        this.commitPageChange(targetPage, () => {
          this.applyViewportState(profile.incoming);
          this.pageTurnPhaseTimer = setTimeout(() => {
            this.pageTurnPhaseTimer = -1;
            const nextCtx = this.resolveUiContext();
            if (!nextCtx) {
              this.finishPageTurnAnimation();
              return;
            }
            nextCtx.animateTo({
              duration: profile.inDuration,
              curve: curves.initCurve(profile.inCurve),
              onFinish: () => {
                this.finishPageTurnAnimation();
              }
            }, () => {
              this.resetViewportTransform();
            });
          }, 16);
        });
      }
    }, () => {
      this.applyViewportState(profile.outgoing);
    });
  }

  private scheduleSettingsReapply(reason: string, delayMs: number = SETTINGS_APPLY_DELAY_MS): void {
    if (!this.ready) {
      logger.debug(TAG, `跳过排版重应用: ready=false, reason=${reason}`);
      return;
    }
    if (this.applySettingsTimer !== -1) {
      clearTimeout(this.applySettingsTimer);
    }
    this.applySettingsTimer = setTimeout(() => {
      this.applySettingsTimer = -1;
      if (!this.ready || this.isPageTurnAnimating) {
        logger.debug(
          TAG,
          `取消排版重应用: ready=${this.ready}, animating=${this.isPageTurnAnimating}, reason=${reason}`
        );
        return;
      }
      const vpW = this.lastVpW > 0 ? this.lastVpW : this.fallbackVpW;
      const vpH = this.lastVpH > 0 ? this.lastVpH : this.fallbackVpH;
      const savedPage = this.currentPage;
      const anchorRatio = this.lastProgressRatio;
      logger.info(
        TAG,
        `执行排版重应用: reason=${reason}, page=${savedPage}, ratio=${anchorRatio.toFixed(3)}, vp=${vpW}x${vpH}, text(${this.describeTextSettings(this.activeTextSettings)}), page(${this.describePageSettings(this.activePageSettings)})`
      );
      this.applyInjectedLayout(
        vpW,
        vpH,
        savedPage,
        this.activeTextSettings,
        this.activePageSettings,
        false,
        `scheduled:${reason}`,
        anchorRatio
      );
    }, delayMs);
  }

  private scheduleContinuousBoundarySwitch(direction: 'prev' | 'next'): void {
    const now = Date.now();
    if ((now - this.lastBoundarySwitchTime) < 420) {
      return;
    }
    this.clearBoundarySwitchTimer();
    this.boundarySwitchTimer = setTimeout(() => {
      this.boundarySwitchTimer = -1;
      if (!this.ready || this.isPageTurnAnimating || !this.isContinuousMode()) {
        return;
      }
      this.lastBoundarySwitchTime = Date.now();
      this.params.callbacks.onSpineChangeRequested(direction);
    }, 140);
  }

  private resetContinuousBoundarySwitch(): void {
    this.clearBoundarySwitchTimer();
  }

  private handleContinuousBoundaryUpdate(
    payload: PaginationUpdatePayload,
    previousOffset: number
  ): void {
    if (!this.isContinuousMode() || !this.ready || this.isPageTurnAnimating) {
      this.resetContinuousBoundarySwitch();
      return;
    }
    if (Date.now() < this.boundarySuppressionUntil) {
      this.resetContinuousBoundarySwitch();
      return;
    }
    const delta = payload.currentOffset - previousOffset;
    const edgeThreshold = Math.max(12, payload.pageExtent * 0.04);
    const nearEnd = payload.currentOffset >= Math.max(0, payload.maxOffset - edgeThreshold);
    const nearStart = payload.currentOffset <= edgeThreshold;
    if (delta > 6 && nearEnd && payload.currentPage >= Math.max(0, payload.pageCount - 1)) {
      this.scheduleContinuousBoundarySwitch('next');
      return;
    }
    if (delta < -6 && nearStart && payload.currentPage <= 0) {
      this.scheduleContinuousBoundarySwitch('prev');
      return;
    }
    this.resetContinuousBoundarySwitch();
  }

  private handlePaginationChanged(payloadJson: string): void {
    let payload: PaginationUpdatePayload | null = null;
    try {
      const clean = this.parseWebViewJson(payloadJson);
      payload = JSON.parse(clean) as PaginationUpdatePayload;
    } catch (error) {
      logger.warn(TAG, `分页状态回传解析失败: ${String(error)}`);
      return;
    }
    if (!payload) {
      return;
    }
    const previousPage = this.currentPage;
    const previousCount = this.currentPageCount;
    const previousOffset = this.lastPaginationOffset;
    const nextCount = Math.max(1, Math.floor(Number(payload.pageCount) || 1));
    const nextPage = Math.max(0, Math.min(Math.floor(Number(payload.currentPage) || 0), nextCount - 1));
    this.currentLayoutKind = (payload.layoutKind as EpubPageLayoutKind) || this.currentLayoutKind;
    this.currentPageCount = nextCount;
    this.currentPage = nextPage;
    this.lastPaginationOffset = Math.max(0, Number(payload.currentOffset) || 0);
    this.lastPaginationPageExtent = Math.max(0, Number(payload.pageExtent) || 0);
    this.lastPaginationMaxOffset = Math.max(0, Number(payload.maxOffset) || 0);
    this.lastProgressRatio = this.computeProgressRatio(
      this.currentPage,
      this.currentPageCount,
      this.lastPaginationOffset,
      this.lastPaginationMaxOffset
    );
    if (this.ready && (previousPage !== this.currentPage || previousCount !== this.currentPageCount)) {
      this.params.callbacks.onPageChange(this.currentPage, this.currentPageCount);
    }
    if (this.ready && (payload.source === 'scroll' || payload.source === 'window_scroll')) {
      this.handleContinuousBoundaryUpdate(payload, previousOffset);
    }
  }

  private handleReaderTap(payloadJson: string): void {
    if (!this.params.callbacks.onReaderTap) {
      return;
    }
    try {
      const clean = this.parseWebViewJson(payloadJson);
      const payload = JSON.parse(clean) as ReaderTapPayload;
      const safeXRatio = this.clamp(Number(payload.xRatio) || 0, 0, 1);
      const safeYRatio = this.clamp(Number(payload.yRatio) || 0, 0, 1);
      this.params.callbacks.onReaderTap(safeXRatio, safeYRatio);
    } catch (error) {
      logger.warn(TAG, `阅读器点击事件解析失败: ${String(error)}`);
    }
  }

  private buildController(): EpubWebViewReaderController {
    const self = this;
    return new EpubWebViewReaderControllerImpl(
      (
        spineFilePath: string,
        pageOffset: number,
        transitionDirection: EpubSpineTransitionDirection
      ): void => {
        const normalizedDirection = transitionDirection ?? 'none';
        if (normalizedDirection !== 'none' && self.ready && !self.isPageTurnAnimating) {
          self.performAnimatedSpineTransition(
            spineFilePath,
            pageOffset,
            normalizedDirection === 'next'
          );
          return;
        }
        self.pendingSpineTransition = null;
        self.finishPageTurnAnimation();
        self.loadSpineItemImmediate(spineFilePath, pageOffset);
      },
      (forward: boolean): boolean => {
        if (!self.ready || self.isPageTurnAnimating || self.currentPageCount <= 1) {
          return false;
        }
        const nextPage = forward ? self.currentPage + 1 : self.currentPage - 1;
        if (nextPage < 0 || nextPage >= self.currentPageCount) {
          return false;
        }
        self.performAnimatedPageTurn(nextPage, forward);
        return true;
      },
      (pageIndex: number): boolean => {
        return self.goToPageImmediate(pageIndex);
      },
      (): number => {
        return self.currentPageCount;
      },
      (): number => {
        return self.currentPage;
      },
      (settings: EBookReadingSettings): void => {
        self.activeTextSettings = self.cloneTextSettings(settings);
        self.viewportBackgroundColor = self.activeTextSettings.backgroundColor;
        logger.info(TAG, `控制器收到文本设置更新: ${self.describeTextSettings(self.activeTextSettings)}`);
        self.scheduleSettingsReapply('controller_text_settings');
      },
      (settings: MangaReadingSettings): void => {
        self.activePageSettings = self.clonePageSettings(settings);
        logger.info(TAG, `控制器收到翻页设置更新: ${self.describePageSettings(self.activePageSettings)}`);
        self.scheduleSettingsReapply('controller_page_settings');
      },
      (): boolean => {
        return self.ready && !self.isPageTurnAnimating;
      }
    );
  }

  build() {
    Stack() {
      Web({
        src: this.pendingSpinePath.length > 0 ? `file://${this.pendingSpinePath}` : 'about:blank',
        controller: this.webviewController
      })
        .width('100%')
        .height('100%')
        .metaViewport(true)
        .fileAccess(true)
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .imageAccess(true)
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        .overScrollMode(OverScrollMode.NEVER)
        .javaScriptProxy({
          object: this.jsProxy,
          name: 'arkts',
          methodList: ['onPaginationChanged', 'onReaderTap'],
          controller: this.webviewController
        })
        .transform(this.viewportMatrix)
        .opacity(this.viewportOpacity)
        .onPageEnd((_event) => {
          this.clearApplySettingsTimer();
          this.clearPageTurnPhaseTimer();
          if (this.pendingSpineTransition === null) {
            this.finishPageTurnAnimation();
          }
          if (this.params.isFixedLayout) {
            this.runJs(
              '(function(){return JSON.stringify({w:window.innerWidth,h:window.innerHeight,visualW:window.visualViewport?(window.visualViewport.width||0):0,visualH:window.visualViewport?(window.visualViewport.height||0):0,visualScale:window.visualViewport?(window.visualViewport.scale||0):0});})();',
              (raw: string) => {
                let vpW = this.fallbackVpW;
                let vpH = this.fallbackVpH;
                let visualW = this.fallbackVpW;
                let visualH = this.fallbackVpH;
                let visualScale = 1;
                try {
                  const clean = this.parseWebViewJson(raw);
                  const dims = JSON.parse(clean) as ViewportDims;
                  if (dims.w > 0) {
                    vpW = dims.w;
                  }
                  if (dims.h > 0) {
                    vpH = dims.h;
                  }
                  if (dims.visualW > 0) {
                    visualW = dims.visualW;
                  }
                  if (dims.visualH > 0) {
                    visualH = dims.visualH;
                  }
                  if (dims.visualScale > 0) {
                    visualScale = dims.visualScale;
                  }
                } catch (_error) {
                  logger.warn(TAG, 'Fixed-layout viewport parse failed, fallback to display metrics');
                }
                this.lastVpW = vpW;
                this.lastVpH = vpH;
                this.lastVisualVpW = visualW;
                this.lastVisualVpH = visualH;
                this.lastVisualVpScale = visualScale;
                this.applyInjectedLayout(
                  vpW,
                  vpH,
                  this.pendingPageOffset,
                  this.activeTextSettings,
                  this.activePageSettings,
                  true,
                  'page_end_fixed'
                );
                this.pendingPageOffset = 0;
              }
            );
            return;
          }
          this.queryViewportThenInject(this.pendingPageOffset, 'page_end_reflow');
          this.pendingPageOffset = 0;
        })
        .onErrorReceive((event) => {
          if (event) {
            logger.warn(TAG, `WebView load error: ${event.error.getErrorInfo()}`);
          }
        });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.viewportBackgroundColor)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const widthVp = Number(newArea.width);
      const heightVp = Number(newArea.height);
      if (widthVp > 0) {
        this.hostWidthVp = widthVp;
      }
      if (heightVp > 0) {
        this.hostHeightVp = heightVp;
      }
    })
  }
}
