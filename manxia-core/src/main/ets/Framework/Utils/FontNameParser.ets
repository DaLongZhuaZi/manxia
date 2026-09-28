import { SafeFileUtils } from '../../Utils/SafeFileUtils';
// 文件路径: entry/src/main/ets/Framework/Utils/FontNameParser.ets
/**
 * TTF/OTF 字体名称解析器
 * 解析字体文件内部的真实名称，支持中文、日文、韩文等多语言字体名称
 */

import { fileIo } from '@kit.CoreFileKit';
import { logger } from '../../Utils/Logger';

const TAG = 'FontNameParser';

// 字体名称ID常量 (OpenType规范)
const NAME_ID_COPYRIGHT: number = 0;
const NAME_ID_FONT_FAMILY: number = 1;           // 字体族名称
const NAME_ID_FONT_SUBFAMILY: number = 2;        // 字体子族名称 (Regular, Bold等)
const NAME_ID_UNIQUE_ID: number = 3;
const NAME_ID_FULL_NAME: number = 4;             // 完整字体名称
const NAME_ID_VERSION: number = 5;
const NAME_ID_POSTSCRIPT_NAME: number = 6;       // PostScript名称
const NAME_ID_TRADEMARK: number = 7;
const NAME_ID_MANUFACTURER: number = 8;
const NAME_ID_DESIGNER: number = 9;
const NAME_ID_DESCRIPTION: number = 10;
const NAME_ID_VENDOR_URL: number = 11;
const NAME_ID_DESIGNER_URL: number = 12;
const NAME_ID_LICENSE: number = 13;
const NAME_ID_LICENSE_URL: number = 14;
const NAME_ID_TYPOGRAPHIC_FAMILY: number = 16;   // 首选字体族名称
const NAME_ID_TYPOGRAPHIC_SUBFAMILY: number = 17;
const NAME_ID_SAMPLE_TEXT: number = 19;
const NAME_ID_CID_FONT_NAME: number = 20;

// 平台ID
const PLATFORM_ID_UNICODE: number = 0;
const PLATFORM_ID_MACINTOSH: number = 1;
const PLATFORM_ID_WINDOWS: number = 3;

// Windows编码ID
const WINDOWS_ENCODING_SYMBOL: number = 0;
const WINDOWS_ENCODING_UNICODE_BMP: number = 1;    // Unicode BMP (UCS-2)
const WINDOWS_ENCODING_SHIFT_JIS: number = 2;
const WINDOWS_ENCODING_PRC: number = 3;            // 简体中文 GB2312
const WINDOWS_ENCODING_BIG5: number = 4;           // 繁体中文
const WINDOWS_ENCODING_WANSUNG: number = 5;        // 韩文
const WINDOWS_ENCODING_JOHAB: number = 6;
const WINDOWS_ENCODING_UNICODE_FULL: number = 10;  // Unicode full (UCS-4)

// Windows语言ID
const WINDOWS_LANG_ENGLISH_US: number = 0x0409;
const WINDOWS_LANG_CHINESE_SIMPLIFIED: number = 0x0804;
const WINDOWS_LANG_CHINESE_TRADITIONAL: number = 0x0404;
const WINDOWS_LANG_JAPANESE: number = 0x0411;
const WINDOWS_LANG_KOREAN: number = 0x0412;

// Macintosh编码ID
const MAC_ENCODING_ROMAN: number = 0;
const MAC_ENCODING_JAPANESE: number = 1;
const MAC_ENCODING_CHINESE_TRADITIONAL: number = 2;
const MAC_ENCODING_KOREAN: number = 3;
const MAC_ENCODING_ARABIC: number = 4;
const MAC_ENCODING_HEBREW: number = 5;
const MAC_ENCODING_GREEK: number = 6;
const MAC_ENCODING_RUSSIAN: number = 7;
const MAC_ENCODING_CHINESE_SIMPLIFIED: number = 25;

// 解析结果接口
export interface FontNameInfo {
  familyName: string;           // 字体族名称
  fullName: string;             // 完整名称
  postScriptName: string;       // PostScript名称
  displayName: string;          // 推荐显示名称 (优先本地化名称)
  localizedFamilyName?: string; // 本地化字体族名称 (中文等)
  localizedFullName?: string;   // 本地化完整名称
  subfamily?: string;           // 子族名称
  version?: string;             // 版本
}

