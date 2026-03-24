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
import States from './State';
import Exception from '../../util/Exception';
import System from '../../util/System';
import Prefix from './Prefix';
import Huffman from './Huffman';
import Utils from './Utils';
import Context from './Context';
import HuffmanTreeGroup from "./HuffmanTreeGroup";
import Dictionary from './Dictionary'
import Transform from "./Transform";


export default class Decode {
    private static DEFAULT_CODE_LENGTH: number = 8;
    private static CODE_LENGTH_REPEAT_CODE: number = 16;
    private static NUM_LITERAL_CODES: number = 256;
    private static NUM_INSERT_AND_COPY_CODES: number = 704;
    private static NUM_BLOCK_LENGTH_CODES: number = 26;
    private static LITERAL_CONTEXT_BITS: number = 6;
    private static DISTANCE_CONTEXT_BITS: number = 2;
    private static HUFFMAN_TABLE_BITS: number = 8;
    private static HUFFMAN_TABLE_MASK: number = 255;
    private static CODE_LENGTH_CODES: number = 18;
    private static CODE_LENGTH_CODE_ORDER: Int32Array = new Int32Array([1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15]);
    private static NUM_DISTANCE_SHORT_CODES: number = 16;
    private static DISTANCE_SHORT_CODE_INDEX_OFFSET: Int32Array = new Int32Array([3, 2, 1, 0, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2]);
    private static DISTANCE_SHORT_CODE_VALUE_OFFSET: Int32Array = new Int32Array([0, 0, 0, 0, -1, 1, -2, 2, -3, 3, -1, 1, -2, 2, -3, 3]);
    private static FIXED_TABLE: Int32Array = new Int32Array([131072, 131076, 131075, 196610, 131072, 131076, 131075, 262145, 131072, 131076, 131075, 196610, 131072, 131076, 131075, 262149]);

    constructor() {

    }

    private static decodeVarLenUnsignedBytes(br: BitReader): number {
        if (BitReader.readBits(br, 1) != 0) {
            let n: number = BitReader.readBits(br, 3);
            return n == 0 ? 1 : BitReader.readBits(br, n) + (1 << n);
        } else {
            return 0;
        }
    }

    private static decodeMetaBlockLength(br: BitReader, state: States): void {
        state.inputEnd = BitReader.readBits(br, 1) == 1;
        state.metaBlockLengths = 0;
        state.isUncompressed = false;
        state.isMetadata = false;
        if (!state.inputEnd || BitReader.readBits(br, 1) == 0) {
            let sizeNibbles: number = BitReader.readBits(br, 2) + 4;
            let sizeBytes: number;
            let i: number;
            if (sizeNibbles == 7) {
                state.isMetadata = true;
                if (BitReader.readBits(br, 1) != 0) {
                    throw new Exception("Corrupted reserved bit");
                }

                sizeBytes = BitReader.readBits(br, 2);
                if (sizeBytes == 0) {
                    return;
                }

                for (i = 0; i < sizeBytes; ++i) {
                    let bits: number = BitReader.readBits(br, 8);
                    if (bits == 0 && i + 1 == sizeBytes && sizeBytes > 1) {
                        throw new Exception("Exuberant nibble");
                    }

                    state.metaBlockLengths |= bits << i * 8;
                }
            } else {
                for (sizeBytes = 0; sizeBytes < sizeNibbles; ++sizeBytes) {
                    i = BitReader.readBits(br, 4);
                    if (i == 0 && sizeBytes + 1 == sizeNibbles && sizeNibbles > 4) {
                        throw new Exception("Exuberant nibble");
                    }

                    state.metaBlockLengths |= i << sizeBytes * 4;
                }
            }

            ++state.metaBlockLengths;
            if (!state.inputEnd) {
                state.isUncompressed = BitReader.readBits(br, 1) == 1;
            }

        }
    }

