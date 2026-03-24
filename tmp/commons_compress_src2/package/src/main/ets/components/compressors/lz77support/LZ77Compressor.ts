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
import Exception from '../../util/Exception'
import Arrays from '../../util/Arrays'
import { int } from '../../util/CustomTypings'
import Parameters from './Parameters'
import System from '../../util/System'

enum BlockType {
    LITERAL, BACK_REFERENCE, EOD
}


export class Block {
    private BlockType: BlockType

    public getType(): BlockType {
        return BlockType.BACK_REFERENCE
    }
}

export class LiteralBlock extends Block {
    private data: Int8Array;
    private offset: int;
    private length: int;

    constructor(data: Int8Array | Int32Array, offset: int, length: int) {
        super()
        this.data = new Int8Array(data);
        this.offset = offset;
        this.length = length;
    }

    public getData(): Int8Array {
        return this.data;
    }

    public getOffset(): int {
        return this.offset;
    }

    public getLength(): int {
        return this.length;
    }

    public getType(): BlockType {
        return BlockType.LITERAL;
    }

    public toString(): string {
        return "LiteralBlock starting at " + this.offset + " with length " + this.length;
    }
}


class BackReference extends Block {
    private offset: int;
    private length: int;

    constructor(offset: int, length: int) {
        super()
        this.offset = offset;
        this.length = length;
    }

    public getOffset(): int {
        return this.offset;
    }

    public getLength(): int {
        return this.length;
    }

    public getType(): BlockType {
        return BlockType.BACK_REFERENCE;
    }

    public toString(): string {
        return "BackReference with offset " + this.offset + " and length " + this.length;
    }
}

class EOD extends Block {
    public getType(): BlockType {
        return BlockType.EOD;
    }
}


interface Callback {

    accept(b: Block): void
}


export class LZ77Compressor {
    private static THE_EOD: Block = new EOD();
    static NUMBER_OF_BYTES_IN_HASH: int = 3;
    private static NO_MATCH: int = -1;
    private params: Parameters;
    private callback: Function;
    private window: Int8Array;
    private head: Int32Array;
    private prev: Int32Array;
    private wMask: int = 0;
    private initialized: boolean;
    private currentPosition: int = 0;
    private lookahead: int = 0;
    private insertHash: int = 0;
    private blockStart: int = 0;
    private matchStart: int = LZ77Compressor.NO_MATCH;
    private missedInserts: int = 0;

    constructor(params: Parameters, callback: (b: Block) => void) {

        if (params == null || callback == null) {
            return
        }

        this.params = params;
        this.callback = callback;

        let wSize: int = params.getWindowSize();
        this.window = new Int8Array(wSize * 2);
        this.wMask = wSize - 1;
        this.head = new Int32Array(LZ77Compressor.HASH_SIZE);
        Arrays.fill(this.head, LZ77Compressor.NO_MATCH);
        this.prev = new Int32Array(wSize);
    }

    public compressByte(data: Int8Array, off?: int, len?: int): void {
        off = off == undefined ? 0 : off;
        len = len == undefined ? data.length - off : len;

        let wSize: int = this.params.getWindowSize();
        while (len > wSize) { // chop into windowSize sized chunks
            this.doCompress(data, off, wSize);
            off += wSize;
            len -= wSize;
        }
        if (len > 0) {
            this.doCompress(data, off, len);
        }
    }

    public finish(): void {
        if (this.blockStart != this.currentPosition || this.lookahead > 0) {
            this.currentPosition += this.lookahead;
            this.flushLiteralBlock();
        }
        this.callback(LZ77Compressor.THE_EOD);
    }

    public prefill(data: Int8Array): void {
        if (this.currentPosition != 0 || this.lookahead != 0) {
            throw new Exception();
        }


        let len = Math.min(this.params.getWindowSize(), data.length);
        System.arraycopy(data, data.length - len, this.window, 0, len);

        if (len >= LZ77Compressor.NUMBER_OF_BYTES_IN_HASH) {
            this.initialize();
            let stop: int = len - LZ77Compressor.NUMBER_OF_BYTES_IN_HASH + 1;
            for (let i: int = 0; i < stop; i++) {
                this.insertString(i);
            }
            this.missedInserts = LZ77Compressor.NUMBER_OF_BYTES_IN_HASH - 1;
        } else { // not enough data to hash anything
            this.missedInserts = len;
        }
        this.blockStart = this.currentPosition = len;
    }

    private static HASH_SIZE: int = 1 << 15;
    private static HASH_MASK: int = LZ77Compressor.HASH_SIZE - 1;
    private static H_SHIFT: int = 5;

    public nextHash(oldHash: int, nextByte: number): int {
        let nextVal: int = nextByte & 0xFF;
        return ((oldHash << LZ77Compressor.H_SHIFT) ^ nextVal) & LZ77Compressor.HASH_MASK;
    }

    private doCompress(data: Int8Array, off: int, len: int): void {
        let spaceLeft: int = this.window.length - this.currentPosition - this.lookahead;
        if (len > spaceLeft) {
            this.slide();
        }
        System.arraycopy(data, off, this.window, this.currentPosition + this.lookahead, len);
        this.lookahead += len;
        if (!this.initialized && this.lookahead >= this.params.getMinBackReferenceLength()) {
            this.initialize();
        }
        if (this.initialized) {
            this.compress();
        }
    }

