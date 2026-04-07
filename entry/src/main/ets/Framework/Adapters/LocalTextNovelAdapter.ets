import { EBook, EBookReadingSettings, DEFAULT_EBOOK_READING_SETTINGS, EBookPageMode } from '../../Models/EBookModels';
import {
  TextReaderSettings,
  DEFAULT_TEXT_READER_SETTINGS,
  TextReadingMode,
  TextPageTurnAnimation,
  BackgroundType,
  TextAlignment,
  SavedBackgroundImage
} from '../../Models/TextReaderModels';
import { NovelReaderPageParams } from '../../pages/NovelBookshelfPage';

export const LOCAL_TXT_NOVEL_SOURCE_ID: string = 'local_txt_ebook';
const LOCAL_TXT_NOVEL_BOOK_ID_PREFIX: string = 'local_txt_ebook_';

function cloneTextReaderSettings(settings: TextReaderSettings): TextReaderSettings {
  const savedBackgroundImages: SavedBackgroundImage[] = [];
  const sourceImages = settings.savedBackgroundImages ?? [];
  for (let i = 0; i < sourceImages.length; i++) {
    const item = sourceImages[i];
    const savedImage: SavedBackgroundImage = {
      path: item.path,
      addTime: item.addTime
    };
    savedBackgroundImages.push(savedImage);
  }

  return {
    readingMode: settings.readingMode,
    readingDirection: settings.readingDirection,
    pageTurnAnimation: settings.pageTurnAnimation,
    background: {
      type: settings.background.type,
      color: settings.background.color,
      imagePath: settings.background.imagePath,
      imageOpacity: settings.background.imageOpacity,
      gradientStart: settings.background.gradientStart,
      gradientEnd: settings.background.gradientEnd,
      gradientAngle: settings.background.gradientAngle
    },
    savedBackgroundImages: savedBackgroundImages,
    textStyle: {
      fontSize: settings.textStyle.fontSize,
      lineHeight: settings.textStyle.lineHeight,
      paragraphSpacing: settings.textStyle.paragraphSpacing,
      firstLineIndent: settings.textStyle.firstLineIndent,
      letterSpacing: settings.textStyle.letterSpacing,
      textColor: settings.textStyle.textColor,
      fontWeight: settings.textStyle.fontWeight,
      fontFamily: settings.textStyle.fontFamily,
      fontPath: settings.textStyle.fontPath,
      textAlignment: settings.textStyle.textAlignment
    },
    pageMargins: {
      top: settings.pageMargins.top,
      bottom: settings.pageMargins.bottom,
      left: settings.pageMargins.left,
      right: settings.pageMargins.right
    },
    keepScreenOn: settings.keepScreenOn,
    showPageNumber: settings.showPageNumber,
    showProgress: settings.showProgress,
    showTime: settings.showTime,
    showBattery: settings.showBattery,
    tapToTurn: settings.tapToTurn,
    volumeKeyNavigation: settings.volumeKeyNavigation,
    autoScrollSpeed: settings.autoScrollSpeed,
    autoPageTurnEnabled: settings.autoPageTurnEnabled,
    autoPageTurnInterval: settings.autoPageTurnInterval,
    curlBackOpacity: settings.curlBackOpacity,
    readAloud: settings.readAloud
  };
}

function toTextAlignment(value: string | undefined, fallback: TextAlignment): TextAlignment {
  if (value === TextAlignment.LEFT || value === TextAlignment.CENTER ||
      value === TextAlignment.RIGHT || value === TextAlignment.JUSTIFY) {
    return value;
  }
  return fallback;
}

function toPageTurnAnimation(value: string | undefined, fallback: TextPageTurnAnimation): TextPageTurnAnimation {
  if (value === TextPageTurnAnimation.NONE || value === TextPageTurnAnimation.SLIDE ||
      value === TextPageTurnAnimation.CURL || value === TextPageTurnAnimation.FADE) {
    return value;
  }
  return fallback;
}

function resolveOptionalNumber(value: number | undefined, fallback: number): number {
  return value !== undefined ? value : fallback;
}

function resolveOptionalString(value: string | undefined, fallback: string): string {
  return value !== undefined ? value : fallback;
}