    private static readSymbol(table: Int32Array, offset: number, br: BitReader): number {
        let val: number = br.accumulator.shru(br.bitOffsets).toInt();
        offset += val & 255;
        let bits: number = table[offset] >> 16;
        let sym: number = table[offset] & 0xFFFF;
        if (bits <= 8) {
            br.bitOffsets += bits;
            return sym;
        } else {
            offset += sym;
            let mask: number = (1 << bits) - 1;
            offset += (val & mask) >>> 8;
            br.bitOffsets += (table[offset] >> 16) + 8;
            return table[offset] & 0xFFFF;
        }
    }

    private static readBlockLength(table: Int32Array, offset: number, br: BitReader): number {
        BitReader.fillBitWindow(br);
        let code: number = Decode.readSymbol(table, offset, br);
        let n: number = Prefix.BLOCK_LENGTH_N_BITS[code];
        return Prefix.BLOCK_LENGTH_OFFSET[code] + BitReader.readBits(br, n);
    }

    private static translateShortCodes(code: number, ringBuffer: Int32Array, index: number): number {
        if (code < 16) {
            index += this.DISTANCE_SHORT_CODE_INDEX_OFFSET[code];
            index &= 3;
            return ringBuffer[index] + this.DISTANCE_SHORT_CODE_VALUE_OFFSET[code];
        } else {
            return code - 16 + 1;
        }
    }

    private static moveToFront(v: Int32Array, index: number): void {
        let value: number;
        for (value = v[index]; index > 0; --index) {
            v[index] = v[index - 1];
        }
        v[0] = value;
    }

    private static inverseMoveToFrontTransform(v: Int8Array, vLen: number): void {
        let mtf: Int32Array = new Int32Array(256);
        let i: number;
        for (i = 0; i < 256; mtf[i] = i++) {
        }

        for (i = 0; i < vLen; ++i) {
            let index: number = v[i] & 255;
            v[i] = mtf[index];
            if (index != 0) {
                Decode.moveToFront(mtf, index);
            }
        }

    }

    private static readHuffmanCodeLengths(codeLengthCodeLengths: Int32Array, numSymbols: number, codeLengths: Int32Array, br: BitReader): void {
        let symbols: number = 0;
        let prevCodeLen: number = 8;
        let repeat: number = 0;
        let repeatCodeLen: number = 0;
        let space: number = 32768;
        let table: Int32Array = new Int32Array(32);
        Huffman.buildHuffmanTable(table, 0, 5, codeLengthCodeLengths, 18);

        while (symbols < numSymbols && space > 0) {
            BitReader.readMoreInput(br);
            BitReader.fillBitWindow(br);
            let p: number = br.accumulator.shru(br.bitOffsets).toInt() & 31;
            br.bitOffsets += table[p] >> 16;
            let codeLen: number = table[p] & 0xFFFF;
            if (codeLen < 16) {
                repeat = 0;
                codeLengths[symbols++] = codeLen;
                if (codeLen != 0) {
                    prevCodeLen = codeLen;
                    space -= 32768 >> codeLen;
                }
            } else {
                let extraBits: number = codeLen - 14;
                let newLen: number = 0;
                if (codeLen == 16) {
                    newLen = prevCodeLen;
                }

                if (repeatCodeLen != newLen) {
                    repeat = 0;
                    repeatCodeLen = newLen;
                }

                let oldRepeat: number = repeat;
                if (repeat > 0) {
                    repeat -= 2;
                    repeat <<= extraBits;
                }
                repeat += BitReader.readBits(br, extraBits) + 3;
                let repeatDelta: number = repeat - oldRepeat;
                if (symbols + repeatDelta > numSymbols) {
                    throw new Exception("symbol + repeatDelta > numSymbols");
                }

                for (let i: number = 0; i < repeatDelta; ++i) {
                    codeLengths[symbols++] = repeatCodeLen;
                }

                if (repeatCodeLen != 0) {
                    space -= repeatDelta << 15 - repeatCodeLen;
                }
            }
        }

        if (space != 0) {
            throw new Exception("Unused space");
        } else {
            Utils.fillWithZeroesd(codeLengths, symbols, numSymbols - symbols);
        }
    }