/**
 * 解析字体文件获取名称信息
 * @param filePath 字体文件路径
 * @returns 字体名称信息
 */
export async function parseFontName(filePath: string): Promise<FontNameInfo> {
  try {
    // 读取字体文件
    const file = SafeFileUtils.openSync(filePath, fileIo.OpenMode.READ_ONLY);
    const stat = SafeFileUtils.statSync(file.fd);
    
    // 只读取前64KB用于解析名称表，大多数字体的name表都在这个范围内
    const readSize = Math.min(stat.size, 65536);
    const buffer = new ArrayBuffer(readSize);
    SafeFileUtils.readSync(file.fd, buffer);
    SafeFileUtils.closeSync(file);
    
    const dataView = new DataView(buffer);
    
    // 检查文件类型
    const sfntVersion = dataView.getUint32(0, false);
    const isTTF = sfntVersion === 0x00010000 || sfntVersion === 0x74727565; // 'true'
    const isOTF = sfntVersion === 0x4F54544F; // 'OTTO'
    
    if (!isTTF && !isOTF) {
      throw new Error('不支持的字体格式');
    }
    
    // 解析表目录
    const numTables = dataView.getUint16(4, false);
    let nameTableOffset = 0;
    let nameTableLength = 0;
    
    for (let i = 0; i < numTables; i++) {
      const tableOffset = 12 + i * 16;
      const tag = String.fromCharCode(
        dataView.getUint8(tableOffset),
        dataView.getUint8(tableOffset + 1),
        dataView.getUint8(tableOffset + 2),
        dataView.getUint8(tableOffset + 3)
      );
      
      if (tag === 'name') {
        nameTableOffset = dataView.getUint32(tableOffset + 8, false);
        nameTableLength = dataView.getUint32(tableOffset + 12, false);
        break;
      }
    }
    
    if (nameTableOffset === 0) {
      throw new Error('未找到name表');
    }
    
    // 如果name表超出已读取范围，需要重新读取
    if (nameTableOffset + nameTableLength > readSize) {
      const file2 = SafeFileUtils.openSync(filePath, fileIo.OpenMode.READ_ONLY);
      const fullBuffer = new ArrayBuffer(nameTableOffset + nameTableLength);
      SafeFileUtils.readSync(file2.fd, fullBuffer);
      SafeFileUtils.closeSync(file2);
      return parseNameTable(new DataView(fullBuffer), nameTableOffset);
    }
    
    return parseNameTable(dataView, nameTableOffset);
  } catch (error) {
    const errMsg = `解析字体名称失败: ${String(error)}`;
    logger.error(TAG, errMsg);
    throw new Error(errMsg);
  }
}

/**
 * 解析name表
 */
