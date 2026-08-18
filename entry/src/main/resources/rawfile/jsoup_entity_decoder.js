(function (window) {
  'use strict';
  var data = window.__legadoJsoupEntityData;
  if (!data || Number(data.extendedCount) !== 2125) {
    throw new Error('Pinned Jsoup 1.16.2 entity data is unavailable');
  }
  var __legadoJsoupEntityBasePoints = data.basePoints;
  var __legadoJsoupEntityFullPoints = data.fullPoints;
var __legadoJsoupEntityTables = null;
var __legadoJsoupWin1252 = [
  0x20ac,0x0081,0x201a,0x0192,0x201e,0x2026,0x2020,0x2021,
  0x02c6,0x2030,0x0160,0x2039,0x0152,0x008d,0x017d,0x008f,
  0x0090,0x2018,0x2019,0x201c,0x201d,0x2022,0x2013,0x2014,
  0x02dc,0x2122,0x0161,0x203a,0x0153,0x009d,0x017e,0x0178
];
var __legadoFromCodePoint = function(codePoint) {
  if (codePoint <= 0xffff) return String.fromCharCode(codePoint);
  var adjusted = codePoint - 0x10000;
  return String.fromCharCode(0xd800 + (adjusted >> 10), 0xdc00 + (adjusted & 0x3ff));
};
var __legadoParseEntityPoints = function(packed) {
  var map = Object.create(null);
  var records = packed.split('&');
  var maxNameLength = 0;
  for (var index = 0; index < records.length; index++) {
    var record = records[index];
    if (!record) continue;
    var equalsIndex = record.indexOf('=');
    var delimiterIndex = record.indexOf(';', equalsIndex + 1);
    var commaIndex = record.indexOf(',', equalsIndex + 1);
    var name = record.substring(0, equalsIndex);
    var firstEnd = commaIndex > equalsIndex && commaIndex < delimiterIndex ? commaIndex : delimiterIndex;
    var value = __legadoFromCodePoint(parseInt(record.substring(equalsIndex + 1, firstEnd), 36));
    if (commaIndex > equalsIndex && commaIndex < delimiterIndex) {
      value += __legadoFromCodePoint(parseInt(record.substring(commaIndex + 1, delimiterIndex), 36));
    }
    map[name] = value;
    if (name.length > maxNameLength) maxNameLength = name.length;
  }
  return { map: map, maxNameLength: maxNameLength };
};
var __legadoGetEntityTables = function() {
  if (__legadoJsoupEntityTables) return __legadoJsoupEntityTables;
  var base = __legadoParseEntityPoints(__legadoJsoupEntityBasePoints);
  var extended = __legadoParseEntityPoints(__legadoJsoupEntityFullPoints);
  __legadoJsoupEntityTables = {
    base: base.map,
    extended: extended.map,
    maxNameLength: extended.maxNameLength
  };
  return __legadoJsoupEntityTables;
};
var __legadoIsNameLetter = function(character) {
  if (!character) return false;
  var code = character.charCodeAt(0);
  if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) return true;
  return code >= 0x80 && /^\p{L}$/u.test(character);
};
var __legadoIsHexDigit = function(character) {
  if (!character) return false;
  var code = character.charCodeAt(0);
  return (code >= 48 && code <= 57) || (code >= 65 && code <= 70) ||
    (code >= 97 && code <= 102);
};
var __legadoIsDecimalDigit = function(character) {
  if (!character) return false;
  var code = character.charCodeAt(0);
  return code >= 48 && code <= 57;
};
var __legadoNormalizeNumericEntity = function(codePoint) {
  if (!isFinite(codePoint) || codePoint < 0 || codePoint > 0x10ffff ||
      (codePoint >= 0xd800 && codePoint <= 0xdfff)) return 0xfffd;
  if (codePoint >= 0x80 && codePoint <= 0x9f) {
    return __legadoJsoupWin1252[codePoint - 0x80];
  }
  return codePoint;
};
var __legadoDecodeHtmlEntities = function(value, inAttribute) {
  var source = String(value === undefined || value === null ? '' : value);
  if (source.indexOf('&') < 0) return source;
  var tables = __legadoGetEntityTables();
  var output = '';
  var cursor = 0;
  while (cursor < source.length) {
    var ampersand = source.indexOf('&', cursor);
    if (ampersand < 0) { output += source.substring(cursor); break; }
    output += source.substring(cursor, ampersand);
    var referenceStart = ampersand + 1;
    if (referenceStart >= source.length) { output += '&'; break; }
    if (source.charAt(referenceStart) === '#') {
      var digitStart = referenceStart + 1;
      var hexadecimal = false;
      if (source.charAt(digitStart) === 'x' || source.charAt(digitStart) === 'X') {
        hexadecimal = true; digitStart++;
      }
      var digitEnd = digitStart;
      while (digitEnd < source.length &&
        (hexadecimal ? __legadoIsHexDigit(source.charAt(digitEnd)) :
          __legadoIsDecimalDigit(source.charAt(digitEnd)))) digitEnd++;
      if (digitEnd === digitStart) { output += '&'; cursor = referenceStart; continue; }
      var codePoint = parseInt(source.substring(digitStart, digitEnd), hexadecimal ? 16 : 10);
      output += __legadoFromCodePoint(__legadoNormalizeNumericEntity(codePoint));
      cursor = source.charAt(digitEnd) === ';' ? digitEnd + 1 : digitEnd;
      continue;
    }
    var nameEnd = referenceStart;
    while (nameEnd < source.length && __legadoIsNameLetter(source.charAt(nameEnd))) nameEnd++;
    while (nameEnd < source.length && __legadoIsDecimalDigit(source.charAt(nameEnd))) nameEnd++;
    if (nameEnd === referenceStart) { output += '&'; cursor = referenceStart; continue; }
    var hasSemicolon = source.charAt(nameEnd) === ';';
    var name = source.substring(referenceStart, nameEnd);
    var named = hasSemicolon ? tables.extended[name] : tables.base[name];
    if (named === undefined) { output += '&'; cursor = referenceStart; continue; }
    var nextCharacter = hasSemicolon ? '' : source.charAt(nameEnd);
    if (!hasSemicolon && inAttribute &&
        (__legadoIsNameLetter(nextCharacter) || __legadoIsDecimalDigit(nextCharacter) || nextCharacter === '=' ||
          nextCharacter === '-' || nextCharacter === '_')) {
      output += '&'; cursor = referenceStart; continue;
    }
    output += named;
    cursor = hasSemicolon ? nameEnd + 1 : nameEnd;
  }
  return output;
};
  window.__legadoDecodeHtmlEntities = __legadoDecodeHtmlEntities;
})(window);