    static readHuffmanCode(alphabetSize: number, table: Int32Array, offset: number, br: BitReader): void {
        let ok: boolean = true;
        BitReader.readMoreInput(br);
        let codeLengths: Int32Array = new Int32Array(alphabetSize);
        let simpleCodeOrSkip: number = BitReader.readBits(br, 2);
        let maxBits: number;
        let numSymbols: number;
        let i: number;
        if (simpleCodeOrSkip == 1) {
            let maxBitsCounter: number = alphabetSize - 1;
            maxBits = 0;
            let symbols: Int32Array = new Int32Array(4);

            for (numSymbols = BitReader.readBits(br, 2) + 1; maxBitsCounter != 0; ++maxBits) {
                maxBitsCounter >>= 1;
            }

            for (i = 0; i < numSymbols; ++i) {
                symbols[i] = BitReader.readBits(br, maxBits) % alphabetSize;
                codeLengths[symbols[i]] = 2;
            }

            codeLengths[symbols[0]] = 1;
            switch (numSymbols) {
                case 1:
                    break;
                case 2:
                    ok = symbols[0] != symbols[1];
                    codeLengths[symbols[1]] = 1;
                    break;
                case 3:
                    ok = symbols[0] != symbols[1] && symbols[0] != symbols[2] && symbols[1] != symbols[2];
                    break;
                case 4:
                default:
                    ok = symbols[0] != symbols[1] && symbols[0] != symbols[2] && symbols[0] != symbols[3] && symbols[1] != symbols[2] && symbols[1] != symbols[3] && symbols[2] != symbols[3];
                    if (BitReader.readBits(br, 1) == 1) {
                        codeLengths[symbols[2]] = 3;
                        codeLengths[symbols[3]] = 3;
                    } else {
                        codeLengths[symbols[0]] = 2;
                    }
            }
        } else { // Decode Huffman-coded code lengths.
            let codeLengthCodeLengths: Int32Array = new Int32Array(18);
            maxBits = 32;
            let numCodes: number = 0;

            for (numSymbols = simpleCodeOrSkip; numSymbols < 18 && maxBits > 0; ++numSymbols) {
                i = Decode.CODE_LENGTH_CODE_ORDER[numSymbols];
                BitReader.fillBitWindow(br);
                let p: number = br.accumulator.shru(br.bitOffsets).toInt() & 15;
                br.bitOffsets += Decode.FIXED_TABLE[p] >> 16;
                let v: number = Decode.FIXED_TABLE[p] & 0xFFFF;
                codeLengthCodeLengths[i] = v;
                if (v != 0) {
                    maxBits -= 32 >> v;
                    ++numCodes;
                }
            }

            ok = numCodes == 1 || maxBits == 0;
            this.readHuffmanCodeLengths(codeLengthCodeLengths, alphabetSize, codeLengths, br);
        }

        if (!ok) {
            throw new Exception("Can't readHuffmanCode");
        } else {
            Huffman.buildHuffmanTable(table, offset, 8, codeLengths, alphabetSize);
        }
    }

    private static decodeContextMap(contextMapSize: number, contextMap: Int8Array, br: BitReader): number {
        BitReader.readMoreInput(br);
        let numTrees: number = this.decodeVarLenUnsignedBytes(br) + 1;
        if (numTrees == 1) {
            Utils.fillWithZeroes(contextMap, 0, contextMapSize);
            return numTrees;
        } else {
            let useRleForZeros: boolean = BitReader.readBits(br, 1) == 1;
            let maxRunLengthPrefix: number = 0;
            if (useRleForZeros) {
                maxRunLengthPrefix = BitReader.readBits(br, 4) + 1;
            }

            let table: Int32Array = new Int32Array(1080);
            this.readHuffmanCode(numTrees + maxRunLengthPrefix, table, 0, br);
            let i: number = 0;

            while (true) {
                while (i < contextMapSize) {
                    BitReader.readMoreInput(br);
                    BitReader.fillBitWindow(br);
                    let code: number = this.readSymbol(table, 0, br);
                    if (code == 0) {
                        contextMap[i] = 0;
                        ++i;
                    } else if (code <= maxRunLengthPrefix) {
                        for (let reps: number = (1 << code) + BitReader.readBits(br, code); reps != 0; --reps) {
                            if (i >= contextMapSize) {
                                throw new Exception("Corrupted context map");
                            }

                            contextMap[i] = 0;
                            ++i;
                        }
                    } else {
                        contextMap[i] = code - maxRunLengthPrefix;
                        ++i;
                    }
                }
                if (BitReader.readBits(br, 1) == 1) {
                    this.inverseMoveToFrontTransform(contextMap, contextMapSize);
                }

                return numTrees;
            }
        }
    }

