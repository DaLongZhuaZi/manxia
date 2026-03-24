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

import BitReader from './BitReader';
import Decode from './Decode';
import Huffman from './Huffman';

export default class HuffmanTreeGroup {
    private alphabetSize: number;
    codes: Int32Array;
    trees: Int32Array;

    constructor() {

    }

    static init(group: HuffmanTreeGroup, alphabetSize: number, n: number): void {
        group.alphabetSize = alphabetSize;
        group.codes = new Int32Array(n * Huffman.HUFFMAN_MAX_TABLE_SIZE);
        group.trees = new Int32Array(n);
    }

    static decode(group: HuffmanTreeGroup, br: BitReader): void {
        let next: number = 0;
        let n: number = group.trees.length;
        for (let i: number = 0; i < n; ++i) {
            group.trees[i] = next;
            Decode.readHuffmanCode(group.alphabetSize, group.codes, next, br);
            next += Huffman.HUFFMAN_MAX_TABLE_SIZE;
        }
    }
}