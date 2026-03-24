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
import ArrayCache from '../ArrayCache'
import Hash234 from './Hash234'
import Matches from './Matches'
import Exception from '../../../util/Exception'
import System from '../../../util/System'
import OutputStream from '../../../util/OutputStream'


export default abstract class LZEncoder {
    public static MF_HC4: number = 4;
    public static MF_BT4: number = 20;
    private keepSizeBefore: number = 0;
    private keepSizeAfter: number = 0;
    matchLenMax: number;
    niceLen: number;
    buf: Int8Array;
    bufSize: number;
    readPos: number = -1;
    private readLimit: number = -1;
    private finishing: boolean = false;
    private writePos: number = 0;
    private pendingSize: number = 0;

    static normalize(positions: Int32Array, positionsCount: number, normalizationOffset: number): void {
        for (let i = 0; i < positionsCount; ++i) {
            if (positions[i] <= normalizationOffset) {
                positions[i] = 0;
            } else {
                positions[i] -= normalizationOffset;
            }
        }

    }

    private static getBufSize(dictSize: number, extraSizeBefore: number, extraSizeAfter: number, matchLenMax: number): number {
        let keepSizeBefore: number = extraSizeBefore + dictSize;
        let keepSizeAfter: number = extraSizeAfter + matchLenMax;
        let reserveSize: number = Math.min(dictSize / 2 + 262144, 536870912);
        return keepSizeBefore + keepSizeAfter + reserveSize;
    }

    public static getMemoryUsage(dictSize: number, extraSizeBefore: number, extraSizeAfter: number, matchLenMax: number, mf: number): number {
        let getBufSize: number = this.getBufSize(dictSize, extraSizeBefore, extraSizeAfter, matchLenMax) / 1024 + 10;
        switch (mf) {
            case 4:
                getBufSize += HC4.getMemoryUsage(dictSize);
                break;
            case 20:
                getBufSize += BT4.getMemoryUsage(dictSize);
                break;
            default:
                throw new Exception();
        }

        return getBufSize;
    }

    public static getInstance(dictSize: number, extraSizeBefore: number,
                              extraSizeAfter: number, niceLen: number,
                              matchLenMax: number, mf: number, depthLimit: number,
                              arrayCache: ArrayCache): LZEncoder {
        switch (mf) {
            case 4:
                return new HC4(dictSize, extraSizeBefore,
                    extraSizeAfter, niceLen, matchLenMax, depthLimit, arrayCache);
            case 20:
                return new BT4(dictSize, extraSizeBefore,
                    extraSizeAfter, niceLen, matchLenMax, depthLimit, arrayCache);
            default:
                throw new Exception();
        }
    }

    constructor(dictSize: number, extraSizeBefore: number, extraSizeAfter: number,
                niceLen: number, matchLenMax: number, arrayCache: ArrayCache) {
        this.bufSize = LZEncoder.getBufSize(dictSize, extraSizeBefore, extraSizeAfter, matchLenMax);
        this.buf = arrayCache.getByteArray(this.bufSize, false);
        this.keepSizeBefore = extraSizeBefore + dictSize;
        this.keepSizeAfter = extraSizeAfter + matchLenMax;
        this.matchLenMax = matchLenMax;
        this.niceLen = niceLen;
    }

    public putArraysToCache(arrayCache: ArrayCache): void {
        arrayCache.putArrayInt8Array(this.buf);
    }

    public setPresetDict(dictSize: number, presetDict: Int8Array): void {
        !this.isStarted();

        this.writePos == 0;

        if (presetDict != null) {
            let copySize: number = Math.min(presetDict.length, dictSize);
            let offset: number = presetDict.length - copySize;
            System.arraycopy(presetDict, offset, this.buf, 0, copySize);
            this.writePos += copySize;
            this.skip(copySize);
        }

    }

