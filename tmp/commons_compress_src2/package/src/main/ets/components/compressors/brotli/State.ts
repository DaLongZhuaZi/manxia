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
import HuffmanTreeGroup from './HuffmanTreeGroup';
import BitReader from './BitReader';
import Long from "../../util/long/index";
import InputStream from '../../util/InputStream';
import Exception from '../../util/Exception';
import RunningState from './RunningState';
import Huffman from './Huffman';

export default class States {
    runningState: number = RunningState.UNINITIALIZED;
    nextRunningState: number = 0;
    br: BitReader = new BitReader();
    ringBuffer: Int8Array;
    blockTypeTrees: Int32Array = new Int32Array(3 * Huffman.HUFFMAN_MAX_TABLE_SIZE);
    blockLenTrees: Int32Array = new Int32Array(3 * Huffman.HUFFMAN_MAX_TABLE_SIZE);
    metaBlockLengths: number = 0;
    inputEnd: boolean = false;
    isUncompressed: boolean = false;
    isMetadata: boolean = false;
    hGroup0: HuffmanTreeGroup = new HuffmanTreeGroup();
    hGroup1: HuffmanTreeGroup = new HuffmanTreeGroup();
    hGroup2: HuffmanTreeGroup = new HuffmanTreeGroup();
    blockLength: Int32Array = new Int32Array(3);
    numBlockTypes: Int32Array = new Int32Array(3);
    blockTypeRb: Int32Array = new Int32Array(6);
    distRb: Int32Array = new Int32Array([16, 15, 11, 4]);
    pos: number = 0;
    maxDistance: number = 0;
    distRbIdx: number = 0;
    trivialLiteralContext: boolean = false;
    literalTreeIndex: number = 0;
    literalTree: number = 0;
    j: number = 0;
    insertLength: number = 0;
    contextModes: Int8Array;
    contextMap: Int8Array;
    contextMapSlice: number = 0;
    distContextMapSlice: number = 0;
    contextLookupOffset1: number = 0;
    contextLookupOffset2: number = 0;
    treeCommandOffset: number = 0;
    distanceCode: number = 0;
    distContextMap: Int8Array;
    numDirectDistanceCodes: number = 0;
    distancePostfixMask: number = 0;
    distancePostfixBits: number = 0;
    distance: number = 0;
    copyLength: number = 0;
    copyDst: number = 0;
    maxBackwardDistance: number = 0;
    maxRingBufferSize: number = 0;
    ringBufferSize: number = 0;
    expectedTotalSize: Long = Long.fromNumber(0);
    customDictionary: Int8Array = new Int8Array(0);
    bytesToIgnore: number = 0;
    outputOffset: number = 0;
    outputLength: number = 0;
    outputUsed: number = 0;
    bytesWritten: number = 0;
    bytesToWrite: number = 0;
    output: Int8Array;

    constructor() {

    }

    private static decodeWindowBits(br: BitReader): number {
        if (BitReader.readBits(br, 1) == 0) {
            return 16;
        } else {
            let n: number = BitReader.readBits(br, 3);
            if (n != 0) {
                return 17 + n;
            }
            n = BitReader.readBits(br, 3);
            if (n != 0) {
                return 8 + n;
            }
            return 17;
        }
    }

    static setInput(state: States, input: InputStream): void {
        if (state.runningState != 0) {
            throw new Exception("State MUST be uninitialized");
        }
        BitReader.init(state.br, input);
        let windowBits: number = States.decodeWindowBits(state.br);
        if (windowBits == 9) {
            throw new Exception("Invalid 'windowBits' code");
        }
        state.maxRingBufferSize = 1 << windowBits;
        state.maxBackwardDistance = state.maxRingBufferSize - 16;
        state.runningState = RunningState.BLOCK_START;
    }

    static close(state: States): void{
        if (state.runningState == 0) {
            throw new Exception("State MUST be initialized");
        }
        if (state.runningState == RunningState.CLOSED) {
            return;
        }
        state.runningState = RunningState.CLOSED;
        BitReader.close(state.br);
    }
}