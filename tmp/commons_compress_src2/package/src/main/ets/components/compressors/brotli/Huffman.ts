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

export default class Huffman {
    static HUFFMAN_MAX_TABLE_SIZE: number = 1080;
    private static MAX_LENGTH: number = 15;

    constructor() {

    }

    private static getNextKey(key: number, len: number): number {
        let step: number = 1 << (len - 1);
        while ((key & step) != 0) {
            step >>= 1;
        }
        return (key & (step - 1)) + step;
    }

    private static replicateValue(table: Int32Array, offset: number, step: number, end: number, item: number): void {
        do {
            end -= step;
            table[offset + end] = item;
        } while (end > 0);
    }

    private static nextTableBitSize(count: Int32Array, len: number, rootBits: number): number {
        let left: number = 1 << (len - rootBits);
        while (len < Huffman.MAX_LENGTH) {
            left -= count[len];
            if (left <= 0) {
                break;
            }
            len++;
            left <<= 1;
        }
        return len - rootBits;
    }

    static buildHuffmanTable(rootTable: Int32Array, tableOffset: number, rootBits: number, codeLengths: Int32Array, codeLengthsSize: number): void {
        let key: number; // Reversed prefix code.
        let sorted: Int32Array = new Int32Array(codeLengthsSize); // Symbols sorted by code length.
        let count: Int32Array = new Int32Array(16); // Number of codes of each length.
        let offset: Int32Array = new Int32Array(16); // Offsets in sorted table for each length.
        let symbols: number;
        for (symbols = 0; symbols < codeLengthsSize; symbols++) {
            count[codeLengths[symbols]]++;
        }

        offset[1] = 0;
        for (let len: number = 1; len < Huffman.MAX_LENGTH; len++) {
            offset[len + 1] = offset[len] + count[len];
        }
        for (symbols = 0; symbols < codeLengthsSize; symbols++) {
            if (codeLengths[symbols] != 0) {
                sorted[offset[codeLengths[symbols]]++] = symbols;
            }
        }
        let tableBits: number = rootBits;
        let tableSize: number = 1 << rootBits;
        let totalSize: number = tableSize;

        if (offset[Huffman.MAX_LENGTH] == 1) {
            for (key = 0; key < totalSize; key++) {
                rootTable[tableOffset + key] = sorted[0];
            }
            return;
        }

        key = 0;
        symbols = 0;
        for (let len: number = 1, step = 2; len <= rootBits; len++, step <<= 1) {
            for (; count[len] > 0; count[len]--) {
                Huffman.replicateValue(rootTable, tableOffset + key, step, tableSize, len << 16 | sorted[symbols++]);
                key = Huffman.getNextKey(key, len);
            }
        }
        let mask: number = tableSize - 1;
        let low: number = -1;
        let currentOffset: number = tableOffset;
        for (let len: number = rootBits + 1, step = 2; len <= Huffman.MAX_LENGTH; len++, step <<= 1) {
            for (; count[len] > 0; count[len]--) {
                if ((key & mask) != low) {
                    currentOffset += tableSize;
                    tableBits = Huffman.nextTableBitSize(count, len, rootBits);
                    tableSize = 1 << tableBits;
                    totalSize += tableSize;
                    low = key & mask;
                    rootTable[tableOffset + low] =
                    (tableBits + rootBits) << 16 | (currentOffset - tableOffset - low);
                }
                Huffman.replicateValue(rootTable, currentOffset + (key >> rootBits), step, tableSize,
                    (len - rootBits) << 16 | sorted[symbols++]);
                key = Huffman.getNextKey(key, len);
            }
        }
    }
}