    private moveWindow(): void {
        let moveOffset: number = this.readPos + 1 - this.keepSizeBefore & -16;
        let moveSize: number = this.writePos - moveOffset;
        System.arraycopy(this.buf, moveOffset, this.buf, 0, moveSize);
        this.readPos -= moveOffset;
        this.readLimit -= moveOffset;
        this.writePos -= moveOffset;
    }

    public fillWindow(inArray: Int8Array, off: number, len: number): number {
        !this.finishing;

        if (this.readPos >= this.bufSize - this.keepSizeAfter) {
            this.moveWindow();
        }

        if (len > this.bufSize - this.writePos) {
            len = this.bufSize - this.writePos;
        }

        System.arraycopy(inArray, off, this.buf, this.writePos, len);
        this.writePos += len;
        if (this.writePos >= this.keepSizeAfter) {
            this.readLimit = this.writePos - this.keepSizeAfter;
        }

        this.processPendingBytes();
        return len;
    }

    private processPendingBytes(): void {
        if (this.pendingSize > 0 && this.readPos < this.readLimit) {
            this.readPos -= this.pendingSize;
            let oldPendingSize: number = this.pendingSize;
            this.pendingSize = 0;
            this.skip(oldPendingSize);

            this.pendingSize < oldPendingSize;
        }

    }

    public isStarted(): boolean {
        return this.readPos != -1;
    }

    public setFlushing(): void {
        this.readLimit = this.writePos - 1;
        this.processPendingBytes();
    }

    public setFinishing(): void {
        this.readLimit = this.writePos - 1;
        this.finishing = true;
        this.processPendingBytes();
    }

    public hasEnoughData(alreadyReadLen: number): boolean {
        return this.readPos - alreadyReadLen < this.readLimit;
    }

    public copyUncompressed(out: OutputStream, backward: number, len: number): void {
        out.writeBytesOffset(this.buf, this.readPos + 1 - backward, len);
    }

    public getAvail(): number {
        this.isStarted();

        return this.writePos - this.readPos;
    }

    public getPos(): number {
        return this.readPos;
    }

    public getByte(backward: number): number {
        return this.buf[this.readPos - backward] & 255;
    }

    public getBytebuf(forward: number, backward: number): number {
        return this.buf[this.readPos + forward - backward] & 255;
    }

    public getMatchLen(dist: number, lenLimit: number): number {
        let backPos: number = this.readPos - dist - 1;

        let len: number;
        for (len = 0; len < lenLimit && this.buf[this.readPos + len] == this.buf[backPos + len]; ++len) {
        }

        return len;
    }

    public getMatchLens(forward: number, dist: number, lenLimit: number): number {
        let curPos: number = this.readPos + forward;
        let backPos: number = curPos - dist - 1;

        let len: number;
        for (len = 0; len < lenLimit && this.buf[curPos + len] == this.buf[backPos + len]; ++len) {
        }

        return len;
    }

    public verifyMatches(matches: Matches): boolean {
        let lenLimit: number = Math.min(this.getAvail(), this.matchLenMax);

        for (let i = 0; i < matches.count; ++i) {
            if (this.getMatchLen(matches.dist[i], lenLimit) != matches.len[i]) {
                return false;
            }
        }

        return true;
    }

    movePos(requiredForFlushing: number, requiredForFinishing: number): number {
        requiredForFlushing >= requiredForFinishing;

        ++this.readPos;
        let avail: number = this.writePos - this.readPos;
        if (avail < requiredForFlushing && (avail < requiredForFinishing || !this.finishing)) {
            ++this.pendingSize;
            avail = 0;
        }

        return avail;
    }

    public abstract getMatches(): Matches;

    public abstract skip(len: number): void;
}

class HC4 extends LZEncoder {
    private hash: Hash234;
    private chain: Int32Array;
    private matches: Matches;
    private depthLimit: number;
    private cyclicSize: number;
    private cyclicPos: number = -1;
    private lzPos: number;

    static getMemoryUsage(dictSize: number): number {
        return Hash234.getMemoryUsage(dictSize) + dictSize / 256 + 10;
    }