function resolveOptionalBoolean(value: boolean | undefined, fallback: boolean): boolean {
  return value !== undefined ? value : fallback;
}

function buildComparableEBookReadingSettings(settings: EBookReadingSettings): EBookReadingSettings {
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
    letterSpacing: resolveOptionalNumber(settings.letterSpacing, DEFAULT_TEXT_READER_SETTINGS.textStyle.letterSpacing),
    paragraphSpacing: resolveOptionalNumber(settings.paragraphSpacing, DEFAULT_TEXT_READER_SETTINGS.textStyle.paragraphSpacing),
    firstLineIndent: resolveOptionalNumber(settings.firstLineIndent, DEFAULT_TEXT_READER_SETTINGS.textStyle.firstLineIndent),
    textAlignment: resolveOptionalString(settings.textAlignment, DEFAULT_TEXT_READER_SETTINGS.textStyle.textAlignment),
    pageTurnAnimation: resolveOptionalString(settings.pageTurnAnimation, DEFAULT_TEXT_READER_SETTINGS.pageTurnAnimation),
    tapToTurn: resolveOptionalBoolean(settings.tapToTurn, DEFAULT_TEXT_READER_SETTINGS.tapToTurn),
    volumeKeyNavigation: resolveOptionalBoolean(settings.volumeKeyNavigation, DEFAULT_TEXT_READER_SETTINGS.volumeKeyNavigation),
    keepScreenOn: resolveOptionalBoolean(settings.keepScreenOn, DEFAULT_TEXT_READER_SETTINGS.keepScreenOn),
    showPageNumber: resolveOptionalBoolean(settings.showPageNumber, DEFAULT_TEXT_READER_SETTINGS.showPageNumber),
    showProgress: resolveOptionalBoolean(settings.showProgress, DEFAULT_TEXT_READER_SETTINGS.showProgress),
    showTime: resolveOptionalBoolean(settings.showTime, DEFAULT_TEXT_READER_SETTINGS.showTime),
    showBattery: resolveOptionalBoolean(settings.showBattery, DEFAULT_TEXT_READER_SETTINGS.showBattery),
    backgroundType: resolveOptionalString(settings.backgroundType, DEFAULT_TEXT_READER_SETTINGS.background.type),
    backgroundImagePath: resolveOptionalString(settings.backgroundImagePath, ''),
    backgroundImageOpacity: resolveOptionalNumber(
      settings.backgroundImageOpacity,
      DEFAULT_TEXT_READER_SETTINGS.background.imageOpacity ?? 1.0
    )
  };
}

const DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS: EBookReadingSettings =
  buildComparableEBookReadingSettings(DEFAULT_EBOOK_READING_SETTINGS);

export function buildLocalTextNovelBookId(ebookId: string): string {
  return `${LOCAL_TXT_NOVEL_BOOK_ID_PREFIX}${ebookId}`;
}

export function isLocalTxtNovelReaderSource(sourceId: string): boolean {
  return sourceId === LOCAL_TXT_NOVEL_SOURCE_ID;
}

export function hasCustomLocalTextNovelReadingSettings(
  ebookSettings: EBookReadingSettings | null | undefined
): boolean {
  if (!ebookSettings) {
    return false;
  }

  const comparable = buildComparableEBookReadingSettings(ebookSettings);
  return comparable.fontSize !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.fontSize
    || comparable.fontFamily !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.fontFamily
    || comparable.fontPath !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.fontPath
    || comparable.fontWeight !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.fontWeight
    || comparable.lineHeight !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.lineHeight
    || comparable.backgroundColor !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.backgroundColor
    || comparable.textColor !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.textColor
    || comparable.themeBgImage !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.themeBgImage
    || comparable.nightMode !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.nightMode
    || comparable.followSystemTheme !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.followSystemTheme
    || comparable.pageMargin !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.pageMargin
    || comparable.pageMode !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.pageMode
    || comparable.brightness !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.brightness
    || comparable.autoSave !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.autoSave
    || comparable.saveInterval !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.saveInterval
    || comparable.letterSpacing !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.letterSpacing
    || comparable.paragraphSpacing !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.paragraphSpacing
    || comparable.firstLineIndent !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.firstLineIndent
    || comparable.textAlignment !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.textAlignment
    || comparable.pageTurnAnimation !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.pageTurnAnimation
    || comparable.tapToTurn !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.tapToTurn
    || comparable.volumeKeyNavigation !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.volumeKeyNavigation
    || comparable.keepScreenOn !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.keepScreenOn
    || comparable.showPageNumber !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.showPageNumber
    || comparable.showProgress !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.showProgress
    || comparable.showTime !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.showTime
    || comparable.showBattery !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.showBattery
    || comparable.backgroundType !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.backgroundType
    || comparable.backgroundImagePath !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.backgroundImagePath
    || comparable.backgroundImageOpacity !== DEFAULT_LOCAL_TXT_EBOOK_READING_SETTINGS.backgroundImageOpacity;
}

