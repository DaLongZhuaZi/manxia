import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { logger } from '../../Utils/Logger';

const TAG = 'MobiParser';

export interface MobiConversionResult {
  success: boolean;
  extractedRootPath: string;
  errorMessage: string;
  title: string;
  author: string;
  coverImagePath: string;
  chapterCount: number;
}

interface PalmRecord {
  offset: number;
}

interface MobiMetadata {
  title: string;
  author: string;
  language: string;
  coverImageIndex: number;
}

interface MobiChapterData {
  title: string;
  body: string;
}

interface MobiHeaderInfo {
  recordBase: number;
  compression: number;
  textRecordCount: number;
  recordSize: number;
  mobiHeaderLen: number;
  encoding: number;
  fileVersion: number;
  firstNonBookRecord: number;
  firstImageRecord: number;
  exthFlags: number;
  drmOffset: number;
  drmCount: number;
  trailingFlags: number;
  huffcdicRecord: number;
  huffcdicRecordCount: number;
  ncxIndex: number;
  fdstRecord: number;
  fdstRecordCount: number;
  fragIndex: number;
  skelIndex: number;
  guideIndex: number;
  title: string;
  author: string;
  language: string;
  coverImageIndex: number;
  boundaryRecordIndex: number;
}

interface MobiTextBytesResult {
  bytes: Uint8Array;
  actualTextCount: number;
}

interface MobiKf8BuildResult {
  html: string;
  sectionCount: number;
}

interface MobiIndexHeader {
  length: number;
  idxt: number;
  numRecords: number;
  numCncx: number;
}

interface MobiTagxHeader {
  length: number;
  numControlBytes: number;
}

interface MobiTagxTag {
  tag: number;
  numValues: number;
  bitmask: number;
  controlByte: number;
}

interface MobiPtagx {
  tag: number;
  tagValueCount: number;
  valueCount: number;
  valueBytes: number;
  usesByteCount: boolean;
}

interface MobiIndexTag {
  tagId: number;
  values: number[];
}

interface MobiIndexEntry {
  label: string;
  tagMap: Map<number, MobiIndexTag>;
}

interface MobiIndexData {
  table: MobiIndexEntry[];
  cncx: Map<number, string>;
}

interface MobiSkeleton {
  index: number;
  name: string;
  numFrag: number;
  offset: number;
  length: number;
}

interface MobiFragment {
  insertOffset: number;
  selector: string;
  index: number;
  offset: number;
  length: number;
}

// PalmDOC compression types
const COMPRESSION_NONE = 1;
const COMPRESSION_PALMDOC = 2;
const COMPRESSION_HUFFDIC = 17480;

// Text encoding
const ENCODING_UTF8 = 65001;
const ENCODING_WINDOWS_1252 = 1252;

// EXTH record types
const EXTH_AUTHOR = 100;
const EXTH_CONTRIBUTOR = 108;
const EXTH_LANGUAGE = 524;
const EXTH_COVER_OFFSET = 201;
const EXTH_TITLE = 503;
const EXTH_BOUNDARY = 121;
const INVALID_RECORD_INDEX = 0xFFFFFFFF;
const MOBI_IMAGE_FILE_PATTERN: RegExp = /\.(bmp|gif|jpe?g|png|webp)$/i;
const MOBI_CONVERSION_VERSION = '20260424_azw3_kf8_v4';
const MOBI_CONVERSION_MARKER_FILE = '.mobi_conversion_version';
const MOBI_SOFT_PAGE_BREAK_HTML = '<span class="mnx-soft-page-break"></span>';
const MOBI_CHAPTER_TITLE_PATTERN: RegExp =
  /^(第\s*[0-9０-９零〇一二两三四五六七八九十百千万亿]+\s*[章回卷节集部篇].{0,80}|卷\s*[0-9０-９零〇一二两三四五六七八九十百千万亿]+.{0,80}|Chapter\s+[0-9IVXLCDM]+.{0,80}|Part\s+[0-9IVXLCDM]+.{0,80}|Book\s+[0-9IVXLCDM]+.{0,80}|序章|序言|前言|楔子|引子|尾声|后记|附录.{0,40})$/i;
const MOBI_NUMBERED_TITLE_PATTERN: RegExp =
  /^[0-9０-９零〇一二两三四五六七八九十百千万亿]+\s*[、.．]\s*\S.{0,60}$/i;
const MOBI_NOTE_LIKE_TITLE_PATTERN: RegExp = /^(注|注释|标记|标注|脚注|尾注|说明|备注|参考|引用|notes?|footnotes?|endnotes?)\s*[:：]?\s*$/i;

function u32(dv: DataView, offset: number): number {
  if (offset + 4 > dv.byteLength) {
    return 0;
  }
  return dv.getUint32(offset, false);
}

function u16(dv: DataView, offset: number): number {
  if (offset + 2 > dv.byteLength) {
    return 0;
  }
  return dv.getUint16(offset, false);
}

function readAscii(dv: DataView, offset: number, length: number): string {
  let result = '';
  const end = Math.min(offset + length, dv.byteLength);
  for (let i = offset; i < end; i++) {
    const code = dv.getUint8(i);
    if (code === 0) {
      break;
    }
    result += String.fromCharCode(code);
  }
  return result;
}

function decompressPalmDoc(input: Uint8Array): Uint8Array {
  const output: number[] = [];
  let i = 0;
  while (i < input.length) {
    const c = input[i++];
    if (c === 0x00) {
      output.push(0x00);
    } else if (c >= 0x01 && c <= 0x08) {
      for (let j = 0; j < c && i < input.length; j++) {
        output.push(input[i++]);
      }
    } else if (c <= 0x7F) {
      output.push(c);
    } else if (c >= 0x80 && c <= 0xBF) {
      if (i >= input.length) {
        break;
      }
      const next = input[i++];
      const twoByte = (c << 8) | next;
      const distance = (twoByte >> 3) & 0x7FF;
      const length = (twoByte & 0x07) + 3;
      if (distance === 0) {
        continue;
      }
      const start = output.length - distance;
      for (let j = 0; j < length; j++) {
        const srcIdx = start + j;
        output.push(srcIdx >= 0 && srcIdx < output.length ? output[srcIdx] : 0x20);
      }
    } else {
      output.push(0x20);
      output.push(c ^ 0x80);
    }
  }
  return new Uint8Array(output);
}

function detectImageExtension(data: Uint8Array): string {
  if (data.length >= 2 && data[0] === 0xFF && data[1] === 0xD8) {
    return '.jpg';
  }
  if (data.length >= 4 &&
    data[0] === 0x89 && data[1] === 0x50 && data[2] === 0x4E && data[3] === 0x47) {
    return '.png';
  }
  if (data.length >= 3 &&
    data[0] === 0x47 && data[1] === 0x49 && data[2] === 0x46) {
    return '.gif';
  }
  if (data.length >= 12 &&
    data[0] === 0x52 && data[1] === 0x49 && data[2] === 0x46 && data[3] === 0x46 &&
    data[8] === 0x57 && data[9] === 0x45 && data[10] === 0x42 && data[11] === 0x50) {
    return '.webp';
  }
  if (data.length >= 2 && data[0] === 0x42 && data[1] === 0x4D) {
    return '.bmp';
  }
  return '';
}

function getImageMediaType(fileName: string): string {
  const lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.bmp')) {
    return 'image/bmp';
  }
  return 'image/jpeg';
}

function escapeXml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function resolveImageFileName(imageFileMap: Map<number, string>, rawIndex: string): string {
  const trimmed = rawIndex.trim();
  const decimalIndex = Number(trimmed);
  if (Number.isFinite(decimalIndex)) {
    const oneBasedName = imageFileMap.get(Math.max(0, Math.floor(decimalIndex) - 1));
    if (oneBasedName) {
      return oneBasedName;
    }
    const directName = imageFileMap.get(Math.floor(decimalIndex));
    if (directName) {
      return directName;
    }
  }

  const hexIndex = parseInt(trimmed, 16);
  if (Number.isFinite(hexIndex)) {
    const oneBasedName = imageFileMap.get(Math.max(0, hexIndex - 1));
    if (oneBasedName) {
      return oneBasedName;
    }
    const directName = imageFileMap.get(hexIndex);
    if (directName) {
      return directName;
    }
  }

  const base32Index = parseInt(trimmed, 32);
  if (Number.isFinite(base32Index)) {
    const oneBasedName = imageFileMap.get(Math.max(0, base32Index - 1));
    if (oneBasedName) {
      return oneBasedName;
    }
    const directName = imageFileMap.get(base32Index);
    if (directName) {
      return directName;
    }
  }
  return '';
}

