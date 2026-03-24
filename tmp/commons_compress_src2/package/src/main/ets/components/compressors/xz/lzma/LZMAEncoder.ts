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
import LZMACoder from './LZMACoder'
import StateClass from './StateClass'
import Optimum from './Optimum'
import RangeEncoder from '../rangecoder/RangeEncoder'
import LZEncoder from '../lz/LZEncoder'
import Matches from '../lz/Matches'
import ArrayCache from '../ArrayCache'
import Exception from '../../../util/Exception'
import System from '../../../util/System'
import LiteralCoder from './LiteralCoder'
import LengthCoder from './LengthCoder'
import LiteralSubcoder from './LiteralSubcoder'

export default abstract class LZMAEncoder extends LZMACoder {
    public static MODE_FAST: number = 1;
    public static MODE_NORMAL: number = 2;
    private static LZMA2_UNCOMPRESSED_LIMIT: number = (2 << 20) - LZMACoder.MATCH_LEN_MAX;
    private static LZMA2_COMPRESSED_LIMIT: number = (64 << 10) - 26;
    private static DIST_PRICE_UPDATE_INTERVAL: number = LZMACoder.FULL_DISTANCES;
    private static ALIGN_PRICE_UPDATE_INTERVAL: number = LZMACoder.ALIGN_SIZE;
    private rc: RangeEncoder;
    lz: LZEncoder;
    literalEncoder: LiteralEncoder;
    matchLenEncoder: LengthEncoder;
    repLenEncoder: LengthEncoder;
    niceLen: number;
    private distPriceCount: number = 0;
    private alignPriceCount: number = 0;
    private distSlotPricesSize: number = 0;
    private distSlotPrices: Array<Int32Array> = new Array<Int32Array>();
    private static fullDistPrices: Array<Int32Array> = new Array<Int32Array>(LZMAEncoder.DIST_STATES);
    private alignPrices: Int32Array = new Int32Array(LZMAEncoder.ALIGN_SIZE);

    static initfullDistPricesArray() {
        for (let i = 0;i < LZMAEncoder.fullDistPrices.length; i++) {
            LZMAEncoder.fullDistPrices[i] = new Int32Array(LZMACoder.FULL_DISTANCES);
        }
    }

    back: number = 0;
    readAhead: number = -1;
    private uncompressedSize: number = 0;

    public static getMemoryUsage(mode: number, dictSize: number,
                                 extraSizeBefore: number, mf: number): number {
        let m: number = 80;

        switch (mode) {
            case LZMAEncoder.MODE_FAST:
                m += LZMAEncoderFast.getMemoryUsage(
                    dictSize, extraSizeBefore, mf);
                break;

            case LZMAEncoder.MODE_NORMAL:
                m += LZMAEncoderNormal.getMemoryUsage(
                    dictSize, extraSizeBefore, mf);
                break;

            default:
                throw new Exception();
        }

        return m;
    }

    public static getInstance(
        rc: RangeEncoder, lc: number, lp: number, pb: number, mode: number,
        dictSize: number, extraSizeBefore: number,
        niceLen: number, mf: number, depthLimit: number,
        arrayCache: ArrayCache): LZMAEncoder {
        switch (mode) {
            case LZMAEncoder.MODE_FAST:
                return new LZMAEncoderFast(rc, lc, lp, pb,
                    dictSize, extraSizeBefore,
                    niceLen, mf, depthLimit,
                    arrayCache);

            case LZMAEncoder.MODE_NORMAL:
                return new LZMAEncoderNormal(rc, lc, lp, pb,
                    dictSize, extraSizeBefore,
                    niceLen, mf, depthLimit,
                    arrayCache);
        }

        throw new Exception();
    }

    public putArraysToCache(arrayCache: ArrayCache): void {
        this.lz.putArraysToCache(arrayCache);
    }

    public static getDistSlot(dist: number): number {
        if (dist <= LZMAEncoder.DIST_MODEL_START && dist >= 0)
        return dist;

        let n: number = dist;
        let i: number = 31;

        if ((n & 0xFFFF0000) == 0) {
            n <<= 16;
            i = 15;
        }

        if ((n & 0xFF000000) == 0) {
            n <<= 8;
            i -= 8;
        }

        if ((n & 0xF0000000) == 0) {
            n <<= 4;
            i -= 4;
        }

        if ((n & 0xC0000000) == 0) {
            n <<= 2;
            i -= 2;
        }

        if ((n & 0x80000000) == 0)
        --i;

        return (i << 1) + ((dist >>> (i - 1)) & 1);
    }

    abstract getNextSymbol(): number;

    constructor(rc: RangeEncoder, lz: LZEncoder,
                lc: number, lp: number, pb: number, dictSize: number, niceLen: number) {
        super(pb);
        this.rc = rc;
        this.lz = lz;
        this.niceLen = niceLen;

        this.literalEncoder = new LiteralEncoder(lc, lp, lz, rc, this);
        this.matchLenEncoder = new LengthEncoder(pb, niceLen, this.rc);
        this.repLenEncoder = new LengthEncoder(pb, niceLen, this.rc);

        this.distSlotPricesSize = LZMAEncoder.getDistSlot(dictSize - 1) + 1;
        this.distSlotPrices = new Array<Int32Array>(LZMACoder.DIST_STATES);
        this.distSlotPricesArray()

        this.reset();
    }

    distSlotPricesArray() {
        for (let i = 0;i < this.distSlotPrices.length; i++) {
            this.distSlotPrices[i] = new Int32Array(this.distSlotPricesSize);
        }
    }

    public getLZEncoder(): LZEncoder {
        return this.lz;
    }

    public reset(): void {
        super.reset();
        this.literalEncoder.reset();
        this.matchLenEncoder.reset();
        this.repLenEncoder.reset();
        this.distPriceCount = 0;
        this.alignPriceCount = 0;

        this.uncompressedSize += this.readAhead + 1;
        this.readAhead = -1;
    }

    public getUncompressedSize(): number {
        return this.uncompressedSize;
    }