function parseNameTable(dataView: DataView, offset: number): FontNameInfo {
  const format = dataView.getUint16(offset, false);
  const count = dataView.getUint16(offset + 2, false);
  const stringOffset = dataView.getUint16(offset + 4, false);
  
  // 存储不同语言版本的名称
  const names: Map<string, string> = new Map();
  
  for (let i = 0; i < count; i++) {
    const recordOffset = offset + 6 + i * 12;
    const platformID = dataView.getUint16(recordOffset, false);
    const encodingID = dataView.getUint16(recordOffset + 2, false);
    const languageID = dataView.getUint16(recordOffset + 4, false);
    const nameID = dataView.getUint16(recordOffset + 6, false);
    const length = dataView.getUint16(recordOffset + 8, false);
    const strOffset = dataView.getUint16(recordOffset + 10, false);
    
    // 只处理我们关心的名称ID
    if (nameID !== NAME_ID_FONT_FAMILY && 
        nameID !== NAME_ID_FULL_NAME && 
        nameID !== NAME_ID_POSTSCRIPT_NAME &&
        nameID !== NAME_ID_FONT_SUBFAMILY &&
        nameID !== NAME_ID_VERSION &&
        nameID !== NAME_ID_TYPOGRAPHIC_FAMILY) {
      continue;
    }
    
    try {
      const strStart = offset + stringOffset + strOffset;
      const strData = new Uint8Array(dataView.buffer, strStart, length);
      
      let str = '';
      
      // 根据平台和编码解码字符串
      if (platformID === PLATFORM_ID_WINDOWS) {
        // Windows平台使用UTF-16BE
        str = decodeUTF16BE(strData);
      } else if (platformID === PLATFORM_ID_MACINTOSH) {
        // Macintosh平台
        if (encodingID === MAC_ENCODING_ROMAN) {
          str = decodeMacRoman(strData);
        } else if (encodingID === MAC_ENCODING_CHINESE_SIMPLIFIED || 
                   encodingID === MAC_ENCODING_CHINESE_TRADITIONAL) {
          // 尝试UTF-16BE解码
          str = decodeUTF16BE(strData);
        } else {
          str = decodeMacRoman(strData);
        }
      } else if (platformID === PLATFORM_ID_UNICODE) {
        // Unicode平台使用UTF-16BE
        str = decodeUTF16BE(strData);
      }
      
      if (str && str.trim()) {
        // 生成唯一键：nameID_platformID_languageID
        const key = `${nameID}_${platformID}_${languageID}`;
        names.set(key, str.trim());
      }
    } catch (e) {
      // 忽略解码错误
    }
  }
  
  // 提取各种名称，优先使用本地化版本
  const result: FontNameInfo = {
    familyName: '',
    fullName: '',
    postScriptName: '',
    displayName: ''
  };
  
  // 获取英文名称作为基础
  const englishLangs: number[] = [WINDOWS_LANG_ENGLISH_US, 0];
  result.familyName = getNameByPriority(names, NAME_ID_FONT_FAMILY, englishLangs) || 
                      getNameByPriority(names, NAME_ID_TYPOGRAPHIC_FAMILY, englishLangs) || '';
  
  result.fullName = getNameByPriority(names, NAME_ID_FULL_NAME, englishLangs) || '';
  
  result.postScriptName = getNameByPriority(names, NAME_ID_POSTSCRIPT_NAME, englishLangs) || '';
  
  result.subfamily = getNameByPriority(names, NAME_ID_FONT_SUBFAMILY, englishLangs);
  
  result.version = getNameByPriority(names, NAME_ID_VERSION, englishLangs);
  
  // 获取本地化名称 (中文、日文、韩文)
  const localizedLangs: number[] = [
    WINDOWS_LANG_CHINESE_SIMPLIFIED,
    WINDOWS_LANG_CHINESE_TRADITIONAL,
    WINDOWS_LANG_JAPANESE,
    WINDOWS_LANG_KOREAN
  ];
  const localizedFamily = getNameByPriority(names, NAME_ID_FONT_FAMILY, localizedLangs) || 
                          getNameByPriority(names, NAME_ID_TYPOGRAPHIC_FAMILY, localizedLangs);
  
  const localizedFull = getNameByPriority(names, NAME_ID_FULL_NAME, localizedLangs);
  
  if (localizedFamily && localizedFamily !== result.familyName) {
    result.localizedFamilyName = localizedFamily;
  }
  
  if (localizedFull && localizedFull !== result.fullName) {
    result.localizedFullName = localizedFull;
  }
  
  // 确定显示名称：优先本地化名称，其次完整名称，最后字体族名称
  result.displayName = result.localizedFamilyName || 
                       result.localizedFullName || 
                       result.fullName || 
                       result.familyName ||
                       'Unknown Font';
  
  // 如果familyName为空，使用displayName
  if (!result.familyName) {
    result.familyName = result.displayName;
  }
  
  logger.info(TAG, `解析字体名称成功: displayName=${result.displayName}, familyName=${result.familyName}, localizedFamily=${result.localizedFamilyName || 'N/A'}`);
  
  return result;
}

/**
 * 按优先级获取名称
 */
function getNameByPriority(names: Map<string, string>, nameID: number, languagePriority: number[]): string | undefined {
  // 先尝试Windows平台
  for (let i = 0; i < languagePriority.length; i++) {
    const langID = languagePriority[i];
    const key = `${nameID}_${PLATFORM_ID_WINDOWS}_${langID}`;
    if (names.has(key)) {
      return names.get(key);
    }
  }
  
  // 再尝试Unicode平台
  for (let i = 0; i < languagePriority.length; i++) {
    const langID = languagePriority[i];
    const key = `${nameID}_${PLATFORM_ID_UNICODE}_${langID}`;
    if (names.has(key)) {
      return names.get(key);
    }
  }
  
  // 最后尝试Mac平台
  for (let i = 0; i < languagePriority.length; i++) {
    const langID = languagePriority[i];
    const key = `${nameID}_${PLATFORM_ID_MACINTOSH}_${langID}`;
    if (names.has(key)) {
      return names.get(key);
    }
  }
  
  // 如果都没找到，返回任意一个该nameID的值
  const prefix = `${nameID}_`;
  const entries = names.entries();
  let entry = entries.next();
  while (!entry.done) {
    const key = entry.value[0];
    const value = entry.value[1];
    if (key.startsWith(prefix)) {
      return value;
    }
    entry = entries.next();
  }
  
  return undefined;
}