    private static decodeBlockTypeAndLength(state: States, treeType: number): void {
        let br: BitReader = state.br;
        let ringBuffers: Int32Array = state.blockTypeRb;
        let offset: number = treeType * 2;
        BitReader.fillBitWindow(br);
        let blockType: number = this.readSymbol(state.blockTypeTrees, treeType * 1080, br);
        state.blockLength[treeType] = this.readBlockLength(state.blockLenTrees, treeType * 1080, br);
        if (blockType == 1) {
            blockType = ringBuffers[offset + 1] + 1;
        } else if (blockType == 0) {
            blockType = ringBuffers[offset];
        } else {
            blockType -= 2;
        }

        if (blockType >= state.numBlockTypes[treeType]) {
            blockType -= state.numBlockTypes[treeType];
        }

        ringBuffers[offset] = ringBuffers[offset + 1];
        ringBuffers[offset + 1] = blockType;
    }

    private static decodeLiteralBlockSwitch(state: States): void {
        this.decodeBlockTypeAndLength(state, 0);
        let literalBlockType: number = state.blockTypeRb[1];
        state.contextMapSlice = literalBlockType << 6;
        state.literalTreeIndex = state.contextMap[state.contextMapSlice] & 255;
        state.literalTree = state.hGroup0.trees[state.literalTreeIndex];
        let contextMode: number = state.contextModes[literalBlockType];
        state.contextLookupOffset1 = Context.LOOKUP_OFFSETS[contextMode];
        state.contextLookupOffset2 = Context.LOOKUP_OFFSETS[contextMode + 1];
    }

    private static decodeCommandBlockSwitch(state: States): void {
        this.decodeBlockTypeAndLength(state, 1);
        state.treeCommandOffset = state.hGroup1.trees[state.blockTypeRb[3]];
    }

    private static decodeDistanceBlockSwitch(state: States): void {
        this.decodeBlockTypeAndLength(state, 2);
        state.distContextMapSlice = state.blockTypeRb[5] << 2;
    }

    private static maybeReallocateRingBuffer(state: States): void {
        let newSize: number = state.maxRingBufferSize;
        let ringBufferSizeWithSlack: number;

        if (newSize > state.expectedTotalSize.toNumber()) {
            for (ringBufferSizeWithSlack = state.expectedTotalSize.toNumber() + state.customDictionary.length; newSize >> 1 > ringBufferSizeWithSlack; newSize >>= 1) {
            }

            if (!state.inputEnd && newSize < 16384 && state.maxRingBufferSize >= 16384) {
                newSize = 16384;
            }
        }

        if (newSize > state.ringBufferSize) {
            ringBufferSizeWithSlack = newSize + 37;
            let newBuffer: Int8Array = new Int8Array(ringBufferSizeWithSlack);
            if (state.ringBuffer != null) {
                System.arraycopy(state.ringBuffer, 0, newBuffer, 0, state.ringBufferSize);
            } else if (state.customDictionary.length != 0) {
                let length: number = state.customDictionary.length;
                let offset: number = 0;
                if (length > state.maxBackwardDistance) {
                    offset = length - state.maxBackwardDistance;
                    length = state.maxBackwardDistance;
                }

                System.arraycopy(state.customDictionary, offset, newBuffer, 0, length);
                state.pos = length;
                state.bytesToIgnore = length;
            }

            state.ringBuffer = newBuffer;
            state.ringBufferSize = newSize;
        }
    }

