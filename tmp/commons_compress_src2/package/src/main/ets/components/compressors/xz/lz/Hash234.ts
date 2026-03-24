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
import CRC32Hash from './CRC32Hash'
import ArrayCache from '../ArrayCache'
import LZEncoder from './LZEncoder'

export default class Hash234 extends CRC32Hash {
    private static HASH_2_SIZE: number = 1 << 10;
    private static HASH_2_MASK: number = Hash234.HASH_2_SIZE - 1;
    private static HASH_3_SIZE: number = 1 << 16;
    private static HASH_3_MASK: number = Hash234.HASH_3_SIZE - 1;
    private hash4Mask: number;
    private hash2Table: Int32Array;
    private hash3Table: Int32Array;
    private hash4Table: Int32Array;
    private hash4Size: number;
    private hash2Value: number = 0;
    private hash3Value: number = 0;
    private hash4Value: number = 0;

    static getHash4Size(dictSize: number): number {
        let h: number = dictSize - 1;
        h |= h >>> 1;
        h |= h >>> 2;
        h |= h >>> 4;
        h |= h >>> 8;
        h >>>= 1;
        h |= 65535;
        if (h > 16777216) {
            h >>>= 1;
        }

        return h + 1;
    }

    static getMemoryUsage(dictSize: number): number {
        return (66560 + Hash234.getHash4Size(dictSize)) / 256 + 4;
    }

    constructor(dictSize: number, arrayCache: ArrayCache) {
        super()
        this.hash2Table = arrayCache.getIntArray(1024, true);
        this.hash3Table = arrayCache.getIntArray(65536, true);
        this.hash4Size = Hash234.getHash4Size(dictSize);
        this.hash4Table = arrayCache.getIntArray(this.hash4Size, true);
        this.hash4Mask = this.hash4Size - 1;
    }

    putArraysToCache(arrayCache: ArrayCache): void {
        arrayCache.putArray(this.hash4Table);
        arrayCache.putArray(this.hash3Table);
        arrayCache.putArray(this.hash2Table);
    }

    calcHashes(buf: Int8Array, off: number): void {
        let temp: number = CRC32Hash.crcTable[buf[off] & 255] ^ buf[off + 1] & 255;
        this.hash2Value = temp & 1023;
        temp ^= (buf[off + 2] & 255) << 8;
        this.hash3Value = temp & Hash234.HASH_3_MASK;
        temp ^= CRC32Hash.crcTable[buf[off + 3] & 255] << 5;
        this.hash4Value = temp & this.hash4Mask;
    }

    getHash2Pos(): number {
        return this.hash2Table[this.hash2Value];
    }

    getHash3Pos(): number {
        return this.hash3Table[this.hash3Value];
    }

    getHash4Pos(): number {
        return this.hash4Table[this.hash4Value];
    }

    updateTables(pos: number): void {
        this.hash2Table[this.hash2Value] = pos;
        this.hash3Table[this.hash3Value] = pos;
        this.hash4Table[this.hash4Value] = pos;
    }

    normalize(normalizationOffset: number): void {
        LZEncoder.normalize(this.hash2Table, 1024, normalizationOffset);
        LZEncoder.normalize(this.hash3Table, 65536, normalizationOffset);
        LZEncoder.normalize(this.hash4Table, this.hash4Size, normalizationOffset);
    }
}