/**
 * 解码UTF-16BE字符串
 */
function decodeUTF16BE(data: Uint8Array): string {
  let result = '';
  for (let i = 0; i < data.length - 1; i += 2) {
    const charCode = (data[i] << 8) | data[i + 1];
    
    // 处理代理对 (surrogate pairs) 用于扩展字符
    if (charCode >= 0xD800 && charCode <= 0xDBFF && i + 3 < data.length) {
      const highSurrogate = charCode;
      const lowSurrogate = (data[i + 2] << 8) | data[i + 3];
      if (lowSurrogate >= 0xDC00 && lowSurrogate <= 0xDFFF) {
        const codePoint = 0x10000 + ((highSurrogate - 0xD800) << 10) + (lowSurrogate - 0xDC00);
        result += String.fromCodePoint(codePoint);
        i += 2;
        continue;
      }
    }
    
    result += String.fromCharCode(charCode);
  }
  return result;
}

/**
 * 解码Mac Roman字符串
 */
function decodeMacRoman(data: Uint8Array): string {
  // Mac Roman到Unicode的映射表 (0x80-0xFF)
  const macRomanToUnicode: number[] = [
    0x00C4, 0x00C5, 0x00C7, 0x00C9, 0x00D1, 0x00D6, 0x00DC, 0x00E1,
    0x00E0, 0x00E2, 0x00E4, 0x00E3, 0x00E5, 0x00E7, 0x00E9, 0x00E8,
    0x00EA, 0x00EB, 0x00ED, 0x00EC, 0x00EE, 0x00EF, 0x00F1, 0x00F3,
    0x00F2, 0x00F4, 0x00F6, 0x00F5, 0x00FA, 0x00F9, 0x00FB, 0x00FC,
    0x2020, 0x00B0, 0x00A2, 0x00A3, 0x00A7, 0x2022, 0x00B6, 0x00DF,
    0x00AE, 0x00A9, 0x2122, 0x00B4, 0x00A8, 0x2260, 0x00C6, 0x00D8,
    0x221E, 0x00B1, 0x2264, 0x2265, 0x00A5, 0x00B5, 0x2202, 0x2211,
    0x220F, 0x03C0, 0x222B, 0x00AA, 0x00BA, 0x03A9, 0x00E6, 0x00F8,
    0x00BF, 0x00A1, 0x00AC, 0x221A, 0x0192, 0x2248, 0x2206, 0x00AB,
    0x00BB, 0x2026, 0x00A0, 0x00C0, 0x00C3, 0x00D5, 0x0152, 0x0153,
    0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0x00F7, 0x25CA,
    0x00FF, 0x0178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02,
    0x2021, 0x00B7, 0x201A, 0x201E, 0x2030, 0x00C2, 0x00CA, 0x00C1,
    0x00CB, 0x00C8, 0x00CD, 0x00CE, 0x00CF, 0x00CC, 0x00D3, 0x00D4,
    0xF8FF, 0x00D2, 0x00DA, 0x00DB, 0x00D9, 0x0131, 0x02C6, 0x02DC,
    0x00AF, 0x02D8, 0x02D9, 0x02DA, 0x00B8, 0x02DD, 0x02DB, 0x02C7
  ];
  
  let result = '';
  for (let i = 0; i < data.length; i++) {
    const byte = data[i];
    if (byte < 0x80) {
      result += String.fromCharCode(byte);
    } else {
      result += String.fromCharCode(macRomanToUnicode[byte - 0x80]);
    }
  }
  return result;
}

/**
 * 从文件路径提取文件名（不含扩展名）作为备用名称
 */
export function extractFileNameWithoutExt(filePath: string): string {
  const fileName = filePath.split('/').pop() || filePath.split('\\').pop() || 'Unknown';
  return fileName.replace(/\.(ttf|otf|woff|woff2|ttc)$/i, '');
}