    private static readMetablockInfo(state: States): void {
        let br: BitReader = state.br;
        if (state.inputEnd) {
            state.nextRunningState = 10;
            state.bytesToWrite = state.pos;
            state.bytesWritten = 0;
            state.runningState = 12;
        } else {
            state.hGroup0.codes = null;
            state.hGroup0.trees = null;
            state.hGroup1.codes = null;
            state.hGroup1.trees = null;
            state.hGroup2.codes = null;
            state.hGroup2.trees = null;
            BitReader.readMoreInput(br);
            this.decodeMetaBlockLength(br, state);
            if (state.metaBlockLengths != 0 || state.isMetadata) {
                if (!state.isUncompressed && !state.isMetadata) {
                    state.runningState = 2;
                } else {
                    BitReader.jumpToByteBoundary(br);
                    state.runningState = state.isMetadata ? 4 : 5;
                }

                if (!state.isMetadata) {
                    state.expectedTotalSize = state.expectedTotalSize.add(state.metaBlockLengths);
                    if (state.ringBufferSize < state.maxRingBufferSize) {
                        Decode.maybeReallocateRingBuffer(state);
                    }

                }
            }
        }
    }

    private static readMetablockHuffmanCodesAndContextMaps(state: States): void {
        let br: BitReader = state.br;

        let numDistanceCodes: number;
        for (numDistanceCodes = 0; numDistanceCodes < 3; ++numDistanceCodes) {
            state.numBlockTypes[numDistanceCodes] = this.decodeVarLenUnsignedBytes(br) + 1;
            state.blockLength[numDistanceCodes] = 268435456;
            if (state.numBlockTypes[numDistanceCodes] > 1) {
                this.readHuffmanCode(state.numBlockTypes[numDistanceCodes] + 2, state.blockTypeTrees, numDistanceCodes * 1080, br);
                this.readHuffmanCode(26, state.blockLenTrees, numDistanceCodes * 1080, br);
                state.blockLength[numDistanceCodes] = this.readBlockLength(state.blockLenTrees, numDistanceCodes * 1080, br);
            }
        }

        BitReader.readMoreInput(br);
        state.distancePostfixBits = BitReader.readBits(br, 2);
        state.numDirectDistanceCodes = 16 + (BitReader.readBits(br, 4) << state.distancePostfixBits);
        state.distancePostfixMask = (1 << state.distancePostfixBits) - 1;
        numDistanceCodes = state.numDirectDistanceCodes + (48 << state.distancePostfixBits);
        state.contextModes = new Int8Array(state.numBlockTypes[0]);
        let numLiteralTrees: number = 0;

        let j: number;
        while (numLiteralTrees < state.numBlockTypes[0]) {
            for (j = Math.min(numLiteralTrees + 96, state.numBlockTypes[0]); numLiteralTrees < j; ++numLiteralTrees) {
                state.contextModes[numLiteralTrees] = BitReader.readBits(br, 2) << 1;
            }

            BitReader.readMoreInput(br);
        }

        state.contextMap = new Int8Array(state.numBlockTypes[0] << 6);
        numLiteralTrees = this.decodeContextMap(state.numBlockTypes[0] << 6, state.contextMap, br);
        state.trivialLiteralContext = true;

        for (j = 0; j < state.numBlockTypes[0] << 6; ++j) {
            if (state.contextMap[j] != j >> 6) {
                state.trivialLiteralContext = false;
                break;
            }
        }

        state.distContextMap = new Int8Array(state.numBlockTypes[2] << 2);
        j = this.decodeContextMap(state.numBlockTypes[2] << 2, state.distContextMap, br);
        HuffmanTreeGroup.init(state.hGroup0, 256, numLiteralTrees);
        HuffmanTreeGroup.init(state.hGroup1, 704, state.numBlockTypes[1]);
        HuffmanTreeGroup.init(state.hGroup2, numDistanceCodes, j);
        HuffmanTreeGroup.decode(state.hGroup0, br);
        HuffmanTreeGroup.decode(state.hGroup1, br);
        HuffmanTreeGroup.decode(state.hGroup2, br);
        state.contextMapSlice = 0;
        state.distContextMapSlice = 0;
        state.contextLookupOffset1 = Context.LOOKUP_OFFSETS[state.contextModes[0]];
        state.contextLookupOffset2 = Context.LOOKUP_OFFSETS[state.contextModes[0] + 1];
        state.literalTreeIndex = 0;
        state.literalTree = state.hGroup0.trees[0];
        state.treeCommandOffset = state.hGroup1.trees[0];
        state.blockTypeRb[0] = state.blockTypeRb[2] = state.blockTypeRb[4] = 1;
        state.blockTypeRb[1] = state.blockTypeRb[3] = state.blockTypeRb[5] = 0;
    }