export function buildNovelReaderParamsFromTxtEBook(ebook: EBook, coverComponentId?: string): NovelReaderPageParams {
  const totalChapters = Math.max(ebook.chapters.length, 1);
  const preferredChapterIndex = Math.max(0, Math.min(
    ebook.readingProgress?.currentChapterIndex ?? 0,
    totalChapters - 1
  ));
  const chapter = ebook.chapters[preferredChapterIndex];
  const chapterUrl = chapter?.id || `local_txt_chapter_${preferredChapterIndex}`;
  const chapterTitle = chapter?.title || `Chapter ${preferredChapterIndex + 1}`;
  const currentPageIndex = Math.max(0, ebook.readingProgress?.currentPosition ?? 0);

  return {
    sourceId: LOCAL_TXT_NOVEL_SOURCE_ID,
    bookUrl: `ebook://${ebook.id}`,
    bookName: ebook.metadata?.title || 'Imported TXT',
    chapterUrl: chapterUrl,
    chapterTitle: chapterTitle,
    chapterIndex: preferredChapterIndex,
    totalChapters: totalChapters,
    chapterPageIndex: currentPageIndex,
    tocUrl: ebook.filePath || `ebook://${ebook.id}`,
    author: ebook.metadata?.author || '',
    coverUrl: ebook.metadata?.coverImagePath || '',
    sourceName: 'Local TXT',
    coverComponentId: coverComponentId,
    localEbookId: ebook.id
  };
}

export function buildTextReaderSettingsFromEBookSettings(
  ebookSettings: EBookReadingSettings | null | undefined,
  fallback: TextReaderSettings = DEFAULT_TEXT_READER_SETTINGS
): TextReaderSettings {
  const base = cloneTextReaderSettings(fallback);
  if (!ebookSettings) {
    return base;
  }

  base.textStyle.fontSize = ebookSettings.fontSize || base.textStyle.fontSize;
  base.textStyle.lineHeight = ebookSettings.lineHeight || base.textStyle.lineHeight;
  base.textStyle.fontWeight = ebookSettings.fontWeight || base.textStyle.fontWeight;
  base.textStyle.letterSpacing = ebookSettings.letterSpacing ?? base.textStyle.letterSpacing;
  base.textStyle.paragraphSpacing = ebookSettings.paragraphSpacing ?? base.textStyle.paragraphSpacing;
  base.textStyle.firstLineIndent = ebookSettings.firstLineIndent ?? base.textStyle.firstLineIndent;
  base.textStyle.textColor = ebookSettings.textColor || base.textStyle.textColor;
  base.textStyle.fontFamily = ebookSettings.fontFamily || base.textStyle.fontFamily;
  base.textStyle.fontPath = ebookSettings.fontPath || base.textStyle.fontPath;
  base.textStyle.textAlignment = toTextAlignment(
    ebookSettings.textAlignment,
    base.textStyle.textAlignment
  );

  base.background.type = ebookSettings.backgroundType === BackgroundType.IMAGE
    ? BackgroundType.IMAGE
    : BackgroundType.COLOR;
  base.background.color = ebookSettings.backgroundColor || base.background.color;
  base.background.imagePath = ebookSettings.backgroundImagePath || base.background.imagePath;
  base.background.imageOpacity = ebookSettings.backgroundImageOpacity ?? base.background.imageOpacity;

  const safeMargin = Math.max(0, Math.round(ebookSettings.pageMargin ?? base.pageMargins.left));
  base.pageMargins.left = safeMargin;
  base.pageMargins.right = safeMargin;

  base.pageTurnAnimation = toPageTurnAnimation(
    ebookSettings.pageTurnAnimation,
    base.pageTurnAnimation
  );
  base.tapToTurn = ebookSettings.tapToTurn ?? base.tapToTurn;
  base.volumeKeyNavigation = ebookSettings.volumeKeyNavigation ?? base.volumeKeyNavigation;
  base.keepScreenOn = ebookSettings.keepScreenOn ?? base.keepScreenOn;
  base.showPageNumber = ebookSettings.showPageNumber ?? base.showPageNumber;
  base.showProgress = ebookSettings.showProgress ?? base.showProgress;
  base.showTime = ebookSettings.showTime ?? base.showTime;
  base.showBattery = ebookSettings.showBattery ?? base.showBattery;

  if (ebookSettings.pageMode === EBookPageMode.HORIZONTAL && base.readingMode === TextReadingMode.DUAL_PAGE) {
    base.readingMode = TextReadingMode.PAGE;
  }

  return base;
}

