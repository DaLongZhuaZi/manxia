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

// PalmDOC compression types
const COMPRESSION_NONE = 1;
const COMPRESSION_PALMDOC = 2;
const COMPRESSION_HUFFDIC = 17480;

// Text encoding
const ENCODING_UTF8 = 65001;

// EXTH record types
const EXTH_AUTHOR = 100;
const EXTH_CONTRIBUTOR = 108;
const EXTH_LANGUAGE = 524;
const EXTH_COVER_OFFSET = 201;

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
  if (data.length >= 4 &&
    data[0] === 0x52 && data[1] === 0x49 && data[2] === 0x46 && data[3] === 0x46) {
    return '.webp';
  }
  return '.jpg';
}

function escapeXml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function postProcessMobiHtml(html: string, imageFileMap: Map<number, string>): string {
  let result = html;

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

  result = result.replace(/<mbp:pagebreak\s*\/?>/gi, '<hr class="mnx-page-break"/>');
  result = result.replace(/<\/?mbp:[^>]+>/gi, '');
  result = result.replace(/\s*filepos\s*=\s*["']?\d+["']?/gi, '');

  return result;
}

function splitIntoChapters(bodyHtml: string): string[] {
  const breakPattern = /<hr\s+class="mnx-page-break"\s*\/?>/gi;
  const rawParts = bodyHtml.split(breakPattern);

  if (rawParts.length > 1) {
    const chapters: string[] = [];
    for (const part of rawParts) {
      const trimmed = part.trim();
      if (trimmed.length > 50) {
        chapters.push(trimmed);
      } else if (chapters.length > 0) {
        chapters[chapters.length - 1] += '\n' + trimmed;
      }
    }
    if (chapters.length > 0) {
      return chapters;
    }
  }

  // Try heading-based splitting
  const headingPattern = /(?=<h[12]\b)/gi;
  const headingParts = bodyHtml.split(headingPattern);
  if (headingParts.length > 2) {
    const MAX_CHAPTER_SIZE = 60000;
    const chapters: string[] = [];
    let current = '';
    for (const part of headingParts) {
      current += part;
      if (current.length >= MAX_CHAPTER_SIZE) {
        chapters.push(current);
        current = '';
      }
    }
    if (current.length > 0) {
      chapters.push(current);
    }
    return chapters.length > 0 ? chapters : [bodyHtml];
  }

  // Size-based splitting for very long single-chapter books
  const SIZE_LIMIT = 80000;
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
  hasCover: boolean
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

  const coverMeta = hasCover ? '    <meta name="cover" content="cover-image"/>\n' : '';
  const coverItem = hasCover
    ? '    <item id="cover-image" href="Images/cover.jpg" media-type="image/jpeg"/>\n'
    : '';

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
${coverItem}${chapterItems}
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

function buildTocNcx(title: string, chapterCount: number): string {
  const navPointParts: string[] = [];
  for (let i = 0; i < chapterCount; i++) {
    const n = String(i + 1).padStart(3, '0');
    navPointParts.push(`  <navPoint id="nav${n}" playOrder="${i + 1}">
    <navLabel><text>第${i + 1}章</text></navLabel>
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
img { max-width: 100%; height: auto; display: block; margin: 0.5em auto; }`;
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
  fileIo.writeSync(file.fd, data.buffer as ArrayBuffer, {
    offset: data.byteOffset,
    length: data.byteLength
  });
  fileIo.closeSync(file);
}

function pathExists(path: string): boolean {
  try {
    fileIo.statSync(path);
    return true;
  } catch {
    return false;
  }
}

function hashFilePath(path: string): string {
  let hash = 5381;
  for (let i = 0; i < path.length; i++) {
    hash = (((hash << 5) + hash) ^ path.charCodeAt(i)) | 0;
  }
  return Math.abs(hash).toString(36);
}

function decodeBytes(bytes: Uint8Array, _encoding: number): string {
  try {
    return new util.TextDecoder('utf-8', { ignoreBOM: true }).decodeToString(bytes);
  } catch {
    // Fallback: treat each byte as Latin-1 character
    let result = '';
    for (let i = 0; i < bytes.length; i++) {
      result += String.fromCharCode(bytes[i]);
    }
    return result;
  }
}

/**
 * Convert a MOBI/AZW file to a pseudo-EPUB extracted directory.
 * Supports MOBI6 with no-compression or LZ77 (PalmDOC) compression.
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

    const data = new Uint8Array(buffer);
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

    // --- Record 0: PalmDOC + MOBI headers ---
    const r0 = records[0].offset;

    // PalmDOC header
    const compression = u16(dv, r0 + 0);
    const textRecordCount = u16(dv, r0 + 8);

    if (compression === COMPRESSION_HUFFDIC) {
      return fail('HUFFDIC压缩格式暂不支持，请在设置中禁用MOBI WebView后重试');
    }
    if (compression !== COMPRESSION_NONE && compression !== COMPRESSION_PALMDOC) {
      return fail(`未知压缩格式: ${compression}`);
    }

    // MOBI header (starts at r0 + 16)
    const mobiOff = r0 + 16;
    if (mobiOff + 4 > dv.byteLength || readAscii(dv, mobiOff, 4) !== 'MOBI') {
      return fail('缺少MOBI头部标识');
    }

    const mobiHeaderLen = u32(dv, mobiOff + 0x04);
    const encoding = u32(dv, mobiOff + 0x0C);
    const fileVersion = u32(dv, mobiOff + 0x14);

    // KF8/AZW3 — fall back to ReaderKit
    if (fileVersion === 8) {
      return fail('KF8_FALLBACK');
    }

    // firstNonBookRecord, fullName, firstImageRecord, EXTH flags
    const firstNonBookRecord = u32(dv, mobiOff + 0x40);
    const fullNameOffset = u32(dv, mobiOff + 0x44);
    const fullNameLength = u32(dv, mobiOff + 0x48);
    const firstImageRecord = u32(dv, mobiOff + 0x5C);
    const exthFlags = u32(dv, mobiOff + 0x70);

    // DRM check
    const drmOffset = u32(dv, mobiOff + 0x94);
    const drmCount = u32(dv, mobiOff + 0x98);
    if (drmOffset !== 0xFFFFFFFF && drmCount > 0 && drmCount !== 0xFFFFFFFF) {
      return fail('该文件有DRM保护，无法直接阅读。请使用已解除DRM保护的文件。');
    }

    // --- Read full title ---
    let bookTitle = '';
    if (fullNameOffset > 0 && fullNameLength > 0) {
      const tStart = r0 + fullNameOffset;
      const tEnd = tStart + fullNameLength;
      if (tEnd <= dv.byteLength) {
        bookTitle = decodeBytes(new Uint8Array(buffer, tStart, fullNameLength), encoding);
      }
    }
    if (!bookTitle) {
      bookTitle = readAscii(dv, r0, 32).trim();
    }

    // --- Parse EXTH metadata ---
    const meta: MobiMetadata = {
      title: bookTitle || '未知书名',
      author: '',
      language: 'zh-CN',
      coverImageIndex: -1
    };

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
                if (!meta.author) {
                  meta.author = decodeBytes(recBytes, encoding).trim();
                }
                break;
              case EXTH_LANGUAGE:
                meta.language = decodeBytes(recBytes, encoding).trim() || 'zh-CN';
                break;
              case EXTH_COVER_OFFSET:
                if (safeDataLen >= 4) {
                  const coverOff = u32(dv, dataStart);
                  if (coverOff !== 0xFFFFFFFF) {
                    const imgBase = firstImageRecord !== 0xFFFFFFFF ? firstImageRecord : firstNonBookRecord;
                    meta.coverImageIndex = imgBase + coverOff;
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

    // --- Build output directory ---
    const lastSlash = normalizedPath.lastIndexOf('/');
    const parentDir = lastSlash > 0 ? normalizedPath.substring(0, lastSlash) : '';
    const baseName = normalizedPath.substring(lastSlash + 1).replace(/\.[^.]+$/, '');
    const safeBase = baseName.replace(/[^0-9A-Za-z_\-一-鿿]+/g, '_').replace(/_+/g, '_');
    const hash = hashFilePath(normalizedPath);
    const extractRoot = `${parentDir}/__mobi_conv_${safeBase}_${hash}`;
    const opfPath = `${extractRoot}/OEBPS/content.opf`;

    // --- Return cached result if already converted ---
    if (pathExists(opfPath)) {
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
      const coverPath = meta.coverImageIndex >= 0 ? `${extractRoot}/OEBPS/Images/cover.jpg` : '';
      return {
        success: true,
        extractedRootPath: extractRoot,
        errorMessage: '',
        title: meta.title,
        author: meta.author,
        coverImagePath: coverPath,
        chapterCount: cachedChapters
      };
    }

    // --- Create directories ---
    fileIo.mkdirSync(extractRoot, true);
    fileIo.mkdirSync(`${extractRoot}/META-INF`, true);
    fileIo.mkdirSync(`${extractRoot}/OEBPS`, true);
    fileIo.mkdirSync(`${extractRoot}/OEBPS/Images`, true);

    writeTextFile(`${extractRoot}/META-INF/container.xml`, buildContainer());

    // --- Decompress text records ---
    const textChunks: Uint8Array[] = [];
    const actualTextCount = Math.min(textRecordCount, records.length - 1);
    for (let i = 1; i <= actualTextCount; i++) {
      const recStart = records[i].offset;
      const recEnd = i + 1 < records.length ? records[i + 1].offset : dv.byteLength;
      const recSize = recEnd - recStart;
      if (recSize <= 0 || recStart >= dv.byteLength) {
        continue;
      }
      const safeSize = Math.min(recSize, dv.byteLength - recStart);
      const recData = new Uint8Array(buffer, recStart, safeSize);
      textChunks.push(
        compression === COMPRESSION_PALMDOC ? decompressPalmDoc(recData) : recData
      );
    }

    // Concatenate all text
    const totalSize = textChunks.reduce((s: number, c: Uint8Array) => s + c.length, 0);
    const allText = new Uint8Array(totalSize);
    let off = 0;
    for (const chunk of textChunks) {
      allText.set(chunk, off);
      off += chunk.length;
    }
    const htmlText = decodeBytes(allText, encoding);

    // --- Extract images ---
    const imgBase = firstImageRecord !== 0xFFFFFFFF
      ? firstImageRecord
      : (firstNonBookRecord !== 0xFFFFFFFF ? firstNonBookRecord : records.length);
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
      if (first4 === 'FLIS' || first4 === 'FCIS' || first4 === 'BOUN' || first4 === 'DATP') {
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
    const processedHtml = postProcessMobiHtml(htmlText, imageFileMap);

    // Extract body content
    let bodyContent = processedHtml;
    const bodyMatch = processedHtml.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
    if (bodyMatch && bodyMatch[1]) {
      bodyContent = bodyMatch[1].trim();
    }

    // --- Split and write chapters ---
    const chapters = splitIntoChapters(bodyContent);
    for (let i = 0; i < chapters.length; i++) {
      const n = String(i + 1).padStart(3, '0');
      writeTextFile(
        `${extractRoot}/OEBPS/chapter${n}.html`,
        buildChapterHtml(chapters[i], meta.title, i + 1)
      );
    }

    // --- Write OPF, NCX, CSS ---
    writeTextFile(
      `${extractRoot}/OEBPS/content.opf`,
      buildOpf(meta.title, meta.author, meta.language, chapters.length, coverImagePath.length > 0)
    );
    writeTextFile(`${extractRoot}/OEBPS/toc.ncx`, buildTocNcx(meta.title, chapters.length));
    writeTextFile(`${extractRoot}/OEBPS/style.css`, buildStyle());

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
