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
import Exception from './Exception';

export default class ArchiveUtils {
    public static isArrayZero(a: Int8Array, size: number): boolean {
        for (let i = 0; i < size; i++) {
            if (a[i] != 0) {
                return false;
            }
        }
        return true;
    }

    public static matchAsciiBuffer(expected: string, buffer: Int8Array, offset?: number, length?: number): boolean {
        offset = offset == undefined ? 0 : offset;
        length = length == undefined ? buffer.length - offset : length

        let buffer1: Int8Array = new Int8Array(expected.length);
        for (let i = 0; i < expected.length; i++) {
            buffer1[i] = expected.charCodeAt(i);
        }
        return this.isEqual(buffer1, 0, buffer1.length, buffer, offset, length, false);
    }

    public static isEqual(
        buffer1: Int8Array, offset1: number, length1: number,
        buffer2: Int8Array, offset2: number, length2: number,
        ignoreTrailingNulls: boolean): boolean {
        let minLen: number = length1 < length2 ? length1 : length2;
        for (let i = 0; i < minLen; i++) {
            if (buffer1[offset1 + i] != buffer2[offset2 + i]) {
                return false;
            }
        }
        if (length1 == length2) {
            return true;
        }
        if (ignoreTrailingNulls) {
            if (length1 > length2) {
                for (let i = length2; i < length1; i++) {
                    if (buffer1[offset1 + i] != 0) {
                        return false;
                    }
                }
            } else {
                for (let i = length1; i < length2; i++) {
                    if (buffer2[offset2 + i] != 0) {
                        return false;
                    }
                }
            }
            return true;
        }
        return false;
    }

    public static toAsciiBytes(inputString: string): Int8Array {
        let buffer: Int8Array = new Int8Array(inputString.length);
        try {
            for (let i = 0; i < inputString.length; i++) {
                buffer[i] = inputString.charCodeAt(i);
            }
        } catch (err) {
            throw new Exception(err);
        }
        return buffer;
    }

    public static toAsciiString(inputBytes: Int8Array): string {
        return String.fromCharCode.apply(null, inputBytes);
    }

    public static toAsciiStringView(inputBytes: Int8Array, offset: number, length: number): string {
        return String.fromCharCode.apply(null, inputBytes.subarray(offset, offset + length));
    }
}