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
import Long from "./long/index";
import InputStream from './InputStream';
import ByteOrder from './ByteOrder';
import Exception from './Exception';

export default class BitInputStream {
    public static SIZE: number = 8;
    private static MAXIMUM_CACHE_SIZE: number = 63; // bits in long minus sign bit
    private static MASKS: Array<Long> = new Array<Long>(BitInputStream.MAXIMUM_CACHE_SIZE + 1);

    public static staticInit() {
        for (let i = 0; i < (BitInputStream.MAXIMUM_CACHE_SIZE + 1); i++) {
            BitInputStream.MASKS[i] = Long.fromNumber(0);
        }
        for (let i = 1; i <= BitInputStream.MAXIMUM_CACHE_SIZE; i++) {
            BitInputStream.MASKS[i] = BitInputStream.MASKS[i - 1].shiftLeft(1).add(1);
        }
    }

    private inputStream: InputStream;
    private byteOrder: ByteOrder;
    private bitsCached: Long = Long.fromNumber(0);
    private bitsCachedSize: number = 0;

    constructor(inputStream: InputStream, byteOrder: ByteOrder) {
        this.inputStream = inputStream;
        this.byteOrder = byteOrder;
    }

    public close(): void {
        this.inputStream.close();
    }

    public clearBitCache(): void {
        this.bitsCached = Long.fromNumber(0);
        this.bitsCachedSize = 0;
    }

    public readBits(count: number): Long {
        if (count < 0 || count > BitInputStream.MAXIMUM_CACHE_SIZE) {
            throw new Exception("count must not be negative or greater than " + BitInputStream.MAXIMUM_CACHE_SIZE);
        }
        if (this.ensureCache(count)) {
            return Long.fromNumber(-1);
        }

        if (this.bitsCachedSize < count) {
            return this.processBitsGreater57(count);
        }
        return this.readCachedBits(count);
    }

    public bitsCacheds(): number {
        return this.bitsCachedSize;
    }

    public bitsAvailable(): Long {
        return Long.fromNumber(BitInputStream.SIZE).mul(this.inputStream.available()).add(this.bitsCachedSize);
    }

    public alignWithByteBoundary(): void {
        let toSkip: number = this.bitsCachedSize % BitInputStream.SIZE;
        if (toSkip > 0) {
            this.readCachedBits(toSkip);
        }
    }

    public getBytesRead(): Long {
        return Long.fromNumber(this.inputStream.getBytesCount());
    }

    private processBitsGreater57(count: number): Long {
        let bitsOut: Long;
        let overflowBits: number;
        let overflow: Long = Long.fromNumber(0);

        let bitsToAddCount: number = count - this.bitsCachedSize;
        overflowBits = BitInputStream.SIZE - bitsToAddCount;
        let nextByte: Long = Long.fromNumber(this.inputStream.read());
        if (nextByte.lessThan(0)) {
            return nextByte;
        }
        if (this.byteOrder == ByteOrder.LITTLE_ENDIAN) {
            let bitsToAdd: Long = nextByte.and(BitInputStream.MASKS[bitsToAddCount]);
            this.bitsCached = this.bitsCached.or(bitsToAdd.shiftLeft(this.bitsCachedSize));
            overflow = (nextByte.shiftRightUnsigned(bitsToAddCount)).and(BitInputStream.MASKS[overflowBits]);
        } else {
            this.bitsCached = this.bitsCached.shiftLeft(bitsToAddCount);
            let bitsToAdd: Long = (nextByte.shiftRightUnsigned(overflowBits)).and(BitInputStream.MASKS[bitsToAddCount]);
            this.bitsCached = this.bitsCached.or(bitsToAdd);
            overflow = nextByte.or(BitInputStream.MASKS[overflowBits]);
        }
        bitsOut = this.bitsCached.and(BitInputStream.MASKS[count]);
        this.bitsCached = overflow;
        this.bitsCachedSize = overflowBits;
        return bitsOut;
    }

    private readCachedBits(count: number): Long {
        let bitsOut: Long;
        if (this.byteOrder == ByteOrder.LITTLE_ENDIAN) {
            bitsOut = this.bitsCached.and(BitInputStream.MASKS[count]);
            this.bitsCached = this.bitsCached.shiftRightUnsigned(count);
        } else {
            let value: Long = this.bitsCached.shiftRight((this.bitsCachedSize - count));
            bitsOut = BitInputStream.MASKS[count].and(value);
        }
        this.bitsCachedSize -= count;
        return bitsOut;
    }

    private ensureCache(count: number): boolean {
        while (this.bitsCachedSize < count && this.bitsCachedSize < 57) {
            let nextByte: Long = Long.fromNumber(this.inputStream.read());
            if (nextByte.lessThan(0)) {
                return true;
            }
            if (this.byteOrder == ByteOrder.LITTLE_ENDIAN) {
                this.bitsCached = this.bitsCached.or(nextByte.shiftLeft(this.bitsCachedSize));
            } else {
                this.bitsCached = this.bitsCached.shiftLeft(BitInputStream.SIZE);
                this.bitsCached = this.bitsCached.or(nextByte);
            }
            this.bitsCachedSize += BitInputStream.SIZE;
        }
        return false;
    }
}

BitInputStream.staticInit();