    public resetUncompressedSize(): void {
        this.uncompressedSize = 0;
    }

    public encodeForLZMA1(): void {
        if (!this.lz.isStarted() && !this.encodeInit())
        return;
        while (this.encodeSymbol()) {
        }
    }

    public encodeLZMA1EndMarker(): void {
        let posState: number = (this.lz.getPos() - this.readAhead) & this.posMask;
        this.rc.encodeBit(this.isMatch[this.stateClass.get()], posState, 1);
        this.rc.encodeBit(this.isRep, this.stateClass.get(), 0);
        this.encodeMatch(-1, LZMAEncoder.MATCH_LEN_MIN, posState);
    }

    public encodeForLZMA2(): boolean {
        try {
            if (!this.lz.isStarted() && !this.encodeInit())
            return false;

            while (this.uncompressedSize <= LZMAEncoder.LZMA2_UNCOMPRESSED_LIMIT
            && this.rc.getPendingSize() <= LZMAEncoder.LZMA2_COMPRESSED_LIMIT)
            if (!this.encodeSymbol())
            return false;
        } catch (e) {
            throw new Error();
        }

        return true;
    }

    private encodeInit(): boolean{
        this.readAhead == -1;
        if (!this.lz.hasEnoughData(0))
        return false;
        this.skip(1);
        this.rc.encodeBit(this.isMatch[this.stateClass.get()], 0, 0);
        this.literalEncoder.encodeInit();

        --this.readAhead;
        this.readAhead == -1;

        ++this.uncompressedSize;
        this.uncompressedSize == 1;

        return true;
    }

    private encodeSymbol(): boolean {
        if (!this.lz.hasEnoughData(this.readAhead + 1))
        return false;

        let len: number = this.getNextSymbol();

        this.readAhead >= 0;
        let posState: number = (this.lz.getPos() - this.readAhead) & this.posMask;

        if (this.back == -1) {
            len == 1;
            this.rc.encodeBit(this.isMatch[this.stateClass.get()], posState, 0);
            this.literalEncoder.encode();
        } else {
            this.rc.encodeBit(this.isMatch[this.stateClass.get()], posState, 1);
            if (this.back < LZMAEncoder.REPS) {
                this.lz.getMatchLens(-this.readAhead, this.reps[this.back], len) == len;
                this.rc.encodeBit(this.isRep, this.stateClass.get(), 1);
                this.encodeRepMatch(this.back, len, posState);
            } else {
                // Normal match
                this.lz.getMatchLens(-this.readAhead, this.back - LZMAEncoder.REPS, len) == len;
                this.rc.encodeBit(this.isRep, this.stateClass.get(), 0);
                this.encodeMatch(this.back - LZMAEncoder.REPS, len, posState);
            }
        }

        this.readAhead -= len;
        this.uncompressedSize += len;

        return true;
    }

    private encodeMatch(dist: number, len: number, posState: number): void
    {
        this.stateClass.updateMatch();
        this.matchLenEncoder.encode(len, posState);

        let distSlot: number = LZMAEncoder.getDistSlot(dist);
        this.rc.encodeBitTree(this.distSlots[this.getDistState(len)], distSlot);

        if (distSlot >= LZMAEncoder.DIST_MODEL_START) {
            let footerBits: number = (distSlot >>> 1) - 1;
            let base: number = (2 | (distSlot & 1)) << footerBits;
            let distReduced: number = dist - base;

            if (distSlot < LZMAEncoder.DIST_MODEL_END) {
                this.rc.encodeReverseBitTree(
                    this.distSpecial[distSlot - LZMAEncoder.DIST_MODEL_START],
                    distReduced);
            } else {
                this.rc.encodeDirectBits(distReduced >>> LZMAEncoder.ALIGN_BITS,
                    footerBits - LZMAEncoder.ALIGN_BITS);
                this.rc.encodeReverseBitTree(this.distAlign, distReduced & LZMAEncoder.ALIGN_MASK);
                --this.alignPriceCount;
            }
        }

        this.reps[3] = this.reps[2];
        this.reps[2] = this.reps[1];
        this.reps[1] = this.reps[0];
        this.reps[0] = dist;

        --this.distPriceCount;
    }

    private encodeRepMatch(rep: number, len: number, posState: number): void
    {
        if (rep == 0) {
            this.rc.encodeBit(this.isRep0, this.stateClass.get(), 0);
            this.rc.encodeBit(this.isRep0Long[this.stateClass.get()], posState, len == 1 ? 0 : 1);
        } else {
            let dist: number = this.reps[rep];
            this.rc.encodeBit(this.isRep0, this.stateClass.get(), 1);

            if (rep == 1) {
                this.rc.encodeBit(this.isRep1, this.stateClass.get(), 0);
            } else {
                this.rc.encodeBit(this.isRep1, this.stateClass.get(), 1);
                this.rc.encodeBit(this.isRep2, this.stateClass.get(), rep - 2);

                if (rep == 3)
                this.reps[3] = this.reps[2];

                this.reps[2] = this.reps[1];
            }

            this.reps[1] = this.reps[0];
            this.reps[0] = dist;
        }

        if (len == 1) {
            this.stateClass.updateShortRep();
        } else {
            this.repLenEncoder.encode(len, posState);
            this.stateClass.updateLongRep();
        }
    }

    getMatches(): Matches {
        ++this.readAhead;
        let matches: Matches = this.lz.getMatches();
        this.lz.verifyMatches(matches);
        return matches;
    }

    skip(len: number): void {
        this.readAhead += len;
        this.lz.skip(len);
    }

    getAnyMatchPrice(stateClass: StateClass, posState: number): number {
        return RangeEncoder.getBitPrice(this.isMatch[stateClass.get()][posState], 1);
    }

    getNormalMatchPrice(anyMatchPrice: number, stateClass: StateClass): number {
        return anyMatchPrice
        + RangeEncoder.getBitPrice(this.isRep[stateClass.get()], 0);
    }

