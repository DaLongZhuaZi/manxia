/**
 * Jsoup 1.16.2-compatible HTML character-reference decoder.
 *
 * The packed entity data is generated from the pinned Jsoup EntitiesData.java.
 * Text and attribute contexts intentionally share the same scanner but retain
 * Jsoup's distinct ambiguity rule for semicolon-less named references.
 */

import {
  JSOUP_BASE_ENTITY_COUNT,
  JSOUP_BASE_ENTITY_POINTS,
  JSOUP_EXTENDED_ENTITY_COUNT,
  JSOUP_FULL_ENTITY_POINTS
} from './JsoupEntityData';

class JsoupEntityTables {
  readonly base: Map<string, string>;
  readonly extended: Map<string, string>;
  readonly reverse: Map<string, string>;
  readonly maxNameLength: number;

  constructor(base: Map<string, string>, extended: Map<string, string>, reverse: Map<string, string>,
    maxNameLength: number) {
    this.base = base;
    this.extended = extended;
    this.reverse = reverse;
    this.maxNameLength = maxNameLength;
  }
}

export class HtmlEntities {
  private static tables: JsoupEntityTables | null = null;
  private static readonly WIN_1252_EXTENSIONS: number[] = [
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
  ];

  private static getTables(): JsoupEntityTables {
    if (HtmlEntities.tables !== null) {
      return HtmlEntities.tables;
    }
    const base = HtmlEntities.parsePackedEntities(JSOUP_BASE_ENTITY_POINTS, JSOUP_BASE_ENTITY_COUNT);
    const extended = HtmlEntities.parsePackedEntities(JSOUP_FULL_ENTITY_POINTS, JSOUP_EXTENDED_ENTITY_COUNT);
    const reverse = new Map<string, string>();
    let maxNameLength = 0;
    extended.forEach((value: string, name: string): void => {
      if (name.length > maxNameLength) {
        maxNameLength = name.length;
      }
      if (!reverse.has(value)) {
        reverse.set(value, name);
      }
    });
    HtmlEntities.tables = new JsoupEntityTables(base, extended, reverse, maxNameLength);
    return HtmlEntities.tables;
  }

  private static parsePackedEntities(packed: string, expectedCount: number): Map<string, string> {
    const result = new Map<string, string>();
    const records = packed.split('&');
    for (let index = 0; index < records.length; index++) {
      const record = records[index];
      if (record.length === 0) {
        continue;
      }
      const equalsIndex = record.indexOf('=');
      const delimiterIndex = record.indexOf(';', equalsIndex + 1);
      const commaIndex = record.indexOf(',', equalsIndex + 1);
      if (equalsIndex <= 0 || delimiterIndex <= equalsIndex) {
        throw new Error('Invalid generated Jsoup entity record.');
      }
      const name = record.substring(0, equalsIndex);
      const firstEnd = commaIndex > equalsIndex && commaIndex < delimiterIndex ? commaIndex : delimiterIndex;
      const firstCodePoint = parseInt(record.substring(equalsIndex + 1, firstEnd), 36);
      let value = HtmlEntities.fromCodePoint(firstCodePoint);
      if (commaIndex > equalsIndex && commaIndex < delimiterIndex) {
        const secondCodePoint = parseInt(record.substring(commaIndex + 1, delimiterIndex), 36);
        value += HtmlEntities.fromCodePoint(secondCodePoint);
      }
      result.set(name, value);
    }
    if (result.size !== expectedCount) {
      throw new Error(`Generated Jsoup entity count mismatch: actual=${result.size}, expected=${expectedCount}`);
    }
    return result;
  }

  private static fromCodePoint(codePoint: number): string {
    if (codePoint <= 0xFFFF) {
      return String.fromCharCode(codePoint);
    }
    const adjusted = codePoint - 0x10000;
    return String.fromCharCode(0xD800 + (adjusted >> 10), 0xDC00 + (adjusted & 0x3FF));
  }