    private slide(): void {
        let wSize: int = this.params.getWindowSize();
        if (this.blockStart != this.currentPosition && this.blockStart < wSize) {
            this.flushLiteralBlock();
            this.blockStart = this.currentPosition;
        }
        System.arraycopy(this.window, wSize, this.window, 0, wSize);
        this.currentPosition -= wSize;
        this.matchStart -= wSize;
        this.blockStart -= wSize;
        for (let i: int = 0; i < LZ77Compressor.HASH_SIZE; i++) {
            let h: int = this.head[i];
            this.head[i] = h >= wSize ? h - wSize : LZ77Compressor.NO_MATCH;
        }
        for (let i: int = 0; i < wSize; i++) {
            let p: int = this.prev[i];
            this.prev[i] = p >= wSize ? p - wSize : LZ77Compressor.NO_MATCH;
        }
    }

    private initialize(): void {
        for (let i: int = 0; i < LZ77Compressor.NUMBER_OF_BYTES_IN_HASH - 1; i++) {
            this.insertHash = this.nextHash(this.insertHash, this.window[i]);
        }
        this.initialized = true;
    }

    private compress(): void {
        let minMatch: int = this.params.getMinBackReferenceLength();
        let lazy: boolean = this.params.getLazyMatching();
        let lazyThreshold: int = this.params.getLazyMatchingThreshold();

        while (this.lookahead >= minMatch) {
            this.catchUpMissedInserts();
            let matchLength: int = 0;
            let hashHead: int = this.insertString(this.currentPosition);
            if (hashHead != LZ77Compressor.NO_MATCH && hashHead - this.currentPosition <= this.params.getMaxOffset()) {
                // sets matchStart as a side effect
                matchLength = this.longestMatch(hashHead);

                if (lazy && matchLength <= lazyThreshold && this.lookahead > minMatch) {
                    // try to find a longer match using the next position
                    matchLength = this.longestMatchForNextPosition(matchLength);
                }
            }
            if (matchLength >= minMatch) {
                if (this.blockStart != this.currentPosition) {
                    // emit preceeding literal block
                    this.flushLiteralBlock();
                    this.blockStart = LZ77Compressor.NO_MATCH;
                }
                this.flushBackReference(matchLength);
                this.insertStringsInMatch(matchLength);
                this.lookahead -= matchLength;
                this.currentPosition += matchLength;
                this.blockStart = this.currentPosition;
            } else {
                // no match, append to current or start a new literal
                this.lookahead--;
                this.currentPosition++;
                if (this.currentPosition - this.blockStart >= this.params.getMaxLiteralLength()) {
                    this.flushLiteralBlock();
                    this.blockStart = this.currentPosition;
                }
            }
        }
    }

    private insertString(pos: int): int {
        this.insertHash = this.nextHash(this.insertHash, this.window[pos - 1 + LZ77Compressor.NUMBER_OF_BYTES_IN_HASH]);
        let hashHead: int = this.head[this.insertHash];
        this.prev[pos & this.wMask] = hashHead;
        this.head[this.insertHash] = pos;
        return hashHead;
    }

    private longestMatchForNextPosition(prevMatchLength: int): int {
        let prevMatchStart: int = this.matchStart;
        let prevInsertHash: int = this.insertHash;

        this.lookahead--;
        this.currentPosition++;
        let hashHead: int = this.insertString(this.currentPosition);
        let prevHashHead: int = this.prev[this.currentPosition & this.wMask];
        let matchLength: int = this.longestMatch(hashHead);

        if (matchLength <= prevMatchLength) {

            matchLength = prevMatchLength;
            this.matchStart = prevMatchStart;

            this.head[this.insertHash] = prevHashHead;
            this.insertHash = prevInsertHash;
            this.currentPosition--;
            this.lookahead++;
        }
        return matchLength;
    }

    private insertStringsInMatch(matchLength: int): void {

        let stop: int = Math.min(matchLength - 1, this.lookahead - LZ77Compressor.NUMBER_OF_BYTES_IN_HASH);
        for (let i: int = 1; i <= stop; i++) {
            this.insertString(this.currentPosition + i);
        }
        this.missedInserts = matchLength - stop - 1;
    }

    private catchUpMissedInserts(): void {
        while (this.missedInserts > 0) {
            this.insertString(this.currentPosition - this.missedInserts--);
        }
    }

    private flushBackReference(matchLength: int): void {
        this.callback(new BackReference(this.currentPosition - this.matchStart, matchLength));
    }

    private flushLiteralBlock(): void {
        this.callback(new LiteralBlock(this.window, this.blockStart, this.currentPosition - this.blockStart));
    }

    private longestMatch(matchHead: int): int {
        let minLength: int = this.params.getMinBackReferenceLength();
        let longestMatchLength: int = minLength - 1;
        let maxPossibleLength: int = Math.min(this.params.getMaxBackReferenceLength(), this.lookahead);
        let minIndex: int = Math.max(0, this.currentPosition - this.params.getMaxOffset());
        let niceBackReferenceLength: int = Math.min(maxPossibleLength, this.params.getNiceBackReferenceLength());
        let maxCandidates: int = this.params.getMaxCandidates();
        for (let candidates: int = 0; candidates < maxCandidates && matchHead >= minIndex; candidates++) {
            let currentLength: int = 0;
            for (let i: int = 0; i < maxPossibleLength; i++) {
                if (this.window[matchHead + i] != this.window[this.currentPosition + i]) {
                    break;
                }
                currentLength++;
            }
            if (currentLength > longestMatchLength) {
                longestMatchLength = currentLength;
                this.matchStart = matchHead;
                if (currentLength >= niceBackReferenceLength) {
                    break;
                }
            }
            matchHead = this.prev[matchHead & this.wMask];
        }
        return longestMatchLength;
    }
}