    getAnyRepPrice(anyMatchPrice: number, stateClass: StateClass): number {
        return anyMatchPrice
        + RangeEncoder.getBitPrice(this.isRep[stateClass.get()], 1);
    }

    getShortRepPrice(anyRepPrice: number, stateClass: StateClass, posState: number): number {
        return anyRepPrice
        + RangeEncoder.getBitPrice(this.isRep0[stateClass.get()], 0)
        + RangeEncoder.getBitPrice(this.isRep0Long[stateClass.get()][posState],
            0);
    }

    getLongRepPrice(anyRepPrice: number, rep: number, stateClass: StateClass, posState: number): number {
        let price: number = anyRepPrice;

        if (rep == 0) {
            price += RangeEncoder.getBitPrice(this.isRep0[stateClass.get()], 0)
            + RangeEncoder.getBitPrice(
                this.isRep0Long[this.stateClass.get()][posState], 1);
        } else {
            price += RangeEncoder.getBitPrice(this.isRep0[stateClass.get()], 1);

            if (rep == 1)
            price += RangeEncoder.getBitPrice(this.isRep1[stateClass.get()], 0);
            else
            price += RangeEncoder.getBitPrice(this.isRep1[stateClass.get()], 1)
            + RangeEncoder.getBitPrice(this.isRep2[stateClass.get()],
                rep - 2);
        }

        return price;
    }

    getLongRepAndLenPrice(rep: number, len: number, stateClass: StateClass, posState: number): number {
        let anyMatchPrice: number = this.getAnyMatchPrice(stateClass, posState);
        let anyRepPrice: number = this.getAnyRepPrice(anyMatchPrice, stateClass);
        let longRepPrice: number = this.getLongRepPrice(anyRepPrice, rep, stateClass, posState);
        return longRepPrice + this.repLenEncoder.getPrice(len, posState);
    }

    getMatchAndLenPrice(normalMatchPrice: number,
                        dist: number, len: number, posState: number): number {
        let price: number = normalMatchPrice
        + this.matchLenEncoder.getPrice(len, posState);
        let distState: number = this.getDistState(len);

        if (dist < LZMAEncoder.FULL_DISTANCES) {
            price += LZMAEncoder.fullDistPrices[distState][dist];
        } else {
            let distSlot: number = LZMAEncoder.getDistSlot(dist);
            price += this.distSlotPrices[distState][distSlot]
            + this.alignPrices[dist & LZMAEncoder.ALIGN_MASK];
        }

        return price;
    }

    private updateDistPrices(): void {
        this.distPriceCount = LZMAEncoder.DIST_PRICE_UPDATE_INTERVAL;

        for (let distState: number = 0; distState < LZMAEncoder.DIST_STATES; ++distState) {
            for (let distSlot = 0; distSlot < this.distSlotPricesSize; ++distSlot)
            this.distSlotPrices[distState][distSlot]
            = RangeEncoder.getBitTreePrice(
                this.distSlots[distState], distSlot);

            for (let distSlot: number = LZMAEncoder.DIST_MODEL_END; distSlot < this.distSlotPricesSize;
                 ++distSlot) {
                let count: number = (distSlot >>> 1) - 1 - LZMAEncoder.ALIGN_BITS;
                this.distSlotPrices[distState][distSlot]
                += RangeEncoder.getDirectBitsPrice(count);
            }

            for (let dist: number = 0; dist < LZMAEncoder.DIST_MODEL_START; ++dist)
            LZMAEncoder.fullDistPrices[distState][dist]
            = this.distSlotPrices[distState][dist];
        }

        let dist: number = LZMAEncoder.DIST_MODEL_START;
        for (let distSlot = LZMAEncoder.DIST_MODEL_START; distSlot < LZMAEncoder.DIST_MODEL_END;
             ++distSlot) {
            let footerBits: number = (distSlot >>> 1) - 1;
            let base: number = (2 | (distSlot & 1)) << footerBits;

            let limit: number = this.distSpecial[distSlot - LZMAEncoder.DIST_MODEL_START].length;
            for (let i = 0; i < limit; ++i) {
                let distReduced: number = dist - base;
                let price: number = RangeEncoder.getReverseBitTreePrice(
                    this.distSpecial[distSlot - LZMAEncoder.DIST_MODEL_START],
                    distReduced);

                for (let distState = 0; distState < LZMAEncoder.DIST_STATES; ++distState)
                LZMAEncoder.fullDistPrices[distState][dist]
                = this.distSlotPrices[distState][distSlot] + price;

                ++dist;
            }
        }

        dist == LZMAEncoder.FULL_DISTANCES;
    }

    private updateAlignPrices(): void {
        this.alignPriceCount = LZMAEncoder.ALIGN_PRICE_UPDATE_INTERVAL;

        for (let i = 0; i < LZMAEncoder.ALIGN_SIZE; ++i)
        this.alignPrices[i] = RangeEncoder.getReverseBitTreePrice(this.distAlign,
            i);
    }

    updatePrices(): void {
        if (this.distPriceCount <= 0)
        this.updateDistPrices();

        if (this.alignPriceCount <= 0)
        this.updateAlignPrices();

        this.matchLenEncoder.updatePrices();
        this.repLenEncoder.updatePrices();
    }
}

LZMAEncoder.initfullDistPricesArray()

class LiteralEncoder extends LiteralCoder {
    private subencoders: Array<LiteralSubencoder>;
    private lzma: LZMAEncoder;
    private lz: LZEncoder;

    constructor(lc: number, lp: number, lz: LZEncoder, rc: RangeEncoder, lzma: LZMAEncoder) {
        super(lc, lp);

        this.subencoders = new Array<LiteralSubencoder>(1 << (lc + lp));
        this.lz = lz;
        this.lzma = lzma;
        for (let i = 0; i < this.subencoders.length; ++i) {
            this.subencoders[i] = new LiteralSubencoder(lz, rc, lzma)
        }
    }

    reset(): void {
        for (let i = 0; i < this.subencoders.length; ++i)
        this.subencoders[i].reset();
    }

