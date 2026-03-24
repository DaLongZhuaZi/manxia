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
import WordTransformType from './WordTransformType';

export default class Transform {
    private prefix: Int8Array;
    private type: number;
    private suffix: Int8Array;
    static TRANSFORMS: Array<Transform> = [
        new Transform("", WordTransformType.IDENTITY, ""),
        new Transform("", WordTransformType.IDENTITY, " "),
        new Transform(" ", WordTransformType.IDENTITY, " "),
        new Transform("", WordTransformType.OMIT_FIRST_1, ""),
        new Transform("", WordTransformType.UPPERCASE_FIRST, " "),
        new Transform("", WordTransformType.IDENTITY, " the "),
        new Transform(" ", WordTransformType.IDENTITY, ""),
        new Transform("s ", WordTransformType.IDENTITY, " "),
        new Transform("", WordTransformType.IDENTITY, " of "),
        new Transform("", WordTransformType.UPPERCASE_FIRST, ""),
        new Transform("", WordTransformType.IDENTITY, " and "),
        new Transform("", WordTransformType.OMIT_FIRST_2, ""),
        new Transform("", WordTransformType.OMIT_LAST_1, ""),
        new Transform(", ", WordTransformType.IDENTITY, " "),
        new Transform("", WordTransformType.IDENTITY, ", "),
        new Transform(" ", WordTransformType.UPPERCASE_FIRST, " "),
        new Transform("", WordTransformType.IDENTITY, " in "),
        new Transform("", WordTransformType.IDENTITY, " to "),
        new Transform("e ", WordTransformType.IDENTITY, " "),
        new Transform("", WordTransformType.IDENTITY, "\""),
        new Transform("", WordTransformType.IDENTITY, "."),
        new Transform("", WordTransformType.IDENTITY, "\">"),
        new Transform("", WordTransformType.IDENTITY, "\n"),
        new Transform("", WordTransformType.OMIT_LAST_3, ""),
        new Transform("", WordTransformType.IDENTITY, "]"),
        new Transform("", WordTransformType.IDENTITY, " for "),
        new Transform("", WordTransformType.OMIT_FIRST_3, ""),
        new Transform("", WordTransformType.OMIT_LAST_2, ""),
        new Transform("", WordTransformType.IDENTITY, " a "),
        new Transform("", WordTransformType.IDENTITY, " that "),
        new Transform(" ", WordTransformType.UPPERCASE_FIRST, ""),
        new Transform("", WordTransformType.IDENTITY, ". "),
        new Transform(".", WordTransformType.IDENTITY, ""),
        new Transform(" ", WordTransformType.IDENTITY, ", "),
        new Transform("", WordTransformType.OMIT_FIRST_4, ""),
        new Transform("", WordTransformType.IDENTITY, " with "),
        new Transform("", WordTransformType.IDENTITY, "'"),
        new Transform("", WordTransformType.IDENTITY, " from "),
        new Transform("", WordTransformType.IDENTITY, " by "),
        new Transform("", WordTransformType.OMIT_FIRST_5, ""),
        new Transform("", WordTransformType.OMIT_FIRST_6, ""),
        new Transform(" the ", WordTransformType.IDENTITY, ""),
        new Transform("", WordTransformType.OMIT_LAST_4, ""),
        new Transform("", WordTransformType.IDENTITY, ". The "),
        new Transform("", WordTransformType.UPPERCASE_ALL, ""),
        new Transform("", WordTransformType.IDENTITY, " on "),
        new Transform("", WordTransformType.IDENTITY, " as "),
        new Transform("", WordTransformType.IDENTITY, " is "),
        new Transform("", WordTransformType.OMIT_LAST_1, ""),
        new Transform("", WordTransformType.OMIT_LAST_1, "ing "),
        new Transform("", WordTransformType.IDENTITY, "\n\t"),
        new Transform("", WordTransformType.IDENTITY, ":"),
        new Transform(" ", WordTransformType.IDENTITY, ". "),
        new Transform("", WordTransformType.IDENTITY, "ed "),
        new Transform("", WordTransformType.OMIT_FIRST_9, ""),
        new Transform("", WordTransformType.OMIT_FIRST_7, ""),
        new Transform("", WordTransformType.OMIT_LAST_6, ""),
        new Transform("", WordTransformType.IDENTITY, "("),
        new Transform("", WordTransformType.UPPERCASE_FIRST, ", "),
        new Transform("", WordTransformType.OMIT_LAST_8, ""),
        new Transform("", WordTransformType.IDENTITY, " at "),
        new Transform("", WordTransformType.IDENTITY, "ly "),
        new Transform(" the ", WordTransformType.IDENTITY, " of "),
        new Transform("", WordTransformType.OMIT_LAST_5, ""),
        new Transform("", WordTransformType.OMIT_LAST_9, ""),
        new Transform(" ", WordTransformType.UPPERCASE_FIRST, ", "),
        new Transform("", WordTransformType.UPPERCASE_FIRST, "\""),
        new Transform(".", WordTransformType.IDENTITY, "("),
        new Transform("", WordTransformType.UPPERCASE_ALL, " "),
        new Transform("", WordTransformType.UPPERCASE_FIRST, "\">"),
        new Transform("", WordTransformType.IDENTITY, "=\""),
        new Transform(" ", WordTransformType.IDENTITY, "."),
        new Transform(".com/", WordTransformType.IDENTITY, ""),
        new Transform(" the ", WordTransformType.IDENTITY, " of the "),
        new Transform("", WordTransformType.UPPERCASE_FIRST, "'"),
        new Transform("", WordTransformType.IDENTITY, ". This "),
        new Transform("", WordTransformType.IDENTITY, ","),
        new Transform(".", WordTransformType.IDENTITY, " "),
        new Transform("", WordTransformType.UPPERCASE_FIRST, "("),
        new Transform("", WordTransformType.UPPERCASE_FIRST, "."),
        new Transform("", WordTransformType.IDENTITY, " not "),
        new Transform(" ", WordTransformType.IDENTITY, "=\""),
        new Transform("", WordTransformType.IDENTITY, "er "),
        new Transform(" ", WordTransformType.UPPERCASE_ALL, " "),
        new Transform("", WordTransformType.IDENTITY, "al "),
        new Transform(" ", WordTransformType.UPPERCASE_ALL, ""),
        new Transform("", WordTransformType.IDENTITY, "='"),
        new Transform("", WordTransformType.UPPERCASE_ALL, "\""),
        new Transform("", WordTransformType.UPPERCASE_FIRST, ". "),
        new Transform(" ", WordTransformType.IDENTITY, "("),
        new Transform("", WordTransformType.IDENTITY, "ful "),
        new Transform(" ", WordTransformType.UPPERCASE_FIRST, ". "),
        new Transform("", WordTransformType.IDENTITY, "ive "),
        new Transform("", WordTransformType.IDENTITY, "less "),
        new Transform("", WordTransformType.UPPERCASE_ALL, "'"),
        new Transform("", WordTransformType.IDENTITY, "est "),
        new Transform(" ", WordTransformType.UPPERCASE_FIRST, "."),
        new Transform("", WordTransformType.UPPERCASE_ALL, "\">"),
        new Transform(" ", WordTransformType.IDENTITY, "='"),
        new Transform("", WordTransformType.UPPERCASE_FIRST, ","),
        new Transform("", WordTransformType.IDENTITY, "ize "),
        new Transform("", WordTransformType.UPPERCASE_ALL, "."),
        new Transform("\u00c2\u00a0", WordTransformType.IDENTITY, ""),
        new Transform(" ", WordTransformType.IDENTITY, ","),
        new Transform("", WordTransformType.UPPERCASE_FIRST, "=\""),
        new Transform("", WordTransformType.UPPERCASE_ALL, "=\""),
        new Transform("", WordTransformType.IDENTITY, "ous "),
        new Transform("", WordTransformType.UPPERCASE_ALL, ", "),
        new Transform("", WordTransformType.UPPERCASE_FIRST, "='"),
        new Transform(" ", WordTransformType.UPPERCASE_FIRST, ","),
        new Transform(" ", WordTransformType.UPPERCASE_ALL, "=\""),
        new Transform(" ", WordTransformType.UPPERCASE_ALL, ", "),
        new Transform("", WordTransformType.UPPERCASE_ALL, ","),
        new Transform("", WordTransformType.UPPERCASE_ALL, "("),
        new Transform("", WordTransformType.UPPERCASE_ALL, ". "),
        new Transform(" ", WordTransformType.UPPERCASE_ALL, "."),
        new Transform("", WordTransformType.UPPERCASE_ALL, "='"),
        new Transform(" ", WordTransformType.UPPERCASE_ALL, ". "),
        new Transform(" ", WordTransformType.UPPERCASE_FIRST, "=\""),
        new Transform(" ", WordTransformType.UPPERCASE_ALL, "='"),
        new Transform(" ", WordTransformType.UPPERCASE_FIRST, "='")
    ];

