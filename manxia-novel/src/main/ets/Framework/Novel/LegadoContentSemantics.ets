import { HtmlFormatter } from './HtmlFormatter';
import { LegadoBookSourceType } from './LegadoSourceTypes';

/**
 * The value returned by a Legado selector is not necessarily reader-ready.
 * In particular, `@html` intentionally returns HTML; upstream Legado formats
 * that value before it is delivered to the reading surface.  Keep that
 * boundary explicit so transport/rule extraction never leaks markup into a
 * TEXT reader again.
 */
export enum LegadoContentPresentationStatus {
  READABLE = 'readable',
  EMPTY = 'empty',
  RAW_HTML = 'raw_html',
  RAW_ENTITY = 'raw_entity',
  INVALID_IMAGE = 'invalid_image'
}

export class LegadoContentPresentationAssessment {
  readonly status: LegadoContentPresentationStatus;
  readonly visibleLength: number;

  constructor(status: LegadoContentPresentationStatus, visibleLength: number) {
    this.status = status;
    this.visibleLength = visibleLength;
  }

  isReadable(): boolean {
    return this.status === LegadoContentPresentationStatus.READABLE;
  }
}

export class LegadoContentSemantics {
  private static readonly rawHtmlRegex: RegExp = /<\/?[A-Za-z][^>]*>/;
  private static readonly rawEntityRegex: RegExp = /&(nbsp|ensp|emsp|thinsp|zwnj|zwj|lt|gt|amp|quot|apos|#\d+|#x[0-9a-f]+);/i;
  private static readonly imageTagRegex: RegExp = /<img\b[^>]*\bsrc\s*=\s*[^\s>]+[^>]*>/i;
  private static readonly imageTagStripRegex: RegExp = /<img\b[^>]*>/gi;
  private static readonly imageUrlCandidateRegex: RegExp = /^(?:(?:https?:)?\/\/|\/|\.\.?\/|data:image\/)|\.(?:avif|bmp|gif|jpe?g|png|webp)(?:[?#].*)?$/i;

  /**
   * Mirrors the post-extraction step in Legado's BookContent: normal text
   * and image output preserve valid image nodes while all other HTML becomes
   * reader text; audio payloads stay URL/data oriented and are not formatted
   * as document HTML.
   */
  static normalizePageContent(
    extractedContent: string,
    sourceType: number,
    baseUrl: string
  ): string {
    if (extractedContent.trim().length <= 0) {
      return '';
    }
    if (sourceType === LegadoBookSourceType.AUDIO) {
      return LegadoContentSemantics.unescapeIfRequired(extractedContent).trim();
    }
    const formatted = HtmlFormatter.formatKeepImg(extractedContent, baseUrl, true);
    if (sourceType === LegadoBookSourceType.IMAGE) {
      return LegadoContentSemantics.normalizeImagePage(formatted, baseUrl).trim();
    }
    return LegadoContentSemantics.unescapeIfRequired(formatted);
  }

  /** Joins already-normalized pages without retaining raw transport bodies. */
  static joinNormalizedPages(parts: string[]): string {
    const nonEmpty: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const value = parts[i];
      if (value.trim().length > 0) {
        nonEmpty.push(value);
      }
    }
    return nonEmpty.join('\n');
  }

  /**
   * A qualification gate for the final reader payload. It deliberately
   * accepts retained <img> nodes for IMAGE sources, but treats residual HTML
   * or common HTML entities as an invalid TEXT/FILE reader hand-off.
   */
  static assessReaderPayload(content: string, sourceType: number): LegadoContentPresentationAssessment {
    const value = content.trim();
    if (value.length <= 0) {
      return new LegadoContentPresentationAssessment(LegadoContentPresentationStatus.EMPTY, 0);
    }
    if (sourceType === LegadoBookSourceType.AUDIO) {
      return new LegadoContentPresentationAssessment(LegadoContentPresentationStatus.READABLE, value.length);
    }
    if (sourceType === LegadoBookSourceType.IMAGE) {
      const hasImage = LegadoContentSemantics.imageTagRegex.test(value);
      LegadoContentSemantics.imageTagRegex.lastIndex = 0;
      if (!hasImage) {
        return new LegadoContentPresentationAssessment(LegadoContentPresentationStatus.INVALID_IMAGE, 0);
      }
      return new LegadoContentPresentationAssessment(LegadoContentPresentationStatus.READABLE, value.length);
    }
    if (LegadoContentSemantics.rawHtmlRegex.test(value)) {
      LegadoContentSemantics.rawHtmlRegex.lastIndex = 0;
      return new LegadoContentPresentationAssessment(LegadoContentPresentationStatus.RAW_HTML, 0);
    }
    if (LegadoContentSemantics.rawEntityRegex.test(value)) {
      LegadoContentSemantics.rawEntityRegex.lastIndex = 0;
      return new LegadoContentPresentationAssessment(LegadoContentPresentationStatus.RAW_ENTITY, 0);
    }
    return new LegadoContentPresentationAssessment(LegadoContentPresentationStatus.READABLE, value.length);
  }

  /** Used only by assertions and diagnostics; it does not persist reader text. */
  static visibleTextLength(content: string): number {
    const withoutImages = content.replace(LegadoContentSemantics.imageTagStripRegex, '');
    LegadoContentSemantics.imageTagStripRegex.lastIndex = 0;
    return withoutImages.trim().length;
  }

  private static unescapeIfRequired(content: string): string {
    if (content.indexOf('&') < 0) {
      return content;
    }
    return HtmlFormatter.unescapeHtml(content);
  }

  /**
   * `@src` and JSON selectors commonly return a newline-separated image URL
   * list rather than literal `<img>` markup. The reader contract is image
   * nodes, so translate only URL-looking lines and leave non-image text for
   * the presentation gate to reject instead of pretending it is readable.
   */
  private static normalizeImagePage(content: string, baseUrl: string): string {
    if (LegadoContentSemantics.imageTagRegex.test(content)) {
      LegadoContentSemantics.imageTagRegex.lastIndex = 0;
      return LegadoContentSemantics.unescapeIfRequired(content);
    }
    LegadoContentSemantics.imageTagRegex.lastIndex = 0;
    const lines = content.split(/\r?\n/);
    const imageNodes: string[] = [];
    for (let index = 0; index < lines.length; index++) {
      const candidate = LegadoContentSemantics.unescapeIfRequired(lines[index]).trim();
      if (!LegadoContentSemantics.imageUrlCandidateRegex.test(candidate)) {
        continue;
      }
      const resolvedUrl = HtmlFormatter.resolveUrlForImage(candidate, baseUrl);
      if (resolvedUrl.length > 0) {
        imageNodes.push(`<img src="${resolvedUrl}">`);
      }
    }
    return imageNodes.join('\n');
  }
}