    encodeInit(): void {
        this.lzma.readAhead >= 0;
        this.subencoders[0].encode();
    }

    encode(): void{
        this.lzma.readAhead >= 0;
        let i: number = this.getSubcoderIndex(this.lz.getByte(1 + this.lzma.readAhead),
            this.lz.getPos() - this.lzma.readAhead);
        this.subencoders[i].encode();
    }

    getPrice(curByte: number, matchByte: number,
             prevByte: number, pos: number, state: StateClass): number {
        let price: number = RangeEncoder.getBitPrice(
            this.lzma.isMatch[state.get()][pos & this.lzma.posMask], 0);

        let i: number = this.getSubcoderIndex(prevByte, pos);
        price += state.isLiteral()
            ? this.subencoders[i].getNormalPrice(curByte)
            : this.subencoders[i].getMatchedPrice(curByte, matchByte);

        return price;
    }
}

class LiteralSubencoder extends LiteralSubcoder {
    private lzma: LZMAEncoder;
    private lz: LZEncoder;
    private rc: RangeEncoder;

    constructor(lz: LZEncoder, rc: RangeEncoder, lzma: LZMAEncoder) {
        super()
        this.lz = lz;
        this.rc = rc;
        this.lzma = lzma;
    }

    encode(): void{
        let symbolnum: number = this.lz.getByte(this.lzma.readAhead) | 0x100;

        if (this.lzma.stateClass.isLiteral()) {
            let subencoderIndex: number;
            let bit: number;

            do {
                subencoderIndex = symbolnum >>> 8;
                bit = (symbolnum >>> 7) & 1;
                this.rc.encodeBit(this.probs, subencoderIndex, bit);
                symbolnum <<= 1;
            } while (symbolnum < 0x10000);

        } else {
            let matchByte: number = this.lz.getByte(this.lzma.reps[0] + 1 + this.lzma.readAhead);
            let offset: number = 0x100;
            let subencoderIndex: number;
            let matchBit: number;
            let bit: number;

            do {
                matchByte <<= 1;
                matchBit = matchByte & offset;
                subencoderIndex = offset + matchBit + (symbolnum >>> 8);
                bit = (symbolnum >>> 7) & 1;
                this.rc.encodeBit(this.probs, subencoderIndex, bit);
                symbolnum <<= 1;
                offset &= ~(matchByte ^ symbolnum);
            } while (symbolnum < 0x10000);
        }

        this.lzma.stateClass.updateLiteral();
    }

    getNormalPrice(symbolnum: number): number {
        let price: number = 0;
        let subencoderIndex: number;
        let bit: number;

        symbolnum |= 0x100;

        do {
            subencoderIndex = symbolnum >>> 8;
            bit = (symbolnum >>> 7) & 1;
            price += RangeEncoder.getBitPrice(this.probs[subencoderIndex],
                bit);
            symbolnum <<= 1;
        } while (symbolnum < (0x100 << 8));

        return price;
    }

    getMatchedPrice(symbolnum: number, matchByte: number): number{
        let price: number = 0;
        let offset: number = 0x100;
        let subencoderIndex: number;
        let matchBit: number;
        let bit: number;

        symbolnum |= 0x100;

        do {
            matchByte <<= 1;
            matchBit = matchByte & offset;
            subencoderIndex = offset + matchBit + (symbolnum >>> 8);
            bit = (symbolnum >>> 7) & 1;
            price += RangeEncoder.getBitPrice(this.probs[subencoderIndex],
                bit);
            symbolnum <<= 1;
            offset &= ~(matchByte ^ symbolnum);
        } while (symbolnum < (0x100 << 8));

        return price;
    }
}

class LengthEncoder extends LengthCoder {
    private static PRICE_UPDATE_INTERVAL: number = 32;
    private rc: RangeEncoder;
    private counters: Int32Array = new Int32Array(0);
    private prices: Array<Int32Array> = new Array<Int32Array>();

    initpricesArray() {
        for (let i = 0;i < this.prices.length; i++) {
            this.prices[i] = new Int32Array(0);
        }
    }

    constructor(pb: number, niceLen: number, rc: RangeEncoder) {
        super()
        this.initpricesArray()
        let posStates: number = 1 << pb;
        this.counters = new Int32Array(posStates);
        this.rc = rc

        let lenSymbols: number = Math.max(niceLen - LZMACoder.MATCH_LEN_MIN + 1,
            LengthCoder.LOW_SYMBOLS + LengthCoder.MID_SYMBOLS);
        this.prices = new Array<Int32Array>(posStates);
        this.pricesArray(lenSymbols)
    }

    pricesArray(lenSymbols) {
        for (let i = 0;i < this.prices.length; i++) {
            this.prices[i] = new Int32Array(lenSymbols);
        }
    }

    reset(): void {
        super.reset();
        for (let i: number = 0; i < this.counters.length; ++i)
        this.counters[i] = 0;
    }

    encode(len, posState: number): void{
        len -= LZMACoder.MATCH_LEN_MIN;

        if (len < LengthCoder.LOW_SYMBOLS) {
            this.rc.encodeBit(this.choice, 0, 0);
            this.rc.encodeBitTree(this.low[posState], len);
        } else {
            this.rc.encodeBit(this.choice, 0, 1);
            len -= LengthCoder.LOW_SYMBOLS;

            if (len < LengthCoder.MID_SYMBOLS) {
                this.rc.encodeBit(this.choice, 1, 0);
                this.rc.encodeBitTree(this.mid[posState], len);
            } else {
                this.rc.encodeBit(this.choice, 1, 1);
                this.rc.encodeBitTree(this.high, len - LengthCoder.MID_SYMBOLS);
            }
        }

        --this.counters[posState];
    }

    getPrice(len: number, posState: number): number {
        return this.prices[posState][len - LZMACoder.MATCH_LEN_MIN];
    }