  private static isNameLetter(character: string): boolean {
    if (character.length === 0) {
      return false;
    }
    const code = character.charCodeAt(0);
    if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
      return true;
    }
    return code >= 0x80 && /^\p{L}$/u.test(character);
  }

  private static isHexDigit(character: string): boolean {
    if (character.length === 0) {
      return false;
    }
    const code = character.charCodeAt(0);
    return (code >= 48 && code <= 57) || (code >= 65 && code <= 70) || (code >= 97 && code <= 102);
  }

  private static isDecimalDigit(character: string): boolean {
    if (character.length === 0) {
      return false;
    }
    const code = character.charCodeAt(0);
    return code >= 48 && code <= 57;
  }

  private static normalizeNumericCodePoint(codePoint: number): number {
    if (!Number.isFinite(codePoint) || codePoint < 0 || codePoint > 0x10FFFF ||
      (codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
      return 0xFFFD;
    }
    if (codePoint >= 0x80 && codePoint <= 0x9F) {
      return HtmlEntities.WIN_1252_EXTENSIONS[codePoint - 0x80];
    }
    return codePoint;
  }

  static decode(text: string): string {
    return HtmlEntities.decodeInternal(text, false);
  }

  static decodeAttribute(text: string): string {
    return HtmlEntities.decodeInternal(text, true);
  }

  private static decodeInternal(text: string, inAttribute: boolean): string {
    if (text.length === 0 || text.indexOf('&') < 0) {
      return text;
    }
    const tables = HtmlEntities.getTables();
    let output = '';
    let cursor = 0;
    while (cursor < text.length) {
      const ampersand = text.indexOf('&', cursor);
      if (ampersand < 0) {
        output += text.substring(cursor);
        break;
      }
      output += text.substring(cursor, ampersand);
      const referenceStart = ampersand + 1;
      if (referenceStart >= text.length) {
        output += '&';
        break;
      }

      if (text.charAt(referenceStart) === '#') {
        let digitStart = referenceStart + 1;
        let hexadecimal = false;
        if (digitStart < text.length && (text.charAt(digitStart) === 'x' || text.charAt(digitStart) === 'X')) {
          hexadecimal = true;
          digitStart++;
        }
        let digitEnd = digitStart;
        while (digitEnd < text.length &&
          (hexadecimal ? HtmlEntities.isHexDigit(text.charAt(digitEnd)) :
            HtmlEntities.isDecimalDigit(text.charAt(digitEnd)))) {
          digitEnd++;
        }
        if (digitEnd === digitStart) {
          output += '&';
          cursor = referenceStart;
          continue;
        }
        const codePoint = parseInt(text.substring(digitStart, digitEnd), hexadecimal ? 16 : 10);
        output += HtmlEntities.fromCodePoint(HtmlEntities.normalizeNumericCodePoint(codePoint));
        cursor = digitEnd < text.length && text.charAt(digitEnd) === ';' ? digitEnd + 1 : digitEnd;
        continue;
      }

      let nameEnd = referenceStart;
      while (nameEnd < text.length && HtmlEntities.isNameLetter(text.charAt(nameEnd))) {
        nameEnd++;
      }
      while (nameEnd < text.length && HtmlEntities.isDecimalDigit(text.charAt(nameEnd))) {
        nameEnd++;
      }
      if (nameEnd === referenceStart) {
        output += '&';
        cursor = referenceStart;
        continue;
      }
      const hasSemicolon = nameEnd < text.length && text.charAt(nameEnd) === ';';
      const name = text.substring(referenceStart, nameEnd);
      const namedValue = hasSemicolon ? tables.extended.get(name) : tables.base.get(name);
      if (namedValue === undefined) {
        output += '&';
        cursor = referenceStart;
        continue;
      }
      const nextCharacter = hasSemicolon ? '' : text.charAt(nameEnd);
      if (!hasSemicolon && inAttribute &&
        (HtmlEntities.isNameLetter(nextCharacter) || HtmlEntities.isDecimalDigit(nextCharacter) || nextCharacter === '=' ||
          nextCharacter === '-' || nextCharacter === '_')) {
        output += '&';
        cursor = referenceStart;
        continue;
      }
      output += namedValue;
      cursor = hasSemicolon ? nameEnd + 1 : nameEnd;
    }
    return output;
  }

  static encode(text: string): string {
    if (text.length === 0) {
      return text;
    }
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/\"/g, '&quot;').replace(/'/g, '&#39;');
  }

  static encodeNonAscii(text: string): string {
    if (text.length === 0) {
      return text;
    }
    const reverse = HtmlEntities.getTables().reverse;
    let result = '';
    for (let index = 0; index < text.length; index++) {
      const first = text.charCodeAt(index);
      let value = text.charAt(index);
      let codePoint = first;
      if (first >= 0xD800 && first <= 0xDBFF && index + 1 < text.length) {
        const second = text.charCodeAt(index + 1);
        if (second >= 0xDC00 && second <= 0xDFFF) {
          value = text.substring(index, index + 2);
          codePoint = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
          index++;
        }
      }
      if (codePoint <= 127) {
        result += value;
        continue;
      }
      const name = reverse.get(value);
      result += name === undefined ? `&#${codePoint};` : `&${name};`;
    }
    return result;
  }

  static escape(text: string): string {
    return HtmlEntities.encode(text);
  }

  static unescape(text: string): string {
    return HtmlEntities.decode(text);
  }

  static containsEntities(text: string): boolean {
    return /&[#a-zA-Z0-9]+;?/.test(text);
  }

  static getNamedEntity(name: string): string | undefined {
    return HtmlEntities.getTables().extended.get(name);
  }

  static getEntityName(value: string): string | undefined {
    return HtmlEntities.getTables().reverse.get(value);
  }
}
