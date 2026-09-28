/**
 * EPUB CSS 构建器
 * 从 EpubWebViewReaderComponent 提取的纯函数工具类
 * 负责生成所有注入 WebView 的 CSS 样式
 */

import {
  EBookReadingSettings
} from 'manxia_core/src/main/ets/Models/EBookModels';
import {
  ReadingSettings as MangaReadingSettings,
  ReadingMode,
  DoublePagePortraitLayout
} from 'manxia_core/src/main/ets/Models/MangaModels';

export type EpubPageLayoutKind =
  'horizontal_paged' |
  'vertical_paged' |
  'double_page' |
  'continuous_horizontal' |
  'continuous_vertical';

export interface CssBuilderViewportState {
  hostWidthVp: number;
  hostHeightVp: number;
  fallbackVpW: number;
  fallbackVpH: number;
  lastVisualVpW: number;
  lastVisualVpH: number;
  contentSafeTopInset: number;
  isFixedLayout: boolean;
  isCurrentSpineImageLike: boolean;
}

export class EpubCssBuilder {

  static clamp(value: number, min: number, max: number): number {
    const normalized = isNaN(value) ? min : value;
    return Math.max(min, Math.min(max, normalized));
  }

  static toRgba(color: string, alpha: number): string {
    const normalizedAlpha = EpubCssBuilder.clamp(alpha, 0, 1);
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

  static normalizeFileUrl(rawPath: string): string {
    const trimmed = rawPath.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    const normalized = trimmed.replace(/\\/g, '/');
    if (normalized.startsWith('file://')) {
      return `file://${EpubCssBuilder.encodeFilePathForUrl(normalized.substring('file://'.length))}`;
    }
    if (/^[A-Za-z]:\//.test(normalized)) {
      return `file:///${EpubCssBuilder.encodeFilePathForUrl(normalized)}`;
    }
    if (normalized.startsWith('/')) {
      return `file://${EpubCssBuilder.encodeFilePathForUrl(normalized)}`;
    }
    return EpubCssBuilder.encodeFilePathForUrl(normalized);
  }

  static encodeFilePathForUrl(filePath: string): string {
    const normalizedPath = filePath.replace(/\\/g, '/');
    const segments = normalizedPath.split('/');
    const encodedSegments: string[] = [];
    for (let i = 0; i < segments.length; i++) {
      const segment = segments[i];
      if (segment.length <= 0) {
        encodedSegments.push(segment);
        continue;
      }
      let decodedSegment = segment;
      try {
        decodedSegment = decodeURIComponent(segment);
      } catch (_error) {
        decodedSegment = segment;
      }
      if (i === 0 && /^[A-Za-z]:$/.test(decodedSegment)) {
        encodedSegments.push(decodedSegment);
      } else {
        encodedSegments.push(encodeURIComponent(decodedSegment));
      }
    }
    return encodedSegments.join('/');
  }

  static resolveTextAlignment(value: string | undefined): string {
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

  static getViewportScale(vpW: number, vpH: number, vpState: CssBuilderViewportState): number {
    const baseW = vpState.lastVisualVpW > 0 ? vpState.lastVisualVpW : (vpState.fallbackVpW > 0 ? vpState.fallbackVpW : vpW);
    const baseH = vpState.lastVisualVpH > 0 ? vpState.lastVisualVpH : (vpState.fallbackVpH > 0 ? vpState.fallbackVpH : vpH);
    const scaleW = baseW > 0 ? vpW / baseW : 1;
    const scaleH = baseH > 0 ? vpH / baseH : 1;
    const safeScaleW = isNaN(scaleW) || scaleW <= 0 ? 1 : scaleW;
    const safeScaleH = isNaN(scaleH) || scaleH <= 0 ? 1 : scaleH;
    return EpubCssBuilder.clamp(Math.min(safeScaleW, safeScaleH), 1, 4);
  }

  static getCssPxPerHostVp(vpW: number, vpH: number, vpState: CssBuilderViewportState): number {
    const hostW = vpState.hostWidthVp > 1 ? vpState.hostWidthVp : vpState.fallbackVpW;
    const hostH = vpState.hostHeightVp > 1 ? vpState.hostHeightVp : vpState.fallbackVpH;
    const scaleW = hostW > 0 ? vpW / hostW : 1;
    const scaleH = hostH > 0 ? vpH / hostH : 1;
    const safeScaleW = isNaN(scaleW) || scaleW <= 0 ? 1 : scaleW;
    const safeScaleH = isNaN(scaleH) || scaleH <= 0 ? 1 : scaleH;
    return EpubCssBuilder.clamp(Math.min(safeScaleW, safeScaleH), 1, 4);
  }

  static getContentSafeTopInsetCssPx(vpW: number, vpH: number, vpState: CssBuilderViewportState): number {
    const safeTopInsetVp = vpState.contentSafeTopInset;
    return EpubCssBuilder.clamp(safeTopInsetVp * EpubCssBuilder.getCssPxPerHostVp(vpW, vpH, vpState), 0, 480);
  }

  static isContinuousVerticalMode(settings: MangaReadingSettings): boolean {
    return settings.readingMode === ReadingMode.WEBTOON ||
      settings.readingMode === ReadingMode.WEBTOON_WITH_GAP ||
      settings.readingMode === ReadingMode.CONTINUOUS_VERTICAL;
  }

  static isContinuousHorizontalMode(_settings: MangaReadingSettings): boolean {
    return false;
  }

  static isContinuousMode(settings: MangaReadingSettings): boolean {
    return EpubCssBuilder.isContinuousVerticalMode(settings) || EpubCssBuilder.isContinuousHorizontalMode(settings);
  }

  static getLayoutKind(settings: MangaReadingSettings, vpW: number, vpH: number): EpubPageLayoutKind {
    if (EpubCssBuilder.isContinuousVerticalMode(settings)) {
      return 'continuous_vertical';
    }
    if (EpubCssBuilder.isContinuousHorizontalMode(settings)) {
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

  static buildFontCss(textSettings: EBookReadingSettings): string {
    const fontPath = (textSettings.fontPath ?? '').trim();
    if (fontPath.length <= 0) {
      return '';
    }
    const fontUrl = EpubCssBuilder.normalizeFileUrl(fontPath);
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

  static resolveFontFamily(textSettings: EBookReadingSettings): string {
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

  static buildBackgroundCss(textSettings: EBookReadingSettings): string {
    const backgroundType = (textSettings.backgroundType ?? 'COLOR').trim().toUpperCase();
    const backgroundImagePath = (textSettings.backgroundImagePath ?? '').trim();
    if (backgroundType !== 'IMAGE' || backgroundImagePath.length <= 0) {
      return '';
    }
    const backgroundUrl = EpubCssBuilder.normalizeFileUrl(backgroundImagePath);
    if (backgroundUrl.length <= 0) {
      return '';
    }
    const opacity = EpubCssBuilder.clamp(textSettings.backgroundImageOpacity ?? 0.3, 0, 1);
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

  static buildReflowCss(
    vpW: number,
    vpH: number,
    textSettings: EBookReadingSettings,
    pageSettings: MangaReadingSettings,
    vpState: CssBuilderViewportState
  ): string {
    const layoutKind = EpubCssBuilder.getLayoutKind(pageSettings, vpW, vpH);
    const viewportScale = EpubCssBuilder.getViewportScale(vpW, vpH, vpState);
    const sideMargin = EpubCssBuilder.clamp((textSettings.pageMargin ?? 16) * viewportScale, 0, 240);
    const userTopMargin = EpubCssBuilder.clamp(
      (textSettings.pageTopMargin ?? textSettings.pageMargin ?? 24) * viewportScale,
      0,
      240
    );
    const safeTopInset = EpubCssBuilder.getContentSafeTopInsetCssPx(vpW, vpH, vpState);
    const topMargin = EpubCssBuilder.clamp(userTopMargin + safeTopInset, 0, 360);
    const rawBottomMargin = EpubCssBuilder.clamp(
      (textSettings.pageBottomMargin ?? textSettings.pageMargin ?? 24) * viewportScale,
      0,
      240
    );
    const fontSize = EpubCssBuilder.clamp((textSettings.fontSize ?? 18) * viewportScale, 10, 160);
    const lineHeight = EpubCssBuilder.clamp(textSettings.lineHeight ?? 1.8, 1.0, 3.2);
    const fontWeight = EpubCssBuilder.clamp(textSettings.fontWeight ?? 400, 100, 900);
    const letterSpacing = EpubCssBuilder.clamp((textSettings.letterSpacing ?? 0) * viewportScale, -8, 24);
    const paragraphSpacing = EpubCssBuilder.clamp((textSettings.paragraphSpacing ?? 8) * viewportScale, 0, 120);
    const firstLineIndent = EpubCssBuilder.clamp(textSettings.firstLineIndent ?? 0, 0, 8);
    const showBottomInfo = !vpState.isCurrentSpineImageLike && (
      textSettings.showPageNumber !== false ||
      (textSettings.showProgress ?? false) ||
      textSettings.showTime !== false ||
      (textSettings.showBattery ?? false)
    );
    const bottomInfoHeight = showBottomInfo ? EpubCssBuilder.clamp(28 * viewportScale, 0, 72) : 0;
    const bottomMargin = rawBottomMargin + bottomInfoHeight;
    const backgroundColor = textSettings.backgroundColor ?? '#FFFFFF';
    const textColor = textSettings.textColor ?? '#000000';
    const bodyOverlayColor = (textSettings.backgroundType ?? 'COLOR').trim().toUpperCase() === 'IMAGE'
      ? EpubCssBuilder.toRgba(backgroundColor, 0.9)
      : backgroundColor;
    const webtoonLeftMargin = EpubCssBuilder.isContinuousVerticalMode(pageSettings)
      ? EpubCssBuilder.clamp(pageSettings.webtoonLeftMargin ?? 0, 0, 50)
      : 0;
    const webtoonRightMargin = EpubCssBuilder.isContinuousVerticalMode(pageSettings)
      ? EpubCssBuilder.clamp(pageSettings.webtoonRightMargin ?? 0, 0, 50)
      : 0;
    const leftPadding = sideMargin + (EpubCssBuilder.isContinuousVerticalMode(pageSettings) ? (vpW * webtoonLeftMargin / 100) : 0);
    const rightPadding = sideMargin + (EpubCssBuilder.isContinuousVerticalMode(pageSettings) ? (vpW * webtoonRightMargin / 100) : 0);
    const contentW = Math.max(1, vpW - leftPadding - rightPadding);
    const contentH = Math.max(1, vpH - topMargin - bottomMargin);
    const inlineMediaMaxWidth = Math.max(24, Math.min(contentW, vpW * 0.4));
    const columnCount = layoutKind === 'double_page' ? 2 : 1;
    const pageGap = leftPadding + rightPadding;
    const columnWidth = Math.max(1, (vpW - columnCount * pageGap) / columnCount);
    const fontCss = EpubCssBuilder.buildFontCss(textSettings);
    const fontFamily = EpubCssBuilder.resolveFontFamily(textSettings);
    const backgroundCss = EpubCssBuilder.buildBackgroundCss(textSettings);
    const textAlign = EpubCssBuilder.resolveTextAlignment(textSettings.textAlignment);
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

    const textInheritanceCss = `
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

    const footnoteCss = `
      .mnx-footnote-ref {
        color: ${textColor} !important;
        font-size: 0.72em !important;
        line-height: 1 !important;
        vertical-align: super !important;
        text-indent: 0 !important;
        margin: 0 0.06em !important;
        padding: 0 0.08em !important;
        text-decoration: none !important;
      }
      .mnx-footnote-ref::after {
        content: attr(data-mnx-footnote-marker);
      }
      .mnx-footnote-ref[data-mnx-has-visible-marker='true']::after {
        content: '';
      }
      .mnx-footnote-anchor {
        scroll-margin-top: ${topMargin + 8}px !important;
        scroll-margin-bottom: ${bottomMargin + 8}px !important;
      }
      .mnx-footnote-body-hidden {
        display: none !important;
      }
      #__mnx_footnote_layer {
        position: fixed !important;
        left: ${leftPadding}px !important;
        right: ${rightPadding}px !important;
        bottom: ${Math.max(4, Math.floor(rawBottomMargin + bottomInfoHeight * 0.25))}px !important;
        max-height: ${Math.max(56, Math.floor(contentH * 0.28))}px !important;
        overflow: hidden !important;
        z-index: 2147483647 !important;
        box-sizing: border-box !important;
        padding: 0.35em 0 0 !important;
        border-top: 1px solid ${EpubCssBuilder.toRgba(textColor, 0.32)} !important;
        background: ${EpubCssBuilder.toRgba(backgroundColor, 0.94)} !important;
        color: ${textColor} !important;
        font-size: 0.78rem !important;
        line-height: 1.35 !important;
        letter-spacing: ${letterSpacing}px !important;
        text-align: left !important;
        pointer-events: none !important;
      }
      #__mnx_footnote_layer[data-mnx-visible='false'] {
        display: none !important;
      }
      #__mnx_footnote_layer .mnx-footnote-row {
        display: flex !important;
        align-items: flex-start !important;
        gap: 0.35em !important;
        margin: 0 0 0.25em 0 !important;
        padding: 0 !important;
        text-indent: 0 !important;
        color: ${textColor} !important;
        font-size: inherit !important;
        line-height: inherit !important;
      }
      #__mnx_footnote_layer .mnx-footnote-num {
        flex: 0 0 auto !important;
        min-width: 1.8em !important;
        text-align: right !important;
        font-size: inherit !important;
      }
      #__mnx_footnote_layer .mnx-footnote-text {
        flex: 1 1 auto !important;
        min-width: 0 !important;
        font-size: inherit !important;
      }
    `;

    const imageLikeDocumentCss = `
      html[data-mnx-content-kind='image_like'] body,
      html[data-mnx-content-kind='image_like'] body * {
        box-sizing: border-box !important;
      }
      html[data-mnx-content-kind='image_like'] body > * {
        width: 100% !important;
        height: 100% !important;
        max-width: 100% !important;
        max-height: 100% !important;
        margin: 0 auto !important;
        flex: 1 1 auto !important;
        overflow: hidden !important;
      }
      html[data-mnx-content-kind='image_like'] body > div,
      html[data-mnx-content-kind='image_like'] body > figure,
      html[data-mnx-content-kind='image_like'] body > section,
      html[data-mnx-content-kind='image_like'] body > article,
      html[data-mnx-content-kind='image_like'] body > main,
      html[data-mnx-content-kind='image_like'] body > p {
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
      }
      html[data-mnx-content-kind='image_like'] picture,
      html[data-mnx-content-kind='image_like'] img,
      html[data-mnx-content-kind='image_like'] svg,
      html[data-mnx-content-kind='image_like'] video,
      html[data-mnx-content-kind='image_like'] canvas {
        flex: 0 1 auto !important;
        min-width: 0 !important;
        min-height: 0 !important;
      }
      html[data-mnx-content-kind='image_like'] picture,
      html[data-mnx-content-kind='image_like'] figure,
      html[data-mnx-content-kind='image_like'] div,
      html[data-mnx-content-kind='image_like'] section,
      html[data-mnx-content-kind='image_like'] article,
      html[data-mnx-content-kind='image_like'] main {
        max-width: 100% !important;
        max-height: 100% !important;
      }
      html[data-mnx-content-kind='image_like'] img,
      html[data-mnx-content-kind='image_like'] svg,
      html[data-mnx-content-kind='image_like'] video,
      html[data-mnx-content-kind='image_like'] canvas {
        width: auto !important;
        height: auto !important;
        max-width: ${contentW}px !important;
        max-height: ${contentH}px !important;
        display: block !important;
        object-fit: contain !important;
        margin: 0 auto !important;
        break-inside: avoid !important;
        transform: none !important;
      }
    `;

    const mixedMediaCss = `
      html[data-mnx-content-kind='text_like'] img[data-mnx-media-role='inline'],
      html[data-mnx-content-kind='text_like'] svg[data-mnx-media-role='inline'],
      html[data-mnx-content-kind='text_like'] video[data-mnx-media-role='inline'],
      html[data-mnx-content-kind='text_like'] canvas[data-mnx-media-role='inline'],
      html[data-mnx-content-kind='text_like'] picture[data-mnx-media-role='inline'] {
        display: inline-block !important;
        width: auto !important;
        height: auto !important;
        max-width: ${inlineMediaMaxWidth}px !important;
        max-height: 1.35em !important;
        margin: 0 0.08em !important;
        padding: 0 !important;
        object-fit: contain !important;
        vertical-align: -0.18em !important;
        break-inside: auto !important;
        page-break-inside: auto !important;
        transform: none !important;
      }
      html[data-mnx-content-kind='text_like'] sup img[data-mnx-media-role='inline'],
      html[data-mnx-content-kind='text_like'] sub img[data-mnx-media-role='inline'],
      html[data-mnx-content-kind='text_like'] sup svg[data-mnx-media-role='inline'],
      html[data-mnx-content-kind='text_like'] sub svg[data-mnx-media-role='inline'] {
        max-height: 1em !important;
        vertical-align: baseline !important;
      }
      html[data-mnx-content-kind='text_like'] img[data-mnx-media-role='block'],
      html[data-mnx-content-kind='text_like'] svg[data-mnx-media-role='block'],
      html[data-mnx-content-kind='text_like'] video[data-mnx-media-role='block'],
      html[data-mnx-content-kind='text_like'] canvas[data-mnx-media-role='block'] {
        display: block !important;
        width: auto !important;
        height: auto !important;
        object-fit: contain !important;
        margin-left: auto !important;
        margin-right: auto !important;
        transform: none !important;
      }
      html[data-mnx-content-kind='text_like'] picture[data-mnx-media-role='block'],
      html[data-mnx-content-kind='text_like'] figure[data-mnx-media-role='block'] {
        display: block !important;
        max-width: 100% !important;
        break-inside: avoid !important;
      }
    `;

    if (layoutKind === 'continuous_vertical') {
      const imageGap = pageSettings.readingMode === ReadingMode.WEBTOON_WITH_GAP
        ? EpubCssBuilder.clamp(pageSettings.pageSpacing ?? 12, 0, 80)
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
          min-width: 100% !important;
          height: 100% !important;
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
          padding-top: ${topMargin}px !important;
          padding-right: ${rightPadding}px !important;
          padding-bottom: ${bottomMargin}px !important;
          padding-left: ${leftPadding}px !important;
          box-sizing: border-box !important;
          width: 100% !important;
          min-height: 100% !important;
          overflow-x: hidden !important;
          overflow-y: visible !important;
          background-color: ${bodyOverlayColor} !important;
          ${commonTextCss}
        }
        ${textInheritanceCss}
        ${paragraphCss}
        ${footnoteCss}
        ${mixedMediaCss}
        html[data-mnx-content-kind='text_like'] img[data-mnx-media-role='block'],
        html[data-mnx-content-kind='text_like'] svg[data-mnx-media-role='block'],
        html[data-mnx-content-kind='text_like'] video[data-mnx-media-role='block'],
        html[data-mnx-content-kind='text_like'] canvas[data-mnx-media-role='block'] {
          max-width: ${contentW}px !important;
          max-height: none !important;
          margin-bottom: ${imageGap}px !important;
          break-inside: avoid !important;
        }
        html[data-mnx-content-kind='text_like'] picture[data-mnx-media-role='block'],
        html[data-mnx-content-kind='text_like'] figure[data-mnx-media-role='block'] {
          max-width: 100% !important;
          break-inside: avoid !important;
        }
        ${imageLikeDocumentCss}
        html[data-mnx-content-kind='image_like'] {
          overflow-x: hidden !important;
          overflow-y: auto !important;
          scroll-snap-type: none !important;
        }
        html[data-mnx-content-kind='image_like'] body {
          display: flex !important;
          flex-direction: column !important;
          align-items: center !important;
          justify-content: flex-start !important;
        }
        html[data-mnx-content-kind='image_like'] img,
        html[data-mnx-content-kind='image_like'] svg,
        html[data-mnx-content-kind='image_like'] video,
        html[data-mnx-content-kind='image_like'] canvas {
          max-height: none !important;
          margin-bottom: ${imageGap}px !important;
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
          min-width: 100% !important;
          height: 100% !important;
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
          padding-top: ${topMargin}px !important;
          padding-right: ${rightPadding}px !important;
          padding-bottom: ${bottomMargin}px !important;
          padding-left: ${leftPadding}px !important;
          box-sizing: border-box !important;
          width: 100% !important;
          min-height: 100% !important;
          overflow-x: hidden !important;
          overflow-y: visible !important;
          background-color: ${bodyOverlayColor} !important;
          ${commonTextCss}
        }
        ${textInheritanceCss}
        ${paragraphCss}
        ${footnoteCss}
        ${mixedMediaCss}
        html[data-mnx-content-kind='text_like'] img[data-mnx-media-role='block'],
        html[data-mnx-content-kind='text_like'] svg[data-mnx-media-role='block'],
        html[data-mnx-content-kind='text_like'] video[data-mnx-media-role='block'],
        html[data-mnx-content-kind='text_like'] canvas[data-mnx-media-role='block'] {
          max-width: ${contentW}px !important;
          max-height: ${contentH}px !important;
          break-inside: avoid !important;
        }
        html[data-mnx-content-kind='text_like'] picture[data-mnx-media-role='block'],
        html[data-mnx-content-kind='text_like'] figure[data-mnx-media-role='block'] {
          max-width: 100% !important;
          break-inside: avoid !important;
        }
        ${imageLikeDocumentCss}
        html[data-mnx-content-kind='image_like'] {
          overflow-x: hidden !important;
          overflow-y: hidden !important;
          scroll-snap-type: none !important;
        }
        html[data-mnx-content-kind='image_like'] body {
          display: flex !important;
          flex-direction: column !important;
          align-items: center !important;
          justify-content: center !important;
          height: 100% !important;
          min-height: 100% !important;
          overflow: hidden !important;
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
        min-width: 100% !important;
        height: 100% !important;
        min-height: 100% !important;
        overflow-x: hidden !important;
        overflow-y: hidden !important;
        overscroll-behavior: contain !important;
        scroll-behavior: auto !important;
        scroll-snap-type: none !important;
        touch-action: pan-y !important;
        background-color: ${backgroundColor} !important;
        ${rootTextCss}
      }
      body {
        position: relative !important;
        z-index: 1 !important;
        margin: 0 !important;
        padding-top: ${topMargin}px !important;
        padding-right: ${rightPadding}px !important;
        padding-bottom: ${bottomMargin}px !important;
        padding-left: ${leftPadding}px !important;
        box-sizing: border-box !important;
        column-width: ${columnWidth}px !important;
        column-gap: ${pageGap}px !important;
        column-fill: auto !important;
        min-width: 100% !important;
        width: 100% !important;
        height: 100% !important;
        min-height: 100% !important;
        overflow-y: hidden !important;
        overflow-x: visible !important;
        touch-action: pan-y !important;
        background-color: ${bodyOverlayColor} !important;
        ${commonTextCss}
      }
      ${textInheritanceCss}
      ${paragraphCss}
      ${footnoteCss}
      ${mixedMediaCss}
      html[data-mnx-content-kind='text_like'] img[data-mnx-media-role='block'],
      html[data-mnx-content-kind='text_like'] svg[data-mnx-media-role='block'],
      html[data-mnx-content-kind='text_like'] video[data-mnx-media-role='block'],
      html[data-mnx-content-kind='text_like'] canvas[data-mnx-media-role='block'] {
        max-width: ${columnWidth}px !important;
        max-height: ${contentH}px !important;
        break-inside: avoid-column !important;
      }
      html[data-mnx-content-kind='text_like'] picture[data-mnx-media-role='block'],
      html[data-mnx-content-kind='text_like'] figure[data-mnx-media-role='block'] {
        max-width: 100% !important;
        break-inside: avoid-column !important;
      }
      ${imageLikeDocumentCss}
      html[data-mnx-content-kind='image_like'] {
        overflow-x: hidden !important;
        overflow-y: hidden !important;
        scroll-snap-type: none !important;
        touch-action: none !important;
      }
      html[data-mnx-content-kind='image_like'] body {
        display: flex !important;
        flex-direction: column !important;
        align-items: center !important;
        justify-content: center !important;
        width: 100% !important;
        height: 100% !important;
        min-height: 100% !important;
        column-width: auto !important;
        column-gap: 0px !important;
        overflow: hidden !important;
        touch-action: none !important;
      }
      * {
        -webkit-tap-highlight-color: transparent !important;
      }
      ::-webkit-scrollbar {
        display: none !important;
      }
      `;
  }

  static buildPublisherLayoutCss(vpW: number, vpH: number, textSettings: EBookReadingSettings): string {
    const backgroundColor = textSettings.backgroundColor ?? '#FFFFFF';
    const backgroundCss = EpubCssBuilder.buildBackgroundCss(textSettings);
    const mediaMaxWidth = Math.max(1, Math.round(vpW));
    const mediaMaxHeight = Math.max(1, Math.round(vpH));
    return `
      ${backgroundCss}
      html {
        margin: 0 !important;
        padding: 0 !important;
        width: 100% !important;
        min-width: 100% !important;
        height: 100% !important;
        min-height: 100% !important;
        overflow: hidden !important;
        overscroll-behavior: contain !important;
        scroll-behavior: auto !important;
        background-color: ${backgroundColor} !important;
        -webkit-text-size-adjust: 100% !important;
        text-size-adjust: 100% !important;
      }
      body {
        position: relative !important;
        z-index: 1 !important;
        box-sizing: border-box !important;
        max-width: 100% !important;
        min-height: 100% !important;
        overflow: hidden !important;
        transform-origin: top center !important;
      }
      html[data-mnx-content-kind='publisher_layout'] body > * {
        max-width: 100% !important;
        box-sizing: border-box !important;
      }
      html[data-mnx-content-kind='publisher_layout'] .duokan-image-single,
      html[data-mnx-content-kind='publisher_layout'] [class*='normal-center-single'] {
        min-height: 0 !important;
        max-height: 100vh !important;
        box-sizing: border-box !important;
      }
      html[data-mnx-content-kind='publisher_layout'] img,
      html[data-mnx-content-kind='publisher_layout'] svg,
      html[data-mnx-content-kind='publisher_layout'] video,
      html[data-mnx-content-kind='publisher_layout'] canvas {
        max-width: ${mediaMaxWidth}px !important;
        max-height: ${mediaMaxHeight}px !important;
        object-fit: contain !important;
        box-sizing: border-box !important;
      }
      html[data-mnx-content-kind='publisher_layout'] .duokan-image-single img,
      html[data-mnx-content-kind='publisher_layout'] .illus img,
      html[data-mnx-content-kind='publisher_layout'] img.w,
      html[data-mnx-content-kind='publisher_layout'] img.h {
        width: auto !important;
        height: auto !important;
      }
      * {
        -webkit-tap-highlight-color: transparent !important;
      }
      ::-webkit-scrollbar {
        display: none !important;
      }
    `;
  }

  static buildCoverPageCss(vpW: number, vpH: number, textSettings: EBookReadingSettings): string {
    const backgroundColor = textSettings.backgroundColor ?? '#FFFFFF';
    const backgroundCss = EpubCssBuilder.buildBackgroundCss(textSettings);
    const fallbackWidth = Math.max(1, Math.round(vpW));
    const fallbackHeight = Math.max(1, Math.round(vpH));
    const coverWidthCss = 'var(--mnx-cover-vw, var(--mnx-cover-fallback-vw, 100vw))';
    const coverHeightCss = 'var(--mnx-cover-vh, var(--mnx-cover-fallback-vh, 100vh))';
    return `
      ${backgroundCss}
      html {
        --mnx-cover-fallback-vw: ${fallbackWidth}px;
        --mnx-cover-fallback-vh: ${fallbackHeight}px;
      }
      html,
      body {
        margin: 0 !important;
        padding: 0 !important;
        width: ${coverWidthCss} !important;
        min-width: ${coverWidthCss} !important;
        max-width: ${coverWidthCss} !important;
        height: ${coverHeightCss} !important;
        min-height: ${coverHeightCss} !important;
        max-height: ${coverHeightCss} !important;
        overflow: hidden !important;
        background-color: ${backgroundColor} !important;
        box-sizing: border-box !important;
        -webkit-text-size-adjust: 100% !important;
        text-size-adjust: 100% !important;
      }
      body {
        position: relative !important;
        z-index: 1 !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
        transform: none !important;
        transform-origin: center center !important;
        -webkit-transform: none !important;
        -webkit-transform-origin: center center !important;
        scale: 1 !important;
        zoom: 1 !important;
        contain: none !important;
      }
      body > *,
      body .center,
      body .illus,
      body .cover,
      body .cover-image,
      body .front-cover,
      body .duokan-image-single,
      body div,
      body figure,
      body picture,
      body section,
      body article,
      body main,
      body p {
        box-sizing: border-box !important;
        position: static !important;
        display: flex !important;
        align-items: center !important;
        justify-content: center !important;
        width: ${coverWidthCss} !important;
        max-width: ${coverWidthCss} !important;
        height: ${coverHeightCss} !important;
        max-height: ${coverHeightCss} !important;
        min-height: 0 !important;
        margin: 0 auto !important;
        padding: 0 !important;
        overflow: hidden !important;
        text-indent: 0 !important;
      }
      body img,
      body svg,
      body image,
      body video,
      body canvas {
        display: block !important;
        position: static !important;
        flex: 0 1 auto !important;
        width: ${coverWidthCss} !important;
        height: ${coverHeightCss} !important;
        min-width: 0 !important;
        min-height: 0 !important;
        max-width: ${coverWidthCss} !important;
        max-height: ${coverHeightCss} !important;
        max-inline-size: ${coverWidthCss} !important;
        max-block-size: ${coverHeightCss} !important;
        object-fit: contain !important;
        object-position: center center !important;
        margin: auto !important;
        padding: 0 !important;
        transform: none !important;
        -webkit-transform: none !important;
        scale: 1 !important;
        zoom: 1 !important;
        box-sizing: border-box !important;
      }
      #__mnx_cover_proxy {
        position: fixed !important;
        left: 0 !important;
        top: 0 !important;
        right: auto !important;
        bottom: auto !important;
        width: ${coverWidthCss} !important;
        height: ${coverHeightCss} !important;
        min-width: ${coverWidthCss} !important;
        min-height: ${coverHeightCss} !important;
        max-width: ${coverWidthCss} !important;
        max-height: ${coverHeightCss} !important;
        display: block !important;
        object-fit: contain !important;
        object-position: center center !important;
        margin: 0 !important;
        padding: 0 !important;
        border: 0 !important;
        transform: none !important;
        -webkit-transform: none !important;
        scale: 1 !important;
        zoom: 1 !important;
        z-index: 2147483647 !important;
        pointer-events: none !important;
        background: transparent !important;
        box-sizing: border-box !important;
      }
      * {
        -webkit-tap-highlight-color: transparent !important;
      }
      ::-webkit-scrollbar {
        display: none !important;
      }
    `;
  }

  static buildFixedCss(vpW: number, vpH: number, textSettings: EBookReadingSettings, vpState: CssBuilderViewportState): string {
    const backgroundColor = textSettings.backgroundColor ?? '#FFFFFF';
    const backgroundCss = EpubCssBuilder.buildBackgroundCss(textSettings);
    const safeTopInset = EpubCssBuilder.getContentSafeTopInsetCssPx(vpW, vpH, vpState);
    return `
      ${backgroundCss}
      html, body {
        margin: 0 !important;
        padding: 0 !important;
        width: ${vpW}px !important;
        height: ${vpH}px !important;
        overflow: hidden !important;
        background-color: ${backgroundColor} !important;
        box-sizing: border-box !important;
      }
      body {
        position: relative !important;
        z-index: 1 !important;
        transform-origin: top left !important;
        padding-top: ${safeTopInset}px !important;
      }
      * {
        -webkit-tap-highlight-color: transparent !important;
        box-sizing: border-box !important;
      }
    `;
  }
}