    updatePrices(): void {
        for (let posState: number = 0; posState < this.counters.length; ++posState) {
            if (this.counters[posState] <= 0) {
                this.counters[posState] = LengthEncoder.PRICE_UPDATE_INTERVAL;
                this.updatePricesPos(posState);
            }
        }
    }

    private updatePricesPos(posState: number): void {
        let choice0Price: number = RangeEncoder.getBitPrice(this.choice[0], 0);

        let i: number = 0;
        for (; i < LengthCoder.LOW_SYMBOLS; ++i)
        this.prices[posState][i] = choice0Price
        + RangeEncoder.getBitTreePrice(this.low[posState], i);

        choice0Price = RangeEncoder.getBitPrice(this.choice[0], 1);
        let choice1Price: number = RangeEncoder.getBitPrice(this.choice[1], 0);

        for (; i < LengthCoder.LOW_SYMBOLS + LengthCoder.MID_SYMBOLS; ++i)
        this.prices[posState][i] = choice0Price + choice1Price
        + RangeEncoder.getBitTreePrice(this.mid[posState],
            i - LengthCoder.LOW_SYMBOLS);

        choice1Price = RangeEncoder.getBitPrice(this.choice[1], 1);

        for (; i < this.prices[posState].length; ++i)
        this.prices[posState][i] = choice0Price + choice1Price
        + RangeEncoder.getBitTreePrice(this.high, i - LengthCoder.LOW_SYMBOLS
        - LengthCoder.MID_SYMBOLS);
    }
}

class LZMAEncoderFast extends LZMAEncoder {
    private static EXTRA_SIZE_BEFORE: number = 1;
    private static EXTRA_SIZE_AFTER: number = 272;
    private matches: Matches = null;

    static getMemoryUsage(dictSize: number, extraSizeBefore: number, mf: number): number {
        return LZEncoder.getMemoryUsage(dictSize, Math.max(extraSizeBefore, 1), 272, 273, mf);
    }

    constructor(rc: RangeEncoder, lc: number, lp: number, pb: number, dictSize: number, extraSizeBefore: number, niceLen: number, mf: number, depthLimit: number, arrayCache: ArrayCache) {
        super(rc, LZEncoder.getInstance(dictSize, Math.max(extraSizeBefore, 1), 272, niceLen, 273, mf, depthLimit, arrayCache), lc, lp, pb, dictSize, niceLen);
    }

    private changePair(smallDist: number, bigDist: number): boolean {
        return smallDist < (bigDist >>> 7);
    }

    getNextSymbol(): number {
        if (this.readAhead == -1) {
            this.matches = this.getMatches();
        }

        this.back = -1;
        let avail: number = Math.min(this.lz.getAvail(), 273);
        if (avail < 2) {
            return 1;
        } else {
            let bestRepLen: number = 0;
            let bestRepIndex: number = 0;

            let rep: number;
            let len: number;
            for (rep = 0; rep < 4; ++rep) {
                len = this.lz.getMatchLen(this.reps[rep], avail);
                if (len >= 2) {
                    if (len >= this.niceLen) {
                        this.back = rep;
                        this.skip(len - 1);
                        return len;
                    }

                    if (len > bestRepLen) {
                        bestRepIndex = rep;
                        bestRepLen = len;
                    }
                }
            }

            let mainLen: number = 0;
            let mainDist: number = 0;
            if (this.matches.count > 0) {
                mainLen = this.matches.len[this.matches.count - 1];
                mainDist = this.matches.dist[this.matches.count - 1];
                if (mainLen >= this.niceLen) {
                    this.back = mainDist + 4;
                    this.skip(mainLen - 1);
                    return mainLen;
                }

                while (this.matches.count > 1 && mainLen == this.matches.len[this.matches.count - 2] + 1 && this.changePair(this.matches.dist[this.matches.count - 2], mainDist)) {
                    --this.matches.count;
                    mainLen = this.matches.len[this.matches.count - 1];
                    mainDist = this.matches.dist[this.matches.count - 1];
                }

                if (mainLen == 2 && mainDist >= 128) {
                    mainLen = 1;
                }
            }

            if (bestRepLen >= 2 && (bestRepLen + 1 >= mainLen || bestRepLen + 2 >= mainLen && mainDist >= 512 || bestRepLen + 3 >= mainLen && mainDist >= 32768)) {
                this.back = bestRepIndex;
                this.skip(bestRepLen - 1);
                return bestRepLen;
            } else if (mainLen >= 2 && avail > 2) {
                this.matches = this.getMatches();
                let newLen: number;
                let newDist: number;
                if (this.matches.count > 0) {
                    newLen = this.matches.len[this.matches.count - 1];
                    newDist = this.matches.dist[this.matches.count - 1];
                    if (newLen >= mainLen && newDist < mainDist || newLen == mainLen + 1 && !this.changePair(mainDist, newDist) || newLen > mainLen + 1 || newLen + 1 >= mainLen && mainLen >= 3 && this.changePair(newDist, mainDist)) {
                        return 1;
                    }
                }

                let limit = Math.max(mainLen - 1, 2);

                for (let rep = 0; rep < 4; ++rep) {
                    if (this.lz.getMatchLen(this.reps[rep], limit) == limit) {
                        return 1;
                    }
                }

                this.back = mainDist + 4;
                this.skip(mainLen - 2);
                return mainLen;
            } else {
                return 1;
            }
        }
    }
}

class LZMAEncoderNormal extends LZMAEncoder {
    private static OPTS: number = 4096;
    private static EXTRA_SIZE_BEFORE: number = LZMAEncoderNormal.OPTS;
    private static EXTRA_SIZE_AFTER: number = LZMAEncoderNormal.OPTS;
    private opts: Optimum[] = new Array<Optimum>(LZMAEncoderNormal.OPTS);
    private optCur: number = 0;
    private optEnd: number = 0;
    private matches: Matches;
    private repLens: Int32Array = new Int32Array(LZMAEncoderNormal.REPS);
    private nextState: StateClass = new StateClass();

