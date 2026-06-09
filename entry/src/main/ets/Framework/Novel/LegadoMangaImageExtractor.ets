/**
 * Legado IMAGE source image extractor.
 *
 * Keeps the original Legado behavior: chapter content is HTML containing img
 * tags, and manga pages are derived from those tags in order.
 */

import { HtmlFormatter } from './HtmlFormatter';

export interface LegadoMangaExtractedImage {
  imageUrl: string;
  requestUrl: string;
  optionSuffix: string;
}

export class LegadoMangaImageExtractor {
  private static readonly imgTagRegex: RegExp = /<img\b[^>]*>/gi;
  private static readonly attrRegex: RegExp = /\s([a-zA-Z0-9:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'<>]+))/g;
  private static readonly quotedValueRegex: RegExp = /"([^"]+)"|'([^']+)'/g;
  private static readonly absoluteUrlRegex: RegExp = /(?:https?:\/\/|\/\/|data:image\/)[^\s<>"'\]\)]+/gi;
  private static readonly imageExtensionRegex: RegExp = /\.(?:jpg|jpeg|png|webp|gif|bmp|avif)(?:[?#,]|$)/i;
  private static readonly clearDataAttrPrefix: string = 'data-';
  private static readonly lazyAttrNames: string[] = [
    'data-src',
    'data-original',
    'data-lazy-src',
    'data-url',
    'data-image',
    'data-img',
    'data-original-src',
    'data-srcset',
    'srcset'
  ];

  static extractImageUrls(content: string, baseUrl: string): string[] {
    const images = LegadoMangaImageExtractor.extractImages(content, baseUrl);
    const result: string[] = [];
    for (let i = 0; i < images.length; i++) {
      result.push(images[i].imageUrl);
    }
    return result;
  }

  static extractImages(content: string, baseUrl: string): LegadoMangaExtractedImage[] {
    const result: LegadoMangaExtractedImage[] = [];
    const seen: Set<string> = new Set<string>();
    if (!content || content.trim().length <= 0) {
      return result;
    }

    LegadoMangaImageExtractor.imgTagRegex.lastIndex = 0;
    let match = LegadoMangaImageExtractor.imgTagRegex.exec(content);
    while (match) {
      const imgTag = match[0];
      const rawUrl = LegadoMangaImageExtractor.extractImageUrlFromTag(imgTag);
      const added = LegadoMangaImageExtractor.addImageCandidate(result, seen, rawUrl, baseUrl);
      if (!added) {
        LegadoMangaImageExtractor.addNestedImageCandidates(result, seen, rawUrl, baseUrl);
      }
      match = LegadoMangaImageExtractor.imgTagRegex.exec(content);
    }

    if (result.length <= 0) {
      const plainCandidates = LegadoMangaImageExtractor.extractPlainImageCandidates(content);
      for (let i = 0; i < plainCandidates.length; i++) {
        LegadoMangaImageExtractor.addImageCandidate(result, seen, plainCandidates[i], baseUrl);
      }
    }

    return result;
  }

  private static addImageCandidate(
    result: LegadoMangaExtractedImage[],
    seen: Set<string>,
    rawUrl: string,
    baseUrl: string
  ): boolean {
    const requestUrl = HtmlFormatter.resolveUrlForImage(rawUrl, baseUrl);
    const imageUrl = HtmlFormatter.getUrlWithoutLegadoOption(requestUrl);
    const optionSuffix = HtmlFormatter.getLegadoUrlOptionSuffix(requestUrl);
    const dedupeKey = requestUrl.length > 0 ? requestUrl : imageUrl;
    if (LegadoMangaImageExtractor.isUsableImageUrl(imageUrl) && !seen.has(dedupeKey)) {
      seen.add(dedupeKey);
      const extracted: LegadoMangaExtractedImage = {
        imageUrl: imageUrl,
        requestUrl: requestUrl,
        optionSuffix: optionSuffix
      };
      result.push(extracted);
      return true;
    }
    return false;
  }

  private static addNestedImageCandidates(
    result: LegadoMangaExtractedImage[],
    seen: Set<string>,
    rawValue: string,
    baseUrl: string
  ): void {
    if (!rawValue || rawValue.trim().length <= 0) {
      return;
    }
    const plainCandidates = LegadoMangaImageExtractor.extractPlainImageCandidates(rawValue);
    for (let i = 0; i < plainCandidates.length; i++) {
      LegadoMangaImageExtractor.addImageCandidate(result, seen, plainCandidates[i], baseUrl);
    }

    const commaParts = HtmlFormatter.unescapeHtml(rawValue).split(',');
    if (commaParts.length <= 1) {
      return;
    }
    for (let i = 0; i < commaParts.length; i++) {
      const candidate = LegadoMangaImageExtractor.normalizePlainCandidate(commaParts[i]);
      if (candidate.length > 0) {
        LegadoMangaImageExtractor.addImageCandidate(result, seen, candidate, baseUrl);
      }
    }
  }

  private static extractImageUrlFromTag(imgTag: string): string {
    let src = '';
    let dataSrc = '';
    let dataAttr = '';

    LegadoMangaImageExtractor.attrRegex.lastIndex = 0;
    let match = LegadoMangaImageExtractor.attrRegex.exec(imgTag);
    while (match) {
      const name = match[1].trim().toLowerCase();
      const rawValue = match[2] || match[3] || match[4] || '';
      const value = LegadoMangaImageExtractor.normalizeAttributeImageValue(
        name,
        HtmlFormatter.unescapeHtml(rawValue.trim())
      );
      if (value.length <= 0) {
        match = LegadoMangaImageExtractor.attrRegex.exec(imgTag);
        continue;
      }
      if (name === 'src') {
        src = value;
      } else if (name === 'data-src') {
        dataSrc = value;
      } else if (dataSrc.length <= 0 && LegadoMangaImageExtractor.isLazyImageAttr(name)) {
        dataSrc = value;
      } else if (dataAttr.length <= 0 && name.startsWith(LegadoMangaImageExtractor.clearDataAttrPrefix)) {
        dataAttr = value;
      }
      match = LegadoMangaImageExtractor.attrRegex.exec(imgTag);
    }

    if (dataSrc.length > 0) {
      return dataSrc;
    }
    if (src.length > 0) {
      return src;
    }
    return dataAttr;
  }

  private static isLazyImageAttr(name: string): boolean {
    for (let i = 0; i < LegadoMangaImageExtractor.lazyAttrNames.length; i++) {
      if (LegadoMangaImageExtractor.lazyAttrNames[i] === name) {
        return true;
      }
    }
    return false;
  }

  private static normalizeAttributeImageValue(name: string, value: string): string {
    const trimmed = value.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    if (name === 'srcset' || name === 'data-srcset') {
      const firstCandidate = trimmed.split(',')[0].trim();
      const spaceIndex = firstCandidate.search(/\s/);
      if (spaceIndex > 0) {
        return firstCandidate.substring(0, spaceIndex).trim();
      }
      return firstCandidate;
    }
    return trimmed;
  }

  private static extractPlainImageCandidates(content: string): string[] {
    const result: string[] = [];
    const seen: Set<string> = new Set<string>();
    const normalizedContent = HtmlFormatter.unescapeHtml(content).replace(/\r/g, '\n');

    LegadoMangaImageExtractor.quotedValueRegex.lastIndex = 0;
    let quotedMatch = LegadoMangaImageExtractor.quotedValueRegex.exec(normalizedContent);
    while (quotedMatch) {
      const quotedValue = quotedMatch[1] || quotedMatch[2] || '';
      LegadoMangaImageExtractor.addPlainCandidate(result, seen, quotedValue);
      quotedMatch = LegadoMangaImageExtractor.quotedValueRegex.exec(normalizedContent);
    }

    const lines = normalizedContent.split(/\n+/);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length <= 0) {
        continue;
      }
      LegadoMangaImageExtractor.addPlainCandidate(result, seen, line);

      LegadoMangaImageExtractor.absoluteUrlRegex.lastIndex = 0;
      let urlMatch = LegadoMangaImageExtractor.absoluteUrlRegex.exec(line);
      while (urlMatch) {
        LegadoMangaImageExtractor.addPlainCandidate(result, seen, urlMatch[0]);
        urlMatch = LegadoMangaImageExtractor.absoluteUrlRegex.exec(line);
      }
    }

    return result;
  }

  private static addPlainCandidate(result: string[], seen: Set<string>, rawValue: string): void {
    const candidate = LegadoMangaImageExtractor.normalizePlainCandidate(rawValue);
    if (candidate.length <= 0 || seen.has(candidate)) {
      return;
    }
    if (!LegadoMangaImageExtractor.looksLikeImageCandidate(candidate)) {
      return;
    }
    seen.add(candidate);
    result.push(candidate);
  }

  private static normalizePlainCandidate(rawValue: string): string {
    let candidate = rawValue.trim();
    if (candidate.length <= 0) {
      return '';
    }
    candidate = candidate.replace(/^[\s"'[(]+/, '');
    candidate = candidate.replace(/[\s"',\]);]+$/, '');
    candidate = candidate.replace(/\\\//g, '/');
    return candidate.trim();
  }

  private static looksLikeImageCandidate(value: string): boolean {
    if (value.startsWith('http://') || value.startsWith('https://') || value.startsWith('//') ||
      value.startsWith('data:image/') || value.startsWith('/') || value.startsWith('./') || value.startsWith('../')) {
      return true;
    }
    return LegadoMangaImageExtractor.imageExtensionRegex.test(value);
  }

  private static isUsableImageUrl(url: string): boolean {
    if (!url || url.trim().length <= 0) {
      return false;
    }
    const normalized = url.trim().toLowerCase();
    if (normalized === '#' || normalized === 'about:blank') {
      return false;
    }
    if (normalized.startsWith('javascript:')) {
      return false;
    }
    if (normalized.startsWith('data:') && normalized.indexOf('image/') < 0) {
      return false;
    }
    if (normalized.startsWith('data:image/gif;base64,r0lgodlhaqaba')) {
      return false;
    }
    if (normalized.includes('placeholder') || normalized.includes('blank.gif') ||
      normalized.includes('spacer.gif') || normalized.includes('transparent.gif')) {
      return false;
    }
    return true;
  }
}