    private static copyUncompressedData(state: States): void {
        let br: BitReader = state.br;
        let ringBuffer: Int8Array = state.ringBuffer;
        if (state.metaBlockLengths <= 0) {
            BitReader.reload(br);
            state.runningState = 1;
        } else {
            let chunkLength: number = Math.min(state.ringBufferSize - state.pos, state.metaBlockLengths);
            BitReader.copyBytes(br, ringBuffer, state.pos, chunkLength);
            state.metaBlockLengths -= chunkLength;
            state.pos += chunkLength;
            if (state.pos == state.ringBufferSize) {
                state.nextRunningState = 5;
                state.bytesToWrite = state.ringBufferSize;
                state.bytesWritten = 0;
                state.runningState = 12;
            } else {
                BitReader.reload(br);
                state.runningState = 1;
            }
        }
    }

    private static writeRingBuffer(state: States): boolean {
        if (state.bytesToIgnore != 0) {
            state.bytesWritten += state.bytesToIgnore;
            state.bytesToIgnore = 0;
        }

        let toWrite: number = Math.min(state.outputLength - state.outputUsed, state.bytesToWrite - state.bytesWritten);
        if (toWrite != 0) {
            System.arraycopy(state.ringBuffer, state.bytesWritten, state.output, state.outputOffset + state.outputUsed, toWrite);
            state.outputUsed += toWrite;
            state.bytesWritten += toWrite;
        }

        return state.outputUsed < state.outputLength;
    }

    static setCustomDictionary(state: States, data: Int8Array): void {
        state.customDictionary = data == null ? new Int8Array(0) : data;
    }