    static getMemoryUsage(dictSize: number, extraSizeBefore: number, mf: number): number {
        return LZEncoder.getMemoryUsage(dictSize,
        Math.max(extraSizeBefore, LZMAEncoderNormal.EXTRA_SIZE_BEFORE),
            LZMAEncoderNormal.EXTRA_SIZE_AFTER, LZMAEncoderNormal.MATCH_LEN_MAX, mf)
        + LZMAEncoderNormal.OPTS * 64 / 1024;
    }

    constructor(rc: RangeEncoder, lc: number, lp: number, pb: number,
                dictSize: number, extraSizeBefore: number,
                niceLen: number, mf: number, depthLimit: number,
                arrayCache: ArrayCache) {
        super(rc, LZEncoder.getInstance(dictSize,
        Math.max(extraSizeBefore,
            LZMAEncoderNormal.EXTRA_SIZE_BEFORE),
            LZMAEncoderNormal.EXTRA_SIZE_AFTER,
            niceLen, LZMAEncoderNormal.MATCH_LEN_MAX,
            mf, depthLimit, arrayCache),
            lc, lp, pb, dictSize, niceLen);

        for (let i = 0; i < LZMAEncoderNormal.OPTS; ++i)
        this.opts[i] = new Optimum();
    }

    public reset(): void {
        this.optCur = 0;
        this.optEnd = 0;
        super.reset();
    }

    private convertOpts(): number {
        this.optEnd = this.optCur;

        let optPrev: number = this.opts[this.optCur].optPrev;

        do {
            let opt: Optimum = this.opts[this.optCur];

            if (opt.prev1IsLiteral) {
                this.opts[optPrev].optPrev = this.optCur;
                this.opts[optPrev].backPrev = -1;
                this.optCur = optPrev--;

                if (opt.hasPrev2) {
                    this.opts[optPrev].optPrev = optPrev + 1;
                    this.opts[optPrev].backPrev = opt.backPrev2;
                    this.optCur = optPrev;
                    optPrev = opt.optPrev2;
                }
            }

            let temp = this.opts[optPrev].optPrev;
            this.opts[optPrev].optPrev = this.optCur;
            this.optCur = optPrev;
            optPrev = temp;
        } while (this.optCur > 0);

        this.optCur = this.opts[0].optPrev;
        this.back = this.opts[this.optCur].backPrev;
        return this.optCur;
    }

    getNextSymbol(): number {
        if (this.optCur < this.optEnd) {
            let len: number = this.opts[this.optCur].optPrev - this.optCur;
            this.optCur = this.opts[this.optCur].optPrev;
            this.back = this.opts[this.optCur].backPrev;
            return len;
        }

        this.optCur == this.optEnd;
        this.optCur = 0;
        this.optEnd = 0;
        this.back = -1;

        if (this.readAhead == -1)
        this.matches = this.getMatches();

        let avail: number = Math.min(this.lz.getAvail(), LZMAEncoderNormal.MATCH_LEN_MAX);
        if (avail < LZMAEncoderNormal.MATCH_LEN_MIN)
        return 1;

        let repBest: number = 0;
        for (let rep: number = 0; rep < LZMAEncoderNormal.REPS; ++rep) {
            this.repLens[rep] = this.lz.getMatchLen(this.reps[rep], avail);

            if (this.repLens[rep] < LZMAEncoderNormal.MATCH_LEN_MIN) {
                this.repLens[rep] = 0;
                continue;
            }

            if (this.repLens[rep] > this.repLens[repBest])
            repBest = rep;
        }

        if (this.repLens[repBest] >= this.niceLen) {
            this.back = repBest;
            this.skip(this.repLens[repBest] - 1);
            return this.repLens[repBest];
        }

        let mainLen: number = 0;
        let mainDist: number = 0;
        if (this.matches.count > 0) {
            mainLen = this.matches.len[this.matches.count - 1];
            mainDist = this.matches.dist[this.matches.count - 1];

            if (mainLen >= this.niceLen) {
                this.back = mainDist + LZMAEncoderNormal.REPS;
                this.skip(mainLen - 1);
                return mainLen;
            }
        }

        let curByte: number = this.lz.getByte(0);
        let matchByte: number = this.lz.getByte(this.reps[0] + 1);

        if (mainLen < LZMAEncoderNormal.MATCH_LEN_MIN && curByte != matchByte
        && this.repLens[repBest] < LZMAEncoderNormal.MATCH_LEN_MIN)
        return 1;


        let pos: number = this.lz.getPos();
        let posState: number = pos & this.posMask;

        {
            let prevByte: number = this.lz.getByte(1);
            let literalPrice: number = this.literalEncoder.getPrice(curByte, matchByte,
                prevByte, pos, this.stateClass);
            this.opts[1].set1(literalPrice, 0, -1);
        }

        let anyMatchPrice: number = this.getAnyMatchPrice(this.stateClass, posState);
        let anyRepPrice: number = this.getAnyRepPrice(anyMatchPrice, this.stateClass);

        if (matchByte == curByte) {
            let shortRepPrice: number = this.getShortRepPrice(anyRepPrice,
                this.stateClass, posState);
            if (shortRepPrice < this.opts[1].price)
            this.opts[1].set1(shortRepPrice, 0, 0);
        }

        this.optEnd = Math.max(mainLen, this.repLens[repBest]);
        if (this.optEnd < LZMAEncoderNormal.MATCH_LEN_MIN) {
            this.back = this.opts[1].backPrev;
            return 1;
        }

        this.updatePrices();
        this.opts[0].state.set(this.stateClass);
        System.arraycopy(this.reps, 0, this.opts[0].reps, 0, LZMAEncoderNormal.REPS);
        for (let i = this.optEnd; i >= LZMAEncoderNormal.MATCH_LEN_MIN; --i)
        this.opts[i].reset();
        for (let rep: number = 0; rep < LZMAEncoderNormal.REPS; ++rep) {
            let repLen: number = this.repLens[rep];
            if (repLen < LZMAEncoderNormal.MATCH_LEN_MIN)
            continue;

            let longRepPrice: number = this.getLongRepPrice(anyRepPrice, rep,
                this.stateClass, posState);
            do {
                let price: number = longRepPrice + this.repLenEncoder.getPrice(repLen,
                    posState);
                if (price < this.opts[repLen].price)
                this.opts[repLen].set1(price, 0, rep);
            } while (--repLen >= LZMAEncoderNormal.MATCH_LEN_MIN);
        }
        {
            let len: number = Math.max(this.repLens[0] + 1, LZMAEncoderNormal.MATCH_LEN_MIN);
            if (len <= mainLen) {
                let normalMatchPrice: number = this.getNormalMatchPrice(anyMatchPrice,
                    this.stateClass);
                let i: number = 0;
                while (len > this.matches.len[i])
                ++i;

                while (true) {
                    let dist: number = this.matches.dist[i];
                    let price: number = this.getMatchAndLenPrice(normalMatchPrice,
                        dist, len, posState);
                    if (price < this.opts[len].price)
                    this.opts[len].set1(price, 0, dist + LZMAEncoderNormal.REPS);

                    if (len == this.matches.len[i])
                    if (++i == this.matches.count)
                    break;

                    ++len;
                }
            }
        }


        avail = Math.min(this.lz.getAvail(), LZMAEncoderNormal.OPTS - 1);

        while (++this.optCur < this.optEnd) {
            this.matches = this.getMatches();
            if (this.matches.count > 0
            && this.matches.len[this.matches.count - 1] >= this.niceLen)
            break;

            --avail;
            ++pos;
            posState = pos & this.posMask;

            this.updateOptStateAndReps();
            anyMatchPrice = this.opts[this.optCur].price
            + this.getAnyMatchPrice(this.opts[this.optCur].state, posState);
            anyRepPrice = this.getAnyRepPrice(anyMatchPrice, this.opts[this.optCur].state);

            this.calc1BytePrices(pos, posState, avail, anyRepPrice);

            if (avail >= LZMAEncoderNormal.MATCH_LEN_MIN) {
                let startLen: number = this.calcLongRepPrices(pos, posState,
                    avail, anyRepPrice);
                if (this.matches.count > 0)
                this.calcNormalMatchPrices(pos, posState, avail,
                    anyMatchPrice, startLen);
            }
        }

        return this.convertOpts();
    }

