/*
 * Copyright (c) 2022 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import DecodeHintType from './DecodeHintType';
import CharacterSetECI from './CharacterSetECI';
import StringEncoding from './StringEncoding';
import { int, char } from './CustomTypings';
import Charset from './Charset';
import StringBuilder from './StringBuilder';


export default class StringUtils {
    public static SHIFT_JIS = CharacterSetECI.SJIS.getName(); // "SJIS"
    public static GB2312 = 'GB2312';
    public static ISO88591 = CharacterSetECI.ISO8859_1.getName(); // "ISO8859_1"
    private static EUC_JP = 'EUC_JP';
    private static UTF8 = CharacterSetECI.UTF8.getName(); // "UTF8"
    private static PLATFORM_DEFAULT_ENCODING = StringUtils.UTF8; // "UTF8"//Charset.defaultCharset().name()
    private static ASSUME_SHIFT_JIS = false;

    static castAsNonUtf8Char(code: number, encoding: Charset = null) {
        const e = encoding ? encoding.getName() : this.ISO88591;
        return StringEncoding.decode(new Uint8Array([code]), e);
    }

    public static guessEncoding(bytes: Uint8Array, hints: Map<DecodeHintType, any>): string {
        if (hints !== null && hints !== undefined && undefined !== hints.get(DecodeHintType.CHARACTER_SET)) {
            return hints.get(DecodeHintType.CHARACTER_SET).toString();
        }
        const length = bytes.length;
        let canBeISO88591 = true;
        let canBeShiftJIS = true;
        let canBeUTF8 = true;
        let utf8BytesLeft = 0;

        let utf2BytesChars = 0;
        let utf3BytesChars = 0;
        let utf4BytesChars = 0;
        let sjisBytesLeft = 0;

        let sjisKatakanaChars = 0;

        let sjisCurKatakanaWordLength = 0;
        let sjisCurDoubleBytesWordLength = 0;
        let sjisMaxKatakanaWordLength = 0;
        let sjisMaxDoubleBytesWordLength = 0;

        let isoHighOther = 0;

        const utf8bom = bytes.length > 3 &&
        bytes[0] === 0xEF &&
        bytes[1] === 0xBB &&
        bytes[2] === 0xBF;

        for (let i = 0;
             i < length && (canBeISO88591 || canBeShiftJIS || canBeUTF8);
             i++) {

            const value = bytes[i] & 0xFF;

            // UTF-8 stuff
            if (canBeUTF8) {
                if (utf8BytesLeft > 0) {
                    if ((value & 0x80) === 0) {
                        canBeUTF8 = false;
                    } else {
                        utf8BytesLeft--;
                    }
                } else if ((value & 0x80) !== 0) {
                    if ((value & 0x40) === 0) {
                        canBeUTF8 = false;
                    } else {
                        utf8BytesLeft++;
                        if ((value & 0x20) === 0) {
                            utf2BytesChars++;
                        } else {
                            utf8BytesLeft++;
                            if ((value & 0x10) === 0) {
                                utf3BytesChars++;
                            } else {
                                utf8BytesLeft++;
                                if ((value & 0x08) === 0) {
                                    utf4BytesChars++;
                                } else {
                                    canBeUTF8 = false;
                                }
                            }
                        }
                    }
                }
            }

            // ISO-8859-1 stuff
            if (canBeISO88591) {
                if (value > 0x7F && value < 0xA0) {
                    canBeISO88591 = false;
                } else if (value > 0x9F) {
                    if (value < 0xC0 || value === 0xD7 || value === 0xF7) {
                        isoHighOther++;
                    }
                }
            }

            if (canBeShiftJIS) {
                if (sjisBytesLeft > 0) {
                    if (value < 0x40 || value === 0x7F || value > 0xFC) {
                        canBeShiftJIS = false;
                    } else {
                        sjisBytesLeft--;
                    }
                } else if (value === 0x80 || value === 0xA0 || value > 0xEF) {
                    canBeShiftJIS = false;
                } else if (value > 0xA0 && value < 0xE0) {
                    sjisKatakanaChars++;
                    sjisCurDoubleBytesWordLength = 0;
                    sjisCurKatakanaWordLength++;
                    if (sjisCurKatakanaWordLength > sjisMaxKatakanaWordLength) {
                        sjisMaxKatakanaWordLength = sjisCurKatakanaWordLength;
                    }
                } else if (value > 0x7F) {
                    sjisBytesLeft++;
                    sjisCurKatakanaWordLength = 0;
                    sjisCurDoubleBytesWordLength++;
                    if (sjisCurDoubleBytesWordLength > sjisMaxDoubleBytesWordLength) {
                        sjisMaxDoubleBytesWordLength = sjisCurDoubleBytesWordLength;
                    }
                } else {
                    // sjisLowChars++
                    sjisCurKatakanaWordLength = 0;
                    sjisCurDoubleBytesWordLength = 0;
                }
            }
        }

        if (canBeUTF8 && utf8BytesLeft > 0) {
            canBeUTF8 = false;
        }
        if (canBeShiftJIS && sjisBytesLeft > 0) {
            canBeShiftJIS = false;
        }

        if (canBeUTF8 && (utf8bom || utf2BytesChars + utf3BytesChars + utf4BytesChars > 0)) {
            return StringUtils.UTF8;
        }
        if (canBeShiftJIS && (StringUtils.ASSUME_SHIFT_JIS || sjisMaxKatakanaWordLength >= 3 || sjisMaxDoubleBytesWordLength >= 3)) {
            return StringUtils.SHIFT_JIS;
        }

        if (canBeISO88591 && canBeShiftJIS) {
            return (sjisMaxKatakanaWordLength === 2 && sjisKatakanaChars === 2) || isoHighOther * 10 >= length
                ? StringUtils.SHIFT_JIS : StringUtils.ISO88591;
        }

        if (canBeISO88591) {
            return StringUtils.ISO88591;
        }
        if (canBeShiftJIS) {
            return StringUtils.SHIFT_JIS;
        }
        if (canBeUTF8) {
            return StringUtils.UTF8;
        }

        return StringUtils.PLATFORM_DEFAULT_ENCODING;
    }

    public static format(append: string, ...args: any[]) {

        let i = -1;

        function callback(exp: string | number, p0: any, p1: any, p2: any, p3: any, p4: any) {

            if (exp === '%%') return '%';
            if (args[++i] === undefined) return undefined;

            exp = p2 ? parseInt(p2.substr(1)) : undefined;

            let base = p3 ? parseInt(p3.substr(1)) : undefined;
            let val: string;

            switch (p4) {
                case 's':
                    val = args[i];
                    break;
                case 'c':
                    val = args[i][0];
                    break;
                case 'f':
                    val = parseFloat(args[i]).toFixed(exp);
                    break;
                case 'p':
                    val = parseFloat(args[i]).toPrecision(exp);
                    break;
                case 'e':
                    val = parseFloat(args[i]).toExponential(exp);
                    break;
                case 'x':
                    val = parseInt(args[i]).toString(base ? base : 16);
                    break;
                case 'd':
                    val = parseFloat(parseInt(args[i], base ? base : 10).toPrecision(exp)).toFixed(0);
                    break;
            }

            val = typeof val === 'object' ? JSON.stringify(val) : (+val).toString(base);
            let size = parseInt(p1); /* padding size */
            let ch = p1 && (p1[0] + '') === '0' ? '0' : ' '; /* isnull? */

            while (val.length < size) val = p0 !== undefined ? val + ch : ch + val; /* isminus? */

            return val;
        }

        let regex = /%(-)?(0?[0-9]+)?([.][0-9]+)?([#][0-9]+)?([scfpexd%])/g;

        return append.replace(regex, callback);
    }

    public static getBytes(str: string, encoding: CharacterSetECI): Uint8Array {
        return StringEncoding.encode(str, encoding);
    }

    public static getCharCode(str: string, index = 0): int {
        return str.charCodeAt(index);
    }

    public static getCharAt(charCode: number): string {
        return String.fromCharCode(charCode);
    }

    public static canEncode(ch: char, encoding: CharacterSetECI): boolean {
        let charAt = StringUtils.getCharAt(ch);
        let bytes = StringUtils.getBytes(charAt, encoding);
        return bytes !== undefined && bytes.length !== 0;
    }

    public static isEmpty(text: string): boolean {
        if (text === undefined) {
            return true;
        }
        if (text.length === 0) {
            return true;
        }
    }

    public static valueOf(array: Int32Array): string {
        let sb: StringBuilder = new StringBuilder();
        for (let element of array) {
            sb.append(StringUtils.getCharAt(element));
        }
        return sb.toString();
    }
}