    constructor(prefix: string, typeName: number, suffix: string) {
        this.prefix = Transform.readUniBytes(prefix);
        this.type = typeName;
        this.suffix = Transform.readUniBytes(suffix);
    }

    static readUniBytes(uniBytes: string): Int8Array {
        let result: Int8Array = new Int8Array(uniBytes.length);
        for (let i: number = 0; i < result.length; ++i) {
            result[i] = uniBytes.charCodeAt(i); // 要返回number类型
        }
        return result;
    }

    static transformDictionaryWord(dst: Int8Array, dstOffset: number, word: Int8Array, wordOffset: number, len: number, transform: Transform): number {
        let offset: number = dstOffset;

        let stringName: Int8Array = transform.prefix;
        let tmp: number = stringName.length;
        let i: number = 0;

        while (i < tmp) {
            dst[offset++] = stringName[i++];
        }

        let op: number = transform.type;
        tmp = WordTransformType.getOmitFirst(op);
        if (tmp > len) {
            tmp = len;
        }
        wordOffset += tmp;
        len -= tmp;
        len -= WordTransformType.getOmitLast(op);
        i = len;
        while (i > 0) {
            dst[offset++] = word[wordOffset++];
            i--;
        }

        if (op == WordTransformType.UPPERCASE_ALL || op == WordTransformType.UPPERCASE_FIRST) {
            let uppercaseOffset: number = offset - len;
            if (op == WordTransformType.UPPERCASE_FIRST) {
                len = 1;
            }
            while (len > 0) {
                tmp = dst[uppercaseOffset] & 255;
                if (tmp < 192) {
                    if (tmp >= 97 && tmp <= 122) {
                        dst[uppercaseOffset] = dst[uppercaseOffset] ^ 32;
                    }
                    uppercaseOffset += 1;
                    len -= 1;
                } else if (tmp < 224) {
                    dst[uppercaseOffset + 1] = dst[uppercaseOffset + 1] ^ 32;
                    uppercaseOffset += 2;
                    len -= 2;
                } else {
                    dst[uppercaseOffset + 2] = dst[uppercaseOffset + 2] ^ 5;
                    uppercaseOffset += 3;
                    len -= 3;
                }
            }
        }

        stringName = transform.suffix;
        tmp = stringName.length;
        i = 0;
        while (i < tmp) {
            dst[offset++] = stringName[i++];
        }

        return offset - dstOffset;
    }
}