    private updateOptStateAndReps(): void {
        let optPrev: number = this.opts[this.optCur].optPrev;
        optPrev < this.optCur;

        if (this.opts[this.optCur].prev1IsLiteral) {
            --optPrev;

            if (this.opts[this.optCur].hasPrev2) {
                this.opts[this.optCur].state.set(this.opts[this.opts[this.optCur].optPrev2].state);
                if (this.opts[this.optCur].backPrev2 < LZMAEncoderNormal.REPS)
                this.opts[this.optCur].state.updateLongRep();
                else
                this.opts[this.optCur].state.updateMatch();
            } else {
                this.opts[this.optCur].state.set(this.opts[optPrev].state);
            }

            this.opts[this.optCur].state.updateLiteral();
        } else {
            this.opts[this.optCur].state.set(this.opts[optPrev].state);
        }

        if (optPrev == this.optCur - 1) {
            this.opts[this.optCur].backPrev == 0 || this.opts[this.optCur].backPrev == -1;

            if (this.opts[this.optCur].backPrev == 0)
            this.opts[this.optCur].state.updateShortRep();
            else
            this.opts[this.optCur].state.updateLiteral();

            System.arraycopy(this.opts[optPrev].reps, 0,
                this.opts[this.optCur].reps, 0, LZMAEncoderNormal.REPS);
        } else {
            let back: number;
            if (this.opts[this.optCur].prev1IsLiteral && this.opts[this.optCur].hasPrev2) {
                optPrev = this.opts[this.optCur].optPrev2;
                back = this.opts[this.optCur].backPrev2;
                this.opts[this.optCur].state.updateLongRep();
            } else {
                back = this.opts[this.optCur].backPrev;
                if (back < LZMAEncoderNormal.REPS)
                this.opts[this.optCur].state.updateLongRep();
                else
                this.opts[this.optCur].state.updateMatch();
            }

            if (back < LZMAEncoderNormal.REPS) {
                this.opts[this.optCur].reps[0] = this.opts[optPrev].reps[back];

                let rep: number;
                for (rep = 1; rep <= back; ++rep)
                this.opts[this.optCur].reps[rep] = this.opts[optPrev].reps[rep - 1];

                for (; rep < LZMAEncoderNormal.REPS; ++rep)
                this.opts[this.optCur].reps[rep] = this.opts[optPrev].reps[rep];
            } else {
                this.opts[this.optCur].reps[0] = back - LZMAEncoderNormal.REPS;
                System.arraycopy(this.opts[optPrev].reps, 0,
                    this.opts[this.optCur].reps, 1, LZMAEncoderNormal.REPS - 1);
            }
        }
    }

    private calc1BytePrices(pos: number, posState: number,
                            avail: number, anyRepPrice: number): void {
        let nextIsByte: boolean = false;

        let curByte: number = this.lz.getByte(0);
        let matchByte: number = this.lz.getByte(this.opts[this.optCur].reps[0] + 1);

        let literalPrice: number = this.opts[this.optCur].price
        + this.literalEncoder.getPrice(curByte, matchByte, this.lz.getByte(1),
            pos, this.opts[this.optCur].state);
        if (literalPrice < this.opts[this.optCur + 1].price) {
            this.opts[this.optCur + 1].set1(literalPrice, this.optCur, -1);
            nextIsByte = true;
        }

        if (matchByte == curByte && (this.opts[this.optCur + 1].optPrev == this.optCur
        || this.opts[this.optCur + 1].backPrev != 0)) {
            let shortRepPrice: number = this.getShortRepPrice(anyRepPrice,
                this.opts[this.optCur].state,
                posState);
            if (shortRepPrice <= this.opts[this.optCur + 1].price) {
                this.opts[this.optCur + 1].set1(shortRepPrice, this.optCur, 0);
                nextIsByte = true;
            }
        }


        if (!nextIsByte && matchByte != curByte && avail > LZMAEncoderNormal.MATCH_LEN_MIN) {
            let lenLimit: number = Math.min(this.niceLen, avail - 1);
            let len: number = this.lz.getMatchLens(1, this.opts[this.optCur].reps[0], lenLimit);

            if (len >= LZMAEncoderNormal.MATCH_LEN_MIN) {
                this.nextState.set(this.opts[this.optCur].state);
                this.nextState.updateLiteral();
                let nextPosState: number = (pos + 1) & this.posMask;
                let price: number = literalPrice
                + this.getLongRepAndLenPrice(0, len,
                    this.nextState, nextPosState);

                let i: number = this.optCur + 1 + len;
                while (this.optEnd < i)
                this.opts[++this.optEnd].reset();

                if (price < this.opts[i].price)
                this.opts[i].set2(price, this.optCur, 0);
            }
        }
    }

