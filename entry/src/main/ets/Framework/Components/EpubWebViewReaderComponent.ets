import { SafeUtils } from '../../Utils/SafeUtils';
import { webview } from '@kit.ArkWeb';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import {
  curves,
  display,
  matrix4,
  promptAction,
  SymbolGlyphModifier,
  UIContext
} from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
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
import { HighlightLineType } from '../../Models/AnnotationModels';
import { DialogSurfaceStyleHelper } from './DialogSurfaceStyleHelper';
import { SettingsGlassStyleHelper } from '../../pages/settings/SettingsGlassStyleHelper';
import {
  CurlStartPosition,
  PageCurlConfigV2,
  PageCurlEffectV2
} from '../../components/PageCurlEffectV2';
import { EpubCssBuilder, EpubPageLayoutKind, CssBuilderViewportState } from './EpubCssBuilder';
import { EpubAnimationEngine } from './EpubAnimationEngine';
import { BridgeJsBuilder } from './BridgeJsBuilder';

const TAG = 'EpubWebViewReaderComponent';
const SETTINGS_APPLY_DELAY_MS = 80;
const REFLOW_SETTLE_DELAY_MS = 260;
const INITIAL_LAYOUT_RECONCILE_DELAY_MS = 480;
const EPUB_WEBVIEW_CAPTURE_COMPONENT_ID = 'epub_webview_reader_content_capture';
const EPUB_CURL_TARGET_CAPTURE_DELAY_MS = 80;
const EPUB_CURL_COVER_RENDER_DELAY_MS = 96;
const EPUB_INTERACTIVE_CURL_TARGET_CAPTURE_DELAY_MS = 80;
const EPUB_INTERACTIVE_CURL_COVER_RENDER_DELAY_MS = 16;
const ABOUT_BLANK_RELOAD_DELAY_MS: number = 120;
const ABOUT_BLANK_VERIFY_DELAY_MS: number = 360;
const ABOUT_BLANK_RELOAD_LIMIT: number = 3;
const IMAGE_RESOURCE_PATH_PATTERN: RegExp = /\.(apng|avif|bmp|gif|heic|heif|jpe?g|png|svg|webp)$/i;
const EPUB_HIGHLIGHT_POPUP_COLOR_OPTIONS: string[] = ['#E8A317', '#3B82F6', '#EF4444', '#22C55E', '#A855F7'];

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

export { EpubPageLayoutKind } from './EpubCssBuilder';
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
  contentExtent: number;
  inlineMediaCount: number;
  blockMediaCount: number;
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
  bodyTransform: string;
  bodyVirtualOffsetAttr: string;
  bodyTextLength: number;
  bodyChildCount: number;
  bodyHtmlLength: number;
  documentUrl: string;
  styleTagParent: string;
  isStyleTagLastChild: boolean;
  rootTagName: string;
  contentKind: string;
}

interface PageCommandResult {
  pageIndex: number;
  offset: number;
  pageCount: number;
  pageExtent: number;
  maxOffset: number;
  requestedOffset: number;
  physicalOffset: number;
  usedVirtualOffset: boolean;
  found?: boolean;
}

interface EpubPaginationSnapshot {
  pageCount: number;
  currentPage: number;
  currentOffset: number;
  pageExtent: number;
  maxOffset: number;
  contentExtent: number;
  rootTagName: string;
}

interface EpubReadAloudHighlightResult {
  pageIndex: number;
  offset: number;
  pageCount: number;
  pageExtent: number;
  maxOffset: number;
  applied: number;
  followed: boolean;
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

interface ReaderSwipePayload {
  deltaX: number;
  deltaY: number;
}

interface ReaderPanPayload {
  phase: string;
  xRatio: number;
  yRatio: number;
  deltaXRatio: number;
  deltaYRatio: number;
}

export interface EpubWebHighlightRange {
  id: string;
  startOffset: number;
  endOffset: number;
  color: string;
  lineType?: HighlightLineType;
  quoteText?: string;
  pageIndex?: number;
  thoughtText?: string;
}

export interface EpubWebSelectionSnapshot {
  selectedText: string;
  startOffset: number;
  endOffset: number;
  contextBefore: string;
  contextAfter: string;
  pageIndex: number;
  pageProgress: number;
  rectX: number;
  rectY: number;
  rectWidth: number;
  rectHeight: number;
}

export interface EpubWebTextSnapshot {
  text: string;
  startOffset: number;
  endOffset: number;
  contextBefore: string;
  contextAfter: string;
  pageIndex: number;
  pageProgress: number;
  quoteText: string;
}

export interface EpubWebPurifyRulePayload {
  id: string;
  pattern: string;
  replacement: string;
  isRegex: boolean;
}

interface EpubWebHighlightTapPayload {
  id: string;
  xRatio: number;
  yRatio: number;
}

interface EpubReaderJsProxy {
  onPaginationChanged: (payloadJson: string) => void;
  onReaderTap: (payloadJson: string) => void;
  onReaderPan: (payloadJson: string) => void;
  onReaderSwipe: (payloadJson: string) => void;
  onEpubHighlightTap: (payloadJson: string) => void;
}

interface PendingSpineTransitionState {
  incoming: ViewportAnimationState;
  inDuration: number;
  inCurve: Curve;
  useCurl: boolean;
  forward: boolean;
}

export interface EpubWebViewReaderController {
  loadSpineItem(
    spineFilePath: string,
    pageOffset: number,
    transitionDirection?: EpubSpineTransitionDirection,
    anchorFragment?: string,
    spineLayoutType?: string,
    spineMediaType?: string
  ): void;
  flipPage(forward: boolean): boolean;
  beginInteractiveCurl(forward: boolean, touchX: number, touchY: number): boolean;
  updateInteractiveCurl(progress: number, touchX: number, touchY: number): void;
  endInteractiveCurl(complete: boolean): boolean;
  cancelInteractiveCurl(): void;
  goToPage(pageIndex: number): boolean;
  goToAnchor(anchorFragment: string): boolean;
  getPageCount(): number;
  getCurrentPage(): number;
  queryCurrentTextSnapshot(onResult: (snapshot: EpubWebTextSnapshot | null) => void): void;
  applyPurifyRules(rules: EpubWebPurifyRulePayload[]): void;
  seekToTextOffset(offset: number): boolean;
  applyReadAloudHighlight(startOffset: number, endOffset: number, follow: boolean, progressOffset?: number): void;
  clearReadAloudHighlight(): void;
  applyReadingSettings(settings: EBookReadingSettings): void;
  applyPageSettings(settings: MangaReadingSettings): void;
  isReady(): boolean;
}

export interface EpubRuntimeBlankSpineInfo {
  spineFilePath: string;
  loadedFileUrl: string;
  documentUrl: string;
  source: string;
  bodyTextLength: number;
  inlineMediaCount: number;
  blockMediaCount: number;
  bodyChildCount: number;
  bodyHtmlLength: number;
}

export enum EpubWebPageChangeSource {
  DEFAULT = 'default',
  READ_ALOUD_FOLLOW = 'read_aloud_follow'
}

export interface EpubWebViewReaderCallbacks {
  onPageChange: (page: number, totalPages: number, source?: EpubWebPageChangeSource) => void;
  onSpineChangeRequested: (direction: 'prev' | 'next') => void;
  onReady: (controller: EpubWebViewReaderController) => void;
  onError: (msg: string) => void;
  onReaderTap?: (xRatio: number, yRatio: number) => void;
  onReaderSwipe?: (deltaX: number, deltaY: number) => void;
  onRuntimeBlankSpine?: (info: EpubRuntimeBlankSpineInfo) => boolean;
  onAddPurifyRule?: (pattern: string) => void;
  onStartReadAloudFromCharIndex?: (charIndex: number) => void;
  onAddHighlight?: (snapshot: EpubWebSelectionSnapshot) => void;
  onAddHighlightWithThought?: (snapshot: EpubWebSelectionSnapshot) => void;
  onUpdateHighlightStyle?: (highlightId: string, lineType: HighlightLineType, color: string) => void;
  onUpdateHighlightThought?: (highlightId: string, thoughtText: string) => void;
}

export interface EpubWebViewReaderParams {
  initialSpineFilePath: string;
  initialPageOffset: number;
  initialAnchorFragment?: string;
  contentSafeTopInset?: number;
  textSettings: EBookReadingSettings;
  pageSettings: MangaReadingSettings;
  isFixedLayout: boolean;
  spineLayoutType?: string;
  spineMediaType?: string;
  callbacks: EpubWebViewReaderCallbacks;
}

class EpubWebViewReaderControllerImpl implements EpubWebViewReaderController {
  private fnLoad: (
    path: string,
    offset: number,
    transitionDirection: EpubSpineTransitionDirection,
    anchorFragment: string,
    spineLayoutType: string,
    spineMediaType: string
  ) => void;
  private fnFlip: (forward: boolean) => boolean;
  private fnBeginInteractiveCurl: (forward: boolean, touchX: number, touchY: number) => boolean;
  private fnUpdateInteractiveCurl: (progress: number, touchX: number, touchY: number) => void;
  private fnEndInteractiveCurl: (complete: boolean) => boolean;
  private fnCancelInteractiveCurl: () => void;
  private fnGoToPage: (pageIndex: number) => boolean;
  private fnGoToAnchor: (anchorFragment: string) => boolean;
  private fnGetCount: () => number;
  private fnGetCurrent: () => number;
  private fnQueryCurrentTextSnapshot: (onResult: (snapshot: EpubWebTextSnapshot | null) => void) => void;
  private fnApplyPurifyRules: (rules: EpubWebPurifyRulePayload[]) => void;
  private fnSeekToTextOffset: (offset: number) => boolean;
  private fnApplyReadAloudHighlight: (startOffset: number, endOffset: number, follow: boolean, progressOffset?: number) => void;
  private fnClearReadAloudHighlight: () => void;
  private fnApplySettings: (s: EBookReadingSettings) => void;
  private fnApplyPageSettings: (s: MangaReadingSettings) => void;
  private fnIsReady: () => boolean;

  constructor(
    fnLoad: (
      path: string,
      offset: number,
      transitionDirection: EpubSpineTransitionDirection,
      anchorFragment: string,
      spineLayoutType: string,
      spineMediaType: string
    ) => void,
    fnFlip: (forward: boolean) => boolean,
    fnBeginInteractiveCurl: (forward: boolean, touchX: number, touchY: number) => boolean,
    fnUpdateInteractiveCurl: (progress: number, touchX: number, touchY: number) => void,
    fnEndInteractiveCurl: (complete: boolean) => boolean,
    fnCancelInteractiveCurl: () => void,
    fnGoToPage: (pageIndex: number) => boolean,
    fnGoToAnchor: (anchorFragment: string) => boolean,
    fnGetCount: () => number,
    fnGetCurrent: () => number,
    fnQueryCurrentTextSnapshot: (onResult: (snapshot: EpubWebTextSnapshot | null) => void) => void,
    fnApplyPurifyRules: (rules: EpubWebPurifyRulePayload[]) => void,
    fnSeekToTextOffset: (offset: number) => boolean,
    fnApplyReadAloudHighlight: (startOffset: number, endOffset: number, follow: boolean, progressOffset?: number) => void,
    fnClearReadAloudHighlight: () => void,
    fnApplySettings: (s: EBookReadingSettings) => void,
    fnApplyPageSettings: (s: MangaReadingSettings) => void,
    fnIsReady: () => boolean
  ) {
    this.fnLoad = fnLoad;
    this.fnFlip = fnFlip;
    this.fnBeginInteractiveCurl = fnBeginInteractiveCurl;
    this.fnUpdateInteractiveCurl = fnUpdateInteractiveCurl;
    this.fnEndInteractiveCurl = fnEndInteractiveCurl;
    this.fnCancelInteractiveCurl = fnCancelInteractiveCurl;
    this.fnGoToPage = fnGoToPage;
    this.fnGoToAnchor = fnGoToAnchor;
    this.fnGetCount = fnGetCount;
    this.fnGetCurrent = fnGetCurrent;
    this.fnQueryCurrentTextSnapshot = fnQueryCurrentTextSnapshot;
    this.fnApplyPurifyRules = fnApplyPurifyRules;
    this.fnSeekToTextOffset = fnSeekToTextOffset;
    this.fnApplyReadAloudHighlight = fnApplyReadAloudHighlight;
    this.fnClearReadAloudHighlight = fnClearReadAloudHighlight;
    this.fnApplySettings = fnApplySettings;
    this.fnApplyPageSettings = fnApplyPageSettings;
    this.fnIsReady = fnIsReady;
  }

  loadSpineItem(
    spineFilePath: string,
    pageOffset: number,
    transitionDirection: EpubSpineTransitionDirection = 'none',
    anchorFragment: string = '',
    spineLayoutType: string = '',
    spineMediaType: string = ''
  ): void {
    this.fnLoad(spineFilePath, pageOffset, transitionDirection, anchorFragment, spineLayoutType, spineMediaType);
  }

  flipPage(forward: boolean): boolean {
    return this.fnFlip(forward);
  }

  beginInteractiveCurl(forward: boolean, touchX: number, touchY: number): boolean {
    return this.fnBeginInteractiveCurl(forward, touchX, touchY);
  }

  updateInteractiveCurl(progress: number, touchX: number, touchY: number): void {
    this.fnUpdateInteractiveCurl(progress, touchX, touchY);
  }

  endInteractiveCurl(complete: boolean): boolean {
    return this.fnEndInteractiveCurl(complete);
  }

  cancelInteractiveCurl(): void {
    this.fnCancelInteractiveCurl();
  }

  goToPage(pageIndex: number): boolean {
    return this.fnGoToPage(pageIndex);
  }

  goToAnchor(anchorFragment: string): boolean {
    return this.fnGoToAnchor(anchorFragment);
  }

  getPageCount(): number {
    return this.fnGetCount();
  }

  getCurrentPage(): number {
    return this.fnGetCurrent();
  }

  queryCurrentTextSnapshot(onResult: (snapshot: EpubWebTextSnapshot | null) => void): void {
    this.fnQueryCurrentTextSnapshot(onResult);
  }

  applyPurifyRules(rules: EpubWebPurifyRulePayload[]): void {
    this.fnApplyPurifyRules(rules);
  }

  seekToTextOffset(offset: number): boolean {
    return this.fnSeekToTextOffset(offset);
  }

  applyReadAloudHighlight(startOffset: number, endOffset: number, follow: boolean, progressOffset?: number): void {
    this.fnApplyReadAloudHighlight(startOffset, endOffset, follow, progressOffset);
  }