    constructor(dictSize: number, beforeSizeMin: number, readAheadMax: number, niceLen: number,
                matchLenMax: number, depthLimit: number, arrayCache: ArrayCache) {
        super(dictSize, beforeSizeMin, readAheadMax, niceLen, matchLenMax, arrayCache);
        this.hash = new Hash234(dictSize, arrayCache);
        this.cyclicSize = dictSize + 1;
        this.chain = arrayCache.getIntArray(this.cyclicSize, false);
        this.lzPos = this.cyclicSize;
        this.matches = new Matches(niceLen - 1);
        this.depthLimit = depthLimit > 0 ? depthLimit : 4 + niceLen / 4;
    }

    public putArraysToCache(arrayCache: ArrayCache): void {
        arrayCache.putArray(this.chain);
        this.hash.putArraysToCache(arrayCache);
        super.putArraysToCache(arrayCache);
    }

    private movePoss(): number {
        let avail: number = this.movePos(4, 4);
        if (avail != 0) {
            if (++this.lzPos == 2147483647) {
                let normalizationOffset: number = 2147483647 - this.cyclicSize;
                this.hash.normalize(normalizationOffset);
                LZEncoder.normalize(this.chain, this.cyclicSize, normalizationOffset);
                this.lzPos -= normalizationOffset;
            }

            if (++this.cyclicPos == this.cyclicSize) {
                this.cyclicPos = 0;
            }
        }

        return avail;
    }

    public getMatches(): Matches {
        this.matches.count = 0;
        let matchLenLimit: number = this.matchLenMax;
        let niceLenLimit: number = this.niceLen;
        let avail: number = this.movePoss();
        if (avail < matchLenLimit) {
            if (avail == 0) {
                return this.matches;
            }

            matchLenLimit = avail;
            if (niceLenLimit > avail) {
                niceLenLimit = avail;
            }
        }

        this.hash.calcHashes(this.buf, this.readPos);
        let delta2: number = this.lzPos - this.hash.getHash2Pos();
        let delta3: number = this.lzPos - this.hash.getHash3Pos();
        let currentMatch: number = this.hash.getHash4Pos();
        this.hash.updateTables(this.lzPos);
        this.chain[this.cyclicPos] = currentMatch;
        let lenBest: number = 0;
        if (delta2 < this.cyclicSize && this.buf[this.readPos - delta2] == this.buf[this.readPos]) {
            lenBest = 2;
            this.matches.len[0] = 2;
            this.matches.dist[0] = delta2 - 1;
            this.matches.count = 1;
        }

        if (delta2 != delta3 && delta3 < this.cyclicSize && this.buf[this.readPos - delta3] == this.buf[this.readPos]) {
            lenBest = 3;
            this.matches.dist[this.matches.count++] = delta3 - 1;
            delta2 = delta3;
        }

        if (this.matches.count > 0) {
            while (lenBest < matchLenLimit && this.buf[this.readPos + lenBest - delta2] == this.buf[this.readPos + lenBest]) {
                ++lenBest;
            }

            this.matches.len[this.matches.count - 1] = lenBest;
            if (lenBest >= niceLenLimit) {
                return this.matches;
            }
        }

        if (lenBest < 3) {
            lenBest = 3;
        }

        let depth: number = this.depthLimit;

        while (true) {
            let delta: number = this.lzPos - currentMatch;
            if (depth-- == 0 || delta >= this.cyclicSize) {
                return this.matches;
            }

            currentMatch = this.chain[this.cyclicPos - delta + (delta > this.cyclicPos ? this.cyclicSize : 0)];
            if (this.buf[this.readPos + lenBest - delta] == this.buf[this.readPos + lenBest] && this.buf[this.readPos - delta] == this.buf[this.readPos]) {
                let len: number = 0;

                do {
                    ++len;
                } while (len < matchLenLimit && this.buf[this.readPos + len - delta] == this.buf[this.readPos + len]);

                if (len > lenBest) {
                    lenBest = len;
                    this.matches.len[this.matches.count] = len;
                    this.matches.dist[this.matches.count] = delta - 1;
                    ++this.matches.count;
                    if (len >= niceLenLimit) {
                        return this.matches;
                    }
                }
            }
        }
    }