    private calcLongRepPrices(pos: number, posState: number,
                              avail: number, anyRepPrice: number): number {
        let startLen: number = LZMAEncoderNormal.MATCH_LEN_MIN;
        let lenLimit: number = Math.min(avail, this.niceLen);

        for (let rep: number = 0; rep < LZMAEncoderNormal.REPS; ++rep) {
            let len: number = this.lz.getMatchLen(this.opts[this.optCur].reps[rep], lenLimit);
            if (len < LZMAEncoderNormal.MATCH_LEN_MIN)
            continue;

            while (this.optEnd < this.optCur + len)
            this.opts[++this.optEnd].reset();

            let longRepPrice: number = this.getLongRepPrice(anyRepPrice, rep,
                this.opts[this.optCur].state, posState);

            for (let i = len; i >= LZMAEncoderNormal.MATCH_LEN_MIN; --i) {
                let price: number = longRepPrice
                + this.repLenEncoder.getPrice(i, posState);
                if (price < this.opts[this.optCur + i].price)
                this.opts[this.optCur + i].set1(price, this.optCur, rep);
            }

            if (rep == 0)
            startLen = len + 1;

            let len2Limit: number = Math.min(this.niceLen, avail - len - 1);
            let len2: number = this.lz.getMatchLens(len + 1, this.opts[this.optCur].reps[rep],
                len2Limit);

            if (len2 >= LZMAEncoderNormal.MATCH_LEN_MIN) {
                // Rep
                let price: number = longRepPrice
                + this.repLenEncoder.getPrice(len, posState);
                this.nextState.set(this.opts[this.optCur].state);
                this.nextState.updateLongRep();

                // Literal
                let curByte: number = this.lz.getBytebuf(len, 0);
                let matchByte: number = this.lz.getByte(0); // lz.getByte(len, len)
                let prevByte: number = this.lz.getBytebuf(len, 1);
                price += this.literalEncoder.getPrice(curByte, matchByte, prevByte,
                    pos + len, this.nextState);
                this.nextState.updateLiteral();

                // Rep0
                let nextPosState: number = (pos + len + 1) & this.posMask;
                price += this.getLongRepAndLenPrice(0, len2,
                    this.nextState, nextPosState);

                let i: number = this.optCur + len + 1 + len2;
                while (this.optEnd < i)
                this.opts[++this.optEnd].reset();

                if (price < this.opts[i].price)
                this.opts[i].set3(price, this.optCur, rep, len, 0);
            }
        }

        return startLen;
    }

    private calcNormalMatchPrices(pos: number, posState: number, avail: number,
                                  anyMatchPrice: number, startLen: number): void {
        if (this.matches.len[this.matches.count - 1] > avail) {
            this.matches.count = 0;
            while (this.matches.len[this.matches.count] < avail)
            ++this.matches.count;

            this.matches.len[this.matches.count++] = avail;
        }

        if (this.matches.len[this.matches.count - 1] < startLen)
        return;

        while (this.optEnd < this.optCur + this.matches.len[this.matches.count - 1])
        this.opts[++this.optEnd].reset();

        let normalMatchPrice: number = this.getNormalMatchPrice(anyMatchPrice,
            this.opts[this.optCur].state);

        let match: number = 0;
        while (startLen > this.matches.len[match])
        ++match;

        for (let len: number = startLen;; ++len) {
            let dist: number = this.matches.dist[match];

            let matchAndLenPrice: number = this.getMatchAndLenPrice(normalMatchPrice,
                dist, len, posState);
            if (matchAndLenPrice < this.opts[this.optCur + len].price)
            this.opts[this.optCur + len].set1(matchAndLenPrice,
                this.optCur, dist + LZMAEncoderNormal.REPS);

            if (len != this.matches.len[match])
            continue;

            let len2Limit: number = Math.min(this.niceLen, avail - len - 1);
            let len2: number = this.lz.getMatchLens(len + 1, dist, len2Limit);

            if (len2 >= LZMAEncoderNormal.MATCH_LEN_MIN) {
                this.nextState.set(this.opts[this.optCur].state);
                this.nextState.updateMatch();

                let curByte: number = this.lz.getBytebuf(len, 0);
                let matchByte: number = this.lz.getByte(0); // lz.getByte(len, len)
                let prevByte: number = this.lz.getBytebuf(len, 1);
                let price: number = matchAndLenPrice
                + this.literalEncoder.getPrice(curByte, matchByte,
                    prevByte, pos + len,
                    this.nextState);
                this.nextState.updateLiteral();

                let nextPosState: number = (pos + len + 1) & this.posMask;
                price += this.getLongRepAndLenPrice(0, len2,
                    this.nextState, nextPosState);

                let i: number = this.optCur + len + 1 + len2;
                while (this.optEnd < i)
                this.opts[++this.optEnd].reset();

                if (price < this.opts[i].price)
                this.opts[i].set3(price, this.optCur, dist + LZMAEncoderNormal.REPS, len, 0);
            }

            if (++match == this.matches.count)
            break;
        }
    }
}