    static decompress(state: States): void {
        if (state.runningState == 0) {
            throw new Exception("Can't decompress until initialized");
        } else if (state.runningState == 11) {
            throw new Exception("Can't decompress after close");
        } else {
            let br: BitReader = state.br;
            let ringBufferMask: number = state.ringBufferSize - 1;
            let ringBuffer: Int8Array = state.ringBuffer;

            while (state.runningState != 10) {
                let postfix: number;
                let n: number;
                let offset: number;

                let var10002: number;
                switch (state.runningState) {
                    case 1:
                        if (state.metaBlockLengths < 0) {
                            throw new Exception("Invalid metablock length");
                        }
                        this.readMetablockInfo(state);
                        ringBufferMask = state.ringBufferSize - 1;
                        ringBuffer = state.ringBuffer;
                        break;
                    case 2:
                        this.readMetablockHuffmanCodesAndContextMaps(state);
                        state.runningState = 3;

                    case 3:
                        if (state.metaBlockLengths <= 0) {
                            state.runningState = 1;
                            break;
                        } else {
                            BitReader.readMoreInput(br);
                            if (state.blockLength[1] == 0) {
                                this.decodeCommandBlockSwitch(state);
                            }

                            var10002 = state.blockLength[1]--;
                            BitReader.fillBitWindow(br);
                            let cmdCode: number = this.readSymbol(state.hGroup1.codes, state.treeCommandOffset, br);
                            let rangeIdx: number = cmdCode >>> 6;
                            state.distanceCode = 0;
                            if (rangeIdx >= 2) {
                                rangeIdx -= 2;
                                state.distanceCode = -1;
                            }
                            let insertCode: number = Prefix.INSERT_RANGE_LUT[rangeIdx] + (cmdCode >>> 3 & 7);
                            let copyCode: number = Prefix.COPY_RANGE_LUT[rangeIdx] + (cmdCode & 7);
                            state.insertLength = Prefix.INSERT_LENGTH_OFFSET[insertCode] + BitReader.readBits(br, Prefix.INSERT_LENGTH_N_BITS[insertCode]);
                            state.copyLength = Prefix.COPY_LENGTH_OFFSET[copyCode] + BitReader.readBits(br, Prefix.COPY_LENGTH_N_BITS[copyCode]);
                            state.j = 0;
                            state.runningState = 6;
                        }
                    case 6:
                        if (state.trivialLiteralContext) {
                            while (state.j < state.insertLength) {
                                BitReader.readMoreInput(br);
                                if (state.blockLength[0] == 0) {
                                    this.decodeLiteralBlockSwitch(state);
                                }

                                var10002 = state.blockLength[0]--;
                                BitReader.fillBitWindow(br);
                                ringBuffer[state.pos] = this.readSymbol(state.hGroup0.codes, state.literalTree, br);
                                ++state.j;
                                if (state.pos++ == ringBufferMask) {
                                    state.nextRunningState = 6;
                                    state.bytesToWrite = state.ringBufferSize;
                                    state.bytesWritten = 0;
                                    state.runningState = 12;
                                    break;
                                }
                            }
                        } else {
                            postfix = ringBuffer[state.pos - 1 & ringBufferMask] & 255;
                            n = ringBuffer[state.pos - 2 & ringBufferMask] & 255;

                            while (state.j < state.insertLength) {
                                BitReader.readMoreInput(br);
                                if (state.blockLength[0] == 0) {
                                    this.decodeLiteralBlockSwitch(state);
                                }

                                offset = state.contextMap[state.contextMapSlice + (Context.LOOKUP[state.contextLookupOffset1 + postfix] | Context.LOOKUP[state.contextLookupOffset2 + n])] & 255;
                                var10002 = state.blockLength[0]--;
                                n = postfix;
                                BitReader.fillBitWindow(br);
                                postfix = this.readSymbol(state.hGroup0.codes, state.hGroup0.trees[offset], br);
                                ringBuffer[state.pos] = postfix;
                                ++state.j;
                                if (state.pos++ == ringBufferMask) {
                                    state.nextRunningState = 6;
                                    state.bytesToWrite = state.ringBufferSize;
                                    state.bytesWritten = 0;
                                    state.runningState = 12;
                                    break;
                                }
                            }
                        }

                        if (state.runningState != 6) {
                            break;
                        }

                        state.metaBlockLengths -= state.insertLength;
                        if (state.metaBlockLengths <= 0) {
                            state.runningState = 3;
                            break;
                        } else {
                            if (state.distanceCode < 0) {
                                BitReader.readMoreInput(br);
                                if (state.blockLength[2] == 0) {
                                    this.decodeDistanceBlockSwitch(state);
                                }

                                var10002 = state.blockLength[2]--;
                                BitReader.fillBitWindow(br);
                                state.distanceCode = this.readSymbol(state.hGroup2.codes, state.hGroup2.trees[state.distContextMap[state.distContextMapSlice + (state.copyLength > 4 ? 3 : state.copyLength - 2)] & 255], br);
                                if (state.distanceCode >= state.numDirectDistanceCodes) {
                                    state.distanceCode -= state.numDirectDistanceCodes;
                                    postfix = state.distanceCode & state.distancePostfixMask;
                                    state.distanceCode >>>= state.distancePostfixBits;
                                    n = (state.distanceCode >>> 1) + 1;
                                    offset = (2 + (state.distanceCode & 1) << n) - 4;
                                    state.distanceCode = state.numDirectDistanceCodes + postfix + (offset + BitReader.readBits(br, n) << state.distancePostfixBits);
                                }
                            }

                            state.distance = this.translateShortCodes(state.distanceCode, state.distRb, state.distRbIdx);
                            if (state.distance < 0) {
                                throw new Exception("Negative distance");
                            }

                            if (state.maxDistance != state.maxBackwardDistance && state.pos < state.maxBackwardDistance) {
                                state.maxDistance = state.pos;
                            } else {
                                state.maxDistance = state.maxBackwardDistance;
                            }

                            state.copyDst = state.pos;
                            if (state.distance > state.maxDistance) {
                                state.runningState = 9;
                                break;
                            } else {
                                if (state.distanceCode > 0) {
                                    state.distRb[state.distRbIdx & 3] = state.distance;
                                    ++state.distRbIdx;
                                }

                                if (state.copyLength > state.metaBlockLengths) {
                                    throw new Exception("Invalid backward reference");
                                }

                                state.j = 0;
                                state.runningState = 7;

                            }
                        }
                    case 7:
                        postfix = state.pos - state.distance & ringBufferMask;
                        n = state.pos;
                        offset = state.copyLength - state.j;
                        if (postfix + offset < ringBufferMask && n + offset < ringBufferMask) {
                            for (let k: number = 0; k < offset; ++k) {
                                ringBuffer[n++] = ringBuffer[postfix++];
                            }

                            state.j += offset;
                            state.metaBlockLengths -= offset;
                            state.pos += offset;
                        } else {
                            while (state.j < state.copyLength) {
                                ringBuffer[state.pos] = ringBuffer[state.pos - state.distance & ringBufferMask];
                                --state.metaBlockLengths;
                                ++state.j;
                                if (state.pos++ == ringBufferMask) {
                                    state.nextRunningState = 7;
                                    state.bytesToWrite = state.ringBufferSize;
                                    state.bytesWritten = 0;
                                    state.runningState = 12;
                                    break;
                                }
                            }
                        }

                        if (state.runningState == 7) {
                            state.runningState = 3;
                        }
                        break;
                    case 4:
                        while (state.metaBlockLengths > 0) {
                            BitReader.readMoreInput(br);
                            BitReader.readBits(br, 8);
                            --state.metaBlockLengths;
                        }

                        state.runningState = 1;
                        break;
                    case 5:
                        this.copyUncompressedData(state);
                        break;
                    case 8:
                        System.arraycopy(ringBuffer, state.ringBufferSize, ringBuffer, 0, state.copyDst - state.ringBufferSize);
                        state.runningState = 3;
                        break;
                    case 9:
                        if (state.copyLength >= 4 && state.copyLength <= 24) {
                            offset = Dictionary.OFFSETS_BY_LENGTH[state.copyLength];
                            let wordId: number = state.distance - state.maxDistance - 1;
                            let shift: number = Dictionary.SIZE_BITS_BY_LENGTH[state.copyLength];
                            let mask: number = (1 << shift) - 1;
                            let wordIdx: number = wordId & mask;
                            let transformIdx: number = wordId >>> shift;
                            offset += wordIdx * state.copyLength;
                            if (transformIdx >= Transform.TRANSFORMS.length) {
                                throw new Exception("Invalid backward reference");
                            }

                            let len: number = Transform.transformDictionaryWord(ringBuffer, state.copyDst, Dictionary.getData(), offset, state.copyLength, Transform.TRANSFORMS[transformIdx]);
                            state.copyDst += len;
                            state.pos += len;
                            state.metaBlockLengths -= len;
                            if (state.copyDst >= state.ringBufferSize) {
                                state.nextRunningState = 8;
                                state.bytesToWrite = state.ringBufferSize;
                                state.bytesWritten = 0;
                                state.runningState = 12;
                            } else {
                                state.runningState = 3;
                            }
                            break;
                        }

                        throw new Exception("Invalid backward reference");
                    case 10:
                    case 11:

                    case 12:
                        if (!this.writeRingBuffer(state)) {
                            return;
                        }

                        if (state.pos >= state.maxBackwardDistance) {
                            state.maxDistance = state.maxBackwardDistance;
                        }

                        state.pos &= ringBufferMask;
                        state.runningState = state.nextRunningState;
                        break;
                    default:
                        throw new Exception("Unexpected state " + state.runningState);
                }
            }

            if (state.runningState == 10) {
                if (state.metaBlockLengths < 0) {
                    throw new Exception("Invalid metablock length");
                }
                BitReader.jumpToByteBoundary(br);
                BitReader.checkHealth(state.br, true);
            }

        }
    }
}