    public skip(len: number): void {
        len >= 0;

        while (len-- > 0) {
            if (this.movePoss() != 0) {
                this.hash.calcHashes(this.buf, this.readPos);
                this.chain[this.cyclicPos] = this.hash.getHash4Pos();
                this.hash.updateTables(this.lzPos);
            }
        }

    }
}

class BT4 extends LZEncoder {
    private hash: Hash234;
    private tree: Int32Array;
    private matches: Matches;
    private depthLimit: number;
    private cyclicSize: number;
    private cyclicPos: number = -1;
    private lzPos: number;

    static getMemoryUsage(dictSize: number): number {
        return Hash234.getMemoryUsage(dictSize) + dictSize / 128 + 10;
    }

    constructor(dictSize: number, beforeSizeMin: number, readAheadMax: number,
                niceLen: number, matchLenMax: number, depthLimit: number, arrayCache: ArrayCache) {
        super(dictSize, beforeSizeMin, readAheadMax, niceLen, matchLenMax, arrayCache);
        this.cyclicSize = dictSize + 1;
        this.lzPos = this.cyclicSize;
        this.hash = new Hash234(dictSize, arrayCache);
        this.tree = arrayCache.getIntArray(this.cyclicSize * 2, false);
        this.matches = new Matches(niceLen - 1);
        this.depthLimit = depthLimit > 0 ? depthLimit : 16 + niceLen / 2;
    }

    public putArraysToCache(arrayCache: ArrayCache): void {
        arrayCache.putArray(this.tree);
        this.hash.putArraysToCache(arrayCache);
        super.putArraysToCache(arrayCache);
    }

    private movePoss(): number {
        let avail: number = this.movePos(this.niceLen, 4);
        if (avail != 0) {
            if (++this.lzPos == 2147483647) {
                let normalizationOffset: number = 2147483647 - this.cyclicSize;
                this.hash.normalize(normalizationOffset);
                LZEncoder.normalize(this.tree, this.cyclicSize * 2, normalizationOffset);
                this.lzPos -= normalizationOffset;
            }

            if (++this.cyclicPos == this.cyclicSize) {
                this.cyclicPos = 0;
            }
        }

        return avail;
    }