function postProcessMobiHtml(html: string, imageFileMap: Map<number, string>): string {
  let result = html;
  result = result.replace(/\u0000/g, '');

  // Replace img tags containing recindex with proper file src
  result = result.replace(/<img\b([^>]*)>/gi, (_match: string, attrs: string) => {
    const recindexMatch = attrs.match(/\brecindex\s*=\s*["']?(\d+)["']?/i);
    if (!recindexMatch) {
      return `<img${attrs}>`;
    }
    const recIdx = Number(recindexMatch[1]);
    const filename = imageFileMap.get(recIdx) || `image${String(recIdx + 1).padStart(4, '0')}.jpg`;
    const cleanAttrs = attrs
      .replace(/\s*\brecindex\s*=\s*["']?\d+["']?/gi, '')
      .replace(/\s*\bsrc\s*=\s*["'][^"']*["']/gi, '');
    return `<img${cleanAttrs} src="Images/${filename}"/>`;
  });

  result = result.replace(/\s(src|href)\s*=\s*["']kindle:embed:([0-9A-Za-z]+)(?:\?[^"']*)?["']/gi,
    (_match: string, attrName: string, rawIndex: string) => {
      const filename = resolveImageFileName(imageFileMap, rawIndex);
      if (filename.length <= 0) {
        return _match;
      }
      return ` ${attrName}="Images/${filename}"`;
    });

  result = result.replace(/<mbp:pagebreak\s*\/?>/gi, MOBI_SOFT_PAGE_BREAK_HTML);
  result = result.replace(/<\/?mbp:[^>]+>/gi, '');
  result = result.replace(/\s*filepos\s*=\s*["']?\d+["']?/gi, '');

  return result;
}

function appendSizedChapterPart(chapters: string[], part: string, sizeLimit: number): void {
  let remaining = part.trim();
  while (remaining.length > sizeLimit * 2) {
    let end = Math.min(sizeLimit, remaining.length);
    const tagClose = remaining.lastIndexOf('>', end);
    if (tagClose > sizeLimit / 2) {
      end = tagClose + 1;
    }
    chapters.push(remaining.substring(0, end).trim());
    remaining = remaining.substring(end).trim();
  }
  if (remaining.length > 0) {
    chapters.push(remaining);
  }
}

function splitIntoChapters(bodyHtml: string): string[] {
  const semanticChapters = splitIntoSemanticChapters(bodyHtml);
  if (semanticChapters.length > 1) {
    return semanticChapters;
  }

  // Size-based spine chunking only prevents oversized HTML resources; it is not treated as real chapters.
  const SIZE_LIMIT = 160000;
  if (bodyHtml.length > SIZE_LIMIT * 2) {
    const chapters: string[] = [];
    let start = 0;
    while (start < bodyHtml.length) {
      let end = Math.min(start + SIZE_LIMIT, bodyHtml.length);
      if (end < bodyHtml.length) {
        const tagClose = bodyHtml.lastIndexOf('>', end);
        if (tagClose > start + SIZE_LIMIT / 2) {
          end = tagClose + 1;
        }
      }
      chapters.push(bodyHtml.substring(start, end));
      start = end;
    }
    return chapters;
  }

  return [bodyHtml];
}

function stripHtmlTags(text: string): string {
  return text
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, '\'')
    .replace(/\s+/g, ' ')
    .trim();
}

function measureMobiHtmlTextLength(html: string): number {
  return stripHtmlTags(html).replace(/\s+/g, '').length;
}

function isLikelyMobiChapterTitle(title: string): boolean {
  const normalized = title.replace(/\s+/g, ' ').trim();
  if (normalized.length <= 1 || normalized.length > 90) {
    return false;
  }
  if (MOBI_NOTE_LIKE_TITLE_PATTERN.test(normalized)) {
    return false;
  }
  if (/^[0-9０-９]+$/.test(normalized)) {
    return false;
  }
  return MOBI_CHAPTER_TITLE_PATTERN.test(normalized) || MOBI_NUMBERED_TITLE_PATTERN.test(normalized);
}

function hasMobiChapterAttributeHint(attrsText: string): boolean {
  const attrs = attrsText.toLowerCase();
  return attrs.includes('chapter') ||
    attrs.includes('chap') ||
    attrs.includes('title') ||
    attrs.includes('heading') ||
    attrs.includes('headline');
}

function isLikelyMobiChapterBoundary(title: string, tagName: string, attrsText: string): boolean {
  const normalized = title.replace(/\s+/g, ' ').trim();
  if (!isLikelyMobiChapterTitle(normalized)) {
    return false;
  }
  if (MOBI_CHAPTER_TITLE_PATTERN.test(normalized)) {
    return true;
  }
  const lowerTagName = tagName.toLowerCase();
  if (MOBI_NUMBERED_TITLE_PATTERN.test(normalized) && (lowerTagName === 'h1' || lowerTagName === 'h2')) {
    return true;
  }
  return hasMobiChapterAttributeHint(attrsText);
}

function extractLeadingBlockTitle(html: string): string {
  const headingMatch = html.match(/<h[1-6]\b[^>]*>([\s\S]*?)<\/h[1-6]>/i);
  if (headingMatch && headingMatch[1]) {
    return stripHtmlTags(headingMatch[1]);
  }
  const paragraphMatch = html.match(/<(?:p|div)\b[^>]*>([\s\S]{1,240}?)<\/(?:p|div)>/i);
  if (paragraphMatch && paragraphMatch[1]) {
    return stripHtmlTags(paragraphMatch[1]);
  }
  return '';
}

function splitIntoSemanticChapters(bodyHtml: string): string[] {
  const boundaryOffsets: number[] = [0];
  const blockPattern = /<(h[1-6]|p|div)\b([^>]*)>((?:(?!<(?:h[1-6]|p|div)\b)[\s\S])*?)<\/\1>/gi;
  let match = blockPattern.exec(bodyHtml);
  while (match !== null) {
    const offset = match.index;
    const tagName = String(match[1] || '');
    const attrsText = String(match[2] || '');
    const innerHtml = String(match[3] || '');
    const title = stripHtmlTags(innerHtml);
    if (offset > 0 && isLikelyMobiChapterBoundary(title, tagName, attrsText)) {
      const currentStart = boundaryOffsets[boundaryOffsets.length - 1];
      const previousTextLength = measureMobiHtmlTextLength(bodyHtml.substring(currentStart, offset));
      if (previousTextLength >= 300) {
        boundaryOffsets.push(offset);
      }
    }
    match = blockPattern.exec(bodyHtml);
  }

  if (boundaryOffsets.length <= 1) {
    return [];
  }

  const chapters: string[] = [];
  for (let i = 0; i < boundaryOffsets.length; i++) {
    const start = boundaryOffsets[i];
    const end = i + 1 < boundaryOffsets.length ? boundaryOffsets[i + 1] : bodyHtml.length;
    const chapterHtml = bodyHtml.substring(start, end).trim();
    if (measureMobiHtmlTextLength(chapterHtml) < 120 && chapters.length > 0) {
      chapters[chapters.length - 1] += '\n' + chapterHtml;
      continue;
    }
    if (chapterHtml.length > 0) {
      chapters.push(chapterHtml);
    }
  }
  return chapters;
}

function normalizeMobiBodyContent(rawHtml: string): string {
  let body = rawHtml
    .replace(/\u0000/g, '')
    .replace(/[\u0001-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .replace(/<\?xml[\s\S]*?\?>/gi, '')
    .replace(/<!DOCTYPE[\s\S]*?>/gi, '')
    .replace(/<head[\s\S]*?<\/head>/gi, '')
    .replace(/<\/?html[^>]*>/gi, '')
    .replace(/<\/?body[^>]*>/gi, '')
    .trim();

  const hasHtmlTags = /<(p|div|h[1-6]|br|img|section|article|blockquote|ul|ol|li)\b/i.test(body);
  if (hasHtmlTags) {
    return body;
  }

  const paragraphs = body
    .split(/\r?\n\s*\r?\n|\r?\n/)
    .map((part: string) => part.trim())
    .filter((part: string) => part.length > 0);
  if (paragraphs.length <= 0) {
    return '';
  }
  const htmlParagraphs: string[] = [];
  for (const paragraph of paragraphs) {
    htmlParagraphs.push(`<p>${escapeXml(paragraph)}</p>`);
  }
  return htmlParagraphs.join('\n');
}

function extractMobiBodyContent(html: string): string {
  const bodyParts: string[] = [];
  const bodyPattern = /<body[^>]*>([\s\S]*?)<\/body>/gi;
  let match = bodyPattern.exec(html);
  while (match !== null) {
    if (match[1]) {
      bodyParts.push(match[1].trim());
    }
    match = bodyPattern.exec(html);
  }
  if (bodyParts.length > 0) {
    return bodyParts.join('\n');
  }
  return html;
}

function extractChapterTitle(chapterBody: string, index: number): string {
  const headingMatch = chapterBody.match(/<h[1-6]\b[^>]*>([\s\S]*?)<\/h[1-6]>/i);
  if (headingMatch && headingMatch[1]) {
    const title = stripHtmlTags(headingMatch[1]);
    if (title.length > 0 && title.length <= 90 && !MOBI_NOTE_LIKE_TITLE_PATTERN.test(title)) {
      return title;
    }
  }

  const leadingTitle = extractLeadingBlockTitle(chapterBody);
  if (isLikelyMobiChapterTitle(leadingTitle)) {
    return leadingTitle;
  }
  return `第${index + 1}章`;
}

function buildChapterData(bodyContent: string): MobiChapterData[] {
  const chapterBodies = splitIntoChapters(bodyContent);
  const chapters: MobiChapterData[] = [];
  for (let i = 0; i < chapterBodies.length; i++) {
    const body = chapterBodies[i].trim();
    if (body.length <= 0) {
      continue;
    }
    chapters.push({
      title: extractChapterTitle(body, chapters.length),
      body: body
    });
  }
  if (chapters.length <= 0 && bodyContent.trim().length > 0) {
    chapters.push({
      title: '第1章',
      body: bodyContent.trim()
    });
  }
  return chapters;
}

function buildChapterHtml(bodyContent: string, title: string, chapterNum: number): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="UTF-8"/>
<title>${escapeXml(title)} - ${chapterNum}</title>
<link rel="stylesheet" href="style.css" type="text/css"/>
</head>
<body>
${bodyContent}
</body>
</html>`;
}

function buildOpf(
  title: string,
  author: string,
  language: string,
  chapterCount: number,
  coverFileName: string,
  imageFileNames: string[]
): string {
  const chapterItemParts: string[] = [];
  const spineRefParts: string[] = [];
  for (let i = 0; i < chapterCount; i++) {
    const n = String(i + 1).padStart(3, '0');
    chapterItemParts.push(`    <item id="ch${n}" href="chapter${n}.html" media-type="application/xhtml+xml"/>`);
    spineRefParts.push(`    <itemref idref="ch${n}"/>`);
  }
  const chapterItems = chapterItemParts.join('\n');
  const spineRefs = spineRefParts.join('\n');

  const coverMeta = coverFileName.length > 0 ? '    <meta name="cover" content="cover-image"/>\n' : '';
  const coverItem = coverFileName.length > 0
    ? `    <item id="cover-image" href="Images/${escapeXml(coverFileName)}" media-type="${getImageMediaType(coverFileName)}"/>\n`
    : '';
  const imageItemParts: string[] = [];
  for (let i = 0; i < imageFileNames.length; i++) {
    const imageFileName = imageFileNames[i];
    if (coverFileName.length > 0 && imageFileName === coverFileName) {
      continue;
    }
    imageItemParts.push(`    <item id="img${String(i + 1).padStart(4, '0')}" href="Images/${escapeXml(imageFileName)}" media-type="${getImageMediaType(imageFileName)}"/>`);
  }
  const imageItems = imageItemParts.length > 0 ? `${imageItemParts.join('\n')}\n` : '';

  return `<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="uid" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>${escapeXml(title)}</dc:title>
    <dc:creator opf:role="aut">${escapeXml(author || '未知作者')}</dc:creator>
    <dc:language>${escapeXml(language || 'zh-CN')}</dc:language>
    <dc:identifier id="uid">mobi-conv-${Date.now()}</dc:identifier>
${coverMeta}  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="css" href="style.css" media-type="text/css"/>
${coverItem}${imageItems}${chapterItems}
  </manifest>
  <spine toc="ncx">
${spineRefs}
  </spine>
</package>`;
}

function buildContainer(): string {
  return `<?xml version="1.0" encoding="UTF-8"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>`;
}

function buildTocNcx(title: string, chapters: MobiChapterData[]): string {
  const navPointParts: string[] = [];
  for (let i = 0; i < chapters.length; i++) {
    const n = String(i + 1).padStart(3, '0');
    const chapterTitle = chapters[i].title || `第${i + 1}章`;
    navPointParts.push(`  <navPoint id="nav${n}" playOrder="${i + 1}">
    <navLabel><text>${escapeXml(chapterTitle)}</text></navLabel>
    <content src="chapter${n}.html"/>
  </navPoint>`);
  }
  const navPoints = navPointParts.join('\n');

  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="mobi-converted"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNormalValue" content="0"/>
  </head>
  <docTitle><text>${escapeXml(title)}</text></docTitle>
  <navMap>
${navPoints}
  </navMap>
</ncx>`;
}

function buildStyle(): string {
  return `body { margin: 0; padding: 0.5em; font-family: serif; }
p { margin: 0.4em 0; line-height: 1.6; text-indent: 2em; }
h1, h2, h3 { font-weight: bold; margin: 0.8em 0 0.4em; text-indent: 0; }
img { max-width: 100%; height: auto; display: block; margin: 0.5em auto; }
.mnx-soft-page-break { display: block; height: 0; line-height: 0; margin: 0; padding: 0; }
sup, .noteref { font-size: 0.75em; vertical-align: super; text-indent: 0; }`;
}

function writeTextFile(path: string, content: string): void {
  const encoder = new util.TextEncoder();
  const encoded = encoder.encodeInto(content);
  const file = fileIo.openSync(path,
    fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  fileIo.writeSync(file.fd, encoded.buffer as ArrayBuffer);
  fileIo.closeSync(file);
}

function writeBinaryFile(path: string, data: Uint8Array): void {
  const file = fileIo.openSync(path,
    fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
  try {
    const output = new ArrayBuffer(data.byteLength);
    const outputView = new Uint8Array(output);
    outputView.set(data);
    fileIo.writeSync(file.fd, output);
  } finally {
    fileIo.closeSync(file);
  }
}

function pathExists(path: string): boolean {
  try {
    fileIo.statSync(path);
    return true;
  } catch {
    return false;
  }
}

function ensureDirectory(path: string): void {
  let statChecked = false;
  let statIsDirectory = false;
  try {
    const stat = fileIo.statSync(path);
    statChecked = true;
    statIsDirectory = stat.isDirectory();
  } catch (_statError) {
  }
  if (statChecked) {
    if (!statIsDirectory) {
      throw new Error(`路径已存在但不是目录: ${path}`);
    }
    return;
  }

  try {
    fileIo.mkdirSync(path, true);
  } catch (error) {
    try {
      const stat = fileIo.statSync(path);
      if (stat.isDirectory()) {
        return;
      }
    } catch (_verifyError) {
    }
    throw error as Error;
  }
}

function readUtf8TextFile(path: string): string {
  const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
  try {
    const stat = fileIo.statSync(file.fd);
    const buffer = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buffer);
    return new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeToString(new Uint8Array(buffer));
  } finally {
    fileIo.closeSync(file);
  }
}

function isMobiConversionCacheCurrent(extractRoot: string): boolean {
  const markerPath = `${extractRoot}/${MOBI_CONVERSION_MARKER_FILE}`;
  if (!pathExists(markerPath)) {
    return false;
  }
  try {
    return readUtf8TextFile(markerPath).trim() === MOBI_CONVERSION_VERSION;
  } catch (error) {
    logger.warn(TAG, `读取 MOBI 转换版本标记失败，将重建缓存: ${String(error)}`);
    return false;
  }
}

function findCachedCoverPath(extractRoot: string): string {
  const candidates = [
    `${extractRoot}/OEBPS/Images/cover.jpg`,
    `${extractRoot}/OEBPS/Images/cover.jpeg`,
    `${extractRoot}/OEBPS/Images/cover.png`,
    `${extractRoot}/OEBPS/Images/cover.gif`,
    `${extractRoot}/OEBPS/Images/cover.webp`
  ];
  for (const candidate of candidates) {
    if (pathExists(candidate)) {
      return candidate;
    }
  }
  return '';
}

function isCachedImageFileUsable(path: string): boolean {
  try {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(file.fd);
      const headerLength = Math.min(32, Math.max(0, stat.size));
      if (headerLength <= 0) {
        return false;
      }
      const buffer = new ArrayBuffer(headerLength);
      const readLength = fileIo.readSync(file.fd, buffer);
      if (readLength <= 0) {
        return false;
      }
      const header = new Uint8Array(buffer, 0, Math.min(readLength, headerLength));
      return detectImageExtension(header).length > 0;
    } finally {
      fileIo.closeSync(file);
    }
  } catch (error) {
    logger.warn(TAG, `检查缓存图片失败: ${path}, error=${String(error)}`);
    return false;
  }
}

function isCachedImageDirectoryUsable(extractRoot: string): boolean {
  const imageDir = `${extractRoot}/OEBPS/Images`;
  if (!pathExists(imageDir)) {
    return true;
  }

  let fileNames: string[] = [];
  try {
    fileNames = fileIo.listFileSync(imageDir);
  } catch (error) {
    logger.warn(TAG, `读取缓存图片目录失败，将重建 MOBI 缓存: ${String(error)}`);
    return false;
  }

  for (let i = 0; i < fileNames.length; i++) {
    const fileName = fileNames[i];
    if (!MOBI_IMAGE_FILE_PATTERN.test(fileName)) {
      continue;
    }
    const imagePath = `${imageDir}/${fileName}`;
    if (!isCachedImageFileUsable(imagePath)) {
      logger.warn(TAG, `检测到损坏的 MOBI 缓存图片，将重建: ${imagePath}`);
      return false;
    }
  }
  return true;
}

function hashFilePath(path: string): string {
  let hash = 5381;
  for (let i = 0; i < path.length; i++) {
    hash = (((hash << 5) + hash) ^ path.charCodeAt(i)) | 0;
  }
  return Math.abs(hash).toString(36);
}

function decodeWindows1252(bytes: Uint8Array): string {
  const specialChars = new Map<number, string>();
  specialChars.set(0x80, '€');
  specialChars.set(0x82, '‚');
  specialChars.set(0x83, 'ƒ');
  specialChars.set(0x84, '„');
  specialChars.set(0x85, '…');
  specialChars.set(0x86, '†');
  specialChars.set(0x87, '‡');
  specialChars.set(0x88, 'ˆ');
  specialChars.set(0x89, '‰');
  specialChars.set(0x8A, 'Š');
  specialChars.set(0x8B, '‹');
  specialChars.set(0x8C, 'Œ');
  specialChars.set(0x8E, 'Ž');
  specialChars.set(0x91, '‘');
  specialChars.set(0x92, '’');
  specialChars.set(0x93, '“');
  specialChars.set(0x94, '”');
  specialChars.set(0x95, '•');
  specialChars.set(0x96, '–');
  specialChars.set(0x97, '—');
  specialChars.set(0x98, '˜');
  specialChars.set(0x99, '™');
  specialChars.set(0x9A, 'š');
  specialChars.set(0x9B, '›');
  specialChars.set(0x9C, 'œ');
  specialChars.set(0x9E, 'ž');
  specialChars.set(0x9F, 'Ÿ');

  let result = '';
  for (let i = 0; i < bytes.length; i++) {
    const byte = bytes[i];
    const special = specialChars.get(byte);
    result += special !== undefined ? special : String.fromCharCode(byte);
  }
  return result;
}

function decodeBytes(bytes: Uint8Array, encoding: number): string {
  if (encoding === ENCODING_WINDOWS_1252) {
    return decodeWindows1252(bytes);
  }
  try {
    return new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeToString(bytes);
  } catch {
    return decodeWindows1252(bytes);
  }
}

function readAsciiBytes(bytes: Uint8Array, offset: number, length: number): string {
  let result = '';
  const safeOffset = Math.max(0, offset);
  const end = Math.min(safeOffset + Math.max(0, length), bytes.byteLength);
  for (let i = safeOffset; i < end; i++) {
    const code = bytes[i];
    if (code === 0) {
      break;
    }
    result += String.fromCharCode(code);
  }
  return result;
}

function u32Bytes(bytes: Uint8Array, offset: number): number {
  if (offset < 0 || offset + 4 > bytes.byteLength) {
    return 0;
  }
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return dv.getUint32(offset, false);
}

function u16Bytes(bytes: Uint8Array, offset: number): number {
  if (offset < 0 || offset + 2 > bytes.byteLength) {
    return 0;
  }
  const dv = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return dv.getUint16(offset, false);
}

function u8Bytes(bytes: Uint8Array, offset: number): number {
  if (offset < 0 || offset >= bytes.byteLength) {
    return 0;
  }
  return bytes[offset];
}

function decodeRecordString(bytes: Uint8Array, offset: number, length: number, encoding: number): string {
  if (offset < 0 || length <= 0 || offset >= bytes.byteLength) {
    return '';
  }
  const safeLength = Math.min(length, bytes.byteLength - offset);
  return decodeBytes(bytes.slice(offset, offset + safeLength), encoding);
}

function countSetBits(value: number): number {
  let current = Math.max(0, Math.floor(value));
  let count = 0;
  while (current > 0) {
    if ((current & 1) !== 0) {
      count++;
    }
    current = current >> 1;
  }
  return count;
}

function removeTrailingEntries(recordData: Uint8Array, trailingFlags: number): Uint8Array {
  if (trailingFlags === 0 || recordData.byteLength <= 0) {
    return recordData;
  }

  const lastIndex = recordData.byteLength - 1;
  const multibyte = (trailingFlags & 1) !== 0;
  const numTrailingEntries = countSetBits(trailingFlags >> 1);
  let extraSize = 0;

  for (let i = 0; i < numTrailingEntries; i++) {
    let value = 0;
    const start = Math.max(0, lastIndex - 4 - extraSize);
    const end = Math.max(0, lastIndex - extraSize);
    for (let j = start; j <= end; j++) {
      const byte = recordData[j];
      if ((byte & 0x80) !== 0) {
        value = 0;
      }
      value = (value << 7) | (byte & 0x7F);
    }
    extraSize += value;
    if (extraSize >= recordData.byteLength) {
      return recordData;
    }
  }

  if (multibyte && extraSize < recordData.byteLength) {
    const byte = recordData[lastIndex - extraSize];
    extraSize += (byte & 0x03) + 1;
  }

  if (extraSize <= 0 || extraSize >= recordData.byteLength) {
    return recordData;
  }
  return recordData.slice(0, recordData.byteLength - extraSize);
}

function decompressTextRecordData(recordData: Uint8Array, compression: number, trailingFlags: number): Uint8Array {
  if (recordData.byteLength <= 0) {
    return new Uint8Array(new ArrayBuffer(0));
  }
  const cleanData = removeTrailingEntries(recordData, trailingFlags);
  if (compression === COMPRESSION_PALMDOC) {
    return decompressPalmDoc(cleanData);
  }
  return cleanData;
}

function getRecordEnd(records: PalmRecord[], recordIndex: number, fileSize: number): number {
  if (recordIndex + 1 < records.length) {
    return Math.min(records[recordIndex + 1].offset, fileSize);
  }
  return fileSize;
}

function readRecordBytes(buffer: ArrayBuffer, records: PalmRecord[], recordIndex: number): Uint8Array {
  if (recordIndex < 0 || recordIndex >= records.length) {
    return new Uint8Array(new ArrayBuffer(0));
  }
  const recordStart = records[recordIndex].offset;
  const recordEnd = getRecordEnd(records, recordIndex, buffer.byteLength);
  if (recordStart < 0 || recordEnd <= recordStart || recordStart >= buffer.byteLength) {
    return new Uint8Array(new ArrayBuffer(0));
  }
  const safeLength = Math.min(recordEnd - recordStart, buffer.byteLength - recordStart);
  return new Uint8Array(buffer, recordStart, safeLength);
}

function decodeTextRecordBytes(recordData: Uint8Array, compression: number, encoding: number, trailingFlags: number): string {
  if (recordData.byteLength <= 0) {
    return '';
  }
  const textBytes = decompressTextRecordData(recordData, compression, trailingFlags);
  return decodeBytes(textBytes, encoding);
}

function isKnownNonTextRecordMarker(marker: string): boolean {
  return marker === 'FLIS' ||
    marker === 'FCIS' ||
    marker === 'FDST' ||
    marker === 'DATP' ||
    marker === 'INDX' ||
    marker === 'TAGX' ||
    marker === 'ORDT' ||
    marker === 'CMET' ||
    marker === 'AUDI' ||
    marker === 'VIDE' ||
    marker === 'FONT' ||
    marker === 'RESC' ||
    marker === 'SRCS' ||
    marker === 'BOUN';
}

function isLikelyHtmlOrTextFragment(text: string): boolean {
  const normalized = text.replace(/\u0000/g, '').replace(/\s+/g, ' ').trim();
  if (normalized.length <= 0) {
    return false;
  }
  if (/<(?:html|body|p|div|h[1-6]|br|img|section|article|blockquote|mbp:pagebreak)\b/i.test(normalized)) {
    return true;
  }
  return normalized.length >= 80 && /[\u4e00-\u9fa5A-Za-z]/.test(normalized);
}

function collectTextFromRecordRange(
  buffer: ArrayBuffer,
  records: PalmRecord[],
  compression: number,
  encoding: number,
  trailingFlags: number,
  startIndex: number,
  endExclusive: number,
  skipRecordZero: boolean
): string {
  const fragments: string[] = [];
  const safeStart = Math.max(skipRecordZero ? 1 : 0, startIndex);
  const safeEnd = Math.min(Math.max(safeStart, endExclusive), records.length);
  for (let i = safeStart; i < safeEnd; i++) {
    const recordData = readRecordBytes(buffer, records, i);
    if (recordData.byteLength <= 0) {
      continue;
    }
    const recordStart = records[i].offset;
    const marker = readAscii(new DataView(buffer), recordStart, Math.min(4, recordData.byteLength));
    if (isKnownNonTextRecordMarker(marker) || detectImageExtension(recordData).length > 0) {
      continue;
    }
    const decoded = decodeTextRecordBytes(recordData, compression, encoding, trailingFlags);
    if (isLikelyHtmlOrTextFragment(decoded)) {
      fragments.push(decoded);
      continue;
    }
    if (compression === COMPRESSION_PALMDOC) {
      const rawDecoded = decodeBytes(recordData, encoding);
      if (isLikelyHtmlOrTextFragment(rawDecoded)) {
        fragments.push(rawDecoded);
      }
    }
  }
  return fragments.join('');
}

function parseMobiHeaderInfo(buffer: ArrayBuffer, records: PalmRecord[], recordBase: number): MobiHeaderInfo | null {
  if (recordBase < 0 || recordBase >= records.length) {
    return null;
  }
  const dv = new DataView(buffer);
  const r0 = records[recordBase].offset;
  const mobiOff = r0 + 16;
  if (mobiOff + 4 > dv.byteLength || readAscii(dv, mobiOff, 4) !== 'MOBI') {
    return null;
  }

  const compression = u16(dv, r0 + 0);
  const textRecordCount = u16(dv, r0 + 8);
  const recordSize = u16(dv, r0 + 10);
  const mobiHeaderLen = u32(dv, mobiOff + 0x04);
  const encoding = u32(dv, mobiOff + 0x0C);
  const fileVersion = u32(dv, mobiOff + 0x14);
  const firstNonBookRecord = u32(dv, mobiOff + 0x40);
  const fullNameOffset = u32(dv, mobiOff + 0x44);
  const fullNameLength = u32(dv, mobiOff + 0x48);
  const firstImageRecord = u32(dv, mobiOff + 0x5C);
  const huffcdicRecord = u32(dv, mobiOff + 0x60);
  const huffcdicRecordCount = u32(dv, mobiOff + 0x64);
  const exthFlags = u32(dv, mobiOff + 0x70);
  const drmOffset = u32(dv, mobiOff + 0x94);
  const drmCount = u32(dv, mobiOff + 0x98);
  const trailingFlags = u32(dv, mobiOff + 0xE0);
  const ncxIndex = u32(dv, mobiOff + 0xE4);
  const fdstRecord = u32(dv, mobiOff + 0xB0);
  const fdstRecordCount = u32(dv, mobiOff + 0xB4);
  const fragIndex = u32(dv, mobiOff + 0xE8);
  const skelIndex = u32(dv, mobiOff + 0xEC);
  const guideIndex = u32(dv, mobiOff + 0xF4);

  let bookTitle = '';
  if (fullNameOffset > 0 && fullNameLength > 0) {
    const tStart = r0 + fullNameOffset;
    const tEnd = tStart + fullNameLength;
    if (tEnd <= dv.byteLength) {
      bookTitle = decodeBytes(new Uint8Array(buffer, tStart, fullNameLength), encoding).trim();
    }
  }
  if (!bookTitle) {
    bookTitle = readAscii(dv, r0, 32).trim();
  }

  let author = '';
  let language = 'zh-CN';
  let coverImageIndex = -1;
  let boundaryRecordIndex = -1;

  if ((exthFlags & 0x40) !== 0 && mobiHeaderLen > 0) {
    const exthStart = mobiOff + mobiHeaderLen;
    if (exthStart + 12 <= dv.byteLength && readAscii(dv, exthStart, 4) === 'EXTH') {
      const exthLen = u32(dv, exthStart + 4);
      const exthCount = u32(dv, exthStart + 8);
      let pos = exthStart + 12;
      for (let i = 0; i < exthCount && pos + 8 <= exthStart + exthLen && pos + 8 <= dv.byteLength; i++) {
        const recType = u32(dv, pos);
        const recLen = u32(dv, pos + 4);
        if (recLen < 8) {
          break;
        }
        const dataStart = pos + 8;
        const dataLen = recLen - 8;
        const safeDataLen = Math.min(dataLen, dv.byteLength - dataStart);

        if (safeDataLen > 0) {
          const recBytes = new Uint8Array(buffer, dataStart, safeDataLen);
          switch (recType) {
            case EXTH_AUTHOR:
            case EXTH_CONTRIBUTOR:
              if (!author) {
                author = decodeBytes(recBytes, encoding).trim();
              }
              break;
            case EXTH_TITLE:
              if (!bookTitle) {
                bookTitle = decodeBytes(recBytes, encoding).trim();
              }
              break;
            case EXTH_LANGUAGE:
              language = decodeBytes(recBytes, encoding).trim() || 'zh-CN';
              break;
            case EXTH_COVER_OFFSET:
              if (safeDataLen >= 4) {
                const coverOff = u32(dv, dataStart);
                if (coverOff !== INVALID_RECORD_INDEX) {
                  const imgBase = firstImageRecord !== INVALID_RECORD_INDEX ? firstImageRecord : firstNonBookRecord;
                  if (imgBase !== INVALID_RECORD_INDEX) {
                    coverImageIndex = imgBase + coverOff;
                  }
                }
              }
              break;
            case EXTH_BOUNDARY:
              if (safeDataLen >= 4) {
                const boundary = u32(dv, dataStart);
                if (boundary !== INVALID_RECORD_INDEX) {
                  boundaryRecordIndex = boundary;
                }
              }
              break;
            default:
              break;
          }
        }
        pos += recLen;
      }
    }
  }

  return {
    recordBase: recordBase,
    compression: compression,
    textRecordCount: textRecordCount,
    recordSize: recordSize,
    mobiHeaderLen: mobiHeaderLen,
    encoding: encoding,
    fileVersion: fileVersion,
    firstNonBookRecord: firstNonBookRecord,
    firstImageRecord: firstImageRecord,
    exthFlags: exthFlags,
    drmOffset: drmOffset,
    drmCount: drmCount,
    trailingFlags: trailingFlags,
    huffcdicRecord: huffcdicRecord,
    huffcdicRecordCount: huffcdicRecordCount,
    ncxIndex: ncxIndex,
    fdstRecord: fdstRecord,
    fdstRecordCount: fdstRecordCount,
    fragIndex: fragIndex,
    skelIndex: skelIndex,
    guideIndex: guideIndex,
    title: bookTitle || '未知书名',
    author: author,
    language: language,
    coverImageIndex: coverImageIndex,
    boundaryRecordIndex: boundaryRecordIndex
  };
}

function getHeaderImageBase(header: MobiHeaderInfo): number {
  if (header.firstImageRecord !== INVALID_RECORD_INDEX) {
    return header.firstImageRecord;
  }
  if (header.firstNonBookRecord !== INVALID_RECORD_INDEX) {
    return header.firstNonBookRecord;
  }
  return -1;
}

function isDrmProtected(header: MobiHeaderInfo): boolean {
  return header.drmOffset !== INVALID_RECORD_INDEX &&
    header.drmCount > 0 &&
    header.drmCount !== INVALID_RECORD_INDEX;
}

function buildMobiTextBytes(buffer: ArrayBuffer, records: PalmRecord[], header: MobiHeaderInfo): MobiTextBytesResult {
  const chunks: Uint8Array[] = [];
  const availableTextRecords = Math.max(0, records.length - header.recordBase - 1);
  const actualTextCount = Math.min(header.textRecordCount, availableTextRecords);
  for (let i = 0; i < actualTextCount; i++) {
    const recordIndex = header.recordBase + i + 1;
    const recData = readRecordBytes(buffer, records, recordIndex);
    if (recData.byteLength <= 0) {
      continue;
    }
    chunks.push(decompressTextRecordData(recData, header.compression, header.trailingFlags));
  }

  const totalSize = chunks.reduce((sum: number, chunk: Uint8Array) => sum + chunk.byteLength, 0);
  const allText = new Uint8Array(totalSize);
  let offset = 0;
  for (const chunk of chunks) {
    allText.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return {
    bytes: allText,
    actualTextCount: actualTextCount
  };
}

function readMobiVarInt(bytes: Uint8Array, start: number): number[] {
  let value = 0;
  let pos = Math.max(0, start);
  let consumed = 0;
  while (pos < bytes.byteLength && consumed < 4) {
    const byte = bytes[pos];
    value = (value << 7) | (byte & 0x7F);
    pos++;
    consumed++;
    if ((byte & 0x80) !== 0) {
      break;
    }
  }
  return [value, consumed];
}

function readMobiIndxHeader(recordData: Uint8Array): MobiIndexHeader | null {
  if (recordData.byteLength < 56 || readAsciiBytes(recordData, 0, 4) !== 'INDX') {
    return null;
  }
  return {
    length: u32Bytes(recordData, 4),
    idxt: u32Bytes(recordData, 20),
    numRecords: u32Bytes(recordData, 24),
    numCncx: u32Bytes(recordData, 52)
  };
}

function readMobiTagxHeader(tagxData: Uint8Array): MobiTagxHeader | null {
  if (tagxData.byteLength < 12 || readAsciiBytes(tagxData, 0, 4) !== 'TAGX') {
    return null;
  }
  return {
    length: u32Bytes(tagxData, 4),
    numControlBytes: u32Bytes(tagxData, 8)
  };
}

function readMobiTagxTags(tagxHeader: MobiTagxHeader, tagxData: Uint8Array): MobiTagxTag[] {
  const tags: MobiTagxTag[] = [];
  const numTags = Math.floor(Math.max(0, tagxHeader.length - 12) / 4);
  for (let i = 0; i < numTags; i++) {
    const offset = 12 + i * 4;
    if (offset + 4 > tagxData.byteLength) {
      break;
    }
    tags.push({
      tag: u8Bytes(tagxData, offset),
      numValues: u8Bytes(tagxData, offset + 1),
      bitmask: u8Bytes(tagxData, offset + 2),
      controlByte: u8Bytes(tagxData, offset + 3)
    });
  }
  return tags;
}

function readMobiIdxtOffsets(recordData: Uint8Array, indxHeader: MobiIndexHeader): number[] {
  const offsets: number[] = [];
  const start = indxHeader.idxt + 4;
  for (let i = 0; i < indxHeader.numRecords; i++) {
    const offset = start + i * 2;
    if (offset + 2 > recordData.byteLength) {
      break;
    }
    offsets.push(u16Bytes(recordData, offset));
  }
  return offsets;
}

function readMobiIndexEntry(
  recordData: Uint8Array,
  tagxHeader: MobiTagxHeader,
  tagTable: MobiTagxTag[],
  idxtOffset: number,
  encoding: number
): MobiIndexEntry | null {
  if (idxtOffset < 0 || idxtOffset >= recordData.byteLength) {
    return null;
  }
  const labelLength = u8Bytes(recordData, idxtOffset);
  const label = decodeRecordString(recordData, idxtOffset + 1, labelLength, encoding);
  const ptagxs: MobiPtagx[] = [];
  const startPos = idxtOffset + 1 + labelLength;
  let controlByteIndex = 0;
  let pos = startPos + tagxHeader.numControlBytes;

  for (const tag of tagTable) {
    if (tag.controlByte === 1) {
      controlByteIndex++;
      continue;
    }
    const controlOffset = startPos + controlByteIndex;
    if (controlOffset >= recordData.byteLength) {
      break;
    }
    let value = u8Bytes(recordData, controlOffset) & tag.bitmask;
    if (value === tag.bitmask) {
      if (countSetBits(tag.bitmask) > 1) {
        const varResult = readMobiVarInt(recordData, pos);
        pos += varResult[1];
        ptagxs.push({
          tag: tag.tag,
          tagValueCount: tag.numValues,
          valueCount: 0,
          valueBytes: varResult[0],
          usesByteCount: true
        });
      } else {
        ptagxs.push({
          tag: tag.tag,
          tagValueCount: tag.numValues,
          valueCount: 1,
          valueBytes: 0,
          usesByteCount: false
        });
      }
    } else {
      let mask = tag.bitmask;
      while ((mask & 1) === 0 && mask > 0) {
        mask = mask >> 1;
        value = value >> 1;
      }
      ptagxs.push({
        tag: tag.tag,
        tagValueCount: tag.numValues,
        valueCount: value,
        valueBytes: 0,
        usesByteCount: false
      });
    }
  }

  const tagMap: Map<number, MobiIndexTag> = new Map();
  for (const ptagx of ptagxs) {
    const values: number[] = [];
    if (ptagx.usesByteCount) {
      let consumedBytes = 0;
      while (consumedBytes < ptagx.valueBytes && pos < recordData.byteLength) {
        const varResult = readMobiVarInt(recordData, pos);
        if (varResult[1] <= 0) {
          break;
        }
        values.push(varResult[0]);
        pos += varResult[1];
        consumedBytes += varResult[1];
      }
    } else {
      const totalValues = ptagx.valueCount * ptagx.tagValueCount;
      for (let i = 0; i < totalValues && pos < recordData.byteLength; i++) {
        const varResult = readMobiVarInt(recordData, pos);
        if (varResult[1] <= 0) {
          break;
        }
        values.push(varResult[0]);
        pos += varResult[1];
      }
    }
    tagMap.set(ptagx.tag, {
      tagId: ptagx.tag,
      values: values
    });
  }

  return {
    label: label,
    tagMap: tagMap
  };
}

function readMobiCncx(
  buffer: ArrayBuffer,
  records: PalmRecord[],
  header: MobiHeaderInfo,
  indxIndex: number,
  indxHeader: MobiIndexHeader
): Map<number, string> {
  const cncx: Map<number, string> = new Map();
  let cncxRecordOffset = 0;
  for (let i = 0; i < indxHeader.numCncx; i++) {
    const recordIndex = header.recordBase + indxIndex + indxHeader.numRecords + i + 1;
    const recordData = readRecordBytes(buffer, records, recordIndex);
    let pos = 0;
    while (pos < recordData.byteLength) {
      const index = pos;
      const varResult = readMobiVarInt(recordData, pos);
      if (varResult[1] <= 0) {
        break;
      }
      pos += varResult[1];
      const stringLength = varResult[0];
      if (stringLength <= 0 || pos + stringLength > recordData.byteLength) {
        break;
      }
      cncx.set(cncxRecordOffset + index, decodeRecordString(recordData, pos, stringLength, header.encoding));
      pos += stringLength;
    }
    cncxRecordOffset += 0x10000;
  }
  return cncx;
}

function readMobiIndexData(
  buffer: ArrayBuffer,
  records: PalmRecord[],
  header: MobiHeaderInfo,
  indxIndex: number
): MobiIndexData | null {
  if (indxIndex < 0 || indxIndex === INVALID_RECORD_INDEX) {
    return null;
  }
  const indxRecord = readRecordBytes(buffer, records, header.recordBase + indxIndex);
  const indxHeader = readMobiIndxHeader(indxRecord);
  if (!indxHeader) {
    return null;
  }
  if (indxHeader.length >= indxRecord.byteLength) {
    return null;
  }
  const tagxData = indxRecord.slice(indxHeader.length);
  const tagxHeader = readMobiTagxHeader(tagxData);
  if (!tagxHeader) {
    return null;
  }
  const tagTable = readMobiTagxTags(tagxHeader, tagxData);
  const cncx = readMobiCncx(buffer, records, header, indxIndex, indxHeader);
  const table: MobiIndexEntry[] = [];

  for (let i = 0; i < indxHeader.numRecords; i++) {
    const recordData = readRecordBytes(buffer, records, header.recordBase + indxIndex + 1 + i);
    const recordHeader = readMobiIndxHeader(recordData);
    if (!recordHeader) {
      continue;
    }
    const idxtOffsets = readMobiIdxtOffsets(recordData, recordHeader);
    for (const idxtOffset of idxtOffsets) {
      const entry = readMobiIndexEntry(recordData, tagxHeader, tagTable, idxtOffset, header.encoding);
      if (entry) {
        table.push(entry);
      }
    }
  }

  return {
    table: table,
    cncx: cncx
  };
}

function getMobiIndexTagValues(tagMap: Map<number, MobiIndexTag>, tagId: number): number[] {
  const tag = tagMap.get(tagId);
  return tag ? tag.values : [];
}

function readMobiSkeletonTable(buffer: ArrayBuffer, records: PalmRecord[], header: MobiHeaderInfo): MobiSkeleton[] {
  const indexData = readMobiIndexData(buffer, records, header, header.skelIndex);
  if (!indexData) {
    return [];
  }
  const skeletons: MobiSkeleton[] = [];
  for (let i = 0; i < indexData.table.length; i++) {
    const entry = indexData.table[i];
    const numFragValues = getMobiIndexTagValues(entry.tagMap, 1);
    const offsetLengthValues = getMobiIndexTagValues(entry.tagMap, 6);
    if (numFragValues.length <= 0 || offsetLengthValues.length < 2) {
      continue;
    }
    skeletons.push({
      index: i,
      name: entry.label,
      numFrag: numFragValues[0],
      offset: offsetLengthValues[0],
      length: offsetLengthValues[1]
    });
  }
  return skeletons;
}

function readMobiFragmentTable(buffer: ArrayBuffer, records: PalmRecord[], header: MobiHeaderInfo): MobiFragment[] {
  const indexData = readMobiIndexData(buffer, records, header, header.fragIndex);
  if (!indexData) {
    return [];
  }
  const fragments: MobiFragment[] = [];
  for (const entry of indexData.table) {
    const selectorValues = getMobiIndexTagValues(entry.tagMap, 2);
    const indexValues = getMobiIndexTagValues(entry.tagMap, 4);
    const offsetLengthValues = getMobiIndexTagValues(entry.tagMap, 6);
    if (indexValues.length <= 0 || offsetLengthValues.length < 2) {
      continue;
    }
    const insertOffset = Number(entry.label);
    if (!Number.isFinite(insertOffset)) {
      continue;
    }
    const selector = selectorValues.length > 0 ? (indexData.cncx.get(selectorValues[0]) || '') : '';
    fragments.push({
      insertOffset: Math.floor(insertOffset),
      selector: selector,
      index: indexValues[0],
      offset: offsetLengthValues[0],
      length: offsetLengthValues[1]
    });
  }
  return fragments;
}

function assembleKf8SectionText(
  allText: Uint8Array,
  skeleton: MobiSkeleton,
  fragments: MobiFragment[],
  encoding: number
): string {
  const fragmentLength = fragments.reduce((sum: number, fragment: MobiFragment) => sum + Math.max(0, fragment.length), 0);
  const sectionLength = Math.max(0, skeleton.length) + fragmentLength;
  if (sectionLength <= 0 || skeleton.offset < 0 || skeleton.offset >= allText.byteLength) {
    return '';
  }
  const rawEnd = Math.min(allText.byteLength, skeleton.offset + sectionLength);
  const raw = allText.slice(skeleton.offset, rawEnd);
  if (raw.byteLength <= 0) {
    return '';
  }

  const output = new Uint8Array(raw.byteLength);
  const skeletonLength = Math.min(Math.max(0, skeleton.length), raw.byteLength);
  output.set(raw.slice(0, skeletonLength), 0);
  let usedLength = skeletonLength;

  for (const fragment of fragments) {
    if (fragment.length <= 0) {
      continue;
    }
    const insertOffset = Math.max(0, Math.min(usedLength, fragment.insertOffset - skeleton.offset));
    const rawOffset = skeletonLength + fragment.offset;
    const rawEndOffset = rawOffset + fragment.length;
    if (rawOffset < 0 || rawEndOffset > raw.byteLength || usedLength + fragment.length > output.byteLength) {
      continue;
    }
    for (let j = usedLength - 1; j >= insertOffset; j--) {
      output[j + fragment.length] = output[j];
    }
    output.set(raw.slice(rawOffset, rawEndOffset), insertOffset);
    usedLength += fragment.length;
  }

  return decodeBytes(output.slice(0, usedLength), encoding);
}

function buildKf8HtmlFromIndexes(
  buffer: ArrayBuffer,
  records: PalmRecord[],
  header: MobiHeaderInfo,
  allText: Uint8Array
): MobiKf8BuildResult {
  if (header.fileVersion < 8 || header.skelIndex <= 0 || header.fragIndex <= 0) {
    return {
      html: '',
      sectionCount: 0
    };
  }

  try {
    const skeletons = readMobiSkeletonTable(buffer, records, header);
    const fragments = readMobiFragmentTable(buffer, records, header);
    if (skeletons.length <= 0 || fragments.length <= 0) {
      return {
        html: '',
        sectionCount: 0
      };
    }

    const htmlParts: string[] = [];
    let fragStart = 0;
    for (const skeleton of skeletons) {
      const fragEnd = Math.min(fragments.length, fragStart + Math.max(0, skeleton.numFrag));
      const sectionFragments = fragments.slice(fragStart, fragEnd);
      fragStart = fragEnd;
      const sectionHtml = assembleKf8SectionText(allText, skeleton, sectionFragments, header.encoding);
      if (isLikelyHtmlOrTextFragment(sectionHtml)) {
        htmlParts.push(sectionHtml);
      }
    }

    return {
      html: htmlParts.join('\n'),
      sectionCount: htmlParts.length
    };
  } catch (error) {
    logger.warn(TAG, `KF8 索引重组失败，回退到原始文本流: ${String(error)}`);
    return {
      html: '',
      sectionCount: 0
    };
  }
}

function extractFdstFlowHtml(
  buffer: ArrayBuffer,
  records: PalmRecord[],
  header: MobiHeaderInfo,
  allText: Uint8Array
): string {
  if (header.fileVersion < 8 || header.fdstRecord <= 0 || header.fdstRecord === INVALID_RECORD_INDEX) {
    return '';
  }
  const fdstRecord = readRecordBytes(buffer, records, header.recordBase + header.fdstRecord);
  if (fdstRecord.byteLength < 12 || readAsciiBytes(fdstRecord, 0, 4) !== 'FDST') {
    return '';
  }
  const count = u32Bytes(fdstRecord, 8);
  const fragments: string[] = [];
  for (let i = 0; i < count; i++) {
    const entryOffset = 12 + i * 8;
    if (entryOffset + 8 > fdstRecord.byteLength) {
      break;
    }
    const start = u32Bytes(fdstRecord, entryOffset);
    const end = u32Bytes(fdstRecord, entryOffset + 4);
    if (end <= start || start >= allText.byteLength) {
      continue;
    }
    const safeEnd = Math.min(end, allText.byteLength);
    const decoded = decodeBytes(allText.slice(start, safeEnd), header.encoding);
    if (isLikelyHtmlOrTextFragment(decoded)) {
      fragments.push(decoded);
    }
  }
  return fragments.join('\n');
}

/**
 * Convert a MOBI/AZW file to a pseudo-EPUB extracted directory.
 * Supports MOBI/KF8 text records with no-compression or LZ77 (PalmDOC) compression.
 * Returns the extraction root path on success.
 */
export async function convertMobiToExtractedDir(filePath: string): Promise<MobiConversionResult> {
  const fail = (msg: string): MobiConversionResult => ({
    success: false,
    extractedRootPath: '',
    errorMessage: msg,
    title: '',
    author: '',
    coverImagePath: '',
    chapterCount: 0
  });

  try {
    const normalizedPath = filePath.startsWith('file://') ? filePath.substring(7) : filePath;

    // --- Read file ---
    const fileHandle = fileIo.openSync(normalizedPath, fileIo.OpenMode.READ_ONLY);
    const stat = fileIo.statSync(fileHandle.fd);
    const buffer = new ArrayBuffer(stat.size);
    fileIo.readSync(fileHandle.fd, buffer);
    fileIo.closeSync(fileHandle);

    const dv = new DataView(buffer);

    // --- Validate Palm DB magic ---
    if (dv.byteLength < 78) {
      return fail('文件太小，不是有效的MOBI文件');
    }
    const dbType = readAscii(dv, 60, 4);
    const dbCreator = readAscii(dv, 64, 4);
    if (dbType !== 'BOOK' || (dbCreator !== 'MOBI' && dbCreator !== 'REZA')) {
      return fail(`不是有效的MOBI文件 (type=${dbType}, creator=${dbCreator})`);
    }

    // --- Parse record list ---
    const numRecords = u16(dv, 76);
    if (numRecords < 2) {
      return fail(`无效的记录数: ${numRecords}`);
    }
    const records: PalmRecord[] = [];
    for (let i = 0; i < numRecords; i++) {
      records.push({ offset: u32(dv, 78 + i * 8) });
    }

    // --- PalmDOC + MOBI headers ---
    const initialHeader = parseMobiHeaderInfo(buffer, records, 0);
    if (!initialHeader) {
      return fail('缺少MOBI头部标识');
    }

    let header = initialHeader;
    if (initialHeader.fileVersion < 8 &&
      initialHeader.boundaryRecordIndex > 0 &&
      initialHeader.boundaryRecordIndex < records.length) {
      const boundaryHeader = parseMobiHeaderInfo(buffer, records, initialHeader.boundaryRecordIndex);
      if (boundaryHeader && boundaryHeader.fileVersion >= 8) {
        header = boundaryHeader;
        logger.info(
          TAG,
          `检测到组合 MOBI/AZW3 KF8 边界，切换到 KF8 记录区: boundary=${initialHeader.boundaryRecordIndex}, version=${boundaryHeader.fileVersion}`
        );
      }
    }

    const compression = header.compression;
    const textRecordCount = header.textRecordCount;
    const encoding = header.encoding;
    const fileVersion = header.fileVersion;
    const imageBaseFromHeader = getHeaderImageBase(header);
    const imageBaseFromInitialHeader = getHeaderImageBase(initialHeader);
    const imgBase = imageBaseFromInitialHeader >= 0 ? imageBaseFromInitialHeader :
      (imageBaseFromHeader >= 0 ? imageBaseFromHeader : records.length);

    if (compression === COMPRESSION_HUFFDIC) {
      return fail('HUFFDIC压缩格式暂不支持本地转换，将尝试使用ReaderKit打开');
    }
    if (compression !== COMPRESSION_NONE && compression !== COMPRESSION_PALMDOC) {
      return fail(`未知压缩格式: ${compression}`);
    }

    if (isDrmProtected(initialHeader) || isDrmProtected(header)) {
      return fail('该文件有DRM保护，无法直接阅读。请使用已解除DRM保护的文件。');
    }

    const meta: MobiMetadata = {
      title: header.title || initialHeader.title || '未知书名',
      author: header.author || initialHeader.author,
      language: header.language || initialHeader.language || 'zh-CN',
      coverImageIndex: initialHeader.coverImageIndex >= 0 ? initialHeader.coverImageIndex : header.coverImageIndex
    };

    logger.info(
      TAG,
      `MOBI头信息: version=${fileVersion}, compression=${compression}, recordBase=${header.recordBase}, ` +
        `textRecordCount=${textRecordCount}, records=${records.length}, resourceStart=${imgBase}, ` +
        `trailingFlags=${header.trailingFlags}, fdst=${header.fdstRecord}, skel=${header.skelIndex}, frag=${header.fragIndex}`
    );

    // --- Build output directory ---
    const lastSlash = normalizedPath.lastIndexOf('/');
    const parentDir = lastSlash > 0 ? normalizedPath.substring(0, lastSlash) : '';
    const baseName = normalizedPath.substring(lastSlash + 1).replace(/\.[^.]+$/, '');
    const safeBase = baseName.replace(/[^0-9A-Za-z_\-一-鿿]+/g, '_').replace(/_+/g, '_');
    const hash = hashFilePath(normalizedPath);
    const extractRoot = `${parentDir}/__mobi_conv_${safeBase}_${hash}`;
    const opfPath = `${extractRoot}/OEBPS/content.opf`;

    // --- Return cached result if already converted ---
    if (pathExists(opfPath) && isCachedImageDirectoryUsable(extractRoot) && isMobiConversionCacheCurrent(extractRoot)) {
      let cachedChapters = 1;
      try {
        const f = fileIo.openSync(opfPath, fileIo.OpenMode.READ_ONLY);
        const s = fileIo.statSync(f.fd);
        const b = new ArrayBuffer(s.size);
        fileIo.readSync(f.fd, b);
        fileIo.closeSync(f);
        const opfText = decodeBytes(new Uint8Array(b), ENCODING_UTF8);
        const itemrefMatches = opfText.match(/<itemref /g);
        cachedChapters = itemrefMatches ? itemrefMatches.length : 1;
      } catch (e) {
        logger.warn(TAG, `读取缓存OPF失败: ${String(e)}`);
      }
      const coverPath = findCachedCoverPath(extractRoot);
      return {
        success: true,
        extractedRootPath: extractRoot,
        errorMessage: '',
        title: meta.title,
        author: meta.author,
        coverImagePath: coverPath,
        chapterCount: cachedChapters
      };
    } else if (pathExists(opfPath)) {
      logger.warn(TAG, `MOBI 转换缓存需要更新，重新生成: ${extractRoot}`);
    }

    // --- Create directories ---
    ensureDirectory(extractRoot);
    ensureDirectory(`${extractRoot}/META-INF`);
    ensureDirectory(`${extractRoot}/OEBPS`);
    ensureDirectory(`${extractRoot}/OEBPS/Images`);

    writeTextFile(`${extractRoot}/META-INF/container.xml`, buildContainer());

    // --- Decompress text records ---
    const textBytesResult = buildMobiTextBytes(buffer, records, header);
    const allText = textBytesResult.bytes;
    const htmlText = decodeBytes(allText, encoding);

    // --- Extract images ---
    const imageFileMap = new Map<number, string>();
    let coverImagePath = '';

    for (let i = imgBase; i < records.length; i++) {
      const recStart = records[i].offset;
      const recEnd = i + 1 < records.length ? records[i + 1].offset : dv.byteLength;
      const recSize = recEnd - recStart;
      if (recSize < 4 || recStart >= dv.byteLength) {
        continue;
      }
      const safeSize = Math.min(recSize, dv.byteLength - recStart);
      const imgData = new Uint8Array(buffer, recStart, safeSize);
      const ext = detectImageExtension(imgData);

      // Skip non-image records (e.g. FLIS, FCIS boundary records)
      const first4 = readAscii(dv, recStart, 4);
      if (ext.length <= 0 || first4 === 'FLIS' || first4 === 'FCIS' || first4 === 'BOUN' || first4 === 'DATP') {
        continue;
      }

      const recIdx = i - imgBase;
      const imageNum = String(recIdx + 1).padStart(4, '0');
      const imageFileName = `image${imageNum}${ext}`;
      imageFileMap.set(recIdx, imageFileName);

      try {
        writeBinaryFile(`${extractRoot}/OEBPS/Images/${imageFileName}`, imgData);
        if (i === meta.coverImageIndex) {
          const coverFile = `${extractRoot}/OEBPS/Images/cover${ext}`;
          writeBinaryFile(coverFile, imgData);
          coverImagePath = coverFile;
        }
      } catch (e) {
        logger.warn(TAG, `写入图片失败 record=${i}: ${String(e)}`);
      }
    }

    // --- Post-process HTML ---
    let sourceHtmlText = htmlText;
    if (fileVersion >= 8) {
      const kf8BuildResult = buildKf8HtmlFromIndexes(buffer, records, header, allText);
      if (kf8BuildResult.html.length > 0) {
        sourceHtmlText = kf8BuildResult.html;
        logger.info(TAG, `KF8 索引重组提取正文成功: sections=${kf8BuildResult.sectionCount}, length=${sourceHtmlText.length}`);
      }
    }
    let processedHtml = postProcessMobiHtml(sourceHtmlText, imageFileMap);

    // Extract body content
    let bodyContent = extractMobiBodyContent(processedHtml);
    bodyContent = normalizeMobiBodyContent(bodyContent);
    if (bodyContent.length <= 0) {
      logger.warn(
        TAG,
        `${fileVersion === 8 ? 'AZW3/KF8' : 'MOBI'} 标准文本记录为空，尝试扫描全部记录提取正文: ` +
          `textRecordCount=${textRecordCount}, actualTextCount=${textBytesResult.actualTextCount}, ` +
          `recordBase=${header.recordBase}, records=${records.length}`
      );
      const fdstHtmlText = extractFdstFlowHtml(buffer, records, header, allText);
      if (fdstHtmlText.length > 0) {
        processedHtml = postProcessMobiHtml(fdstHtmlText, imageFileMap);
        bodyContent = extractMobiBodyContent(processedHtml);
        bodyContent = normalizeMobiBodyContent(bodyContent);
        logger.info(TAG, `${fileVersion === 8 ? 'AZW3/KF8' : 'MOBI'} FDST flow 提取正文: length=${bodyContent.length}`);
      }
      const scannedHtmlText = collectTextFromRecordRange(
        buffer,
        records,
        compression,
        encoding,
        header.trailingFlags,
        header.recordBase + 1,
        records.length,
        false
      );
      if (bodyContent.length <= 0 && scannedHtmlText.length > 0) {
        processedHtml = postProcessMobiHtml(scannedHtmlText, imageFileMap);
        bodyContent = extractMobiBodyContent(processedHtml);
        bodyContent = normalizeMobiBodyContent(bodyContent);
      }
      if (bodyContent.length <= 0) {
        return fail(`未提取到可阅读的${fileVersion === 8 ? 'AZW3/KF8' : 'MOBI'}正文内容`);
      }
      logger.info(TAG, `${fileVersion === 8 ? 'AZW3/KF8' : 'MOBI'} 全记录扫描提取正文成功: length=${bodyContent.length}`);
    }

    // --- Split and write chapters ---
    const chapters = buildChapterData(bodyContent);
    for (let i = 0; i < chapters.length; i++) {
      const n = String(i + 1).padStart(3, '0');
      writeTextFile(
        `${extractRoot}/OEBPS/chapter${n}.html`,
        buildChapterHtml(chapters[i].body, chapters[i].title, i + 1)
      );
    }

    // --- Write OPF, NCX, CSS ---
    const coverFileName = coverImagePath.length > 0
      ? coverImagePath.substring(coverImagePath.lastIndexOf('/') + 1)
      : '';
    const manifestImageFileNames: string[] = [];
    const seenManifestImageNames: Set<string> = new Set();
    for (const imageFileName of imageFileMap.values()) {
      if (!seenManifestImageNames.has(imageFileName)) {
        seenManifestImageNames.add(imageFileName);
        manifestImageFileNames.push(imageFileName);
      }
    }
    if (coverFileName.length > 0 && !seenManifestImageNames.has(coverFileName)) {
      manifestImageFileNames.push(coverFileName);
    }
    writeTextFile(
      `${extractRoot}/OEBPS/content.opf`,
      buildOpf(meta.title, meta.author, meta.language, chapters.length, coverFileName, manifestImageFileNames)
    );
    writeTextFile(`${extractRoot}/OEBPS/toc.ncx`, buildTocNcx(meta.title, chapters));
    writeTextFile(`${extractRoot}/OEBPS/style.css`, buildStyle());
    writeTextFile(`${extractRoot}/${MOBI_CONVERSION_MARKER_FILE}`, MOBI_CONVERSION_VERSION);

    logger.info(TAG, `MOBI转换完成: "${meta.title}" → ${extractRoot}, ${chapters.length}章`);

    return {
      success: true,
      extractedRootPath: extractRoot,
      errorMessage: '',
      title: meta.title,
      author: meta.author,
      coverImagePath,
      chapterCount: chapters.length
    };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    logger.error(TAG, `MOBI转换失败: ${msg}`);
    return fail(msg);
  }
}