  clearReadAloudHighlight(): void {
    this.fnClearReadAloudHighlight();
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
  @Prop enableEpubAnnotations: boolean = false;
  @Prop @Watch('onEpubHighlightRangesChange') epubHighlightRanges: EpubWebHighlightRange[] = [];

  private uiContext: UIContext | null = null;
  private webviewController: webview.WebviewController = new webview.WebviewController();
  private currentPageCount: number = 0;
  private currentPage: number = 0;
  private ready: boolean = false;
  private webControllerAttached: boolean = false;
  private universalAccessRootSignature: string = '';
  private lastLoadedFileUrl: string = '';
  private isPageTurnAnimating: boolean = false;
  private pendingPageOffset: number = 0;
  private pendingSpinePath: string = '';
  private pendingAnchorFragment: string = '';
  private activeSpineLayoutType: string = '';
  private activeSpineMediaType: string = '';
  private applySettingsTimer: number = -1;
  private pendingSettingsReapplyReason: string = '';
  private pageTurnPhaseTimer: number = -1;
  private paintStabilizeTimer: number = -1;
  private aboutBlankReloadTimer: number = -1;
  private aboutBlankReloadCount: number = 0;
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
    pageTopMargin: DEFAULT_EBOOK_READING_SETTINGS.pageTopMargin,
    pageBottomMargin: DEFAULT_EBOOK_READING_SETTINGS.pageBottomMargin,
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
  private webSelectionSnapshot: EpubWebSelectionSnapshot | null = null;
  private webSelectionRefreshTimer: number = -1;
  private webSelectionActionInProgress: boolean = false;
  private pendingThoughtPopupStartOffset: number = -1;
  private pendingThoughtPopupEndOffset: number = -1;
  private pendingThoughtPopupQuoteText: string = '';
  private pendingThoughtPopupRetryCount: number = 0;
  private pendingThoughtPopupTimer: number = -1;
  private suppressNextTapEvent: boolean = false;
  private suppressNextTapResetTimer: number = -1;
  private epubCurlCurrentPixelMap: image.PixelMap | null = null;
  private epubCurlNextPixelMap: image.PixelMap | null = null;
  private epubCurlAnimationTimer: number = -1;
  private epubCurlReleaseTimer: number = -1;
  private epubCurlInteractiveActive: boolean = false;
  private epubCurlInteractiveReady: boolean = false;
  private epubCurlInteractiveEndPending: boolean = false;
  private epubCurlInteractiveEndComplete: boolean = false;
  private epubCurlInteractiveOriginalPage: number = -1;
  private epubCurlInteractiveTargetPage: number = -1;
  private epubCurlPendingProgress: number = 0;
  private epubCurlLastProgress: number = 0;
  private epubCurlLastProgressAt: number = 0;
  private epubCurlReleaseVelocity: number = 0;
  private epubCurlReleaseAnimating: boolean = false;
  private epubCurlReleaseComplete: boolean = false;
  private readerSwipeSuppressedUntil: number = 0;
  private epubCurlEffectConfig: PageCurlConfigV2 = {
    stripCount: 24,
    maxCurlHeight: 100,
    shadowIntensity: 0.6,
    animationDuration: 240,
    enableShadow: true,
    enableHighlight: true,
    flipThreshold: 0.35
  };
  private jsProxy: EpubReaderJsProxy = {
    onPaginationChanged: (payloadJson: string): void => {
      this.handlePaginationChanged(payloadJson);
    },
    onReaderTap: (payloadJson: string): void => {
      this.handleReaderTap(payloadJson);
    },
    onReaderPan: (payloadJson: string): void => {
      this.handleReaderPan(payloadJson);
    },
    onReaderSwipe: (payloadJson: string): void => {
      this.handleReaderSwipe(payloadJson);
    },
    onEpubHighlightTap: (payloadJson: string): void => {
      this.handleEpubHighlightTap(payloadJson);
    }
  };

  @State private viewportOpacity: number = 1;
  @State private viewportMatrix: matrix4.Matrix4Transit = matrix4.identity();
  @State private viewportBackgroundColor: string = DEFAULT_EBOOK_READING_SETTINGS.backgroundColor;
  @State private showEpubCurlSnapshotCover: boolean = false;
  @State private showEpubCurlEffect: boolean = false;
  @State private hideWebViewForEpubCurlCapture: boolean = false;
  @State private epubCurlCanvasReady: boolean = false;
  @State private epubCurlProgress: number = 0;
  @State private epubCurlRenderToken: number = 0;
  @State private epubCurlAnimateTarget: number = -1;
  @State private epubCurlAnimateVelocity: number = 0;
  @State private epubCurlIsForward: boolean = true;
  @State private epubCurlStartPosition: CurlStartPosition = CurlStartPosition.RIGHT_EDGE;
  @State private epubCurlTouchX: number = 0;
  @State private epubCurlTouchY: number = 0;
  @State private webSelectedText: string = '';
  @State private showHighlightThoughtPopup: boolean = false;
  @State private highlightThoughtPopupText: string = '';
  @State private highlightThoughtPopupIsPlaceholder: boolean = false;
  @State private highlightThoughtPopupEditing: boolean = false;
  @State private highlightThoughtPopupInputText: string = '';
  @State private highlightThoughtPopupQuoteText: string = '';
  @State private highlightThoughtPopupHighlightId: string = '';
  @State private highlightThoughtPopupColor: string = '#E8A317';
  @State private highlightThoughtPopupLineType: HighlightLineType = HighlightLineType.UNDERLINE;
  @State private highlightThoughtPopupLeftVp: number = 12;
  @State private highlightThoughtPopupTopVp: number = 72;
  @State private highlightThoughtPopupMaskOpacity: number = 0;
  @State private highlightThoughtPopupOpacity: number = 0;
  @State private highlightThoughtPopupScale: number = 0.88;
  @State private highlightThoughtPopupTranslateY: number = 14;
  private highlightThoughtPopupTimer: number = -1;
  private highlightThoughtPopupHideTimer: number = -1;

  aboutToAppear(): void {
    this.uiContext = this.resolveUiContext();
    const dm = display.getDefaultDisplaySync();
    if (this.uiContext) {
      this.fallbackVpW = this.uiContext.px2vp(dm.width);
      this.fallbackVpH = this.uiContext.px2vp(dm.height);
    }
    this.pendingSpinePath = this.params.initialSpineFilePath;
    this.pendingPageOffset = this.params.initialPageOffset;
    this.pendingAnchorFragment = this.normalizeAnchorFragment(this.params.initialAnchorFragment ?? '');
    this.activeSpineLayoutType = this.params.spineLayoutType ?? '';
    this.activeSpineMediaType = this.params.spineMediaType ?? '';
    this.activeTextSettings = this.cloneTextSettings(this.params.textSettings);
    this.activePageSettings = this.normalizePageSettingsForEpub(this.params.pageSettings);
    this.viewportBackgroundColor = this.activeTextSettings.backgroundColor;
    this.resetViewportTransform();
    logger.info(
      TAG,
      `组件初始化: spine=${this.pendingSpinePath}, pageOffset=${this.pendingPageOffset}, anchor=${this.pendingAnchorFragment || 'none'}, fixed=${this.params.isFixedLayout}, text(${this.describeTextSettings(this.activeTextSettings)}), page(${this.describePageSettings(this.activePageSettings)})`
    );
  }

  aboutToDisappear(): void {
    this.clearDeferredWork();
    this.clearAnnotationTransientTimers();
    this.resetViewportTransform();
    this.pendingSpineTransition = null;
    this.resetEpubCurlState(true);
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

  private clearPaintStabilizeTimer(): void {
    if (this.paintStabilizeTimer !== -1) {
      clearTimeout(this.paintStabilizeTimer);
      this.paintStabilizeTimer = -1;
    }
  }

  private clearAboutBlankReloadTimer(): void {
    if (this.aboutBlankReloadTimer !== -1) {
      clearTimeout(this.aboutBlankReloadTimer);
      this.aboutBlankReloadTimer = -1;
    }
  }

  private clearDeferredWork(): void {
    this.clearApplySettingsTimer();
    this.clearPageTurnPhaseTimer();
    this.clearPaintStabilizeTimer();
    this.clearAboutBlankReloadTimer();
    this.clearBoundarySwitchTimer();
  }

  private clearAnnotationTransientTimers(): void {
    if (this.webSelectionRefreshTimer !== -1) {
      clearTimeout(this.webSelectionRefreshTimer);
      this.webSelectionRefreshTimer = -1;
    }
    if (this.pendingThoughtPopupTimer !== -1) {
      clearTimeout(this.pendingThoughtPopupTimer);
      this.pendingThoughtPopupTimer = -1;
    }
    if (this.suppressNextTapResetTimer !== -1) {
      clearTimeout(this.suppressNextTapResetTimer);
      this.suppressNextTapResetTimer = -1;
    }
    if (this.highlightThoughtPopupTimer !== -1) {
      clearTimeout(this.highlightThoughtPopupTimer);
      this.highlightThoughtPopupTimer = -1;
    }
    if (this.highlightThoughtPopupHideTimer !== -1) {
      clearTimeout(this.highlightThoughtPopupHideTimer);
      this.highlightThoughtPopupHideTimer = -1;
    }
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

  private runJsForResult(code: string, timeoutMs: number): Promise<string> {
    return new Promise<string>((resolve) => {
      let resolved = false;
      let timer = -1;
      const finish = (result: string): void => {
        if (resolved) {
          return;
        }
        resolved = true;
        if (timer !== -1) {
          clearTimeout(timer);
          timer = -1;
        }
        resolve(result);
      };
      timer = setTimeout(() => {
        finish('');
      }, Math.max(16, timeoutMs));
      this.runJs(code, (result: string) => {
        finish(result);
      });
    });
  }

  private parseWebViewJson(raw: string): string {
    if (raw.startsWith('"') && raw.endsWith('"')) {
      try {
        return SafeUtils.parseStr(raw) as string;
      } catch (_error) {
        return raw;
      }
    }
    return raw;
  }

  private isAboutBlankUrl(url: string): boolean {
    const normalized = url.trim();
    return normalized.length <= 0 || normalized === 'about:blank';
  }

  private scheduleAboutBlankReload(reason: string): void {
    if (this.ready || this.lastLoadedFileUrl.length <= 0) {
      return;
    }
    if (this.aboutBlankReloadCount >= ABOUT_BLANK_RELOAD_LIMIT) {
      logger.warn(
        TAG,
        `WebView 首屏仍停留在 about:blank，已停止重试: reason=${reason}, attempts=${this.aboutBlankReloadCount}, loaded=${this.lastLoadedFileUrl || 'none'}`
      );
      this.params.callbacks.onError('WebView 首屏加载停留在空白页，请重新打开电子书');
      return;
    }
    this.aboutBlankReloadCount++;
    const attempt = this.aboutBlankReloadCount;
    this.clearAboutBlankReloadTimer();
    this.aboutBlankReloadTimer = setTimeout(() => {
      this.aboutBlankReloadTimer = -1;
      if (this.ready || this.lastLoadedFileUrl.length <= 0) {
        return;
      }
      try {
        logger.warn(
          TAG,
          `WebView 首屏 about:blank，重新加载真实 spine: reason=${reason}, attempt=${attempt}/${ABOUT_BLANK_RELOAD_LIMIT}, url=${this.lastLoadedFileUrl}`
        );
        this.webviewController.loadUrl(this.lastLoadedFileUrl);
      } catch (error) {
        const msg = String(error);
        logger.error(TAG, `about:blank 重载 WebView spine 失败: ${msg}`);
        this.params.callbacks.onError(`加载失败: ${msg}`);
        return;
      }
      this.aboutBlankReloadTimer = setTimeout(() => {
        this.aboutBlankReloadTimer = -1;
        if (this.ready || this.lastLoadedFileUrl.length <= 0) {
          return;
        }
        logger.warn(
          TAG,
          `WebView about:blank 重载后未收到页面完成事件，主动验证当前 DOM: attempt=${attempt}/${ABOUT_BLANK_RELOAD_LIMIT}`
        );
        this.queryViewportThenInject(this.pendingPageOffset, 'page_end_reflow');
      }, ABOUT_BLANK_VERIFY_DELAY_MS);
    }, ABOUT_BLANK_RELOAD_DELAY_MS);
  }

  private handleAboutBlankPageEnd(url: string): boolean {
    if (!this.isAboutBlankUrl(url) || this.ready || this.pendingSpinePath.length <= 0) {
      return false;
    }
    logger.warn(TAG, `忽略 about:blank 页面完成事件，等待真实 spine: eventUrl=${url || 'empty'}, loaded=${this.lastLoadedFileUrl}`);
    if (this.lastLoadedFileUrl.length > 0) {
      this.scheduleAboutBlankReload('page_end_blank');
    }
    return true;
  }

  private shouldIgnoreInitialBlankProbe(metrics: PaginationMetrics, source: string, notifyReady: boolean): boolean {
    if (!notifyReady || source !== 'page_end_reflow') {
      return false;
    }
    const documentUrl = metrics.documentUrl.trim();
    if (documentUrl === 'about:blank') {
      logger.warn(
        TAG,
        `忽略 about:blank 首屏探测并触发重载: source=${source}, loaded=${this.lastLoadedFileUrl || 'none'}`
      );
      if (this.lastLoadedFileUrl.length > 0) {
        this.scheduleAboutBlankReload('metrics_blank_probe');
      }
      return true;
    }
    return false;
  }

  private shouldHandleRuntimeBlankSpine(metrics: PaginationMetrics, source: string, notifyReady: boolean): boolean {
    return notifyReady &&
      source === 'page_end_reflow' &&
      !this.params.isFixedLayout &&
      metrics.bodyTextLength <= 0 &&
      metrics.inlineMediaCount <= 0 &&
      metrics.blockMediaCount <= 0;
  }

  private handleRuntimeBlankSpine(metrics: PaginationMetrics, source: string, notifyReady: boolean): boolean {
    if (!this.shouldHandleRuntimeBlankSpine(metrics, source, notifyReady)) {
      return false;
    }
    const callback = this.params.callbacks.onRuntimeBlankSpine;
    if (!callback) {
      return false;
    }
    const info: EpubRuntimeBlankSpineInfo = {
      spineFilePath: this.pendingSpinePath,
      loadedFileUrl: this.lastLoadedFileUrl,
      documentUrl: metrics.documentUrl,
      source: source,
      bodyTextLength: metrics.bodyTextLength,
      inlineMediaCount: metrics.inlineMediaCount,
      blockMediaCount: metrics.blockMediaCount,
      bodyChildCount: metrics.bodyChildCount,
      bodyHtmlLength: metrics.bodyHtmlLength
    };
    const handled = callback(info);
    if (!handled) {
      return false;
    }
    this.pendingAnchorFragment = '';
    this.pendingSpineTransition = null;
    this.ready = false;
    this.finishPageTurnAnimation();
    logger.warn(
      TAG,
      `运行时空 WebView spine 已交由宿主跳过: source=${source}, text=${metrics.bodyTextLength}, media=${metrics.inlineMediaCount}/${metrics.blockMediaCount}, bodyChildren=${metrics.bodyChildCount}, bodyHtml=${metrics.bodyHtmlLength}, doc=${metrics.documentUrl || 'none'}`
    );
    return true;
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
          const dims = SafeUtils.parseObj(clean) as ViewportDims;
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
      pageTopMargin: settings.pageTopMargin,
      pageBottomMargin: settings.pageBottomMargin,
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
      doublePageVerticalDirection: settings.doublePageVerticalDirection ?? DEFAULT_READING_SETTINGS.doublePageVerticalDirection,
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

  private normalizePageSettingsForEpub(settings: MangaReadingSettings): MangaReadingSettings {
    const normalized = this.clonePageSettings(settings);
    if (normalized.readingMode === ReadingMode.CONTINUOUS_SCROLL) {
      normalized.readingMode = ReadingMode.SINGLE_PAGE;
      normalized.readingDirection = normalized.readingDirection === ReadingDirection.RIGHT_TO_LEFT
        ? ReadingDirection.RIGHT_TO_LEFT
        : ReadingDirection.LEFT_TO_RIGHT;
      logger.info(TAG, '组件收到 EPUB 连续滚动设置，已按单页模式处理');
    }
    return normalized;
  }

  private getCurrentSpineLayoutType(): string {
    return this.activeSpineLayoutType.trim().toUpperCase();
  }

  private getCurrentSpineMediaType(): string {
    return this.activeSpineMediaType.trim().toLowerCase();
  }

  private getCurrentSpinePathHint(): string {
    return this.pendingSpinePath.trim().toLowerCase();
  }

  private isCurrentSpineImageLike(): boolean {
    const layoutType = this.getCurrentSpineLayoutType();
    if (layoutType === 'IMAGE_PAGE') {
      return true;
    }
    const mediaType = this.getCurrentSpineMediaType();
    if (mediaType.startsWith('image/')) {
      return true;
    }
    const pathHint = this.getCurrentSpinePathHint().replace(/[#?].*$/, '');
    return IMAGE_RESOURCE_PATH_PATTERN.test(pathHint);
  }

  private clamp(value: number, min: number, max: number): number {
    return EpubCssBuilder.clamp(value, min, max);
  }

  private normalizeAnchorFragment(anchorFragment: string): string {
    const trimmed = anchorFragment.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    const normalized = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
    if (normalized.length <= 0) {
      return '';
    }
    try {
      return decodeURIComponent(normalized);
    } catch (_error) {
      return normalized;
    }
  }

  private describeTextSettings(settings: EBookReadingSettings): string {
    const fontPath = (settings.fontPath ?? '').trim();
    const backgroundImagePath = (settings.backgroundImagePath ?? '').trim();
    return `fontSize=${settings.fontSize}, fontFamily=${settings.fontFamily}, fontPath=${fontPath.length > 0 ? fontPath : 'none'}, fontWeight=${settings.fontWeight ?? 400}, lineHeight=${settings.lineHeight}, margin=${settings.pageMargin}, top=${settings.pageTopMargin ?? settings.pageMargin}, bottom=${settings.pageBottomMargin ?? settings.pageMargin}, letterSpacing=${settings.letterSpacing ?? 0}, paragraphSpacing=${settings.paragraphSpacing ?? 8}, firstLineIndent=${settings.firstLineIndent ?? 2}, bg=${settings.backgroundColor}, text=${settings.textColor}, align=${settings.textAlignment ?? 'JUSTIFY'}, bgType=${settings.backgroundType ?? 'COLOR'}, bgImage=${backgroundImagePath.length > 0 ? backgroundImagePath : 'none'}`;
  }

  private describePageSettings(settings: MangaReadingSettings): string {
    return `mode=${settings.readingMode}, direction=${settings.readingDirection}, animation=${settings.pageTurnAnimation}, doublePagePortrait=${settings.doublePagePortraitLayout}`;
  }

  private getViewportScale(vpW: number, vpH: number): number {
    const vpState: CssBuilderViewportState = {
      hostWidthVp: this.hostWidthVp,
      hostHeightVp: this.hostHeightVp,
      fallbackVpW: this.fallbackVpW,
      fallbackVpH: this.fallbackVpH,
      lastVisualVpW: this.lastVisualVpW,
      lastVisualVpH: this.lastVisualVpH,
      contentSafeTopInset: 0,
      isFixedLayout: false,
      isCurrentSpineImageLike: false
    };
    return EpubCssBuilder.getViewportScale(vpW, vpH, vpState);
  }

  private getLayoutKind(settings: MangaReadingSettings, vpW: number, vpH: number): EpubPageLayoutKind {
    return EpubCssBuilder.getLayoutKind(settings, vpW, vpH);
  }

  private isContinuousVerticalMode(settings: MangaReadingSettings = this.activePageSettings): boolean {
    return EpubCssBuilder.isContinuousVerticalMode(settings);
  }

  private isContinuousMode(settings: MangaReadingSettings = this.activePageSettings): boolean {
    return EpubCssBuilder.isContinuousMode(settings);
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
    return EpubAnimationEngine.normalizeAnimationType(animationType);
  }

  private normalizeViewportAnimationType(animationType: PageTurnAnimationType): PageTurnAnimationType {
    return EpubAnimationEngine.normalizeViewportAnimationType(animationType);
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
    return EpubAnimationEngine.buildMatrix(translateX, translateY, translateZ, scaleX, scaleY, rotateX, rotateY);
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
    return EpubAnimationEngine.getAnimationDirectionSign(layoutKind, forward, this.activePageSettings.readingDirection);
  }

  private getAnimationViewportWidthVp(): number {
    if (this.hostWidthVp > 1) {
      return this.hostWidthVp;
    }
    if (this.fallbackVpW > 1) {
      return this.fallbackVpW;
    }
    const dm = display.getDefaultDisplaySync();
    const uiContext = this.resolveUiContext();
    return uiContext ? uiContext.px2vp(dm.width) : dm.width;
  }

  private getAnimationViewportHeightVp(): number {
    if (this.hostHeightVp > 1) {
      return this.hostHeightVp;
    }
    if (this.fallbackVpH > 1) {
      return this.fallbackVpH;
    }
    const dm = display.getDefaultDisplaySync();
    const uiContext = this.resolveUiContext();
    return uiContext ? uiContext.px2vp(dm.height) : dm.height;
  }

  private createTextSafeAnimationProfile(
    layoutKind: EpubPageLayoutKind,
    forward: boolean,
    animationType: PageTurnAnimationType
  ): PageTurnAnimationProfile {
    return EpubAnimationEngine.createTextSafeAnimationProfile(
      layoutKind, forward, animationType,
      this.getAnimationViewportWidthVp(), this.getAnimationViewportHeightVp(),
      this.activePageSettings.readingDirection
    );
  }

  private createAnimationProfile(
    layoutKind: EpubPageLayoutKind,
    forward: boolean,
    animationType: PageTurnAnimationType
  ): PageTurnAnimationProfile {
    return EpubAnimationEngine.createAnimationProfile(
      layoutKind, forward, animationType,
      this.getAnimationViewportWidthVp(), this.getAnimationViewportHeightVp(),
      this.activePageSettings.readingDirection,
      this.params.isFixedLayout
    );
  }

  private escapeJsTemplate(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/`/g, '\\`').replace(/\$\{/g, '\\${');
  }

  private escapeJsSingleQuoted(value: string): string {
    return value.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
  }

  private buildAnnotationBridgeJs(): string {
    return BridgeJsBuilder.buildAnnotationBridgeJs();
  }

  private normalizeFileUrl(rawPath: string): string {
    return EpubCssBuilder.normalizeFileUrl(rawPath);
  }

  private toRgba(color: string, alpha: number): string {
    return EpubCssBuilder.toRgba(color, alpha);
  }

  private resolveTextAlignment(value: string | undefined): string {
    return EpubCssBuilder.resolveTextAlignment(value);
  }

  private buildFontCss(textSettings: EBookReadingSettings): string {
    return EpubCssBuilder.buildFontCss(textSettings);
  }

  private resolveFontFamily(textSettings: EBookReadingSettings): string {
    return EpubCssBuilder.resolveFontFamily(textSettings);
  }

  private buildBackgroundCss(textSettings: EBookReadingSettings): string {
    return EpubCssBuilder.buildBackgroundCss(textSettings);
  }

  private buildReflowCss(
    vpW: number,
    vpH: number,
    textSettings: EBookReadingSettings,
    pageSettings: MangaReadingSettings
  ): string {
    const vpState: CssBuilderViewportState = {
      hostWidthVp: this.hostWidthVp,
      hostHeightVp: this.hostHeightVp,
      fallbackVpW: this.fallbackVpW,
      fallbackVpH: this.fallbackVpH,
      lastVisualVpW: this.lastVisualVpW,
      lastVisualVpH: this.lastVisualVpH,
      contentSafeTopInset: this.params.contentSafeTopInset ?? 0,
      isFixedLayout: this.params.isFixedLayout,
      isCurrentSpineImageLike: this.isCurrentSpineImageLike()
    };
    return EpubCssBuilder.buildReflowCss(vpW, vpH, textSettings, pageSettings, vpState);
  }

  private buildFixedCss(vpW: number, vpH: number, textSettings: EBookReadingSettings): string {
    const vpState: CssBuilderViewportState = {
      hostWidthVp: this.hostWidthVp,
      hostHeightVp: this.hostHeightVp,
      fallbackVpW: this.fallbackVpW,
      fallbackVpH: this.fallbackVpH,
      lastVisualVpW: this.lastVisualVpW,
      lastVisualVpH: this.lastVisualVpH,
      contentSafeTopInset: this.params.contentSafeTopInset ?? 0,
      isFixedLayout: this.params.isFixedLayout,
      isCurrentSpineImageLike: this.isCurrentSpineImageLike()
    };
    return EpubCssBuilder.buildFixedCss(vpW, vpH, textSettings, vpState);
  }

  private buildBridgeJs(layoutKind: EpubPageLayoutKind): string {
    return BridgeJsBuilder.buildBridgeJs(layoutKind);
  }

  private parsePageCommandResult(raw: string, fallbackPage: number): PageCommandResult {
    try {
      const clean = this.parseWebViewJson(raw);
      const parsed = SafeUtils.parseObj(clean) as PageCommandResult;
      const pageIndex = Number(parsed.pageIndex);
      const offset = Number(parsed.offset);
      const pageCount = Number(parsed.pageCount);
      const pageExtent = Number(parsed.pageExtent);
      const maxOffset = Number(parsed.maxOffset);
      const requestedOffset = Number(parsed.requestedOffset);
      const physicalOffset = Number(parsed.physicalOffset);
      return {
        pageIndex: !isNaN(pageIndex) ? pageIndex : fallbackPage,
        offset: !isNaN(offset) ? offset : 0,
        pageCount: !isNaN(pageCount) && pageCount > 0 ? Math.floor(pageCount) : Math.max(1, this.currentPageCount),
        pageExtent: !isNaN(pageExtent) ? Math.max(0, pageExtent) : this.lastPaginationPageExtent,
        maxOffset: !isNaN(maxOffset) ? Math.max(0, maxOffset) : this.lastPaginationMaxOffset,
        requestedOffset: !isNaN(requestedOffset) ? Math.max(0, requestedOffset) : -1,
        physicalOffset: !isNaN(physicalOffset) ? Math.max(0, physicalOffset) : -1,
        usedVirtualOffset: parsed.usedVirtualOffset === true
      };
    } catch (_error) {
      return {
        pageIndex: fallbackPage,
        offset: 0,
        pageCount: Math.max(1, this.currentPageCount),
        pageExtent: this.lastPaginationPageExtent,
        maxOffset: this.lastPaginationMaxOffset,
        requestedOffset: -1,
        physicalOffset: -1,
        usedVirtualOffset: false
      };
    }
  }

  private parseEpubPaginationSnapshot(raw: string): EpubPaginationSnapshot | null {
    if (raw.length <= 0) {
      return null;
    }
    try {
      const clean = this.parseWebViewJson(raw);
      const parsed = SafeUtils.parseObj(clean) as EpubPaginationSnapshot;
      const pageCount = Number(parsed.pageCount);
      const currentPage = Number(parsed.currentPage);
      const currentOffset = Number(parsed.currentOffset);
      const pageExtent = Number(parsed.pageExtent);
      const maxOffset = Number(parsed.maxOffset);
      const contentExtent = Number(parsed.contentExtent);
      return {
        pageCount: !isNaN(pageCount) && pageCount > 0 ? Math.floor(pageCount) : Math.max(1, this.currentPageCount),
        currentPage: !isNaN(currentPage) ? Math.floor(currentPage) : this.currentPage,
        currentOffset: !isNaN(currentOffset) ? Math.max(0, currentOffset) : this.lastPaginationOffset,
        pageExtent: !isNaN(pageExtent) ? Math.max(0, pageExtent) : this.lastPaginationPageExtent,
        maxOffset: !isNaN(maxOffset) ? Math.max(0, maxOffset) : this.lastPaginationMaxOffset,
        contentExtent: !isNaN(contentExtent) ? Math.max(0, contentExtent) : 0,
        rootTagName: parsed.rootTagName ? String(parsed.rootTagName) : ''
      };
    } catch (_error) {
      return null;
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
    if (notifyReady || source.indexOf('scheduled:') < 0) {
      this.ready = false;
    }
    this.viewportBackgroundColor = textSettings.backgroundColor ?? DEFAULT_EBOOK_READING_SETTINGS.backgroundColor;
    const preferImageLike = this.isCurrentSpineImageLike();
    const css = this.params.isFixedLayout
      ? this.buildFixedCss(vpW, vpH, textSettings)
      : this.buildReflowCss(vpW, vpH, textSettings, pageSettings);
    const escapedCss = this.escapeJsTemplate(css);
    const layoutKind = this.params.isFixedLayout
      ? 'horizontal_paged'
      : this.getLayoutKind(pageSettings, vpW, vpH);
    this.currentLayoutKind = layoutKind;
    const bridge = this.buildBridgeJs(layoutKind);
    const annotationBridge = this.buildAnnotationBridgeJs();
    logger.info(
      TAG,
      `应用排版注入: source=${source}, notifyReady=${notifyReady}, fixed=${this.params.isFixedLayout}, pageOffset=${pageOffset}, vp=${vpW}x${vpH}, scale=${this.getViewportScale(vpW, vpH)}, safeTop=${this.params.contentSafeTopInset ?? 0}vp/${EpubCssBuilder.getContentSafeTopInsetCssPx(vpW, vpH, { hostWidthVp: this.hostWidthVp, hostHeightVp: this.hostHeightVp, fallbackVpW: this.fallbackVpW, fallbackVpH: this.fallbackVpH, lastVisualVpW: this.lastVisualVpW, lastVisualVpH: this.lastVisualVpH, contentSafeTopInset: this.params.contentSafeTopInset ?? 0, isFixedLayout: this.params.isFixedLayout, isCurrentSpineImageLike: false })}px, hint=${preferImageLike ? 'image_like' : 'text_like'}, layoutHint=${this.getCurrentSpineLayoutType() || 'n/a'}, mediaHint=${this.getCurrentSpineMediaType() || 'n/a'}, text(${this.describeTextSettings(textSettings)}), page(${this.describePageSettings(pageSettings)})`
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
        window.__mnxEscapeHtml = function(text) {
          return String(text || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
        };
        window.__mnxNormalizeFootnoteId = function(value) {
          var text = String(value || '').trim();
          if (text.charAt(0) === '#') {
            text = text.substring(1);
          }
          try {
            text = decodeURIComponent(text);
          } catch (_decodeError) {
          }
          return text;
        };
        window.__mnxIsFootnoteElement = function(element) {
          if (!element || !element.getAttribute) {
            return false;
          }
          var role = (element.getAttribute('role') || '').toLowerCase();
          var epubType = (element.getAttribute('epub:type') || element.getAttribute('type') || '').toLowerCase();
          var className = (element.getAttribute('class') || '').toLowerCase();
          var idValue = (element.getAttribute('id') || element.getAttribute('name') || '').toLowerCase();
          if (role.indexOf('doc-footnote') >= 0 || role.indexOf('doc-endnote') >= 0) {
            return true;
          }
          if (epubType.indexOf('footnote') >= 0 || epubType.indexOf('endnote') >= 0 || epubType.indexOf('annotation') >= 0) {
            return true;
          }
          if (/(^|[\\s_\\-])(footnote|endnote|annotation|note-body|fn)([\\s_\\-]|$)/i.test(className)) {
            return true;
          }
          return /^(fn|footnote|endnote|note|annotation)[\\-_]?\\d+/i.test(idValue);
        };
        window.__mnxReadFootnoteText = function(element) {
          if (!element) {
            return '';
          }
          var clone = element.cloneNode ? element.cloneNode(true) : element;
          try {
            var backlinks = clone.querySelectorAll ? clone.querySelectorAll('a[href^="#"], .backlink, .reversefootnote') : [];
            for (var bi = 0; bi < backlinks.length; bi++) {
              var linkText = String(backlinks[bi].textContent || '').replace(/\\s+/g, '').trim();
              if (linkText.length <= 2 || /^(返回|back|↩|↑)$/i.test(linkText)) {
                backlinks[bi].remove();
              }
            }
          } catch (_linkError) {
          }
          return String(clone.innerText || clone.textContent || '').replace(/\\s+/g, ' ').trim();
        };
        window.__mnxNormalizeFootnoteDigits = function(text) {
          var source = String(text || '');
          var result = '';
          for (var di = 0; di < source.length; di++) {
            var code = source.charCodeAt(di);
            if (code >= 0xFF10 && code <= 0xFF19) {
              result += String(code - 0xFF10);
            } else {
              result += source.charAt(di);
            }
          }
          return result;
        };
        window.__mnxNormalizeFootnoteMarker = function(text) {
          var clean = window.__mnxNormalizeFootnoteDigits(String(text || '').replace(/\\s+/g, '').trim());
          if (!clean) {
            return '';
          }
          var circled = '①②③④⑤⑥⑦⑧⑨⑩';
          if (clean.length === 1 && circled.indexOf(clean) >= 0) {
            return String(circled.indexOf(clean) + 1);
          }
          var bracketMatch = clean.match(/^[\\[［【(（]?(\\d{1,3})[\\]］】)）]?[\\.．、:：)]?$/);
          if (bracketMatch && bracketMatch[1]) {
            return String(Number(bracketMatch[1]));
          }
          return '';
        };
        window.__mnxExtractLeadingFootnoteMarker = function(text) {
          var clean = window.__mnxNormalizeFootnoteDigits(String(text || '').replace(/\\s+/g, ' ').trim());
          if (!clean) {
            return '';
          }
          var circled = '①②③④⑤⑥⑦⑧⑨⑩';
          var firstChar = clean.charAt(0);
          if (circled.indexOf(firstChar) >= 0) {
            return String(circled.indexOf(firstChar) + 1);
          }
          var match = clean.match(/^[\\[［【(（]?\\s*(\\d{1,3})\\s*[\\]］】)）]?[\\.．、:：)]?/);
          if (match && match[1]) {
            return String(Number(match[1]));
          }
          var labeledMatch = clean.match(/^(?:注|注释|脚注|尾注|附注|note|footnote|endnote)\\s*([0-9]{1,3})\\s*[:：\\.．、)]?/i);
          if (labeledMatch && labeledMatch[1]) {
            return String(Number(labeledMatch[1]));
          }
          return '';
        };
        window.__mnxStripLeadingFootnoteMarker = function(text) {
          var clean = window.__mnxNormalizeFootnoteDigits(String(text || '').replace(/\\s+/g, ' ').trim());
          var circled = '①②③④⑤⑥⑦⑧⑨⑩';
          if (clean.length > 1 && circled.indexOf(clean.charAt(0)) >= 0) {
            return clean.substring(1).replace(/^[\\.．、:：)]\\s*/, '').trim();
          }
          return clean
            .replace(/^[\\[［【(（]?\\s*\\d{1,3}\\s*[\\]］】)）]?[\\.．、:：)]?\\s*/, '')
            .replace(/^(?:注|注释|脚注|尾注|附注|note|footnote|endnote)\\s*\\d{1,3}\\s*[:：\\.．、)]?\\s*/i, '')
            .trim();
        };
        window.__mnxIsFootnoteSectionHeading = function(text) {
          var clean = String(text || '').replace(/\\s+/g, '').trim();
          return /^(注|注释|脚注|尾注|附注|说明|备注|参考注|译注|译者注|编者注|校注|Notes?|Footnotes?|Endnotes?|Annotations?|Translator'?sNotes?|Editor'?sNotes?)[:：]?$/.test(clean);
        };
        window.__mnxIsFootnoteAttributionText = function(text) {
          var clean = String(text || '').replace(/\\s+/g, ' ').trim();
          if (clean.length <= 0 || clean.length > 720) {
            return false;
          }
          return /(译者注|译注|编者注|编注|校注|作者注|原注|按语|附注|訳者注|訳注|編者注|역주|번역자\\s*주|편집자\\s*주|주석|translator['’]?s?\\s+note|trans\\.?\\s+note|editor['’]?s?\\s+note|author['’]?s?\\s+note|note\\s+du\\s+traducteur|note\\s+de\\s+l['’]éditeur|nota\\s+del\\s+traductor|nota\\s+de\\s+la\\s+traductora|nota\\s+del\\s+editor|nota\\s+do\\s+tradutor|nota\\s+da\\s+tradutora|nota\\s+del\\s+traduttore|anmerkung\\s+des\\s+übersetzers|anm\\.?\\s*d\\.?\\s*übers|прим(?:ечание)?\\.?\\s*(?:пер|ред|переводчика|редактора))/i.test(clean);
        };
        window.__mnxBuildFootnoteMarkerAliases = function(marker) {
          var clean = window.__mnxNormalizeFootnoteMarker(marker);
          var aliases = [];
          if (clean.length <= 0) {
            return aliases;
          }
          aliases.push(clean);
          aliases.push('[' + clean + ']');
          aliases.push('［' + clean + '］');
          aliases.push('(' + clean + ')');
          aliases.push('（' + clean + '）');
          aliases.push(clean + '.');
          aliases.push(clean + '．');
          aliases.push(clean + '、');
          var number = Number(clean);
          if (number >= 1 && number <= 10) {
            aliases.push('①②③④⑤⑥⑦⑧⑨⑩'.charAt(number - 1));
          }
          return aliases;
        };
        window.__mnxElementTextHasFootnoteMarker = function(element, marker) {
          if (!element || !marker) {
            return false;
          }
          var text = String(element.innerText || element.textContent || '').replace(/\\s+/g, '').trim();
          if (text.length <= 0) {
            return false;
          }
          var tail = text.substring(Math.max(0, text.length - 18));
          var aliases = window.__mnxBuildFootnoteMarkerAliases(marker);
          for (var ai = 0; ai < aliases.length; ai++) {
            if (aliases[ai] === String(marker) && tail.lastIndexOf(aliases[ai]) !== tail.length - aliases[ai].length) {
              continue;
            }
            if (tail.indexOf(aliases[ai]) >= 0) {
              return true;
            }
          }
          return false;
        };
        window.__mnxFindFootnoteAnchor = function(blocks, currentIndex, candidates) {
          for (var ai = currentIndex - 1; ai >= 0; ai--) {
            var element = blocks[ai];
            if (!element || !element.getAttribute) {
              continue;
            }
            if (element.closest && element.closest('[data-mnx-ignore-pagination="true"]')) {
              continue;
            }
            var isCandidate = false;
            for (var ci = 0; ci < candidates.length; ci++) {
              if (candidates[ci].element === element) {
                isCandidate = true;
                break;
              }
            }
            if (isCandidate) {
              continue;
            }
            var tagName = String(element.tagName || '').toLowerCase();
            var text = String(element.innerText || element.textContent || '').replace(/\\s+/g, ' ').trim();
            if (text.length <= 0 || window.__mnxIsFootnoteSectionHeading(text)) {
              continue;
            }
            if (/^h[1-6]$/.test(tagName) && text.length <= 80) {
              continue;
            }
            return element;
          }
          return null;
        };
        window.__mnxAttachFootnoteRef = function(anchorElement, note) {
          if (!anchorElement || !note || !document.createElement) {
            return null;
          }
          if (anchorElement.querySelectorAll) {
            var existingRefs = anchorElement.querySelectorAll('.mnx-footnote-ref[data-mnx-footnote-id]');
            for (var eri = 0; eri < existingRefs.length; eri++) {
              if ((existingRefs[eri].getAttribute('data-mnx-footnote-id') || '') === note.id) {
                return existingRefs[eri];
              }
            }
          }
          var refElement = document.createElement('sup');
          var marker = '[' + note.number + ']';
          refElement.textContent = marker;
          refElement.classList.add('mnx-footnote-ref');
          refElement.setAttribute('data-mnx-footnote-id', note.id);
          refElement.setAttribute('data-mnx-footnote-number', String(note.number));
          refElement.setAttribute('data-mnx-footnote-marker', marker);
          refElement.setAttribute('data-mnx-has-visible-marker', 'true');
          refElement.setAttribute('data-mnx-auto-footnote-ref', 'true');
          anchorElement.appendChild(refElement);
          return refElement;
        };
        window.__mnxEnsureFootnoteLayer = function() {
          var layer = document.getElementById('__mnx_footnote_layer');
          if (!layer && document.body) {
            layer = document.createElement('div');
            layer.id = '__mnx_footnote_layer';
            layer.setAttribute('data-mnx-ignore-pagination', 'true');
            layer.setAttribute('data-mnx-visible', 'false');
            document.body.appendChild(layer);
          }
          return layer;
        };
        window.__mnxPrepareFootnotes = function() {
          if (!document.body || !document.querySelectorAll) {
            return;
          }
          var existingLayer = document.getElementById('__mnx_footnote_layer');
          if (existingLayer) {
            existingLayer.innerHTML = '';
            existingLayer.setAttribute('data-mnx-visible', 'false');
          }
          var notes = {};
          var notesByMarker = {};
          var noteElements = document.querySelectorAll('aside, section, div, li, p');
          for (var ni = 0; ni < noteElements.length; ni++) {
            var noteElement = noteElements[ni];
            if (!window.__mnxIsFootnoteElement(noteElement)) {
              continue;
            }
            var noteId = noteElement.getAttribute('id') || noteElement.getAttribute('name') || '';
            noteId = window.__mnxNormalizeFootnoteId(noteId);
            if (noteId.length <= 0) {
              noteId = 'mnx_auto_note_' + ni;
              noteElement.setAttribute('id', noteId);
            }
            var noteText = window.__mnxReadFootnoteText(noteElement);
            if (noteText.length > 0) {
              notes[noteId] = {
                id: noteId,
                text: noteText,
                element: noteElement,
                number: 0,
                referenced: false
              };
              var explicitMarker = window.__mnxExtractLeadingFootnoteMarker(noteText);
              if (explicitMarker.length > 0) {
                notes[noteId].number = Number(explicitMarker) || 0;
                if (!notesByMarker[explicitMarker]) {
                  notesByMarker[explicitMarker] = notes[noteId];
                }
              }
            }
          }
          var implicitBlocks = document.querySelectorAll('h1, h2, h3, h4, h5, h6, p, li, div');
          var implicitCandidates = [];
          var afterNoteHeading = false;
          for (var ii = 0; ii < implicitBlocks.length; ii++) {
            var implicitElement = implicitBlocks[ii];
            if (!implicitElement || !implicitElement.getAttribute) {
              continue;
            }
            if (implicitElement.closest && implicitElement.closest('[data-mnx-ignore-pagination="true"]')) {
              continue;
            }
            var implicitText = String(implicitElement.innerText || implicitElement.textContent || '').replace(/\\s+/g, ' ').trim();
            if (implicitText.length <= 0) {
              continue;
            }
            if (window.__mnxIsFootnoteSectionHeading(implicitText)) {
              afterNoteHeading = true;
              continue;
            }
            var implicitMarker = window.__mnxExtractLeadingFootnoteMarker(implicitText);
            var implicitAttributionHint = window.__mnxIsFootnoteAttributionText(implicitText);
            if (implicitMarker.length <= 0 && !implicitAttributionHint) {
              if (/^(h1|h2|h3)$/i.test(implicitElement.tagName || '')) {
                afterNoteHeading = false;
              }
              continue;
            }
            var implicitBody = implicitMarker.length > 0
              ? window.__mnxStripLeadingFootnoteMarker(implicitText)
              : implicitText;
            if (implicitBody.length <= 1 || implicitBody.length > 720) {
              continue;
            }
            var implicitAttrs = (
              (implicitElement.getAttribute('id') || '') + ' ' +
              (implicitElement.getAttribute('name') || '') + ' ' +
              (implicitElement.getAttribute('class') || '')
            ).toLowerCase();
            var implicitAttrHint = /(footnote|endnote|annotation|note|fn)/i.test(implicitAttrs);
            if (/^(h1|h2|h3)$/i.test(implicitElement.tagName || '') &&
              !afterNoteHeading &&
              !implicitAttrHint &&
              !implicitAttributionHint) {
              continue;
            }
            implicitCandidates.push({
              marker: implicitMarker,
              text: implicitBody,
              element: implicitElement,
              order: ii,
              eligible: afterNoteHeading || implicitAttrHint || implicitAttributionHint,
              sequenceEligible: false,
              anchorElement: null
            });
          }
          var sequenceStart = 0;
          while (sequenceStart < implicitCandidates.length) {
            var sequenceEnd = sequenceStart;
            var previousMarkerNumber = Number(implicitCandidates[sequenceStart].marker || '0');
            while (sequenceEnd + 1 < implicitCandidates.length) {
              var nextMarkerNumber = Number(implicitCandidates[sequenceEnd + 1].marker || '0');
              var currentOrder = implicitCandidates[sequenceEnd].order;
              var nextOrder = implicitCandidates[sequenceEnd + 1].order;
              if (previousMarkerNumber > 0 &&
                nextMarkerNumber === previousMarkerNumber + 1 &&
                nextOrder - currentOrder <= 3) {
                sequenceEnd++;
                previousMarkerNumber = nextMarkerNumber;
              } else {
                break;
              }
            }
            if (sequenceEnd > sequenceStart) {
              for (var si = sequenceStart; si <= sequenceEnd; si++) {
                implicitCandidates[si].sequenceEligible = true;
              }
            }
            sequenceStart = sequenceEnd + 1;
          }
          for (var ac = 0; ac < implicitCandidates.length; ac++) {
            var anchorCandidate = implicitCandidates[ac];
            anchorCandidate.anchorElement = window.__mnxFindFootnoteAnchor(implicitBlocks, anchorCandidate.order, implicitCandidates);
            if (anchorCandidate.marker.length > 0 &&
              window.__mnxElementTextHasFootnoteMarker(anchorCandidate.anchorElement, anchorCandidate.marker)) {
              anchorCandidate.eligible = true;
            }
          }
          var tailThreshold = Math.max(0, implicitBlocks.length - Math.max(8, Math.floor(implicitBlocks.length * 0.25)));
          var tailCandidateCount = 0;
          for (var tc = 0; tc < implicitCandidates.length; tc++) {
            if (implicitCandidates[tc].order >= tailThreshold) {
              tailCandidateCount++;
            }
          }
          for (var ic = 0; ic < implicitCandidates.length; ic++) {
            var implicitCandidate = implicitCandidates[ic];
            var tailEligible = tailCandidateCount >= 2 && implicitCandidate.order >= tailThreshold;
            if (!implicitCandidate.eligible && !tailEligible && !implicitCandidate.sequenceEligible) {
              continue;
            }
            if (implicitCandidate.marker.length > 0 && notesByMarker[implicitCandidate.marker]) {
              continue;
            }
            var implicitNoteId = implicitCandidate.marker.length > 0
              ? 'mnx_implicit_note_' + implicitCandidate.marker + '_' + implicitCandidate.order
              : 'mnx_implicit_note_auto_' + implicitCandidate.order;
            notes[implicitNoteId] = {
              id: implicitNoteId,
              text: implicitCandidate.text,
              element: implicitCandidate.element,
              number: Number(implicitCandidate.marker) || 0,
              referenced: false,
              autoAnchorElement: implicitCandidate.anchorElement
            };
            if (implicitCandidate.marker.length > 0) {
              notesByMarker[implicitCandidate.marker] = notes[implicitNoteId];
            }
          }
          var refElements = document.querySelectorAll('a[href^="#"], [role="doc-noteref"], sup a, sup');
          var nextNumber = 1;
          for (var ri = 0; ri < refElements.length; ri++) {
            var refElement = refElements[ri];
            var href = refElement.getAttribute ? (refElement.getAttribute('href') || '') : '';
            var refType = refElement.getAttribute ? ((refElement.getAttribute('epub:type') || refElement.getAttribute('type') || refElement.getAttribute('role') || '').toLowerCase()) : '';
            var targetId = window.__mnxNormalizeFootnoteId(href);
            var note = targetId.length > 0 ? notes[targetId] : null;
            var visibleText = String(refElement.innerText || refElement.textContent || '').replace(/\\s+/g, '').trim();
            var visibleMarker = window.__mnxNormalizeFootnoteMarker(visibleText);
            if (!note && visibleMarker.length > 0 && notesByMarker[visibleMarker]) {
              note = notesByMarker[visibleMarker];
            }
            if (!note && refType.indexOf('noteref') < 0) {
              continue;
            }
            if (!note && targetId.length > 0) {
              var target = document.getElementById(targetId);
              if (target && window.__mnxIsFootnoteElement(target)) {
                var targetText = window.__mnxReadFootnoteText(target);
                if (targetText.length > 0) {
                  note = {
                    id: targetId,
                    text: targetText,
                    element: target,
                    number: 0,
                    referenced: false
                  };
                  notes[targetId] = note;
                }
              }
            }
            if (!note) {
              continue;
            }
            if (note.number <= 0) {
              note.number = nextNumber;
              nextNumber++;
            } else if (note.number >= nextNumber) {
              nextNumber = note.number + 1;
            }
            note.referenced = true;
            if (note.element && note.element.classList) {
              note.element.classList.add('mnx-footnote-body-hidden');
            }
            var marker = '[' + note.number + ']';
            refElement.classList.add('mnx-footnote-ref');
            refElement.setAttribute('data-mnx-footnote-id', note.id);
            refElement.setAttribute('data-mnx-footnote-number', String(note.number));
            refElement.setAttribute('data-mnx-footnote-marker', marker);
            refElement.setAttribute('data-mnx-has-visible-marker', visibleText.length > 0 && visibleText.length <= 4 ? 'true' : 'false');
            if (visibleText.length <= 0) {
              refElement.textContent = marker;
              refElement.setAttribute('data-mnx-has-visible-marker', 'true');
            }
          }
          var autoNoteKeys = Object.keys(notes);
          for (var aki = 0; aki < autoNoteKeys.length; aki++) {
            var autoNote = notes[autoNoteKeys[aki]];
            if (!autoNote || autoNote.referenced || !autoNote.autoAnchorElement) {
              continue;
            }
            if (autoNote.number <= 0) {
              autoNote.number = nextNumber;
              nextNumber++;
            } else if (autoNote.number >= nextNumber) {
              nextNumber = autoNote.number + 1;
            }
            var attachedRef = window.__mnxAttachFootnoteRef(autoNote.autoAnchorElement, autoNote);
            if (!attachedRef) {
              continue;
            }
            autoNote.referenced = true;
            if (autoNote.element && autoNote.element.classList) {
              autoNote.element.classList.add('mnx-footnote-body-hidden');
            }
          }
          var activeNotes = {};
          var noteKeys = Object.keys(notes);
          for (var ki = 0; ki < noteKeys.length; ki++) {
            var key = noteKeys[ki];
            if (notes[key].referenced) {
              activeNotes[key] = notes[key];
            }
          }
          window.__mnxFootnotes = activeNotes;
          window.__mnxEnsureFootnoteLayer();
        };
        window.__mnxUpdateFootnoteLayer = function() {
          var layer = window.__mnxEnsureFootnoteLayer ? window.__mnxEnsureFootnoteLayer() : null;
          if (!layer || !document.querySelectorAll) {
            return;
          }
          var notes = window.__mnxFootnotes || {};
          var refs = document.querySelectorAll('.mnx-footnote-ref[data-mnx-footnote-id]');
          var viewport = window.__mnxGetViewportExtent ? window.__mnxGetViewportExtent() : {
            width: window.innerWidth || 0,
            height: window.innerHeight || 0
          };
          var visibleRows = [];
          var seen = {};
          for (var ri = 0; ri < refs.length; ri++) {
            var ref = refs[ri];
            var noteId = ref.getAttribute('data-mnx-footnote-id') || '';
            var note = notes[noteId];
            if (!note || seen[noteId]) {
              continue;
            }
            var rects = ref.getClientRects ? ref.getClientRects() : [];
            var visible = false;
            for (var r = 0; r < rects.length; r++) {
              var rect = rects[r];
              if (rect.right >= 0 && rect.left <= viewport.width && rect.bottom >= 0 && rect.top <= viewport.height) {
                visible = true;
                break;
              }
            }
            if (!visible) {
              continue;
            }
            seen[noteId] = true;
            visibleRows.push({
              number: note.number || Number(ref.getAttribute('data-mnx-footnote-number') || '0') || visibleRows.length + 1,
              text: note.text || ''
            });
          }
          if (visibleRows.length <= 0) {
            layer.innerHTML = '';
            layer.setAttribute('data-mnx-visible', 'false');
            return;
          }
          var html = '';
          for (var vi = 0; vi < visibleRows.length; vi++) {
            html += '<div class="mnx-footnote-row"><span class="mnx-footnote-num">[' +
              window.__mnxEscapeHtml(String(visibleRows[vi].number)) +
              ']</span><span class="mnx-footnote-text">' +
              window.__mnxEscapeHtml(visibleRows[vi].text) +
              '</span></div>';
          }
          layer.innerHTML = html;
          layer.setAttribute('data-mnx-visible', 'true');
        };
        window.__mnxHasAdjacentText = function(node) {
          var prev = node ? node.previousSibling : null;
          while (prev) {
            if (prev.nodeType === 3 && String(prev.textContent || '').replace(/\\s+/g, '').length > 0) {
              return true;
            }
            if (prev.nodeType === 1) {
              var prevText = String(prev.textContent || '').replace(/\\s+/g, '').trim();
              if (prevText.length > 0) {
                return true;
              }
            }
            prev = prev.previousSibling;
          }
          var next = node ? node.nextSibling : null;
          while (next) {
            if (next.nodeType === 3 && String(next.textContent || '').replace(/\\s+/g, '').length > 0) {
              return true;
            }
            if (next.nodeType === 1) {
              var nextText = String(next.textContent || '').replace(/\\s+/g, '').trim();
              if (nextText.length > 0) {
                return true;
              }
            }
            next = next.nextSibling;
          }
          return false;
        };
        window.__mnxReadMediaDimension = function(element) {
          var tag = element && element.tagName ? element.tagName.toUpperCase() : '';
          var attrWidth = element ? parseFloat(element.getAttribute('width') || '0') : 0;
          var attrHeight = element ? parseFloat(element.getAttribute('height') || '0') : 0;
          var width = !isNaN(attrWidth) && attrWidth > 0 ? attrWidth : 0;
          var height = !isNaN(attrHeight) && attrHeight > 0 ? attrHeight : 0;
          if (tag === 'IMG') {
            width = width || element.clientWidth || element.width || element.naturalWidth || 0;
            height = height || element.clientHeight || element.height || element.naturalHeight || 0;
          } else if (tag === 'SVG') {
            var viewBox = element.getAttribute('viewBox') || '';
            var parts = viewBox.trim().split(/\\s+/);
            if (parts.length === 4) {
              var vbWidth = parseFloat(parts[2]);
              var vbHeight = parseFloat(parts[3]);
              width = width || (!isNaN(vbWidth) ? vbWidth : 0);
              height = height || (!isNaN(vbHeight) ? vbHeight : 0);
            }
            width = width || element.clientWidth || 0;
            height = height || element.clientHeight || 0;
          } else if (tag === 'VIDEO') {
            width = width || element.videoWidth || element.clientWidth || 0;
            height = height || element.videoHeight || element.clientHeight || 0;
          } else if (tag === 'CANVAS') {
            width = width || element.width || element.clientWidth || 0;
            height = height || element.height || element.clientHeight || 0;
          }
          return {
            width: Math.max(0, width),
            height: Math.max(0, height)
          };
        };
        window.__mnxPrepareMediaRoles = function() {
          var body = document.body;
          var stats = { mediaCount: 0, inlineCount: 0, blockCount: 0 };
          if (!body || !body.querySelectorAll) {
            return stats;
          }
          var mediaNodes = body.querySelectorAll('img, svg, video, canvas');
          var inlineTags = ',A,SPAN,EM,STRONG,B,I,U,S,SUP,SUB,SMALL,RUBY,RT,RP,LABEL,';
          for (var mi = 0; mi < mediaNodes.length; mi++) {
            var mediaElement = mediaNodes[mi];
            var tagName = mediaElement.tagName ? mediaElement.tagName.toUpperCase() : '';
            var parent = mediaElement.parentElement;
            var parentTag = parent && parent.tagName ? parent.tagName.toUpperCase() : '';
            var parentText = parent ? String(parent.innerText || parent.textContent || '').replace(/\\s+/g, ' ').trim() : '';
            var childCount = parent && parent.children ? parent.children.length : 0;
            var mediaOnlyParent = childCount <= 1 && parentText.length <= 12;
            var adjacentText = window.__mnxHasAdjacentText(mediaElement);
            var display = '';
            try {
              display = window.getComputedStyle(mediaElement).display || '';
            } catch (_displayError) {
              display = '';
            }
            var dimension = window.__mnxReadMediaDimension(mediaElement);
            var maxDim = Math.max(dimension.width, dimension.height);
            var smallMedia = (maxDim > 0 && maxDim <= 128) ||
              (dimension.height > 0 && dimension.height <= 64) ||
              (dimension.width > 0 && dimension.width <= 96 && dimension.height > 0 && dimension.height <= 96);
            var src = '';
            if (tagName === 'IMG') {
              src = mediaElement.getAttribute('src') || '';
            }
            var decodedSrc = src;
            try {
              decodedSrc = decodeURIComponent(src);
            } catch (_srcError) {
              decodedSrc = src;
            }
            var filenameHint = /(note|mark|icon|symbol|inline|footnote|annotation|zhu|sup|sub|注|标记|标注|脚注|角标)/i.test(decodedSrc);
            var textHint = /(注|标记|标注|脚注|角标|note|mark|footnote|annotation)/i.test(parentText);
            var markerMedia = filenameHint || textHint;
            var inlineParent = inlineTags.indexOf(',' + parentTag + ',') >= 0;
            var originalInline = display === 'inline' || display === 'inline-block';
            var unknownSize = maxDim <= 0;
            var hasTextContext = adjacentText || inlineParent || (!mediaOnlyParent && parentText.length > 0);
            var inlineRole = (hasTextContext && (smallMedia || filenameHint || (originalInline && (unknownSize || maxDim <= 192)))) ||
              (markerMedia && (smallMedia || unknownSize || maxDim <= 192)) ||
              (smallMedia && mediaOnlyParent && parentTag !== 'FIGURE');
            var role = inlineRole ? 'inline' : 'block';
            mediaElement.setAttribute('data-mnx-media-role', role);
            if (parentTag === 'PICTURE') {
              parent.setAttribute('data-mnx-media-role', role);
            }
            var figure = parent;
            while (figure && figure !== body) {
              var figureTag = figure.tagName ? figure.tagName.toUpperCase() : '';
              if (figureTag === 'FIGURE') {
                figure.setAttribute('data-mnx-media-role', role === 'inline' ? 'inline' : 'block');
                break;
              }
              figure = figure.parentElement;
            }
            if (tagName === 'IMG' && mediaElement.getAttribute('data-mnx-role-listener') !== 'true') {
              mediaElement.setAttribute('data-mnx-role-listener', 'true');
              mediaElement.addEventListener('load', function() {
                window.__mnxPrepareMediaRoles();
                if (window.__mnxApplyContentKind) {
                  window.__mnxApplyContentKind();
                }
                if (window.__mnxUpdateFootnoteLayer) {
                  window.__mnxUpdateFootnoteLayer();
                }
                if (window.__mnxSchedulePaginationNotify) {
                  window.__mnxSchedulePaginationNotify('media_load');
                }
              });
            }
            stats.mediaCount++;
            if (role === 'inline') {
              stats.inlineCount++;
            } else {
              stats.blockCount++;
            }
          }
          return stats;
        };
        window.__mnxResolveContentKind = function() {
          var preferImageLike = ${preferImageLike ? 'true' : 'false'};
          var body = document.body;
          if (!body) {
            return preferImageLike ? 'image_like' : 'text_like';
          }
          var mediaStats = window.__mnxPrepareMediaRoles();
          var mediaCount = mediaStats.mediaCount || 0;
          var blockMediaCount = mediaStats.blockCount || 0;
          var textSource = body.innerText || body.textContent || '';
          var normalizedText = textSource.replace(/\\s+/g, ' ').trim();
          var textLength = normalizedText.length;
          if (preferImageLike && (blockMediaCount > 0 || (mediaCount > 0 && textLength <= 120 && blockMediaCount === mediaCount))) {
            return 'image_like';
          }
          if (mediaCount <= 0) {
            return 'text_like';
          }
          if (blockMediaCount <= 0) {
            return 'text_like';
          }
          if (textLength <= 80) {
            return 'image_like';
          }
          var childCount = body.children ? body.children.length : 0;
          var mediaContainerCount = 0;
          if (body.children) {
            for (var ci = 0; ci < body.children.length; ci++) {
              var child = body.children[ci];
              var childText = (child.innerText || child.textContent || '').replace(/\\s+/g, ' ').trim();
              var childHasMedia = !!(child.querySelector && child.querySelector('[data-mnx-media-role="block"]'));
              if (childHasMedia && childText.length <= 24) {
                mediaContainerCount++;
              }
            }
          }
          if (childCount > 0 && mediaContainerCount === childCount && textLength <= 160) {
            return 'image_like';
          }
          if (mediaCount === 1 && blockMediaCount === 1 && textLength <= 160) {
            return 'image_like';
          }
          return 'text_like';
        };
        window.__mnxApplyContentKind = function() {
          var resolvedKind = window.__mnxResolveContentKind ? window.__mnxResolveContentKind() : 'text_like';
          if (document.documentElement) {
            document.documentElement.setAttribute('data-mnx-content-kind', resolvedKind);
          }
          return resolvedKind;
        };
        window.__mnxPrepareFootnotes();
        var resolvedContentKind = window.__mnxApplyContentKind();
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
                           'width','max-width','column-width','column-gap','column-fill','column-count',
                           'transform','transform-origin'];
          for (var pi = 0; pi < blockProps.length; pi++) {
            document.body.style.removeProperty(blockProps[pi]);
          }
          document.body.style.removeProperty('font-size');
          document.body.style.removeProperty('-webkit-text-size-adjust');
          document.body.style.removeProperty('text-size-adjust');
          if (resolvedContentKind === 'image_like' && document.body.children) {
            for (var bi = 0; bi < document.body.children.length; bi++) {
              var bodyChild = document.body.children[bi];
              bodyChild.style.removeProperty('width');
              bodyChild.style.removeProperty('height');
              bodyChild.style.removeProperty('max-width');
              bodyChild.style.removeProperty('max-height');
            }
          }
          // Force synchronous reflow so column layout is computed before we measure
          void document.body.offsetWidth;
        }
        var mediaElements = document.querySelectorAll('img, svg, video, canvas');
        for (var mi = 0; mi < mediaElements.length; mi++) {
          var mediaElement = mediaElements[mi];
          mediaElement.style.removeProperty('width');
          mediaElement.style.removeProperty('height');
          mediaElement.style.removeProperty('max-width');
          mediaElement.style.removeProperty('max-height');
        }
        resolvedContentKind = window.__mnxApplyContentKind();
        if (document.documentElement) {
          document.documentElement.style.removeProperty('font-size');
          document.documentElement.style.removeProperty('-webkit-text-size-adjust');
          document.documentElement.style.removeProperty('text-size-adjust');
        }
        ${bridge}
        ${annotationBridge}
        window.__mnxInstallArkBridge();
        window.__mnxUpdateFootnoteLayer();
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
              contentExtent: paginationState.contentExtent || 0,
              inlineMediaCount: document.querySelectorAll ? document.querySelectorAll('[data-mnx-media-role="inline"]').length : 0,
              blockMediaCount: document.querySelectorAll ? document.querySelectorAll('[data-mnx-media-role="block"]').length : 0,
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
              bodyTransform: document.body ? (document.body.style.transform || '') : '',
              bodyVirtualOffsetAttr: document.body ? (document.body.getAttribute('data-mnx-virtual-offset') || '') : '',
              bodyTextLength: document.body ? String(document.body.innerText || document.body.textContent || '').replace(/\\s+/g, '').length : 0,
              bodyChildCount: document.body && document.body.children ? document.body.children.length : 0,
              bodyHtmlLength: document.body ? String(document.body.innerHTML || '').length : 0,
              documentUrl: document.location ? (document.location.href || '') : '',
              styleTagParent: (function() {
                var styleTag = document.getElementById('__mnx_epub_style');
                return styleTag && styleTag.parentElement ? styleTag.parentElement.tagName : '';
              })(),
              isStyleTagLastChild: (function() {
                var styleTag = document.getElementById('__mnx_epub_style');
                return !!(styleTag && styleTag.parentElement && styleTag.parentElement.lastElementChild === styleTag);
              })(),
              rootTagName: paginationState.rootTagName || '',
              contentKind: document.documentElement ? (document.documentElement.getAttribute('data-mnx-content-kind') || '') : '',
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
              const metrics = SafeUtils.parseObj(cleanMetrics) as PaginationMetrics;
              const parsedCount = Math.floor(Number(metrics.pageCount));
              if (!isNaN(parsedCount) && parsedCount > 0) {
                pageCount = parsedCount;
              }
              logger.debug(
                TAG,
                `Pagination metrics: source=${source}, kind=${metrics.contentKind}, media(inline=${metrics.inlineMediaCount}, block=${metrics.blockMediaCount}), inner=${metrics.innerWidth}x${metrics.innerHeight}, visual=${metrics.visualViewportWidth}x${metrics.visualViewportHeight}@${metrics.visualViewportScale}, scroll=${metrics.scrollWidth}x${metrics.scrollHeight}, root=${metrics.rootTagName}, offset=${metrics.currentOffset}/${metrics.maxOffset}, extent=${metrics.pageExtent}, contentExtent=${metrics.contentExtent}, pages=${pageCount}, current=${metrics.currentPage}, bodyText=${metrics.bodyTextLength}, bodyChildren=${metrics.bodyChildCount}, bodyHtml=${metrics.bodyHtmlLength}, bodyTransform=${metrics.bodyTransform || 'none'}, virtual=${metrics.bodyVirtualOffsetAttr || 'none'}, rootFont=${metrics.rootFontSize}, bodyFont=${metrics.bodyFontSize}/${metrics.bodyLineHeight}, sample=${metrics.sampleTagName}:${metrics.sampleFontSize}/${metrics.sampleLineHeight}, align=${metrics.sampleTextAlign}, styleParent=${metrics.styleTagParent}, styleLast=${metrics.isStyleTagLastChild}, doc=${metrics.documentUrl || 'none'}`
              );
              if (this.shouldIgnoreInitialBlankProbe(metrics, source, notifyReady)) {
                return;
              }
              if (this.handleRuntimeBlankSpine(metrics, source, notifyReady)) {
                return;
              }
            } catch (error) {
              const fallbackCount = parseInt(this.parseWebViewJson(metricsRaw), 10);
              if (!isNaN(fallbackCount) && fallbackCount > 0) {
                pageCount = fallbackCount;
              } else {
                logger.warn(TAG, `Pagination metrics parse failed, fallback to single page: ${String(error)}`);
              }
            }

            this.currentPageCount = pageCount;
            const initialAnchorFragment = this.pendingAnchorFragment;
            const targetPage = anchorRatio >= 0 && this.currentPageCount > 1
              ? Math.max(
                  0,
                  Math.min(
                    Math.round(anchorRatio * Math.max(0, this.currentPageCount - 1)),
                    this.currentPageCount - 1
                  )
                )
              : Math.max(0, Math.min(pageOffset, this.currentPageCount - 1));
            let resolvedTargetPage = targetPage;
            let finished = false;
            const finalize = () => {
              if (finished) {
                return;
              }
              finished = true;
              this.pendingAnchorFragment = '';
              this.completeReaderReady(layoutKind, resolvedTargetPage, this.currentPageCount, notifyReady);
            };
            const fallbackTimer = setTimeout(() => {
              finalize();
            }, 60);
            const pageCommand = initialAnchorFragment.length > 0
              ? `window.__mnxGoToFragmentImmediate('${this.escapeJsSingleQuoted(initialAnchorFragment)}');`
              : `window.__mnxGoToPageImmediate(${targetPage});`;
            this.runJs(pageCommand, (resultRaw: string) => {
              const result = this.parsePageCommandResult(resultRaw, targetPage);
              this.currentPage = result.pageIndex;
              resolvedTargetPage = result.pageIndex;
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
              if (initialAnchorFragment.length > 0) {
                logger.info(
                  TAG,
                  `初始锚点定位完成: fragment=${initialAnchorFragment}, page=${this.currentPage}/${this.currentPageCount}`
                );
              }
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
        const dimension = SafeUtils.parseObj(clean) as FixedLayoutDimension;
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
      this.applyHighlightRangesToWeb('page_commit');
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
      logger.debug(
        TAG,
        `页内翻页完成: target=${targetPage}, resolved=${resolvedPage}/${resolvedPageCount}, offset=${result.offset}/${result.maxOffset}, requested=${result.requestedOffset}, physical=${result.physicalOffset}, virtual=${result.usedVirtualOffset}`
      );
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

  private goToAnchorImmediate(anchorFragment: string): boolean {
    if (!this.ready || this.isPageTurnAnimating) {
      return false;
    }
    const normalizedFragment = this.normalizeAnchorFragment(anchorFragment);
    if (normalizedFragment.length <= 0) {
      return false;
    }
    let finished = false;
    let resolvedPage = this.currentPage;
    let resolvedPageCount = Math.max(1, this.currentPageCount);
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
      this.applyHighlightRangesToWeb('anchor_commit');
    };
    const fallbackTimer = setTimeout(() => {
      finalize();
    }, 60);
    this.runJs(
      `window.__mnxGoToFragmentImmediate('${this.escapeJsSingleQuoted(normalizedFragment)}');`,
      (resultRaw: string) => {
        const result = this.parsePageCommandResult(resultRaw, this.currentPage);
        resolvedPage = result.pageIndex;
        resolvedPageCount = result.pageCount;
        this.lastPaginationOffset = result.offset;
        this.lastPaginationPageExtent = result.pageExtent;
        this.lastPaginationMaxOffset = result.maxOffset;
        logger.info(
          TAG,
          `锚点跳转完成: fragment=${normalizedFragment}, page=${resolvedPage}/${resolvedPageCount}`
        );
        clearTimeout(fallbackTimer);
        finalize();
      }
    );
    return true;
  }

  private finishPageTurnAnimation(): void {
    this.clearDeferredWork();
    this.isPageTurnAnimating = false;
    this.setWebViewHiddenForEpubCurl(false, 'finish_animation');
    this.resetViewportTransform();
  }

  private scheduleWebViewPaintStabilization(reason: string): void {
    this.clearPaintStabilizeTimer();
    const targetPage = Math.max(0, this.currentPage);
    this.paintStabilizeTimer = setTimeout(() => {
      this.paintStabilizeTimer = -1;
      if (!this.uiContext || !this.ready || this.isPageTurnAnimating) {
        return;
      }
      this.runJs(
        `(function() {
          var page = ${targetPage};
          if (window.__mnxGoToPageImmediate) {
            window.__mnxGoToPageImmediate(page);
          }
          if (document.documentElement) {
            document.documentElement.style.setProperty('--mnx-paint-token', String(Date.now()));
            void document.documentElement.offsetHeight;
          }
          if (document.body) {
            void document.body.offsetHeight;
          }
          return 'ok';
        })();`,
        (_result: string) => {
          this.applyHighlightRangesToWeb('paint_stabilized');
          this.viewportOpacity = 0.995;
          setTimeout(() => {
            if (this.uiContext && this.ready && !this.isPageTurnAnimating) {
              this.viewportOpacity = 1;
            }
          }, 48);
          logger.debug(TAG, `WebView 首屏稳帧完成: reason=${reason}, page=${targetPage}`);
        }
      );
    }, 160);
  }

  private loadSpineItemImmediate(
    spineFilePath: string,
    pageOffset: number,
    anchorFragment: string = '',
    spineLayoutType?: string,
    spineMediaType?: string
  ): void {
    this.clearDeferredWork();
    this.configureUniversalAccessRoot(spineFilePath, 'load_spine');
    this.pendingPageOffset = pageOffset;
    this.pendingSpinePath = spineFilePath;
    this.pendingAnchorFragment = this.normalizeAnchorFragment(anchorFragment);
    this.activeSpineLayoutType = spineLayoutType ?? (this.params.spineLayoutType ?? '');
    this.activeSpineMediaType = spineMediaType ?? (this.params.spineMediaType ?? '');
    this.clearWebSelectionState();
    this.clearPendingThoughtPopupRequest();
    this.showHighlightThoughtPopup = false;
    this.ready = false;
    this.currentPageCount = 0;
    this.currentPage = 0;
    this.lastPaginationOffset = 0;
    this.lastPaginationPageExtent = 0;
    this.lastPaginationMaxOffset = 0;
    this.boundarySuppressionUntil = 0;
    this.aboutBlankReloadCount = 0;
    try {
      const fileUrl = this.normalizeFileUrl(spineFilePath);
      if (fileUrl.length <= 0) {
        throw new Error('empty spine file url');
      }
      this.lastLoadedFileUrl = fileUrl;
      logger.info(
        TAG,
        `加载 WebView spine: url=${fileUrl}, accessRoots=${this.universalAccessRootSignature || 'none'}`
      );
      this.webviewController.loadUrl(fileUrl);
    } catch (error) {
      const msg = String(error);
      this.pendingAnchorFragment = '';
      this.pendingSpineTransition = null;
      this.resetEpubCurlState(false);
      this.finishPageTurnAnimation();
      logger.error(TAG, `loadUrl failed: ${msg}`);
      this.params.callbacks.onError(`加载失败: ${msg}`);
    }
  }

  private configureUniversalAccessRoot(spineFilePath: string, source: string): void {
    if (!this.webControllerAttached || spineFilePath.trim().length <= 0) {
      return;
    }
    const accessRoots = this.resolveUniversalAccessRoots(spineFilePath);
    if (accessRoots.length <= 0) {
      return;
    }
    const rootSignature = accessRoots.join('|');
    if (rootSignature === this.universalAccessRootSignature) {
      return;
    }
    try {
      this.webviewController.setPathAllowingUniversalAccess(accessRoots);
      this.universalAccessRootSignature = rootSignature;
      logger.info(TAG, `WebView 本地文件访问白名单已设置: source=${source}, roots=${rootSignature}`);
    } catch (error) {
      logger.warn(
        TAG,
        `WebView 本地文件访问白名单设置失败: source=${source}, roots=${rootSignature}, error=${String(error)}`
      );
    }
  }

  private resolveUniversalAccessRoots(spineFilePath: string): string[] {
    const normalizedPath = this.normalizeFileSystemPath(spineFilePath);
    const roots: string[] = [];
    if (normalizedPath.length <= 0) {
      return roots;
    }
    const packageMarkers: string[] = ['/OEBPS/', '/OPS/', '/EPUB/'];
    for (let i = 0; i < packageMarkers.length; i++) {
      const marker = packageMarkers[i];
      const markerIndex = normalizedPath.indexOf(marker);
      if (markerIndex > 0) {
        this.appendUniversalAccessRoot(roots, normalizedPath.substring(0, markerIndex));
        this.appendUniversalAccessRoot(roots, normalizedPath.substring(0, markerIndex + marker.length - 1));
        break;
      }
    }
    this.appendUniversalAccessRoot(roots, this.resolveParentPath(normalizedPath));
    this.appendUniversalAccessRoot(roots, this.resolveAppFileSubdirectoryRoot(normalizedPath));
    this.appendAssetUniversalAccessRoots(roots, this.activeTextSettings.fontPath ?? '');
    this.appendAssetUniversalAccessRoots(roots, this.activeTextSettings.backgroundImagePath ?? '');
    return roots;
  }

  private appendAssetUniversalAccessRoots(roots: string[], assetPath: string): void {
    const normalizedAssetPath = this.normalizeFileSystemPath(assetPath);
    if (normalizedAssetPath.length <= 0) {
      return;
    }
    this.appendUniversalAccessRoot(roots, this.resolveParentPath(normalizedAssetPath));
    this.appendUniversalAccessRoot(roots, this.resolveAppFileSubdirectoryRoot(normalizedAssetPath));
  }

  private normalizeFileSystemPath(rawPath: string): string {
    let normalizedPath = rawPath.trim().replace(/\\/g, '/');
    if (normalizedPath.startsWith('file://')) {
      normalizedPath = normalizedPath.substring('file://'.length);
      if (normalizedPath.startsWith('localhost/')) {
        normalizedPath = normalizedPath.substring('localhost'.length);
      }
    }
    if (normalizedPath.startsWith('/') && /^[A-Za-z]:\//.test(normalizedPath.substring(1))) {
      normalizedPath = normalizedPath.substring(1);
    }
    try {
      normalizedPath = decodeURI(normalizedPath);
    } catch (_error) {
      normalizedPath = rawPath.trim().replace(/\\/g, '/').replace(/^file:\/\//, '');
    }
    while (normalizedPath.length > 1 && normalizedPath.endsWith('/')) {
      normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
    }
    return normalizedPath;
  }

  private resolveParentPath(filePath: string): string {
    const slashIndex = filePath.lastIndexOf('/');
    if (slashIndex > 0) {
      return filePath.substring(0, slashIndex);
    }
    return '';
  }

  private resolveAppFileSubdirectoryRoot(filePath: string): string {
    const appFilePrefixes: string[] = [
      '/data/storage/el2/base/haps/entry/files/',
      '/data/storage/el2/base/files/',
      '/data/storage/el1/bundle/entry/resource/resfile/'
    ];
    for (let i = 0; i < appFilePrefixes.length; i++) {
      const prefix = appFilePrefixes[i];
      if (!filePath.startsWith(prefix)) {
        continue;
      }
      const remainder = filePath.substring(prefix.length);
      const slashIndex = remainder.indexOf('/');
      if (slashIndex > 0) {
        return `${prefix}${remainder.substring(0, slashIndex)}`;
      }
    }
    return '';
  }

  private appendUniversalAccessRoot(roots: string[], rootPath: string): void {
    const normalizedRoot = this.normalizeFileSystemPath(rootPath);
    if (normalizedRoot.length <= 0 || roots.includes(normalizedRoot)) {
      return;
    }
    if (!this.isValidUniversalAccessRoot(normalizedRoot)) {
      return;
    }
    roots.push(normalizedRoot);
  }

  private isValidUniversalAccessRoot(rootPath: string): boolean {
    const allowedPrefixes: string[] = [
      '/data/storage/el2/base/haps/entry/files/',
      '/data/storage/el2/base/files/',
      '/data/storage/el1/bundle/entry/resource/resfile/'
    ];
    for (let i = 0; i < allowedPrefixes.length; i++) {
      const prefix = allowedPrefixes[i];
      if (rootPath.startsWith(prefix) && rootPath.substring(prefix.length).trim().length > 0) {
        return true;
      }
    }
    return false;
  }

  private getCurrentEpubLayoutKind(): EpubPageLayoutKind {
    if (this.params.isFixedLayout) {
      return 'horizontal_paged';
    }
    return this.getLayoutKind(
      this.activePageSettings,
      this.lastVpW > 0 ? this.lastVpW : this.fallbackVpW,
      this.lastVpH > 0 ? this.lastVpH : this.fallbackVpH
    );
  }

  private isEpubCurlAnimationSupported(layoutKind: EpubPageLayoutKind): boolean {
    if (this.isContinuousMode()) {
      return false;
    }
    if (layoutKind === 'vertical_paged' || layoutKind === 'continuous_vertical') {
      return false;
    }
    if (this.activePageSettings.readingDirection === ReadingDirection.TOP_TO_BOTTOM) {
      return false;
    }
    return layoutKind === 'horizontal_paged' || layoutKind === 'double_page';
  }

  private getEpubCurlStartPosition(forward: boolean): CurlStartPosition {
    const isRtl = this.activePageSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT;
    const curlFromRight = forward ? !isRtl : isRtl;
    return curlFromRight ? CurlStartPosition.RIGHT_EDGE : CurlStartPosition.LEFT_EDGE;
  }

  private prepareEpubCurlGeometry(forward: boolean): void {
    const viewportW = this.getAnimationViewportWidthVp();
    const viewportH = this.getAnimationViewportHeightVp();
    this.epubCurlIsForward = forward;
    this.epubCurlStartPosition = this.getEpubCurlStartPosition(forward);
    this.epubCurlTouchX = this.epubCurlStartPosition === CurlStartPosition.RIGHT_EDGE ? viewportW : 0;
    this.epubCurlTouchY = viewportH / 2;
  }

  private waitMs(delayMs: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, delayMs);
    });
  }

  private async settleEpubCurlTargetSnapshot(targetPage: number, stage: string): Promise<void> {
    await this.waitMs(EPUB_INTERACTIVE_CURL_TARGET_CAPTURE_DELAY_MS);
    const raw = await this.runJsForResult(`
      (function() {
        if (document.documentElement) {
          void document.documentElement.offsetWidth;
        }
        if (document.body) {
          void document.body.offsetHeight;
        }
        var state = window.__mnxRefreshPagination ? window.__mnxRefreshPagination() : null;
        if (window.__mnxUpdateFootnoteLayer) {
          window.__mnxUpdateFootnoteLayer();
        }
        if (!state) {
          return '';
        }
        return JSON.stringify({
          pageCount: state.pageCount || 1,
          currentPage: state.currentPage || 0,
          currentOffset: state.currentOffset || 0,
          pageExtent: state.pageExtent || 0,
          maxOffset: state.maxOffset || 0,
          contentExtent: state.contentExtent || 0,
          rootTagName: state.rootTagName || ''
        });
      })();
    `, 180);
    const snapshot = this.parseEpubPaginationSnapshot(raw);
    if (snapshot) {
      logger.debug(
        TAG,
        `[EPUB卷页] ${stage} 目标页渲染确认: target=${targetPage}, page=${snapshot.currentPage}/${snapshot.pageCount}, offset=${snapshot.currentOffset}/${snapshot.maxOffset}, extent=${snapshot.pageExtent}, root=${snapshot.rootTagName || 'n/a'}`
      );
      if (snapshot.currentPage !== targetPage) {
        logger.warn(
          TAG,
          `[EPUB卷页] ${stage} 目标页确认不一致，重新定位: target=${targetPage}, current=${snapshot.currentPage}`
        );
        await this.commitPageChangeAsync(targetPage);
        await this.waitMs(EPUB_INTERACTIVE_CURL_TARGET_CAPTURE_DELAY_MS);
      }
    } else {
      logger.debug(TAG, `[EPUB卷页] ${stage} 目标页渲染确认无返回，继续等待截图`);
      await this.waitMs(EPUB_INTERACTIVE_CURL_TARGET_CAPTURE_DELAY_MS);
    }
    await this.waitMs(32);
  }

  private async captureEpubCurlSnapshot(stage: string): Promise<image.PixelMap | null> {
    const ctx = this.resolveUiContext();
    if (!ctx) {
      logger.warn(TAG, `[EPUB卷页] ${stage} 截图失败: UIContext为空`);
      return null;
    }
    try {
      const pixelMap = await ctx.getComponentSnapshot().get(EPUB_WEBVIEW_CAPTURE_COMPONENT_ID, {
        waitUntilRenderFinished: true,
        scale: 1
      });
      const imageInfo = await pixelMap.getImageInfo();
      if (imageInfo.size.width <= 0 || imageInfo.size.height <= 0) {
        logger.warn(TAG, `[EPUB卷页] ${stage} 截图尺寸无效: ${imageInfo.size.width}x${imageInfo.size.height}`);
        pixelMap.release();
        return null;
      }
      logger.info(TAG, `[EPUB卷页] ${stage} 截图成功: ${imageInfo.size.width}x${imageInfo.size.height}`);
      return pixelMap;
    } catch (error) {
      logger.warn(TAG, `[EPUB卷页] ${stage} 截图失败: ${String(error)}`);
      return null;
    }
  }

  private releaseEpubCurlPixelMap(pixelMap: image.PixelMap | null, label: string): void {
    if (!pixelMap) {
      return;
    }
    try {
      pixelMap.release();
    } catch (error) {
      logger.warn(TAG, `[EPUB卷页] 释放 ${label} 快照失败: ${String(error)}`);
    }
  }

  private clearEpubCurlAnimationTimer(): void {
    if (this.epubCurlAnimationTimer !== -1) {
      clearTimeout(this.epubCurlAnimationTimer);
      this.epubCurlAnimationTimer = -1;
    }
  }

  private clearEpubCurlReleaseTimer(): void {
    if (this.epubCurlReleaseTimer !== -1) {
      clearTimeout(this.epubCurlReleaseTimer);
      this.epubCurlReleaseTimer = -1;
    }
  }

  private setWebViewHiddenForEpubCurl(hidden: boolean, reason: string): void {
    if (this.hideWebViewForEpubCurlCapture === hidden) {
      return;
    }
    this.hideWebViewForEpubCurlCapture = hidden;
    logger.debug(
      TAG,
      `[EPUB卷页] ${hidden ? '隐藏' : '恢复'} WebView真实滚动层: reason=${reason}`
    );
  }

  private scheduleEpubCurlSnapshotRelease(): void {
    this.clearEpubCurlReleaseTimer();
    this.epubCurlReleaseTimer = setTimeout(() => {
      this.epubCurlReleaseTimer = -1;
      this.releaseEpubCurlPixelMap(this.epubCurlCurrentPixelMap, 'current');
      this.releaseEpubCurlPixelMap(this.epubCurlNextPixelMap, 'next');
      this.epubCurlCurrentPixelMap = null;
      this.epubCurlNextPixelMap = null;
    }, 96);
  }

  private resetEpubCurlState(releaseImmediately: boolean = false): void {
    this.clearEpubCurlAnimationTimer();
    this.clearEpubCurlReleaseTimer();
    this.epubCurlInteractiveActive = false;
    this.epubCurlInteractiveReady = false;
    this.epubCurlInteractiveEndPending = false;
    this.epubCurlInteractiveEndComplete = false;
    this.epubCurlInteractiveOriginalPage = -1;
    this.epubCurlInteractiveTargetPage = -1;
    this.epubCurlPendingProgress = 0;
    this.epubCurlLastProgress = 0;
    this.epubCurlLastProgressAt = 0;
    this.epubCurlReleaseVelocity = 0;
    this.epubCurlReleaseAnimating = false;
    this.epubCurlReleaseComplete = false;
    this.showEpubCurlSnapshotCover = false;
    this.showEpubCurlEffect = false;
    this.setWebViewHiddenForEpubCurl(false, 'reset_state');
    this.epubCurlCanvasReady = false;
    this.epubCurlProgress = 0;
    this.epubCurlAnimateVelocity = 0;
    this.epubCurlAnimateTarget = -1;
    this.epubCurlRenderToken++;
    if (releaseImmediately) {
      this.releaseEpubCurlPixelMap(this.epubCurlCurrentPixelMap, 'current');
      this.releaseEpubCurlPixelMap(this.epubCurlNextPixelMap, 'next');
      this.epubCurlCurrentPixelMap = null;
      this.epubCurlNextPixelMap = null;
    } else {
      this.scheduleEpubCurlSnapshotRelease();
    }
  }

  private easeInOutCubic(progress: number): number {
    const t = this.clamp(progress, 0, 1);
    if (t < 0.5) {
      return 4 * t * t * t;
    }
    const adjusted = -2 * t + 2;
    return 1 - (adjusted * adjusted * adjusted) / 2;
  }

  private startEpubCurlAnimation(onComplete?: () => void): void {
    this.clearEpubCurlAnimationTimer();
    const duration = this.epubCurlEffectConfig.animationDuration;
    const startedAt = Date.now();
    const animateFrame = (): void => {
      if (!this.showEpubCurlEffect) {
        this.clearEpubCurlAnimationTimer();
        if (onComplete) {
          onComplete();
        }
        return;
      }
      const elapsed = Date.now() - startedAt;
      const rawProgress = this.clamp(elapsed / duration, 0, 1);
      this.epubCurlProgress = this.easeInOutCubic(rawProgress);
      if (rawProgress < 1) {
        this.epubCurlAnimationTimer = setTimeout(animateFrame, 16);
        return;
      }
      this.epubCurlAnimationTimer = -1;
      this.showEpubCurlEffect = false;
      this.showEpubCurlSnapshotCover = false;
      this.setWebViewHiddenForEpubCurl(false, 'curl_complete');
      this.epubCurlProgress = 0;
      this.scheduleEpubCurlSnapshotRelease();
      this.finishPageTurnAnimation();
      logger.info(TAG, '[EPUB卷页] 卷页动画完成');
      if (onComplete) {
        onComplete();
      }
    };
    this.epubCurlAnimationTimer = setTimeout(animateFrame, 16);
  }

  private commitPageChangeAsync(targetPage: number): Promise<void> {
    return new Promise<void>((resolve) => {
      this.commitPageChange(targetPage, () => {
        resolve();
      });
    });
  }

  private async performEpubCurlPageTurn(targetPage: number, forward: boolean): Promise<void> {
    this.isPageTurnAnimating = true;
    this.prepareEpubCurlGeometry(forward);
    this.resetEpubCurlState(true);

    const currentPixelMap = await this.captureEpubCurlSnapshot('current');
    if (!currentPixelMap) {
      logger.warn(TAG, '[EPUB卷页] 当前页截图不可用，降级为覆盖动画');
      this.finishPageTurnAnimation();
      this.performViewportAnimatedPageTurn(targetPage, forward, PageTurnAnimationType.COVER);
      return;
    }
    if (!this.uiContext) {
      this.releaseEpubCurlPixelMap(currentPixelMap, 'current');
      this.isPageTurnAnimating = false;
      return;
    }

    this.epubCurlCurrentPixelMap = currentPixelMap;
    this.showEpubCurlSnapshotCover = true;
    this.epubCurlProgress = 0;

    await this.waitMs(EPUB_CURL_COVER_RENDER_DELAY_MS);
    if (!this.uiContext) {
      this.resetEpubCurlState(true);
      this.isPageTurnAnimating = false;
      return;
    }

    logger.debug(TAG, '[EPUB卷页] 保持 WebView真实渲染层可见: reason=page_turn_commit');
    await this.commitPageChangeAsync(targetPage);
    if (!this.uiContext) {
      this.resetEpubCurlState(true);
      this.isPageTurnAnimating = false;
      return;
    }

    this.setWebViewHiddenForEpubCurl(false, 'target_capture');
    await this.settleEpubCurlTargetSnapshot(targetPage, 'target_capture');
    const nextPixelMap = await this.captureEpubCurlSnapshot('next');
    this.setWebViewHiddenForEpubCurl(true, 'curl_effect');
    if (!nextPixelMap) {
      logger.warn(TAG, '[EPUB卷页] 目标页截图不可用，直接完成翻页');
      this.showEpubCurlSnapshotCover = false;
      this.finishPageTurnAnimation();
      this.resetEpubCurlState(false);
      return;
    }

    this.epubCurlNextPixelMap = nextPixelMap;
    this.epubCurlCanvasReady = false;
    this.showEpubCurlEffect = true;
    this.showEpubCurlSnapshotCover = true;
    this.epubCurlRenderToken++;
    this.startEpubCurlAnimation();
  }

  private async performEpubCurlSpineTransition(
    spineFilePath: string,
    pageOffset: number,
    forward: boolean,
    anchorFragment: string = '',
    spineLayoutType: string = '',
    spineMediaType: string = ''
  ): Promise<void> {
    this.isPageTurnAnimating = true;
    this.prepareEpubCurlGeometry(forward);
    this.resetEpubCurlState(true);

    const currentPixelMap = await this.captureEpubCurlSnapshot('spine_current');
    if (!currentPixelMap) {
      logger.warn(TAG, '[EPUB卷页] 跨 spine 当前页截图不可用，直接切换 spine');
      this.pendingSpineTransition = null;
      this.finishPageTurnAnimation();
      this.loadSpineItemImmediate(spineFilePath, pageOffset, anchorFragment, spineLayoutType, spineMediaType);
      return;
    }
    if (!this.uiContext) {
      this.releaseEpubCurlPixelMap(currentPixelMap, 'spine_current');
      this.pendingSpineTransition = null;
      this.finishPageTurnAnimation();
      this.loadSpineItemImmediate(spineFilePath, pageOffset, anchorFragment, spineLayoutType, spineMediaType);
      return;
    }

    this.epubCurlCurrentPixelMap = currentPixelMap;
    this.showEpubCurlSnapshotCover = true;
    this.epubCurlCanvasReady = false;
    this.epubCurlProgress = 0;

    await this.waitMs(EPUB_CURL_COVER_RENDER_DELAY_MS);
    if (!this.uiContext) {
      this.pendingSpineTransition = null;
      this.resetEpubCurlState(true);
      this.finishPageTurnAnimation();
      this.loadSpineItemImmediate(spineFilePath, pageOffset, anchorFragment, spineLayoutType, spineMediaType);
      return;
    }

    this.setWebViewHiddenForEpubCurl(true, 'spine_transition_load');
    this.pendingSpineTransition = {
      incoming: {
        opacity: 1,
        matrix: matrix4.identity()
      },
      inDuration: 0,
      inCurve: Curve.EaseOut,
      useCurl: true,
      forward: forward
    };
    logger.info(
      TAG,
      `[EPUB卷页] 跨 spine 卷页准备完成: direction=${forward ? 'next' : 'prev'}, targetOffset=${pageOffset}`
    );
    this.loadSpineItemImmediate(spineFilePath, pageOffset, anchorFragment, spineLayoutType, spineMediaType);
  }

  private async completeEpubCurlSpineTransition(
    forward: boolean,
    finalizeReady: () => void
  ): Promise<void> {
    await this.waitMs(EPUB_CURL_TARGET_CAPTURE_DELAY_MS);
    if (!this.uiContext || this.epubCurlCurrentPixelMap === null) {
      logger.warn(TAG, '[EPUB卷页] 跨 spine 目标页加载后当前快照不可用，结束覆盖层');
      this.pendingSpineTransition = null;
      this.resetEpubCurlState(false);
      this.finishPageTurnAnimation();
      finalizeReady();
      return;
    }

    this.setWebViewHiddenForEpubCurl(false, 'spine_target_capture');
    await this.waitMs(16);
    const nextPixelMap = await this.captureEpubCurlSnapshot('spine_next');
    this.setWebViewHiddenForEpubCurl(true, 'spine_curl_effect');
    if (!nextPixelMap) {
      logger.warn(TAG, '[EPUB卷页] 跨 spine 目标页截图不可用，直接显示新 spine');
      this.pendingSpineTransition = null;
      this.resetEpubCurlState(false);
      this.finishPageTurnAnimation();
      finalizeReady();
      return;
    }

    this.epubCurlNextPixelMap = nextPixelMap;
    this.epubCurlCanvasReady = false;
    this.showEpubCurlEffect = true;
    this.showEpubCurlSnapshotCover = true;
    this.epubCurlProgress = 0;
    this.epubCurlRenderToken++;
    logger.info(TAG, `[EPUB卷页] 跨 spine 目标页截图就绪: direction=${forward ? 'next' : 'prev'}`);
    let completed = false;
    this.startEpubCurlAnimation(() => {
      if (completed) {
        return;
      }
      completed = true;
      this.pendingSpineTransition = null;
      finalizeReady();
    });
  }

  private beginInteractiveCurl(forward: boolean, touchX: number, touchY: number): boolean {
    if (this.epubCurlInteractiveActive) {
      return true;
    }
    if (!this.ready || this.isPageTurnAnimating || this.currentPageCount <= 1) {
      return false;
    }
    const animationType = this.normalizeAnimationType(
      this.activePageSettings.pageTurnAnimation ?? PageTurnAnimationType.SLIDE
    );
    const layoutKind = this.getCurrentEpubLayoutKind();
    if (animationType !== PageTurnAnimationType.CURL || !this.isEpubCurlAnimationSupported(layoutKind)) {
      return false;
    }
    const targetPage = forward ? this.currentPage + 1 : this.currentPage - 1;
    if (targetPage < 0 || targetPage >= this.currentPageCount) {
      return false;
    }

    this.resetEpubCurlState(true);
    this.isPageTurnAnimating = true;
    this.epubCurlInteractiveActive = true;
    this.epubCurlInteractiveReady = false;
    this.epubCurlInteractiveEndPending = false;
    this.epubCurlInteractiveEndComplete = false;
    this.epubCurlInteractiveOriginalPage = this.currentPage;
    this.epubCurlInteractiveTargetPage = targetPage;
    this.epubCurlPendingProgress = 0;
    this.epubCurlLastProgress = 0;
    this.epubCurlLastProgressAt = Date.now();
    this.epubCurlReleaseVelocity = 0;
    this.epubCurlReleaseAnimating = false;
    this.epubCurlReleaseComplete = false;
    this.epubCurlAnimateVelocity = 0;
    this.epubCurlAnimateTarget = -1;
    this.prepareEpubCurlGeometry(forward);
    this.epubCurlTouchX = touchX;
    this.epubCurlTouchY = touchY;
    logger.info(TAG, `[EPUB卷页] 交互卷页开始: target=${targetPage}, forward=${forward}`);
    void this.prepareInteractiveCurlSnapshots(targetPage, forward);
    return true;
  }

  private async prepareInteractiveCurlSnapshots(targetPage: number, forward: boolean): Promise<void> {
    const currentPixelMap = await this.captureEpubCurlSnapshot('interactive_current');
    if (!this.epubCurlInteractiveActive) {
      this.releaseEpubCurlPixelMap(currentPixelMap, 'interactive_current');
      return;
    }
    if (!currentPixelMap) {
      logger.warn(TAG, '[EPUB卷页] 交互卷页当前页截图不可用，取消交互卷页');
      this.resetEpubCurlState(true);
      this.finishPageTurnAnimation();
      return;
    }
    this.epubCurlCurrentPixelMap = currentPixelMap;
    this.epubCurlCanvasReady = false;
    this.showEpubCurlSnapshotCover = true;
    this.epubCurlProgress = this.clamp(this.epubCurlPendingProgress, 0, 0.96);
    logger.info(TAG, `[EPUB卷页] 交互卷页当前页遮罩就绪: target=${targetPage}, forward=${forward}`);

    await this.waitMs(EPUB_INTERACTIVE_CURL_COVER_RENDER_DELAY_MS);
    if (!this.epubCurlInteractiveActive) {
      return;
    }

    logger.debug(TAG, '[EPUB卷页] 保持 WebView真实渲染层可见: reason=interactive_commit');
    await this.commitPageChangeAsync(targetPage);
    if (!this.epubCurlInteractiveActive) {
      return;
    }

    this.setWebViewHiddenForEpubCurl(false, 'interactive_target_capture');
    await this.settleEpubCurlTargetSnapshot(targetPage, 'interactive_target_capture');
    const nextPixelMap = await this.captureEpubCurlSnapshot('interactive_next');
    if (!this.epubCurlInteractiveActive) {
      this.releaseEpubCurlPixelMap(nextPixelMap, 'interactive_next');
      return;
    }
    if (!nextPixelMap) {
      logger.warn(TAG, '[EPUB卷页] 交互卷页目标页截图不可用，取消交互卷页');
      const originalPage = this.epubCurlInteractiveOriginalPage;
      this.resetEpubCurlState(false);
      if (originalPage >= 0) {
        this.commitPageChange(originalPage, () => {
          this.finishPageTurnAnimation();
        });
      } else {
        this.finishPageTurnAnimation();
      }
      return;
    }

    this.setWebViewHiddenForEpubCurl(true, 'interactive_curl_effect');
    this.epubCurlNextPixelMap = nextPixelMap;
    this.epubCurlInteractiveReady = true;
    this.epubCurlCanvasReady = false;
    this.showEpubCurlEffect = true;
    this.showEpubCurlSnapshotCover = true;
    this.epubCurlProgress = this.clamp(this.epubCurlPendingProgress, 0, 0.96);
    this.epubCurlRenderToken++;
    logger.info(TAG, `[EPUB卷页] 交互卷页快照就绪: target=${targetPage}, forward=${forward}`);

    if (this.epubCurlInteractiveEndPending) {
      this.finishInteractiveCurl(this.epubCurlInteractiveEndComplete);
    }
  }

  private updateInteractiveCurl(progress: number, touchX: number, touchY: number): void {
    if (!this.epubCurlInteractiveActive) {
      return;
    }
    if (this.epubCurlReleaseAnimating) {
      return;
    }
    this.epubCurlTouchX = touchX;
    this.epubCurlTouchY = touchY;
    const nextProgress = this.clamp(progress, 0, 0.96);
    const now = Date.now();
    if (this.epubCurlLastProgressAt > 0 && now > this.epubCurlLastProgressAt) {
      const elapsed = Math.max(1, now - this.epubCurlLastProgressAt);
      const velocity = Math.abs(nextProgress - this.epubCurlLastProgress) / elapsed;
      const decayedVelocity = this.epubCurlReleaseVelocity * 0.86;
      this.epubCurlReleaseVelocity = this.clamp(Math.max(velocity, decayedVelocity), 0, 0.02);
    }
    this.epubCurlLastProgress = nextProgress;
    this.epubCurlLastProgressAt = now;
    this.epubCurlPendingProgress = nextProgress;
    if (this.showEpubCurlEffect) {
      this.epubCurlProgress = this.epubCurlPendingProgress;
    }
  }

  private endInteractiveCurl(complete: boolean): boolean {
    if (!this.epubCurlInteractiveActive) {
      return false;
    }
    if (!this.epubCurlInteractiveReady) {
      this.epubCurlInteractiveEndPending = true;
      this.epubCurlInteractiveEndComplete = complete;
      return true;
    }
    this.finishInteractiveCurl(complete);
    return true;
  }

  private cancelInteractiveCurl(): void {
    if (this.epubCurlInteractiveActive) {
      this.endInteractiveCurl(false);
    }
  }

  private finishInteractiveCurl(complete: boolean): void {
    this.clearEpubCurlAnimationTimer();
    if (!this.epubCurlInteractiveReady) {
      this.epubCurlInteractiveEndPending = true;
      this.epubCurlInteractiveEndComplete = complete;
      return;
    }
    const startProgress = this.clamp(this.epubCurlProgress, 0, 1);
    const targetProgress = complete ? 1 : 0;
    const progressDelta = Math.abs(targetProgress - startProgress);
    if (progressDelta < 0.01) {
      this.finalizeInteractiveCurl(complete);
      return;
    }
    this.epubCurlReleaseAnimating = true;
    this.epubCurlReleaseComplete = complete;
    this.epubCurlAnimateVelocity = complete ? Math.max(this.epubCurlReleaseVelocity, 0.0006) : 0;
    this.epubCurlAnimateTarget = targetProgress;
    logger.info(
      TAG,
      `[EPUB卷页] 交互卷页脱手动画: complete=${complete}, start=${startProgress.toFixed(3)}, target=${targetProgress}, velocity=${this.epubCurlAnimateVelocity.toFixed(5)}`
    );
  }

  private handleEpubCurlInternalAnimationComplete(): void {
    if (!this.epubCurlReleaseAnimating) {
      return;
    }
    const complete = this.epubCurlReleaseComplete;
    this.epubCurlReleaseAnimating = false;
    this.epubCurlAnimateTarget = -1;
    this.epubCurlAnimateVelocity = 0;
    this.epubCurlProgress = complete ? 1 : 0;
    this.finalizeInteractiveCurl(complete);
  }

  private finalizeInteractiveCurl(complete: boolean): void {
    const originalPage = this.epubCurlInteractiveOriginalPage;
    this.epubCurlInteractiveActive = false;
    this.epubCurlInteractiveReady = false;
    this.epubCurlInteractiveEndPending = false;
    if (!complete && originalPage >= 0) {
      this.commitPageChange(originalPage, () => {
        this.resetEpubCurlState(false);
        this.finishPageTurnAnimation();
      });
      return;
    }
    this.resetEpubCurlState(false);
    this.finishPageTurnAnimation();
  }

  private performAnimatedSpineTransition(
    spineFilePath: string,
    pageOffset: number,
    forward: boolean,
    anchorFragment: string = '',
    spineLayoutType: string = '',
    spineMediaType: string = ''
  ): void {
    const requestedAnimationType = this.normalizeAnimationType(
      this.activePageSettings.pageTurnAnimation ?? PageTurnAnimationType.SLIDE
    );
    const ctx = this.resolveUiContext();
    if (requestedAnimationType === PageTurnAnimationType.NONE || !ctx) {
      this.pendingSpineTransition = null;
      this.finishPageTurnAnimation();
      this.loadSpineItemImmediate(spineFilePath, pageOffset, anchorFragment, spineLayoutType, spineMediaType);
      return;
    }

    const layoutKind = this.params.isFixedLayout
      ? 'horizontal_paged'
      : this.getLayoutKind(
        this.activePageSettings,
        this.lastVpW > 0 ? this.lastVpW : this.fallbackVpW,
        this.lastVpH > 0 ? this.lastVpH : this.fallbackVpH
      );
    if (
      requestedAnimationType === PageTurnAnimationType.CURL &&
      this.isEpubCurlAnimationSupported(layoutKind)
    ) {
      logger.info(
        TAG,
        `[EPUB卷页] 执行跨 spine 卷页动画: direction=${forward ? 'next' : 'prev'}, layout=${layoutKind}`
      );
      void this.performEpubCurlSpineTransition(
        spineFilePath,
        pageOffset,
        forward,
        anchorFragment,
        spineLayoutType,
        spineMediaType
      );
      return;
    }

    const animationType = requestedAnimationType === PageTurnAnimationType.CURL
      ? PageTurnAnimationType.COVER
      : requestedAnimationType;
    const profile = this.createAnimationProfile(layoutKind, forward, animationType);
    this.pendingSpineTransition = {
      incoming: profile.incoming,
      inDuration: profile.inDuration,
      inCurve: profile.inCurve,
      useCurl: false,
      forward: forward
    };
    this.isPageTurnAnimating = true;
    logger.info(
      TAG,
      `执行跨 spine viewport 动画: type=${animationType}, direction=${forward ? 'next' : 'prev'}, out=${profile.outDuration}ms, in=${profile.inDuration}ms`
    );

    ctx.animateTo({
      duration: profile.outDuration,
      curve: curves.initCurve(profile.outCurve),
      onFinish: () => {
        this.loadSpineItemImmediate(spineFilePath, pageOffset, anchorFragment, spineLayoutType, spineMediaType);
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
      this.applyHighlightRangesToWeb(notifyReady ? 'initial_ready' : 'layout_reapply');
      this.tryPresentPendingThoughtPopup(notifyReady ? 'initial_ready' : 'layout_reapply');
      this.scheduleWebViewPaintStabilization(notifyReady ? 'initial_ready' : 'layout_reapply');
      if (this.pendingSettingsReapplyReason.length > 0) {
        const pendingReason = this.pendingSettingsReapplyReason;
        this.pendingSettingsReapplyReason = '';
        this.scheduleSettingsReapply(`pending_after_ready:${pendingReason}`, SETTINGS_APPLY_DELAY_MS);
      }
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
    this.applyHighlightRangesToWeb('ready_page_change');

    const pendingTransition = this.pendingSpineTransition;
    if (!pendingTransition) {
      finalizeReady();
      return;
    }
    if (pendingTransition.useCurl) {
      void this.completeEpubCurlSpineTransition(pendingTransition.forward, finalizeReady);
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

  private performViewportAnimatedPageTurn(
    targetPage: number,
    forward: boolean,
    animationType: PageTurnAnimationType
  ): void {
    const layoutKind = this.getLayoutKind(
      this.activePageSettings,
      this.lastVpW > 0 ? this.lastVpW : this.fallbackVpW,
      this.lastVpH > 0 ? this.lastVpH : this.fallbackVpH
    );
    const normalizedAnimation = this.normalizeViewportAnimationType(animationType);

    if (normalizedAnimation === PageTurnAnimationType.NONE) {
      this.commitPageChange(targetPage);
      return;
    }

    const ctx = this.resolveUiContext();
    if (!ctx) {
      this.commitPageChange(targetPage);
      return;
    }

    this.isPageTurnAnimating = true;
    const profile = this.createAnimationProfile(layoutKind, forward, normalizedAnimation);

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

  private performAnimatedPageTurn(targetPage: number, forward: boolean): void {
    const layoutKind = this.getLayoutKind(
      this.activePageSettings,
      this.lastVpW > 0 ? this.lastVpW : this.fallbackVpW,
      this.lastVpH > 0 ? this.lastVpH : this.fallbackVpH
    );
    const animationType = this.normalizeAnimationType(
      this.activePageSettings.pageTurnAnimation ?? PageTurnAnimationType.SLIDE
    );

    if (animationType === PageTurnAnimationType.CURL && this.isEpubCurlAnimationSupported(layoutKind)) {
      void this.performEpubCurlPageTurn(targetPage, forward);
      return;
    }

    if (animationType === PageTurnAnimationType.CURL) {
      logger.info(TAG, `[EPUB卷页] 当前布局不支持卷页，降级为覆盖动画: layout=${layoutKind}`);
      this.performViewportAnimatedPageTurn(targetPage, forward, PageTurnAnimationType.COVER);
      return;
    }

    this.performViewportAnimatedPageTurn(targetPage, forward, animationType);
  }

  private scheduleSettingsReapply(reason: string, delayMs: number = SETTINGS_APPLY_DELAY_MS): void {
    if (!this.ready) {
      this.pendingSettingsReapplyReason = reason;
      logger.debug(TAG, `延迟排版重应用到 ready 后执行: reason=${reason}`);
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
      payload = SafeUtils.parseObj(clean) as PaginationUpdatePayload;
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
    const nextOffset = Math.max(0, Number(payload.currentOffset) || 0);
    const payloadSource = (payload.source ?? '').trim();
    const isNativeScrollUpdate = payloadSource === 'scroll' || payloadSource === 'window_scroll';
    if (this.ready && isNativeScrollUpdate && !this.isPageTurnAnimating && !this.isContinuousMode()) {
      const nativeScrollOffsetDelta = Math.abs(nextOffset - previousOffset);
      if (nextPage === previousPage && nativeScrollOffsetDelta <= 2) {
        return;
      }
      const safePreviousPage = Math.max(0, Math.min(previousPage, nextCount - 1));
      logger.warn(
        TAG,
        `拒绝分页模式原生滚动回调: source=${payloadSource}, reported=${nextPage}/${nextCount}, offset=${nextOffset}, restore=${safePreviousPage}`
      );
      this.runJs(`window.__mnxGoToPageImmediate(${safePreviousPage});`, (_result: string) => {
        this.applyHighlightRangesToWeb('native_scroll_revert');
      });
      return;
    }
    this.currentLayoutKind = (payload.layoutKind as EpubPageLayoutKind) || this.currentLayoutKind;
    this.currentPageCount = nextCount;
    this.currentPage = nextPage;
    this.lastPaginationOffset = nextOffset;
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
      this.applyHighlightRangesToWeb('pagination_change');
    }
    if (this.ready && previousOffset !== this.lastPaginationOffset) {
      this.applyHighlightRangesToWeb('pagination_offset');
    }
    if (this.ready && isNativeScrollUpdate) {
      this.handleContinuousBoundaryUpdate(payload, previousOffset);
    }
  }

  private handleReaderTap(payloadJson: string): void {
    if (!this.params.callbacks.onReaderTap) {
      return;
    }
    if (this.suppressNextTapEvent) {
      return;
    }
    try {
      const clean = this.parseWebViewJson(payloadJson);
      const payload = SafeUtils.parseObj(clean) as ReaderTapPayload;
      const safeXRatio = this.clamp(Number(payload.xRatio) || 0, 0, 1);
      const safeYRatio = this.clamp(Number(payload.yRatio) || 0, 0, 1);
      this.params.callbacks.onReaderTap(safeXRatio, safeYRatio);
    } catch (error) {
      logger.warn(TAG, `阅读器点击事件解析失败: ${String(error)}`);
    }
  }

  private handleReaderPan(payloadJson: string): void {
    try {
      const clean = this.parseWebViewJson(payloadJson);
      const payload = SafeUtils.parseObj(clean) as ReaderPanPayload;
      const phase = String(payload.phase ?? '');
      if (phase === 'update') {
        this.handleReaderPanUpdate(payload);
        return;
      }
      if (phase === 'end') {
        this.handleReaderPanEnd(payload);
        return;
      }
      if (phase === 'cancel') {
        this.handleReaderPanCancel();
      }
    } catch (error) {
      logger.warn(TAG, `阅读器实时拖拽事件解析失败: ${String(error)}`);
    }
  }

  private handleReaderPanUpdate(payload: ReaderPanPayload): void {
    if (this.isContinuousMode() || this.getCurrentEpubLayoutKind() === 'vertical_paged') {
      return;
    }
    const deltaXRatio = Number(payload.deltaXRatio) || 0;
    const deltaYRatio = Number(payload.deltaYRatio) || 0;
    const absXRatio = Math.abs(deltaXRatio);
    const absYRatio = Math.abs(deltaYRatio);
    if (absXRatio < 0.01 || absXRatio < absYRatio * 0.85) {
      return;
    }
    const swipingLeft = deltaXRatio < 0;
    const forward = this.activePageSettings.readingDirection === ReadingDirection.RIGHT_TO_LEFT
      ? !swipingLeft
      : swipingLeft;
    const viewportW = this.getAnimationViewportWidthVp();
    const viewportH = this.getAnimationViewportHeightVp();
    const touchX = this.clamp(Number(payload.xRatio) || 0, 0, 1) * viewportW;
    const touchY = this.clamp(Number(payload.yRatio) || 0.5, 0, 1) * viewportH;
    if (!this.epubCurlInteractiveActive) {
      if (!this.beginInteractiveCurl(forward, touchX, touchY)) {
        return;
      }
      logger.info(TAG, `[EPUB卷页] WebView 实时卷页开始: forward=${forward}`);
    }
    const progress = this.clamp(absXRatio, 0.01, 0.96);
    this.updateInteractiveCurl(progress, touchX, touchY);
    this.readerSwipeSuppressedUntil = Date.now() + 900;
  }

  private handleReaderPanEnd(payload: ReaderPanPayload): void {
    if (!this.epubCurlInteractiveActive) {
      return;
    }
    const deltaXRatio = Number(payload.deltaXRatio) || 0;
    const deltaYRatio = Number(payload.deltaYRatio) || 0;
    const absXRatio = Math.abs(deltaXRatio);
    const absYRatio = Math.abs(deltaYRatio);
    const viewportW = this.getAnimationViewportWidthVp();
    const viewportH = this.getAnimationViewportHeightVp();
    const touchX = this.clamp(Number(payload.xRatio) || 0, 0, 1) * viewportW;
    const touchY = this.clamp(Number(payload.yRatio) || 0.5, 0, 1) * viewportH;
    this.updateInteractiveCurl(this.clamp(absXRatio, 0.01, 0.96), touchX, touchY);
    const complete = absXRatio >= 0.34 || (absXRatio >= 0.22 && absXRatio >= absYRatio * 1.15);
    if (this.endInteractiveCurl(complete)) {
      this.readerSwipeSuppressedUntil = Date.now() + 900;
      logger.info(TAG, `[EPUB卷页] WebView 实时卷页结束: complete=${complete}`);
    }
  }

  private handleReaderPanCancel(): void {
    if (!this.epubCurlInteractiveActive) {
      return;
    }
    this.cancelInteractiveCurl();
    this.readerSwipeSuppressedUntil = Date.now() + 900;
    logger.info(TAG, '[EPUB卷页] WebView 实时卷页取消');
  }

  private handleReaderSwipe(payloadJson: string): void {
    if (!this.params.callbacks.onReaderSwipe) {
      return;
    }
    if (Date.now() < this.readerSwipeSuppressedUntil) {
      logger.debug(TAG, '[EPUB卷页] 忽略已由实时卷页处理的 WebView swipe');
      return;
    }
    try {
      const clean = this.parseWebViewJson(payloadJson);
      const payload = SafeUtils.parseObj(clean) as ReaderSwipePayload;
      const deltaX = Number(payload.deltaX) || 0;
      const deltaY = Number(payload.deltaY) || 0;
      this.params.callbacks.onReaderSwipe(deltaX, deltaY);
    } catch (error) {
      logger.warn(TAG, `阅读器滑动事件解析失败: ${String(error)}`);
    }
  }

  onEpubHighlightRangesChange(_changedPropertyName?: string): void {
    this.applyHighlightRangesToWeb('prop_change');
    this.tryPresentPendingThoughtPopup('highlight_ranges_change');
  }

  private buildHighlightRangesPayloadJson(): string {
    const ranges: EpubWebHighlightRange[] = [];
    for (let i = 0; i < this.epubHighlightRanges.length; i++) {
      const item = this.epubHighlightRanges[i];
      const safeStart = Math.max(0, Math.floor(item.startOffset));
      const safeEnd = Math.max(safeStart + 1, Math.floor(item.endOffset));
      if (!item.id || item.id.length <= 0 || safeEnd <= safeStart) {
        continue;
      }
      const range: EpubWebHighlightRange = {
        id: item.id,
        startOffset: safeStart,
        endOffset: safeEnd,
        color: item.color && item.color.trim().length > 0 ? item.color : '#E8A317',
        lineType: item.lineType === HighlightLineType.WAVY ? HighlightLineType.WAVY : HighlightLineType.UNDERLINE,
        quoteText: item.quoteText ?? '',
        pageIndex: item.pageIndex,
        thoughtText: item.thoughtText ?? ''
      };
      ranges.push(range);
    }
    return JSON.stringify(ranges);
  }

  private applyHighlightRangesToWeb(reason: string): void {
    if (!this.ready) {
      logger.debug(TAG, `延迟 EPUB Web 划线渲染: ready=false, reason=${reason}`);
      return;
    }
    if (!this.enableEpubAnnotations) {
      this.runJs('(function(){ if (window.__mnxRemoveEpubHighlights) { window.__mnxRemoveEpubHighlights(); } return "ok"; })();');
      return;
    }
    const payloadJson = this.buildHighlightRangesPayloadJson();
    const escapedPayload = this.escapeJsTemplate(payloadJson);
    this.runJs(
      `(function(){ if (window.__mnxApplyEpubHighlights) { return window.__mnxApplyEpubHighlights(\`${escapedPayload}\`); } return 'missing'; })();`,
      (resultRaw: string) => {
        logger.debug(TAG, `EPUB Web 划线渲染完成: reason=${reason}, result=${this.parseWebViewJson(resultRaw)}`);
      }
    );
  }

  private parseWebSelectionSnapshot(raw: string): EpubWebSelectionSnapshot | null {
    const clean = this.parseWebViewJson(raw);
    if (!clean || clean.trim().length <= 0) {
      return null;
    }
    try {
      const parsed = SafeUtils.parseObj(clean) as EpubWebSelectionSnapshot;
      const selectedText = (parsed.selectedText ?? '').trim();
      const rawStartOffset = Number(parsed.startOffset);
      const rawEndOffset = Number(parsed.endOffset);
      const startOffset = !isNaN(rawStartOffset) ? Math.max(0, Math.floor(rawStartOffset)) : -1;
      const endOffset = !isNaN(rawEndOffset) ? Math.max(startOffset + 1, Math.floor(rawEndOffset)) : -1;
      if (selectedText.length <= 0 || startOffset < 0 || endOffset <= startOffset) {
        return null;
      }
      const snapshot: EpubWebSelectionSnapshot = {
        selectedText,
        startOffset,
        endOffset,
        contextBefore: parsed.contextBefore ?? '',
        contextAfter: parsed.contextAfter ?? '',
        pageIndex: Math.max(0, Math.floor(Number(parsed.pageIndex) || 0)),
        pageProgress: this.clamp(Number(parsed.pageProgress) || 0, 0, 1),
        rectX: Math.max(0, Number(parsed.rectX) || 0),
        rectY: Math.max(0, Number(parsed.rectY) || 0),
        rectWidth: Math.max(0, Number(parsed.rectWidth) || 0),
        rectHeight: Math.max(0, Number(parsed.rectHeight) || 0)
      };
      return snapshot;
    } catch (error) {
      logger.warn(TAG, `EPUB Web 选区快照解析失败: ${String(error)}`);
      return null;
    }
  }

  private parseWebTextSnapshot(raw: string): EpubWebTextSnapshot | null {
    const clean = this.parseWebViewJson(raw);
    if (!clean || clean.trim().length <= 0) {
      return null;
    }
    try {
      const parsed = SafeUtils.parseObj(clean) as EpubWebTextSnapshot;
      const text = parsed.text ?? '';
      const rawStartOffset = Number(parsed.startOffset);
      const rawEndOffset = Number(parsed.endOffset);
      const startOffset = !isNaN(rawStartOffset) ? Math.max(0, Math.floor(rawStartOffset)) : -1;
      const endOffset = !isNaN(rawEndOffset) ? Math.max(startOffset, Math.floor(rawEndOffset)) : -1;
      if (text.trim().length <= 0 || startOffset < 0 || endOffset < startOffset) {
        return null;
      }
      const snapshot: EpubWebTextSnapshot = {
        text,
        startOffset,
        endOffset,
        contextBefore: parsed.contextBefore ?? '',
        contextAfter: parsed.contextAfter ?? '',
        pageIndex: Math.max(0, Math.floor(Number(parsed.pageIndex) || 0)),
        pageProgress: this.clamp(Number(parsed.pageProgress) || 0, 0, 1),
        quoteText: parsed.quoteText ?? ''
      };
      return snapshot;
    } catch (error) {
      logger.warn(TAG, `EPUB Web 当前文本快照解析失败: ${String(error)}`);
      return null;
    }
  }

  private queryCurrentTextSnapshotFromWeb(onResult: (snapshot: EpubWebTextSnapshot | null) => void): void {
    if (!this.ready) {
      onResult(null);
      return;
    }
    this.runJs(
      '(function(){ return window.__mnxReadCurrentTextSnapshot ? window.__mnxReadCurrentTextSnapshot() : ""; })();',
      (raw: string) => {
        const snapshot = this.parseWebTextSnapshot(raw);
        if (snapshot) {
          logger.debug(
            TAG,
            `EPUB Web 当前文本快照: page=${snapshot.pageIndex}, start=${snapshot.startOffset}, end=${snapshot.endOffset}, textLength=${snapshot.text.length}`
          );
        }
        onResult(snapshot);
      }
    );
  }

  private applyPurifyRulesToWeb(rules: EpubWebPurifyRulePayload[]): void {
    if (!this.ready) {
      logger.debug(TAG, `忽略 EPUB Web 净化规则应用: ready=false, rules=${rules.length}`);
      return;
    }
    const payloadJson = JSON.stringify(rules);
    const escapedPayload = this.escapeJsTemplate(payloadJson);
    this.runJs(
      `(function(){ if (window.__mnxApplyPurifyRules) { return window.__mnxApplyPurifyRules(\`${escapedPayload}\`); } return 'missing'; })();`,
      (resultRaw: string) => {
        logger.info(TAG, `EPUB Web 净化规则应用完成: ${this.parseWebViewJson(resultRaw)}`);
        this.applyHighlightRangesToWeb('purify_rules');
      }
    );
  }

  private seekToTextOffsetImmediate(offset: number): boolean {
    if (!this.ready || this.isPageTurnAnimating) {
      return false;
    }
    const safeOffset = Math.max(0, Math.floor(offset));
    this.runJs(
      `(function(){ if (window.__mnxSeekToTextOffset) { return window.__mnxSeekToTextOffset(${safeOffset}); } return ''; })();`,
      (resultRaw: string) => {
        const result = this.parsePageCommandResult(resultRaw, this.currentPage);
        this.currentPage = Math.max(0, Math.min(result.pageIndex, Math.max(0, result.pageCount - 1)));
        this.currentPageCount = Math.max(1, result.pageCount);
        this.lastPaginationOffset = result.offset;
        this.lastPaginationPageExtent = result.pageExtent;
        this.lastPaginationMaxOffset = result.maxOffset;
        this.lastProgressRatio = this.computeProgressRatio(
          this.currentPage,
          this.currentPageCount,
          this.lastPaginationOffset,
          this.lastPaginationMaxOffset
        );
        this.params.callbacks.onPageChange(this.currentPage, this.currentPageCount);
        this.applyHighlightRangesToWeb('seek_text_offset');
        logger.debug(TAG, `EPUB Web 文本 offset 定位完成: offset=${safeOffset}, page=${this.currentPage}/${this.currentPageCount}`);
      }
    );
    return true;
  }

  private applyReadAloudHighlightToWeb(startOffset: number, endOffset: number, follow: boolean, progressOffset?: number): void {
    if (!this.ready) {
      return;
    }
    const safeStart = Math.max(0, Math.floor(startOffset));
    const safeEnd = Math.max(safeStart + 1, Math.floor(endOffset));
    const safeProgress = Math.max(safeStart, Math.min(safeEnd, Math.floor(progressOffset ?? safeStart)));
    const followLiteral = follow ? 'true' : 'false';
    this.runJs(
      `(function(){ if (window.__mnxApplyReadAloudHighlight) { return window.__mnxApplyReadAloudHighlight(${safeStart}, ${safeEnd}, ${followLiteral}, ${safeProgress}); } return ''; })();`,
      (resultRaw: string) => {
        const clean = this.parseWebViewJson(resultRaw);
        if (!clean || clean.trim().length <= 0) {
          return;
        }
        try {
          const result = SafeUtils.parseObj(clean) as EpubReadAloudHighlightResult;
          const pageCount = Math.max(1, Math.floor(Number(result.pageCount) || this.currentPageCount || 1));
          const pageIndex = Math.max(0, Math.min(pageCount - 1, Math.floor(Number(result.pageIndex) || 0)));
          if (follow && (pageIndex !== this.currentPage || pageCount !== this.currentPageCount)) {
            this.currentPage = pageIndex;
            this.currentPageCount = pageCount;
            this.lastPaginationOffset = Math.max(0, Number(result.offset) || 0);
            this.lastPaginationPageExtent = Math.max(0, Number(result.pageExtent) || 0);
            this.lastPaginationMaxOffset = Math.max(0, Number(result.maxOffset) || 0);
            this.lastProgressRatio = this.computeProgressRatio(
              this.currentPage,
              this.currentPageCount,
              this.lastPaginationOffset,
              this.lastPaginationMaxOffset
            );
            this.params.callbacks.onPageChange(
              this.currentPage,
              this.currentPageCount,
              EpubWebPageChangeSource.READ_ALOUD_FOLLOW
            );
            this.applyHighlightRangesToWeb('read_aloud_follow');
          }
          logger.debug(
            TAG,
            `EPUB Web 听书高亮完成: start=${safeStart}, end=${safeEnd}, progress=${safeProgress}, follow=${follow}, applied=${result.applied}`
          );
        } catch (error) {
          logger.warn(TAG, `EPUB Web 听书高亮结果解析失败: ${String(error)}`);
        }
      }
    );
  }

  private clearReadAloudHighlightFromWeb(): void {
    this.runJs('(function(){ return window.__mnxClearReadAloudHighlight ? window.__mnxClearReadAloudHighlight() : "ok"; })();');
  }

  private queryWebSelectionSnapshot(
    reason: string,
    onResult: (snapshot: EpubWebSelectionSnapshot | null) => void
  ): void {
    this.runJs(
      '(function(){ return window.__mnxReadSelectionSnapshot ? window.__mnxReadSelectionSnapshot() : ""; })();',
      (raw: string) => {
        const snapshot = this.parseWebSelectionSnapshot(raw);
        if (snapshot) {
          this.webSelectionSnapshot = snapshot;
          this.webSelectedText = snapshot.selectedText;
          logger.debug(
            TAG,
            `EPUB Web 选区快照更新: reason=${reason}, start=${snapshot.startOffset}, end=${snapshot.endOffset}, textLength=${snapshot.selectedText.length}`
          );
        }
        onResult(snapshot);
      }
    );
  }

  private scheduleWebSelectionSnapshotRefresh(reason: string): void {
    if (this.webSelectionRefreshTimer !== -1) {
      clearTimeout(this.webSelectionRefreshTimer);
      this.webSelectionRefreshTimer = -1;
    }
    this.webSelectionRefreshTimer = setTimeout(() => {
      this.webSelectionRefreshTimer = -1;
      this.queryWebSelectionSnapshot(reason, (_snapshot: EpubWebSelectionSnapshot | null) => {});
    }, 40);
  }

  private handleWebTextSelectionChange(selectionText: string): void {
    const safeText = selectionText ? selectionText.trim() : '';
    this.webSelectedText = safeText;
    if (safeText.length > 0) {
      this.scheduleWebSelectionSnapshotRefresh('selection_change');
    }
  }

  private clearWebSelectionState(): void {
    this.webSelectionSnapshot = null;
    this.webSelectedText = '';
    this.webSelectionActionInProgress = false;
  }

  private clearWebSelection(): void {
    this.runJs('(function(){ return window.__mnxClearWebSelection ? window.__mnxClearWebSelection() : "ok"; })();');
    this.clearWebSelectionState();
  }

  private handleWebSelectionMenuDisappear(): void {
    if (this.webSelectionActionInProgress) {
      return;
    }
    if (this.webSelectionRefreshTimer !== -1) {
      clearTimeout(this.webSelectionRefreshTimer);
    }
    this.webSelectionRefreshTimer = setTimeout(() => {
      this.webSelectionRefreshTimer = -1;
      if (!this.webSelectionActionInProgress) {
        this.clearWebSelection();
      }
    }, 120);
  }

  private withWebSelectionSnapshot(actionName: string, action: (snapshot: EpubWebSelectionSnapshot) => void): void {
    this.webSelectionActionInProgress = true;
    this.queryWebSelectionSnapshot(actionName, (snapshot: EpubWebSelectionSnapshot | null) => {
      const finalSnapshot = snapshot ?? this.webSelectionSnapshot;
      if (!finalSnapshot) {
        this.getUIContext().getPromptAction().showToast({ message: '未获取到有效选区', duration: 1500 });
        this.clearWebSelection();
        return;
      }
      action(finalSnapshot);
      this.clearWebSelection();
    });
  }

  private copyWebSelectedText(): void {
    const safeText = this.webSelectionSnapshot
      ? this.webSelectionSnapshot.selectedText
      : this.webSelectedText;
    if (safeText.trim().length > 0) {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, safeText);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData);
      this.getUIContext().getPromptAction().showToast({ message: '已复制', duration: 1500 });
    }
    this.clearWebSelection();
  }

  private async shareWebSelectedText(): Promise<void> {
    const safeText = this.webSelectionSnapshot
      ? this.webSelectionSnapshot.selectedText.trim()
      : this.webSelectedText.trim();
    if (safeText.length <= 0) {
      this.clearWebSelection();
      return;
    }

    try {
      const uiContext = this.resolveUiContext();
      const hostContext = uiContext ? uiContext.getHostContext() : null;
      if (!hostContext) {
        throw new Error('hostContext is null');
      }
      const abilityContext = hostContext as common.UIAbilityContext;
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: safeText,
        title: '文本分享',
        description: '来自阅读器的选中文本'
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      await controller.show(abilityContext, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
      logger.info(TAG, `EPUB Web 系统分享成功: textLength=${safeText.length}`);
    } catch (error) {
      logger.error(TAG, `EPUB Web 系统分享失败: ${String(error)}`);
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, safeText);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      systemPasteboard.setData(pasteData);
      this.getUIContext().getPromptAction().showToast({ message: '系统分享失败，已复制到剪贴板', duration: 1800 });
    } finally {
      this.clearWebSelection();
    }
  }

  private addWebHighlightFromSelection(withThought: boolean): void {
    this.withWebSelectionSnapshot(
      withThought ? 'highlight_with_thought' : 'highlight',
      (snapshot: EpubWebSelectionSnapshot) => {
        if (withThought) {
          this.preparePendingThoughtPopupBySelection(snapshot);
          if (this.params.callbacks.onAddHighlightWithThought) {
            this.params.callbacks.onAddHighlightWithThought(snapshot);
          }
          logger.info(
            TAG,
            `触发 EPUB Web“划线并添加想法”: start=${snapshot.startOffset}, end=${snapshot.endOffset}, textLength=${snapshot.selectedText.length}`
          );
        } else if (this.params.callbacks.onAddHighlight) {
          this.params.callbacks.onAddHighlight(snapshot);
          logger.info(
            TAG,
            `触发 EPUB Web 划线: start=${snapshot.startOffset}, end=${snapshot.endOffset}, textLength=${snapshot.selectedText.length}`
          );
        }
      }
    );
  }

  private addPurifyRuleFromWebSelection(): void {
    this.withWebSelectionSnapshot('add_purify_rule', (snapshot: EpubWebSelectionSnapshot) => {
      const pattern = snapshot.selectedText.trim();
      if (pattern.length <= 0) {
        this.getUIContext().getPromptAction().showToast({ message: '未获取到有效选区', duration: 1500 });
        return;
      }
      if (this.params.callbacks.onAddPurifyRule) {
        this.params.callbacks.onAddPurifyRule(pattern);
      }
      this.getUIContext().getPromptAction().showToast({ message: '已添加净化规则', duration: 1500 });
      logger.info(TAG, `触发 EPUB Web 添加净化规则: textLength=${pattern.length}`);
    });
  }

  private startReadAloudFromWebSelection(): void {
    this.withWebSelectionSnapshot('start_read_aloud', (snapshot: EpubWebSelectionSnapshot) => {
      if (!this.params.callbacks.onStartReadAloudFromCharIndex) {
        this.getUIContext().getPromptAction().showToast({ message: '听书功能未就绪', duration: 1500 });
        return;
      }
      const startOffset = Math.max(0, Math.floor(snapshot.startOffset));
      this.params.callbacks.onStartReadAloudFromCharIndex(startOffset);
      this.getUIContext().getPromptAction().showToast({ message: '已从所选句开始听书', duration: 1500 });
      logger.info(TAG, `触发 EPUB Web 从选区听书: start=${startOffset}, textLength=${snapshot.selectedText.length}`);
    });
  }

  private preparePendingThoughtPopupBySelection(snapshot: EpubWebSelectionSnapshot): void {
    this.pendingThoughtPopupStartOffset = snapshot.startOffset;
    this.pendingThoughtPopupEndOffset = snapshot.endOffset;
    this.pendingThoughtPopupQuoteText = snapshot.selectedText;
    this.pendingThoughtPopupRetryCount = 0;
    if (this.pendingThoughtPopupTimer !== -1) {
      clearTimeout(this.pendingThoughtPopupTimer);
      this.pendingThoughtPopupTimer = -1;
    }
  }

  private clearPendingThoughtPopupRequest(): void {
    this.pendingThoughtPopupStartOffset = -1;
    this.pendingThoughtPopupEndOffset = -1;
    this.pendingThoughtPopupQuoteText = '';
    this.pendingThoughtPopupRetryCount = 0;
    if (this.pendingThoughtPopupTimer !== -1) {
      clearTimeout(this.pendingThoughtPopupTimer);
      this.pendingThoughtPopupTimer = -1;
    }
  }

  private findHighlightRangeById(highlightId: string): EpubWebHighlightRange | null {
    for (let i = 0; i < this.epubHighlightRanges.length; i++) {
      const item = this.epubHighlightRanges[i];
      if (item.id === highlightId) {
        return item;
      }
    }
    return null;
  }

  private findPendingThoughtHighlightRange(): EpubWebHighlightRange | null {
    if (this.pendingThoughtPopupStartOffset < 0 || this.pendingThoughtPopupEndOffset <= this.pendingThoughtPopupStartOffset) {
      return null;
    }
    for (let i = 0; i < this.epubHighlightRanges.length; i++) {
      const item = this.epubHighlightRanges[i];
      if (Math.floor(item.startOffset) === this.pendingThoughtPopupStartOffset &&
        Math.floor(item.endOffset) === this.pendingThoughtPopupEndOffset) {
        return item;
      }
    }
    const quote = this.pendingThoughtPopupQuoteText.trim();
    if (quote.length <= 0) {
      return null;
    }
    for (let i = 0; i < this.epubHighlightRanges.length; i++) {
      const item = this.epubHighlightRanges[i];
      const itemQuote = (item.quoteText ?? '').trim();
      if (itemQuote === quote) {
        return item;
      }
    }
    return null;
  }

  private tryPresentPendingThoughtPopup(trigger: string): void {
    if (this.pendingThoughtPopupStartOffset < 0) {
      return;
    }
    const targetRange = this.findPendingThoughtHighlightRange();
    if (!targetRange) {
      if (this.pendingThoughtPopupRetryCount >= 8) {
        logger.warn(TAG, `自动展示 EPUB Web 划线想法悬浮窗失败: trigger=${trigger}`);
        this.clearPendingThoughtPopupRequest();
        return;
      }
      this.pendingThoughtPopupRetryCount += 1;
      if (this.pendingThoughtPopupTimer !== -1) {
        clearTimeout(this.pendingThoughtPopupTimer);
      }
      this.pendingThoughtPopupTimer = setTimeout(() => {
        this.pendingThoughtPopupTimer = -1;
        this.tryPresentPendingThoughtPopup(`retry_${this.pendingThoughtPopupRetryCount}`);
      }, 130);
      return;
    }
    this.showThoughtPopupForRange(targetRange, 0.5, 0.18, true);
    logger.info(TAG, `自动展示 EPUB Web 划线想法悬浮窗成功: trigger=${trigger}, highlightId=${targetRange.id}`);
    this.clearPendingThoughtPopupRequest();
  }

  private handleEpubHighlightTap(payloadJson: string): void {
    try {
      const clean = this.parseWebViewJson(payloadJson);
      const payload = SafeUtils.parseObj(clean) as EpubWebHighlightTapPayload;
      const highlightId = payload.id ?? '';
      const range = this.findHighlightRangeById(highlightId);
      if (!range) {
        logger.warn(TAG, `EPUB Web 划线点击未找到对应数据: highlightId=${highlightId}`);
        return;
      }
      this.showThoughtPopupForRange(
        range,
        this.clamp(Number(payload.xRatio) || 0.5, 0, 1),
        this.clamp(Number(payload.yRatio) || 0.18, 0, 1),
        false
      );
      this.suppressNextTapEvent = true;
      if (this.suppressNextTapResetTimer !== -1) {
        clearTimeout(this.suppressNextTapResetTimer);
      }
      this.suppressNextTapResetTimer = setTimeout(() => {
        this.suppressNextTapEvent = false;
        this.suppressNextTapResetTimer = -1;
      }, 160);
      logger.info(TAG, `点击 EPUB Web 划线文本，展示想法悬浮窗: highlightId=${highlightId}`);
    } catch (error) {
      logger.warn(TAG, `EPUB Web 划线点击解析失败: ${String(error)}`);
    }
  }

  private showThoughtPopupForRange(
    range: EpubWebHighlightRange,
    xRatio: number,
    yRatio: number,
    forceEditWhenEmpty: boolean
  ): void {
    const thoughtText = range.thoughtText ? range.thoughtText.trim() : '';
    const popupText = thoughtText.length > 0 ? thoughtText : '补充想法';
    this.highlightThoughtPopupHighlightId = range.id;
    this.highlightThoughtPopupColor = range.color && range.color.trim().length > 0 ? range.color : '#E8A317';
    this.highlightThoughtPopupLineType = range.lineType === HighlightLineType.WAVY
      ? HighlightLineType.WAVY
      : HighlightLineType.UNDERLINE;
    this.highlightThoughtPopupQuoteText = range.quoteText && range.quoteText.trim().length > 0
      ? range.quoteText
      : this.pendingThoughtPopupQuoteText;
    this.highlightThoughtPopupEditing = false;
    this.highlightThoughtPopupInputText = thoughtText;
    const anchorXVp = this.getAnimationViewportWidthVp() * xRatio;
    const anchorYVp = this.getAnimationViewportHeightVp() * yRatio;
    this.presentHighlightThoughtPopup(popupText, thoughtText.length <= 0, anchorXVp, anchorYVp);
    if (forceEditWhenEmpty && thoughtText.length <= 0) {
      setTimeout(() => {
        this.startHighlightThoughtPopupEdit();
      }, 60);
    }
  }

  private applyHighlightStyleFromPopup(lineType: HighlightLineType, color: string): void {
    const targetColor = color && color.trim().length > 0 ? color : '#E8A317';
    this.highlightThoughtPopupLineType = lineType;
    this.highlightThoughtPopupColor = targetColor;
    if (!this.highlightThoughtPopupHighlightId || this.highlightThoughtPopupHighlightId.length <= 0) {
      return;
    }
    if (this.params.callbacks.onUpdateHighlightStyle) {
      this.params.callbacks.onUpdateHighlightStyle(this.highlightThoughtPopupHighlightId, lineType, targetColor);
    }
    logger.info(
      TAG,
      `触发 EPUB Web 划线样式更新: highlightId=${this.highlightThoughtPopupHighlightId}, lineType=${lineType}, color=${targetColor}`
    );
  }

  private startHighlightThoughtPopupEdit(): void {
    this.highlightThoughtPopupInputText = this.highlightThoughtPopupIsPlaceholder ? '' : this.highlightThoughtPopupText;
    this.highlightThoughtPopupEditing = true;
  }

  private cancelHighlightThoughtPopupEdit(): void {
    this.highlightThoughtPopupEditing = false;
    this.highlightThoughtPopupInputText = this.highlightThoughtPopupIsPlaceholder ? '' : this.highlightThoughtPopupText;
  }

  private submitHighlightThoughtFromPopup(): void {
    if (!this.highlightThoughtPopupHighlightId || this.highlightThoughtPopupHighlightId.length <= 0) {
      logger.warn(TAG, '提交 EPUB Web 划线想法失败: highlightId 为空');
      return;
    }
    const nextThoughtText = this.highlightThoughtPopupInputText.trim();
    this.highlightThoughtPopupText = nextThoughtText.length > 0 ? nextThoughtText : '补充想法';
    this.highlightThoughtPopupIsPlaceholder = nextThoughtText.length <= 0;
    this.highlightThoughtPopupEditing = false;
    if (this.params.callbacks.onUpdateHighlightThought) {
      this.params.callbacks.onUpdateHighlightThought(this.highlightThoughtPopupHighlightId, nextThoughtText);
    }
    logger.info(
      TAG,
      `触发 EPUB Web 划线想法更新: highlightId=${this.highlightThoughtPopupHighlightId}, textLength=${nextThoughtText.length}`
    );
  }

  private presentHighlightThoughtPopup(text: string, isPlaceholder: boolean, anchorXVp: number, anchorYVp: number): void {
    this.highlightThoughtPopupText = text;
    this.highlightThoughtPopupIsPlaceholder = isPlaceholder;
    this.highlightThoughtPopupEditing = false;
    this.highlightThoughtPopupInputText = isPlaceholder ? '' : text;
    this.updateHighlightThoughtPopupPosition(anchorXVp, anchorYVp);
    this.showHighlightThoughtPopup = true;
    this.highlightThoughtPopupMaskOpacity = 0;
    this.highlightThoughtPopupOpacity = 0;
    this.highlightThoughtPopupScale = 0.88;
    this.highlightThoughtPopupTranslateY = 14;
    const ctx = this.resolveUiContext();
    if (ctx) {
      ctx.animateTo({ duration: 180, curve: curves.cubicBezierCurve(0.22, 0.92, 0.28, 1.08) }, () => {
        this.highlightThoughtPopupMaskOpacity = 1;
        this.highlightThoughtPopupOpacity = 1;
        this.highlightThoughtPopupScale = 1.04;
        this.highlightThoughtPopupTranslateY = -3;
      });
      this.highlightThoughtPopupTimer = setTimeout(() => {
        const nextCtx = this.resolveUiContext();
        if (nextCtx) {
          nextCtx.animateTo({ duration: 120, curve: curves.cubicBezierCurve(0.2, 0, 0.2, 1) }, () => {
            this.highlightThoughtPopupScale = 1;
            this.highlightThoughtPopupTranslateY = 0;
          });
        } else {
          this.highlightThoughtPopupScale = 1;
          this.highlightThoughtPopupTranslateY = 0;
        }
        this.highlightThoughtPopupTimer = -1;
      }, 170);
      return;
    }
    this.highlightThoughtPopupMaskOpacity = 1;
    this.highlightThoughtPopupOpacity = 1;
    this.highlightThoughtPopupScale = 1;
    this.highlightThoughtPopupTranslateY = 0;
  }

  private dismissHighlightThoughtPopup(): void {
    if (this.highlightThoughtPopupTimer !== -1) {
      clearTimeout(this.highlightThoughtPopupTimer);
      this.highlightThoughtPopupTimer = -1;
    }
    if (this.highlightThoughtPopupHideTimer !== -1) {
      clearTimeout(this.highlightThoughtPopupHideTimer);
      this.highlightThoughtPopupHideTimer = -1;
    }
    if (!this.showHighlightThoughtPopup) {
      return;
    }
    const ctx = this.resolveUiContext();
    if (ctx) {
      ctx.animateTo({ duration: 90, curve: curves.cubicBezierCurve(0.4, 0, 0.2, 1) }, () => {
        this.highlightThoughtPopupScale = 1.02;
        this.highlightThoughtPopupTranslateY = -2;
      });
      this.highlightThoughtPopupTimer = setTimeout(() => {
        const nextCtx = this.resolveUiContext();
        if (nextCtx) {
          nextCtx.animateTo({ duration: 170, curve: Curve.EaseIn }, () => {
            this.highlightThoughtPopupMaskOpacity = 0;
            this.highlightThoughtPopupOpacity = 0;
            this.highlightThoughtPopupScale = 0.9;
            this.highlightThoughtPopupTranslateY = 12;
          });
        } else {
          this.highlightThoughtPopupMaskOpacity = 0;
          this.highlightThoughtPopupOpacity = 0;
          this.highlightThoughtPopupScale = 0.9;
          this.highlightThoughtPopupTranslateY = 12;
        }
        this.highlightThoughtPopupHideTimer = setTimeout(() => {
          if (this.highlightThoughtPopupOpacity <= 0.01) {
            this.showHighlightThoughtPopup = false;
            this.highlightThoughtPopupQuoteText = '';
            this.highlightThoughtPopupEditing = false;
            this.highlightThoughtPopupInputText = '';
          }
          this.highlightThoughtPopupHideTimer = -1;
        }, 180);
        this.highlightThoughtPopupTimer = -1;
      }, 70);
      return;
    }
    this.showHighlightThoughtPopup = false;
    this.highlightThoughtPopupQuoteText = '';
    this.highlightThoughtPopupEditing = false;
    this.highlightThoughtPopupInputText = '';
  }

  private getHighlightThoughtPopupWidthVp(): number {
    const screenWidthVp = this.getAnimationViewportWidthVp();
    return Math.max(180, Math.min(300, screenWidthVp * 0.78));
  }

  private updateHighlightThoughtPopupPosition(anchorXVp: number, anchorYVp: number): void {
    const popupWidth = this.getHighlightThoughtPopupWidthVp();
    const estimatedHeight = 196;
    const horizontalMargin = 12;
    const verticalGap = 12;
    const minTop = Math.max(16, (this.params.contentSafeTopInset ?? 0) + 8);
    const screenWidth = this.getAnimationViewportWidthVp();
    const screenHeight = this.getAnimationViewportHeightVp();
    const maxLeft = Math.max(horizontalMargin, screenWidth - popupWidth - horizontalMargin);
    let left = anchorXVp - popupWidth / 2;
    if (left < horizontalMargin) {
      left = horizontalMargin;
    }
    if (left > maxLeft) {
      left = maxLeft;
    }

    let top = anchorYVp - estimatedHeight - verticalGap;
    if (top < minTop) {
      top = anchorYVp + verticalGap;
    }
    const maxTop = Math.max(minTop, screenHeight - estimatedHeight - 12);
    if (top > maxTop) {
      top = maxTop;
    }
    if (top < minTop) {
      top = minTop;
    }
    this.highlightThoughtPopupLeftVp = left;
    this.highlightThoughtPopupTopVp = top;
  }

  private buildController(): EpubWebViewReaderController {
    const self = this;
    return new EpubWebViewReaderControllerImpl(
      (
        spineFilePath: string,
        pageOffset: number,
        transitionDirection: EpubSpineTransitionDirection,
        anchorFragment: string,
        spineLayoutType: string,
        spineMediaType: string
      ): void => {
        const normalizedDirection = transitionDirection ?? 'none';
        if (normalizedDirection !== 'none' && !self.isPageTurnAnimating) {
          logger.info(
            TAG,
            `执行跨 spine 动画切换: direction=${normalizedDirection}, ready=${self.ready}, current=${self.currentPage}/${self.currentPageCount}, targetOffset=${pageOffset}`
          );
          self.performAnimatedSpineTransition(
            spineFilePath,
            pageOffset,
            normalizedDirection === 'next',
            anchorFragment,
            spineLayoutType,
            spineMediaType
          );
          return;
        }
        self.pendingSpineTransition = null;
        self.finishPageTurnAnimation();
        self.loadSpineItemImmediate(spineFilePath, pageOffset, anchorFragment, spineLayoutType, spineMediaType);
      },
      (forward: boolean): boolean => {
        if (!self.ready || self.isPageTurnAnimating || self.currentPageCount <= 1) {
          logger.debug(
            TAG,
            `翻页请求未执行: ready=${self.ready}, animating=${self.isPageTurnAnimating}, current=${self.currentPage}, total=${self.currentPageCount}, forward=${forward}, layout=${self.currentLayoutKind}`
          );
          return false;
        }
        const nextPage = forward ? self.currentPage + 1 : self.currentPage - 1;
        if (nextPage < 0 || nextPage >= self.currentPageCount) {
          logger.debug(
            TAG,
            `翻页越界，等待宿主切换 spine: current=${self.currentPage}, total=${self.currentPageCount}, forward=${forward}`
          );
          return false;
        }
        self.performAnimatedPageTurn(nextPage, forward);
        return true;
      },
      (forward: boolean, touchX: number, touchY: number): boolean => {
        return self.beginInteractiveCurl(forward, touchX, touchY);
      },
      (progress: number, touchX: number, touchY: number): void => {
        self.updateInteractiveCurl(progress, touchX, touchY);
      },
      (complete: boolean): boolean => {
        return self.endInteractiveCurl(complete);
      },
      (): void => {
        self.cancelInteractiveCurl();
      },
      (pageIndex: number): boolean => {
        return self.goToPageImmediate(pageIndex);
      },
      (anchorFragment: string): boolean => {
        return self.goToAnchorImmediate(anchorFragment);
      },
      (): number => {
        return self.currentPageCount;
      },
      (): number => {
        return self.currentPage;
      },
      (onResult: (snapshot: EpubWebTextSnapshot | null) => void): void => {
        self.queryCurrentTextSnapshotFromWeb(onResult);
      },
      (rules: EpubWebPurifyRulePayload[]): void => {
        self.applyPurifyRulesToWeb(rules);
      },
      (offset: number): boolean => {
        return self.seekToTextOffsetImmediate(offset);
      },
      (startOffset: number, endOffset: number, follow: boolean, progressOffset?: number): void => {
        self.applyReadAloudHighlightToWeb(startOffset, endOffset, follow, progressOffset);
      },
      (): void => {
        self.clearReadAloudHighlightFromWeb();
      },
      (settings: EBookReadingSettings): void => {
        self.activeTextSettings = self.cloneTextSettings(settings);
        self.viewportBackgroundColor = self.activeTextSettings.backgroundColor;
        self.configureUniversalAccessRoot(self.pendingSpinePath, 'controller_text_settings');
        logger.info(TAG, `控制器收到文本设置更新: ${self.describeTextSettings(self.activeTextSettings)}`);
        self.scheduleSettingsReapply('controller_text_settings');
      },
      (settings: MangaReadingSettings): void => {
        self.activePageSettings = self.normalizePageSettingsForEpub(settings);
        logger.info(TAG, `控制器收到翻页设置更新: ${self.describePageSettings(self.activePageSettings)}`);
        self.scheduleSettingsReapply('controller_page_settings');
      },
      (): boolean => {
        return self.ready && !self.isPageTurnAnimating;
      }
    );
  }

  @Builder
  private buildWebTextSelectionMenuWithSymbol() {
    Menu() {
      MenuItem({
        content: '复制',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.doc_text')).fontSize('18vp')
      })
        .onClick(() => {
          this.copyWebSelectedText();
        })
      MenuItem({
        content: '添加净化规则',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.slider_vertical_3')).fontSize('18vp')
      })
        .onClick(() => {
          this.addPurifyRuleFromWebSelection();
        })
      MenuItem({
        content: '开始听书',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.play_fill')).fontSize('18vp')
      })
        .onClick(() => {
          this.startReadAloudFromWebSelection();
        })
      if (this.enableEpubAnnotations) {
        MenuItem({
          content: '划线',
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.highlighter_line')).fontSize('18vp')
        })
          .onClick(() => {
            this.addWebHighlightFromSelection(false);
          })
        MenuItem({
          content: '划线并添加想法',
          symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.scribble')).fontSize('18vp')
        })
          .onClick(() => {
            this.addWebHighlightFromSelection(true);
          })
      }
      MenuItem({
        content: '分享',
        symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.arrowshape_turn_up_right')).fontSize('18vp')
      })
        .onClick(() => {
          void this.shareWebSelectedText();
        })
    }
    .radius(8)
    .backgroundColor($r('app.color.settings_panel_background'))
  }

  @Builder
  private buildHighlightThoughtPopupLayer() {
    if (this.showHighlightThoughtPopup) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(DialogSurfaceStyleHelper.getPopupMaskColor())
          .backgroundBlurStyle(
            DialogSurfaceStyleHelper.getPopupMaskBlurStyle(),
            DialogSurfaceStyleHelper.getPopupMaskBlurOptions()
          )
          .backgroundEffect(DialogSurfaceStyleHelper.getPopupMaskBackgroundEffect())
          .opacity(this.highlightThoughtPopupMaskOpacity)
          .clip(true)
          .zIndex(0)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.dismissHighlightThoughtPopup();
          })

        Column() {
          Row({ space: 10 }) {
            Column({ space: 8 }) {
              Button() {
                SymbolGlyph($r('sys.symbol.highlighter_line'))
                  .fontSize(16)
                  .fontColor([
                    this.highlightThoughtPopupLineType === HighlightLineType.UNDERLINE ? '#FFFFFF' : this.activeTextSettings.textColor
                  ])
              }
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor(
                this.highlightThoughtPopupLineType === HighlightLineType.UNDERLINE ? this.highlightThoughtPopupColor : '#1A000000'
              )
              .onClick(() => {
                this.applyHighlightStyleFromPopup(HighlightLineType.UNDERLINE, this.highlightThoughtPopupColor);
              })

              Button() {
                SymbolGlyph($r('sys.symbol.scribble'))
                  .fontSize(16)
                  .fontColor([
                    this.highlightThoughtPopupLineType === HighlightLineType.WAVY ? '#FFFFFF' : this.activeTextSettings.textColor
                  ])
              }
              .width(28)
              .height(28)
              .borderRadius(14)
              .backgroundColor(
                this.highlightThoughtPopupLineType === HighlightLineType.WAVY ? this.highlightThoughtPopupColor : '#1A000000'
              )
              .onClick(() => {
                this.applyHighlightStyleFromPopup(HighlightLineType.WAVY, this.highlightThoughtPopupColor);
              })

              ForEach(EPUB_HIGHLIGHT_POPUP_COLOR_OPTIONS, (colorItem: string) => {
                Button() {}
                  .width(18)
                  .height(18)
                  .borderRadius(9)
                  .backgroundColor(colorItem)
                  .border({
                    width: this.highlightThoughtPopupColor === colorItem ? 2 : 1,
                    color: this.highlightThoughtPopupColor === colorItem ? this.activeTextSettings.textColor : '#33000000'
                  })
                  .onClick(() => {
                    this.applyHighlightStyleFromPopup(this.highlightThoughtPopupLineType, colorItem);
                  })
              }, (colorItem: string) => colorItem)
            }
            .width(32)
            .alignItems(HorizontalAlign.Center)

            Column({ space: 8 }) {
              if (this.highlightThoughtPopupEditing) {
                TextInput({
                  text: this.highlightThoughtPopupInputText,
                  placeholder: '补充想法'
                })
                  .fontSize(14)
                  .fontColor(this.activeTextSettings.textColor)
                  .fontFamily(this.activeTextSettings.fontFamily)
                  .width('100%')
                  .onChange((value: string) => {
                    this.highlightThoughtPopupInputText = value;
                  })
                  .onSubmit(() => {
                    this.submitHighlightThoughtFromPopup();
                  })

                Row({ space: 8 }) {
                  Button('保存')
                    .fontSize(12)
                    .fontColor('#FFFFFF')
                    .backgroundColor('#2563EB')
                    .borderRadius(10)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .onClick(() => {
                      this.submitHighlightThoughtFromPopup();
                    })

                  Button('取消')
                    .fontSize(12)
                    .fontColor(this.activeTextSettings.textColor)
                    .backgroundColor('#1A000000')
                    .borderRadius(10)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .onClick(() => {
                      this.cancelHighlightThoughtPopupEdit();
                    })
                }
                .width('100%')
                .justifyContent(FlexAlign.End)
              } else {
                Text(this.highlightThoughtPopupText)
                  .fontSize(14)
                  .fontColor(this.highlightThoughtPopupIsPlaceholder ? '#777777' : this.activeTextSettings.textColor)
                  .lineHeight(20)
                  .maxLines(4)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontFamily(this.activeTextSettings.fontFamily)
                  .width('100%')
                  .onClick(() => {
                    this.startHighlightThoughtPopupEdit();
                  })
              }

              Column({ space: 6 }) {
                Text('当前划线内容（实时预览）')
                  .fontSize(11)
                  .fontColor('#777777')
                  .fontFamily(this.activeTextSettings.fontFamily)
                  .width('100%')

                if (this.highlightThoughtPopupQuoteText.trim().length > 0) {
                  Text() {
                    Span(this.highlightThoughtPopupQuoteText)
                      .decoration({ type: TextDecorationType.Underline, color: this.highlightThoughtPopupColor })
                      .textBackgroundStyle(
                        this.highlightThoughtPopupLineType === HighlightLineType.WAVY
                          ? { color: `${this.highlightThoughtPopupColor}33` }
                          : { color: '#00000000' }
                      )
                  }
                  .fontSize(13)
                  .fontColor(this.activeTextSettings.textColor)
                  .lineHeight(20)
                  .maxLines(4)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontFamily(this.activeTextSettings.fontFamily)
                  .width('100%')
                } else {
                  Text('暂无划线内容')
                    .fontSize(12)
                    .fontColor('#999999')
                    .fontFamily(this.activeTextSettings.fontFamily)
                    .width('100%')
                }
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 8, bottom: 8 })
              .borderRadius(8)
              .backgroundColor('#12000000')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width(this.getHighlightThoughtPopupWidthVp())
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(SettingsGlassStyleHelper.getSheetBackground())
        .backgroundBlurStyle(SettingsGlassStyleHelper.getSheetBlurStyle(), SettingsGlassStyleHelper.getSheetBlurOptions())
        .border({
          width: SettingsGlassStyleHelper.getSheetBorderWidth(),
          color: SettingsGlassStyleHelper.getSheetBorderColor()
        })
        .borderRadius(SettingsGlassStyleHelper.getSheetRadius())
        .shadow({
          radius: SettingsGlassStyleHelper.getSheetRadius() + 4,
          color: SettingsGlassStyleHelper.getSheetShadowColor(),
          offsetX: 0,
          offsetY: 6
        })
        .position({ x: this.highlightThoughtPopupLeftVp, y: this.highlightThoughtPopupTopVp })
        .opacity(this.highlightThoughtPopupOpacity)
        .scale({ x: this.highlightThoughtPopupScale, y: this.highlightThoughtPopupScale })
        .translate({ y: this.highlightThoughtPopupTranslateY })
        .hitTestBehavior(HitTestMode.Default)
        .zIndex(1)
      }
      .width('100%')
      .height('100%')
      .zIndex(80)
    }
  }

  private shouldRenderEpubCurlLayer(): boolean {
    return this.showEpubCurlSnapshotCover || this.showEpubCurlEffect;
  }

  @Builder
  private buildEpubCurlLayer() {
    Stack() {
      if (this.showEpubCurlSnapshotCover && this.epubCurlCurrentPixelMap !== null) {
        Image(this.epubCurlCurrentPixelMap as image.PixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Fill)
          .zIndex(this.epubCurlCanvasReady ? 1 : 4)
      }

      if (this.showEpubCurlEffect) {
        PageCurlEffectV2({
          currentPixelMap: null,
          nextPixelMap: null,
          currentPixelMapProvider: (): image.PixelMap | null => {
            return this.epubCurlCurrentPixelMap;
          },
          nextPixelMapProvider: (): image.PixelMap | null => {
            return this.epubCurlNextPixelMap;
          },
          componentWidth: this.getAnimationViewportWidthVp(),
          componentHeight: this.getAnimationViewportHeightVp(),
          imageDisplayX: 0,
          imageDisplayY: 0,
          imageDisplayWidth: this.getAnimationViewportWidthVp(),
          imageDisplayHeight: this.getAnimationViewportHeightVp(),
          config: this.epubCurlEffectConfig,
          isForward: this.epubCurlIsForward,
          curlStartPosition: this.epubCurlStartPosition,
          curlTouchX: this.epubCurlTouchX,
          curlTouchY: this.epubCurlTouchY,
          curlBackOpacity: this.activePageSettings.curlBackOpacity,
          externalProgress: this.epubCurlProgress,
          renderToken: this.epubCurlRenderToken,
          animateToTarget: this.epubCurlAnimateTarget,
          animateVelocity: this.epubCurlAnimateVelocity,
          canvasBackgroundColor: 'rgba(0,0,0,0)',
          retainBitmapsWhenSourceUnavailable: true,
          renderBackFaceContent: true,
          stabilizeReleaseMotion: true,
          onFirstFrameReady: () => {
            if (this.showEpubCurlEffect) {
              this.epubCurlCanvasReady = true;
            }
          },
          onAnimationComplete: () => {
            this.handleEpubCurlInternalAnimationComplete();
          }
        })
          .width('100%')
          .height('100%')
          .opacity(this.epubCurlCanvasReady ? 1 : 0)
          .zIndex(3)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .hitTestBehavior(HitTestMode.None)
    .zIndex(20)
  }

  build() {
    Stack() {
      Web({
        src: 'about:blank',
        controller: this.webviewController
      })
        .id(EPUB_WEBVIEW_CAPTURE_COMPONENT_ID)
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
          methodList: ['onPaginationChanged', 'onReaderTap', 'onReaderPan', 'onReaderSwipe', 'onEpubHighlightTap'],
          controller: this.webviewController
        })
        .onTextSelectionChange((selectionText: string) => {
          this.handleWebTextSelectionChange(selectionText);
        })
        .bindSelectionMenu(WebElementType.TEXT, this.buildWebTextSelectionMenuWithSymbol, WebResponseType.LONG_PRESS, {
          onAppear: () => {
            this.scheduleWebSelectionSnapshotRefresh('menu_appear');
          },
          onDisappear: () => {
            this.handleWebSelectionMenuDisappear();
          }
        })
        .onControllerAttached(() => {
          this.webControllerAttached = true;
          this.configureUniversalAccessRoot(this.pendingSpinePath, 'controller_attached');
          if (this.pendingSpinePath.length > 0) {
            this.loadSpineItemImmediate(this.pendingSpinePath, this.pendingPageOffset, this.pendingAnchorFragment);
          }
        })
        .transform(this.viewportMatrix)
        .opacity(this.hideWebViewForEpubCurlCapture ? 0 : this.viewportOpacity)
        .onPageBegin((event) => {
          const beginUrl: string = event?.url ? event.url : '';
          logger.debug(TAG, `WebView spine 开始加载: url=${beginUrl || 'empty'}, target=${this.lastLoadedFileUrl || 'none'}`);
        })
        .onPageEnd((event) => {
          const loadedUrl: string = event?.url ? event.url : '';
          if (this.handleAboutBlankPageEnd(loadedUrl)) {
            return;
          }
          this.clearAboutBlankReloadTimer();
          this.aboutBlankReloadCount = 0;
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
                  const dims = SafeUtils.parseObj(clean) as ViewportDims;
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
            logger.warn(
              TAG,
              `WebView load error: ${event.error.getErrorInfo()}, url=${this.lastLoadedFileUrl || 'none'}, accessRoots=${this.universalAccessRootSignature || 'none'}`
            );
          }
        })

      if (this.shouldRenderEpubCurlLayer()) {
        this.buildEpubCurlLayer()
      }

      this.buildHighlightThoughtPopupLayer()
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