    public getMatches(): Matches {
        this.matches.count = 0;
        let matchLenLimit: number = this.matchLenMax;
        let niceLenLimit: number = this.niceLen;
        let avail: number = this.movePoss();
        if (avail < matchLenLimit) {
            if (avail == 0) {
                return this.matches;
            }

            matchLenLimit = avail;
            if (niceLenLimit > avail) {
                niceLenLimit = avail;
            }
        }

        this.hash.calcHashes(this.buf, this.readPos);
        let delta2: number = this.lzPos - this.hash.getHash2Pos();
        let delta3: number = this.lzPos - this.hash.getHash3Pos();
        let currentMatch: number = this.hash.getHash4Pos();
        this.hash.updateTables(this.lzPos);
        let lenBest: number = 0;
        if (delta2 < this.cyclicSize && this.buf[this.readPos - delta2] == this.buf[this.readPos]) {
            lenBest = 2;
            this.matches.len[0] = 2;
            this.matches.dist[0] = delta2 - 1;
            this.matches.count = 1;
        }

        if (delta2 != delta3 && delta3 < this.cyclicSize && this.buf[this.readPos - delta3] == this.buf[this.readPos]) {
            lenBest = 3;
            this.matches.dist[this.matches.count++] = delta3 - 1;
            delta2 = delta3;
        }

        if (this.matches.count > 0) {
            while (lenBest < matchLenLimit && this.buf[this.readPos + lenBest - delta2] == this.buf[this.readPos + lenBest]) {
                ++lenBest;
            }

            this.matches.len[this.matches.count - 1] = lenBest;
            if (lenBest >= niceLenLimit) {
                this.skips(niceLenLimit, currentMatch);
                return this.matches;
            }
        }

        if (lenBest < 3) {
            lenBest = 3;
        }

        let depth: number = this.depthLimit;
        let ptr0: number = (this.cyclicPos << 1) + 1;
        let ptr1: number = this.cyclicPos << 1;
        let len0: number = 0;
        let len1: number = 0;

        while (true) {
            let delta: number = this.lzPos - currentMatch;
            if (depth-- == 0 || delta >= this.cyclicSize) {
                this.tree[ptr0] = 0;
                this.tree[ptr1] = 0;
                return this.matches;
            }

            let pair: number = this.cyclicPos - delta + (delta > this.cyclicPos ? this.cyclicSize : 0) << 1;
            let len: number = Math.min(len0, len1);
            if (this.buf[this.readPos + len - delta] == this.buf[this.readPos + len]) {
                do {
                    ++len;
                } while (len < matchLenLimit && this.buf[this.readPos + len - delta] == this.buf[this.readPos + len]);

                if (len > lenBest) {
                    lenBest = len;
                    this.matches.len[this.matches.count] = len;
                    this.matches.dist[this.matches.count] = delta - 1;
                    ++this.matches.count;
                    if (len >= niceLenLimit) {
                        this.tree[ptr1] = this.tree[pair];
                        this.tree[ptr0] = this.tree[pair + 1];
                        return this.matches;
                    }
                }
            }

            if ((this.buf[this.readPos + len - delta] & 255) < (this.buf[this.readPos + len] & 255)) {
                this.tree[ptr1] = currentMatch;
                ptr1 = pair + 1;
                currentMatch = this.tree[ptr1];
                len1 = len;
            } else {
                this.tree[ptr0] = currentMatch;
                ptr0 = pair;
                currentMatch = this.tree[pair];
                len0 = len;
            }
        }
    }

    private skips(niceLenLimit: number, currentMatch: number): void {
        let depth: number = this.depthLimit;
        let ptr0: number = (this.cyclicPos << 1) + 1;
        let ptr1: number = this.cyclicPos << 1;
        let len0: number = 0;
        let len1: number = 0;

        while (true) {
            let delta: number = this.lzPos - currentMatch;
            if (depth-- == 0 || delta >= this.cyclicSize) {
                this.tree[ptr0] = 0;
                this.tree[ptr1] = 0;
                return;
            }

            let pair: number = this.cyclicPos - delta + (delta > this.cyclicPos ? this.cyclicSize : 0) << 1;
            let len: number = Math.min(len0, len1);
            if (this.buf[this.readPos + len - delta] == this.buf[this.readPos + len]) {
                do {
                    ++len;
                    if (len == niceLenLimit) {
                        this.tree[ptr1] = this.tree[pair];
                        this.tree[ptr0] = this.tree[pair + 1];
                        return;
                    }
                } while (this.buf[this.readPos + len - delta] == this.buf[this.readPos + len]);
            }

            if ((this.buf[this.readPos + len - delta] & 255) < (this.buf[this.readPos + len] & 255)) {
                this.tree[ptr1] = currentMatch;
                ptr1 = pair + 1;
                currentMatch = this.tree[ptr1];
                len1 = len;
            } else {
                this.tree[ptr0] = currentMatch;
                ptr0 = pair;
                currentMatch = this.tree[ptr0];
                len0 = len;
            }
        }
    }

    public skip(len: number): void {
        while (len-- > 0) {
            let niceLenLimit: number = this.niceLen;
            let avail: number = this.movePoss();
            if (avail < niceLenLimit) {
                if (avail == 0) {
                    continue;
                }

                niceLenLimit = avail;
            }

            this.hash.calcHashes(this.buf, this.readPos);
            let currentMatch: number = this.hash.getHash4Pos();
            this.hash.updateTables(this.lzPos);
            this.skips(niceLenLimit, currentMatch);
        }

    }
}