export function syncTextReaderSettingsToEBookSettings(
  settings: TextReaderSettings,
  current: EBookReadingSettings | null | undefined
): EBookReadingSettings {
  const source = current ?? DEFAULT_EBOOK_READING_SETTINGS;
  const next: EBookReadingSettings = {
    fontSize: source.fontSize,
    fontFamily: source.fontFamily,
    fontPath: source.fontPath,
    fontWeight: source.fontWeight,
    lineHeight: source.lineHeight,
    backgroundColor: source.backgroundColor,
    textColor: source.textColor,
    themeBgImage: source.themeBgImage,
    nightMode: source.nightMode,
    followSystemTheme: source.followSystemTheme,
    pageMargin: source.pageMargin,
    pageMode: source.pageMode,
    brightness: source.brightness,
    autoSave: source.autoSave,
    saveInterval: source.saveInterval,
    letterSpacing: source.letterSpacing,
    paragraphSpacing: source.paragraphSpacing,
    firstLineIndent: source.firstLineIndent,
    textAlignment: source.textAlignment,
    pageTurnAnimation: source.pageTurnAnimation,
    tapToTurn: source.tapToTurn,
    volumeKeyNavigation: source.volumeKeyNavigation,
    keepScreenOn: source.keepScreenOn,
    showPageNumber: source.showPageNumber,
    showProgress: source.showProgress,
    showTime: source.showTime,
    showBattery: source.showBattery,
    backgroundType: source.backgroundType,
    backgroundImagePath: source.backgroundImagePath,
    backgroundImageOpacity: source.backgroundImageOpacity
  };

  next.fontSize = settings.textStyle.fontSize;
  next.fontFamily = settings.textStyle.fontFamily;
  next.fontPath = settings.textStyle.fontPath || '';
  next.fontWeight = settings.textStyle.fontWeight;
  next.lineHeight = settings.textStyle.lineHeight;
  next.backgroundColor = settings.background.color || '#F5F0E1';
  next.textColor = settings.textStyle.textColor;
  next.pageMargin = Math.max(0, Math.round(settings.pageMargins.left));
  next.letterSpacing = settings.textStyle.letterSpacing;
  next.paragraphSpacing = settings.textStyle.paragraphSpacing;
  next.firstLineIndent = settings.textStyle.firstLineIndent;
  next.textAlignment = settings.textStyle.textAlignment;
  next.pageTurnAnimation = settings.pageTurnAnimation;
  next.tapToTurn = settings.tapToTurn;
  next.volumeKeyNavigation = settings.volumeKeyNavigation;
  next.keepScreenOn = settings.keepScreenOn;
  next.showPageNumber = settings.showPageNumber;
  next.showProgress = settings.showProgress;
  next.showTime = settings.showTime;
  next.showBattery = settings.showBattery;
  next.backgroundType = settings.background.type;
  next.backgroundImagePath = settings.background.imagePath || '';
  next.backgroundImageOpacity = settings.background.imageOpacity ?? 1;
  next.pageMode = settings.readingMode === TextReadingMode.PAGE &&
    settings.pageTurnAnimation === TextPageTurnAnimation.CURL
    ? EBookPageMode.SIMULATION
    : EBookPageMode.HORIZONTAL;
  next.followSystemTheme = false;

  return next;
}
