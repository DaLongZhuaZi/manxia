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
import CRC from './CRC';
import Rand from './Rand';
import BZip2Constants from './BZip2Constants';
import CompressorInputStream from '../CompressorInputStream';
import type InputStreamStatistics from '../../util/InputStreamStatistics';
import BitInputStream from '../../util/BitInputStream';
import InputStream from '../../util/InputStream';
import ByteOrder from '../../util/ByteOrder';
import Exception from '../../util/Exception';
import IndexOutOfBoundsException from '../../util/IndexOutOfBoundsException';
import IllegalStateException from '../../util/IllegalStateException';
import Arrays from '../../util/Arrays';
import System from '../../util/System';
import Long from "../../util/long/index";

class Data {
    inUse: Array<boolean> = new Array<boolean>(256); // 256 byte
    seqToUnseq: Int8Array = new Int8Array(256); // 256 byte
    selector: Int8Array = new Int8Array(BZip2Constants.MAX_SELECTORS); // 18002 byte
    selectorMtf: Int8Array = new Int8Array(BZip2Constants.MAX_SELECTORS); // 18002 byte
    unzftab: Int32Array = new Int32Array(256); // 1024 byte
    static limit: Array<Int32Array> = new Array<Int32Array>(BZip2Constants.N_GROUPS); // 6192 byte MAX_ALPHA_SIZE
    static base: Array<Int32Array> = new Array<Int32Array>(BZip2Constants.N_GROUPS); // 6192 byte MAX_ALPHA_SIZE
    static perm: Array<Int32Array> = new Array<Int32Array>(BZip2Constants.N_GROUPS); // 6192 byte MAX_ALPHA_SIZE
    minLens: Int32Array = new Int32Array(BZip2Constants.N_GROUPS); // 24 byte
    cftab: Int32Array = new Int32Array(257); // 1028 byte
    getAndMoveToFrontDecode_yy: Int32Array = new Int32Array(256); // 512 byte
    static temp_charArray2d: Array<Int32Array> = new Array<Int32Array>(BZip2Constants.N_GROUPS); // 3096 MAX_ALPHA_SIZE
    recvDecodingTables_pos: Int8Array = new Int8Array(BZip2Constants.N_GROUPS); // 6 byte
    tt: Int32Array; // 3600000 byte
    ll8: Int8Array; // 900000 byte

    static staticInit() {
        for (let i = 0; i < BZip2Constants.N_GROUPS; i++) {
            Data.limit[i] = new Int32Array(BZip2Constants.MAX_ALPHA_SIZE);
            Data.base[i] = new Int32Array(BZip2Constants.MAX_ALPHA_SIZE);
            Data.perm[i] = new Int32Array(BZip2Constants.MAX_ALPHA_SIZE);
            Data.temp_charArray2d[i] = new Int32Array(BZip2Constants.MAX_ALPHA_SIZE);
        }
    }

    constructor(blockSize100k: number) {
        this.ll8 = new Int8Array(blockSize100k * BZip2Constants.BASEBLOCKSIZE);
    }

    initTT(length: number): Int32Array {
        let ttShadow: Int32Array = this.tt;
        if ((ttShadow == null) || (ttShadow.length < length)) {
            this.tt = ttShadow = new Int32Array(length);
        }

        return ttShadow;
    }
}

Data.staticInit()

export default class BZip2CompressorInputStream extends CompressorInputStream
implements InputStreamStatistics {
    private last: number = 0;
    private origPtr: number = 0;
    private blockSize100k: number = 0;
    private blockRandomised: boolean;
    private crc: CRC = new CRC();
    private nInUse: number = 0;
    private bin: BitInputStream;
    private decompressConcatenated: boolean;
    private static EOF: number = 0;
    private static START_BLOCK_STATE: number = 1;
    private static RAND_PART_A_STATE: number = 2;
    private static RAND_PART_B_STATE: number = 3;
    private static RAND_PART_C_STATE: number = 4;
    private static NO_RAND_PART_A_STATE: number = 5;
    private static NO_RAND_PART_B_STATE: number = 6;
    private static NO_RAND_PART_C_STATE: number = 7;
    private currentState: number = BZip2CompressorInputStream.START_BLOCK_STATE;
    private storedBlockCRC: number = 0;
    private storedCombinedCRC: number = 0;
    private computedBlockCRC: number = 0;
    private computedCombinedCRC: number = 0;
    private su_count: number = 0;
    private su_ch2: number = 0;
    private su_chPrev: number = 0;
    private su_i2: number = 0;
    private su_j2: number = 0;
    private su_rNToGo: number = 0;
    private su_rTPos: number = 0;
    private su_tPos: number = 0;
    private su_z: number;
    private data: Data;

    constructor(inputStream: InputStream, decompressConcatenated: boolean) {
        super();
        this.bin = new BitInputStream(inputStream, ByteOrder.BIG_ENDIAN);
        this.decompressConcatenated = decompressConcatenated;
        this.init(true);
        this.initBlock();
    }

    public read(): number {
        if (this.bin != null) {
            let r: number = this.read0();
            this.counts(Long.fromNumber(r < 0 ? -1 : 1));
            return r;
        }
        throw new Exception("Stream closed");
    }

    public readBytesOffset(dest: Int8Array, offs: number, len: number): number {
        if (offs < 0) {
            throw new IndexOutOfBoundsException("offs(" + offs + ") < 0.");
        }
        if (len < 0) {
            throw new IndexOutOfBoundsException("len(" + len + ") < 0.");
        }
        if (offs + len > dest.length) {
            throw new IndexOutOfBoundsException("offs(" + offs + ") + len("
            + len + ") > dest.length(" + dest.length + ").");
        }
        if (this.bin == null) {
            throw new Exception("Stream closed");
        }
        if (len == 0) {
            return 0;
        }

        let hi: number = offs + len;
        let destOffs: number = offs;
        let b: number;
        while (destOffs < hi && ((b = this.read0()) >= 0)) {
            dest[destOffs++] = b;
            this.counts(Long.fromNumber(1));
        }

        return (destOffs == offs) ? -1 : (destOffs - offs);
    }

    public getCompressedCount(): Long {
        return this.bin.getBytesRead();
    }

    private makeMaps(): void {
        let inUse: Array<boolean> = this.data.inUse;
        let seqToUnseq: Int8Array = this.data.seqToUnseq;

        let nInUseShadow: number = 0;

        for (let i = 0; i < 256; i++) {
            if (inUse[i]) {
                seqToUnseq[nInUseShadow++] = i;
            }
        }

        this.nInUse = nInUseShadow;
    }

    private read0(): number {
        switch (this.currentState) {
            case BZip2CompressorInputStream.EOF:
                return -1;

            case BZip2CompressorInputStream.START_BLOCK_STATE:
                return this.setupBlock();

            case BZip2CompressorInputStream.RAND_PART_A_STATE:
                throw new IllegalStateException();

            case BZip2CompressorInputStream.RAND_PART_B_STATE:
                return this.setupRandPartB();

            case BZip2CompressorInputStream.RAND_PART_C_STATE:
                return this.setupRandPartC();

            case BZip2CompressorInputStream.NO_RAND_PART_A_STATE:
                throw new IllegalStateException();

            case BZip2CompressorInputStream.NO_RAND_PART_B_STATE:
                return this.setupNoRandPartB();

            case BZip2CompressorInputStream.NO_RAND_PART_C_STATE:
                return this.setupNoRandPartC();

            default:
                throw new IllegalStateException("");
        }
    }

    private readNextByte(inputStream: BitInputStream): number {
        let b: Long = inputStream.readBits(8);
        return b.toNumber();
    }

    private init(isFirstStream: boolean): boolean {
        if (null == this.bin) {
            throw new Exception("No InputStream");
        }

        if (!isFirstStream) {
            this.bin.clearBitCache();
        }

        let magic0: number = this.readNextByte(this.bin);
        if (magic0 == -1 && !isFirstStream) {
            return false;
        }
        let magic1: number = this.readNextByte(this.bin);
        let magic2: number = this.readNextByte(this.bin);

        if (magic0 != 'B'.charCodeAt(0) || magic1 != 'Z'.charCodeAt(0) || magic2 != 'h'.charCodeAt(0)) {
            throw new Exception(isFirstStream
                ? "Stream is not in the BZip2 format"
                : "Garbage after a valid BZip2 stream");
        }

        let blockSize: number = this.readNextByte(this.bin);
        if ((blockSize < '1'.charCodeAt(0)) || (blockSize > '9'.charCodeAt(0))) {
            throw new Exception("BZip2 block size is invalid");
        }

        this.blockSize100k = blockSize - '0'.charCodeAt(0);
        this.computedCombinedCRC = 0;
        return true;
    }

    private initBlock(): void {
        let bin: BitInputStream = this.bin;
        let magic0: number;
        let magic1: number;
        let magic2: number;
        let magic3: number;
        let magic4: number;
        let magic5: number;

        while (true) {
            // Get the block magic bytes.
            magic0 = BZip2CompressorInputStream.bsGetUByte(bin);
            magic1 = BZip2CompressorInputStream.bsGetUByte(bin);
            magic2 = BZip2CompressorInputStream.bsGetUByte(bin);
            magic3 = BZip2CompressorInputStream.bsGetUByte(bin);
            magic4 = BZip2CompressorInputStream.bsGetUByte(bin);
            magic5 = BZip2CompressorInputStream.bsGetUByte(bin);

            // If isn't end of stream magic, break out of the loop.
            if (magic0 != 0x17 || magic1 != 0x72 || magic2 != 0x45
            || magic3 != 0x38 || magic4 != 0x50 || magic5 != 0x90) {
                break;
            }

            // End of stream was reached. Check the combined CRC and
            // advance to the next .bz2 stream if decoding concatenated
            // streams.
            if (this.complete()) {
                return;
            }
        }

        if (magic0 != 0x31 || // '1'
        magic1 != 0x41 || // ')'
        magic2 != 0x59 || // 'Y'
        magic3 != 0x26 || // '&'
        magic4 != 0x53 || // 'S'
        magic5 != 0x59 // 'Y'
        ) {
            this.currentState = BZip2CompressorInputStream.EOF;
            throw new Exception("Bad block header");
        }
        this.storedBlockCRC = BZip2CompressorInputStream.bsGetInt(bin);
        this.blockRandomised = BZip2CompressorInputStream.bsR(bin, 1) == 1;

        /*
         * Allocate data here instead in constructor, so we do not allocate
         * it if the input file is empty.
         */
        if (this.data == null) {
            this.data = new Data(this.blockSize100k);
        }

        // currBlockNo++;
        this.getAndMoveToFrontDecode();

        this.crc.initializeCRC();
        this.currentState = BZip2CompressorInputStream.START_BLOCK_STATE;
    }

    private endBlock(): void {
        this.computedBlockCRC = this.crc.getFinalCRC();

        if (this.storedBlockCRC != this.computedBlockCRC) {

            this.computedCombinedCRC = (this.storedCombinedCRC << 1)
            | (this.storedCombinedCRC >>> 31);
            this.computedCombinedCRC ^= this.storedBlockCRC;

            throw new Exception("BZip2 CRC error");
        }

        this.computedCombinedCRC = (this.computedCombinedCRC << 1)
        | (this.computedCombinedCRC >>> 31);
        this.computedCombinedCRC ^= this.computedBlockCRC;
    }

    private complete(): boolean {
        this.storedCombinedCRC = BZip2CompressorInputStream.bsGetInt(this.bin);
        this.currentState = BZip2CompressorInputStream.EOF;
        this.data = null;

        if (this.storedCombinedCRC != this.computedCombinedCRC) {
            throw new Exception("BZip2 CRC error");
        }

        return!this.decompressConcatenated || !this.init(false);
    }

    public close(): void {
        let inShadow: BitInputStream = this.bin;
        if (inShadow != null) {
            try {
                inShadow.close();
            } finally {
                this.data = null;
                this.bin = null;
            }
        }
    }

    private static bsR(bin: BitInputStream, n: number): number {
        let thech: Long = bin.readBits(n);
        if (thech.lessThan(0)) {
            throw new Exception("Unexpected end of stream");
        }
        return thech.getLowBits();
    }

    private static bsGetBit(bin: BitInputStream): boolean {
        return this.bsR(bin, 1) != 0;
    }

    private static bsGetUByte(bin: BitInputStream): number {
        return this.bsR(bin, 8);
    }

    private static bsGetInt(bin: BitInputStream): number {
        return this.bsR(bin, 32);
    }

    private static checkBounds(checkVal: number, limitExclusive: number, name: string): void {
        if (checkVal < 0) {
            throw new Exception("Corrupted input, " + name + " value negative");
        }
        if (checkVal >= limitExclusive) {
            throw new Exception("Corrupted input, " + name + " value too big");
        }
    }

    private static hbCreateDecodeTables(limit: Int32Array,
                                        base: Int32Array, perm: Int32Array, length: Int32Array,
                                        minLen: number, maxLen: number, alphaSize: number): void {
        for (let i: number = minLen, pp = 0; i <= maxLen; i++) {
            for (let j = 0; j < alphaSize; j++) {
                if (length[j] == i) {
                    perm[pp++] = j;
                }
            }
        }

        for (let i: number = BZip2Constants.MAX_CODE_LEN; --i > 0; ) {
            base[i] = 0;
            limit[i] = 0;
        }

        for (let i = 0; i < alphaSize; i++) {
            let l: number = length[i];
            this.checkBounds(l, BZip2Constants.MAX_ALPHA_SIZE, "length");
            base[l + 1]++;
        }

        for (let i = 1, b = base[0]; i < BZip2Constants.MAX_CODE_LEN; i++) {
            b += base[i];
            base[i] = b;
        }

        for (let i = minLen, vec = 0, b = base[i]; i <= maxLen; i++) {
            let nb: number = base[i + 1];
            vec += nb - b;
            b = nb;
            limit[i] = vec - 1;
            vec <<= 1;
        }

        for (let i: number = minLen + 1; i <= maxLen; i++) {
            base[i] = ((limit[i - 1] + 1) << 1) - base[i];
        }
    }

    private recvDecodingTables(): void {
        let bin: BitInputStream = this.bin;
        let dataShadow: Data = this.data;
        let inUse: Array<boolean> = dataShadow.inUse;
        let pos: Int8Array = dataShadow.recvDecodingTables_pos;
        let selector: Int8Array = dataShadow.selector;
        let selectorMtf: Int8Array = dataShadow.selectorMtf;

        let inUse16: number = 0;

        for (let i = 0; i < 16; i++) {
            if (BZip2CompressorInputStream.bsGetBit(bin)) {
                inUse16 |= 1 << i;
            }
        }

        Arrays.fillBoolean(inUse, false);
        for (let i = 0; i < 16; i++) {
            if ((inUse16 & (1 << i)) != 0) {
                let i16: number = i << 4;
                for (let j: number = 0; j < 16; j++) {
                    if (BZip2CompressorInputStream.bsGetBit(bin)) {
                        inUse[i16 + j] = true;
                    }
                }
            }
        }

        this.makeMaps();
        let alphaSize: number = this.nInUse + 2;

        let nGroups: number = BZip2CompressorInputStream.bsR(bin, 3);
        let selectors: number = BZip2CompressorInputStream.bsR(bin, 15);
        if (selectors < 0) {
            throw new Exception("Corrupted input, nSelectors value negative");
        }
        BZip2CompressorInputStream.checkBounds(alphaSize, BZip2Constants.MAX_ALPHA_SIZE + 1, "alphaSize");
        BZip2CompressorInputStream.checkBounds(nGroups, BZip2Constants.N_GROUPS + 1, "nGroups");


        for (let i = 0; i < selectors; i++) {
            let j: number = 0;
            while (BZip2CompressorInputStream.bsGetBit(bin)) {
                j++;
            }
            if (i < BZip2Constants.MAX_SELECTORS) {
                selectorMtf[i] = j;
            }
        }
        let nSelectors: number = selectors > BZip2Constants.MAX_SELECTORS ? BZip2Constants.MAX_SELECTORS : selectors;

        for (let v: number = nGroups; --v >= 0; ) {
            pos[v] = v;
        }

        for (let i = 0; i < nSelectors; i++) {
            let v = selectorMtf[i] & 0xff;
            BZip2CompressorInputStream.checkBounds(v, BZip2Constants.N_GROUPS, "selectorMtf");
            let tmp: number = pos[v];
            while (v > 0) {
                pos[v] = pos[v - 1];
                v--;
            }
            pos[0] = tmp;
            selector[i] = tmp;
        }

        let len: Array<Int32Array> = Data.temp_charArray2d;

        /* Now the coding tables */
        for (let t = 0; t < nGroups; t++) {
            let curr: number = BZip2CompressorInputStream.bsR(bin, 5);
            let len_t: Int32Array = len[t];
            for (let i: number = 0; i < alphaSize; i++) {
                while (BZip2CompressorInputStream.bsGetBit(bin)) {
                    curr += BZip2CompressorInputStream.bsGetBit(bin) ? -1 : 1;
                }
                len_t[i] = curr;
            }
        }

        // finally create the Huffman tables
        this.createHuffmanDecodingTables(alphaSize, nGroups);
    }

    private createHuffmanDecodingTables(alphaSize: number, nGroups: number): void {
        let dataShadow: Data = this.data;
        let len: Array<Int32Array> = Data.temp_charArray2d;
        let minLens: Int32Array = dataShadow.minLens;
        let limit: Array<Int32Array> = Data.limit;
        let base: Array<Int32Array> = Data.base;
        let perm: Array<Int32Array> = Data.perm;

        for (let t: number = 0; t < nGroups; t++) {
            let minLen: number = 32;
            let maxLen: number = 0;
            let len_t: Int32Array = len[t];
            for (let i: number = alphaSize; --i >= 0; ) {
                let lent: number = len_t[i];
                if (lent > maxLen) {
                    maxLen = lent;
                }
                if (lent < minLen) {
                    minLen = lent;
                }
            }
            BZip2CompressorInputStream.hbCreateDecodeTables(limit[t], base[t], perm[t], len[t], minLen,
                maxLen, alphaSize);
            minLens[t] = minLen;
        }
    }

    private getAndMoveToFrontDecode(): void {
        let bin: BitInputStream = this.bin;
        this.origPtr = BZip2CompressorInputStream.bsR(bin, 24);
        this.recvDecodingTables();

        let dataShadow: Data = this.data;
        let ll8: Int8Array = dataShadow.ll8;
        let unzftab: Int32Array = dataShadow.unzftab;
        let selector: Int8Array = dataShadow.selector;
        let seqToUnseq: Int8Array = dataShadow.seqToUnseq;
        let yy: Int32Array = dataShadow.getAndMoveToFrontDecode_yy;
        let minLens: Int32Array = dataShadow.minLens;
        let limit: Array<Int32Array> = Data.limit;
        let base: Array<Int32Array> = Data.base;
        let perm: Array<Int32Array> = Data.perm;
        let limitLast: number = this.blockSize100k * 100000;


        for (let i = 256; --i >= 0; ) {
            yy[i] = i;
            unzftab[i] = 0;
        }

        let groupNo: number = 0;
        let groupPos: number = BZip2Constants.G_SIZE - 1;
        let eob: number = this.nInUse + 1;
        let nextSym: number = this.getAndMoveToFrontDecode0();
        let lastShadow: number = -1;
        let zt: number = selector[groupNo] & 0xff;
        BZip2CompressorInputStream.checkBounds(zt, BZip2Constants.N_GROUPS, "zt");
        let base_zt: Int32Array = base[zt];
        let limit_zt: Int32Array = limit[zt];
        let perm_zt: Int32Array = perm[zt];
        let minLens_zt: number = minLens[zt];

        while (nextSym != eob) {
            if ((nextSym == BZip2Constants.RUNA) || (nextSym == BZip2Constants.RUNB)) {
                let s = -1;

                for (let n = 1; true; n <<= 1) {
                    if (nextSym == BZip2Constants.RUNA) {
                        s += n;
                    } else if (nextSym == BZip2Constants.RUNB) {
                        s += n << 1;
                    } else {
                        break;
                    }

                    if (groupPos == 0) {
                        groupPos = BZip2Constants.G_SIZE - 1;
                        BZip2CompressorInputStream.checkBounds(++groupNo, BZip2Constants.MAX_SELECTORS, "groupNo");
                        zt = selector[groupNo] & 0xff;
                        BZip2CompressorInputStream.checkBounds(zt, BZip2Constants.N_GROUPS, "zt");
                        base_zt = base[zt];
                        limit_zt = limit[zt];
                        perm_zt = perm[zt];
                        minLens_zt = minLens[zt];
                    } else {
                        groupPos--;
                    }

                    let zn: number = minLens_zt;
                    BZip2CompressorInputStream.checkBounds(zn, BZip2Constants.MAX_ALPHA_SIZE, "zn");
                    let zvec: number = BZip2CompressorInputStream.bsR(bin, zn);
                    while (zvec > limit_zt[zn]) {
                        BZip2CompressorInputStream.checkBounds(++zn, BZip2Constants.MAX_ALPHA_SIZE, "zn");
                        zvec = (zvec << 1) | BZip2CompressorInputStream.bsR(bin, 1);
                    }
                    let tmp: number = zvec - base_zt[zn];
                    BZip2CompressorInputStream.checkBounds(tmp, BZip2Constants.MAX_ALPHA_SIZE, "zvec");
                    nextSym = perm_zt[tmp];
                }
                BZip2CompressorInputStream.checkBounds(s, this.data.ll8.length, "s");

                let yy0: number = yy[0];
                BZip2CompressorInputStream.checkBounds(yy0, 256, "yy");
                let ch: number = seqToUnseq[yy0];
                unzftab[ch & 0xff] += s + 1;

                let fromIndex: number = ++lastShadow;
                lastShadow += s;
                BZip2CompressorInputStream.checkBounds(lastShadow, this.data.ll8.length, "lastShadow");
                Arrays.fillByte(ll8, fromIndex, lastShadow + 1, ch);

                if (lastShadow >= limitLast) {
                    throw new Exception("Block overrun while expanding RLE in MTF, "
                    + lastShadow + " exceeds " + limitLast);
                }
            } else {
                if (++lastShadow >= limitLast) {
                    throw new Exception("Block overrun in MTF, "
                    + lastShadow + " exceeds " + limitLast);
                }
                BZip2CompressorInputStream.checkBounds(nextSym, 256 + 1, "nextSym");

                let tmp: number = yy[nextSym - 1];
                BZip2CompressorInputStream.checkBounds(tmp, 256, "yy");
                unzftab[seqToUnseq[tmp] & 0xff]++;
                ll8[lastShadow] = seqToUnseq[tmp];

                if (nextSym <= 16) {
                    for (let j: number = nextSym - 1; j > 0; ) {
                        yy[j] = yy[--j];
                    }
                } else {
                    System.arraycopy(yy, 0, yy, 1, nextSym - 1);
                }

                yy[0] = tmp;

                if (groupPos == 0) {
                    groupPos = BZip2Constants.G_SIZE - 1;
                    BZip2CompressorInputStream.checkBounds(++groupNo, BZip2Constants.MAX_SELECTORS, "groupNo");
                    zt = selector[groupNo] & 0xff;
                    BZip2CompressorInputStream.checkBounds(zt, BZip2Constants.N_GROUPS, "zt");
                    base_zt = base[zt];
                    limit_zt = limit[zt];
                    perm_zt = perm[zt];
                    minLens_zt = minLens[zt];
                } else {
                    groupPos--;
                }

                let zn: number = minLens_zt;
                BZip2CompressorInputStream.checkBounds(zn, BZip2Constants.MAX_ALPHA_SIZE, "zn");
                let zvec: number = BZip2CompressorInputStream.bsR(bin, zn);
                while (zvec > limit_zt[zn]) {
                    BZip2CompressorInputStream.checkBounds(++zn, BZip2Constants.MAX_ALPHA_SIZE, "zn");
                    zvec = (zvec << 1) | BZip2CompressorInputStream.bsR(bin, 1);
                }
                let idx: number = zvec - base_zt[zn];
                BZip2CompressorInputStream.checkBounds(idx, BZip2Constants.MAX_ALPHA_SIZE, "zvec");
                nextSym = perm_zt[idx];
            }
        }

        this.last = lastShadow;
    }

    private getAndMoveToFrontDecode0(): number {
        let dataShadow: Data = this.data;
        let zt: number = dataShadow.selector[0] & 0xff;
        BZip2CompressorInputStream.checkBounds(zt, BZip2Constants.N_GROUPS, "zt");
        let limit_zt: Int32Array = Data.limit[zt];
        let zn: number = dataShadow.minLens[zt];
        BZip2CompressorInputStream.checkBounds(zn, BZip2Constants.MAX_ALPHA_SIZE, "zn");
        let zvec: number = BZip2CompressorInputStream.bsR(this.bin, zn);
        while (zvec > limit_zt[zn]) {
            BZip2CompressorInputStream.checkBounds(++zn, BZip2Constants.MAX_ALPHA_SIZE, "zn");
            zvec = (zvec << 1) | BZip2CompressorInputStream.bsR(this.bin, 1);
        }
        let tmp: number = zvec - Data.base[zt][zn];
        BZip2CompressorInputStream.checkBounds(tmp, BZip2Constants.MAX_ALPHA_SIZE, "zvec");

        return Data.perm[zt][tmp];
    }

    private setupBlock(): number {
        if (this.currentState == BZip2CompressorInputStream.EOF || this.data == null) {
            return -1;
        }

        let cftab: Int32Array = this.data.cftab;
        let ttLen: number = this.last + 1;
        let tt: Int32Array = this.data.initTT(ttLen);
        let ll8: Int8Array = this.data.ll8;
        cftab[0] = 0;
        System.arraycopy(this.data.unzftab, 0, cftab, 1, 256);

        for (let i: number = 1, c = cftab[0]; i <= 256; i++) {
            c += cftab[i];
            cftab[i] = c;
        }

        for (let i = 0, lastShadow = this.last; i <= lastShadow; i++) {
            let tmp: number = cftab[ll8[i] & 0xff]++;
            BZip2CompressorInputStream.checkBounds(tmp, ttLen, "tt index");
            tt[tmp] = i;
        }

        if ((this.origPtr < 0) || (this.origPtr >= tt.length)) {
            throw new Exception("Stream corrupted");
        }

        this.su_tPos = tt[this.origPtr];
        this.su_count = 0;
        this.su_i2 = 0;
        this.su_ch2 = 256;

        if (this.blockRandomised) {
            this.su_rNToGo = 0;
            this.su_rTPos = 0;
            return this.setupRandPartA();
        }
        return this.setupNoRandPartA();
    }

    private setupRandPartA(): number {
        if (this.su_i2 <= this.last) {
            this.su_chPrev = this.su_ch2;
            let su_ch2Shadow: number = this.data.ll8[this.su_tPos] & 0xff;
            BZip2CompressorInputStream.checkBounds(this.su_tPos, this.data.tt.length, "su_tPos");
            this.su_tPos = this.data.tt[this.su_tPos];
            if (this.su_rNToGo == 0) {
                this.su_rNToGo = Rand.rNums(this.su_rTPos) - 1;
                if (++this.su_rTPos == 512) {
                    this.su_rTPos = 0;
                }
            } else {
                this.su_rNToGo--;
            }
            this.su_ch2 = su_ch2Shadow ^= (this.su_rNToGo == 1) ? 1 : 0;
            this.su_i2++;
            this.currentState = BZip2CompressorInputStream.RAND_PART_B_STATE;
            this.crc.updateCRC(su_ch2Shadow);
            return su_ch2Shadow;
        }
        this.endBlock();
        this.initBlock();
        return this.setupBlock();
    }

    private setupNoRandPartA(): number {
        if (this.su_i2 <= this.last) {
            this.su_chPrev = this.su_ch2;
            let su_ch2Shadow: number = this.data.ll8[this.su_tPos] & 0xff;
            this.su_ch2 = su_ch2Shadow;
            BZip2CompressorInputStream.checkBounds(this.su_tPos, this.data.tt.length, "su_tPos");
            this.su_tPos = this.data.tt[this.su_tPos];
            this.su_i2++;
            this.currentState = BZip2CompressorInputStream.NO_RAND_PART_B_STATE;
            this.crc.updateCRC(su_ch2Shadow);
            return su_ch2Shadow;
        }
        this.currentState = BZip2CompressorInputStream.NO_RAND_PART_A_STATE;
        this.endBlock();
        this.initBlock();
        return this.setupBlock();
    }

    private setupRandPartB(): number {
        if (this.su_ch2 != this.su_chPrev) {
            this.currentState = BZip2CompressorInputStream.RAND_PART_A_STATE;
            this.su_count = 1;
            return this.setupRandPartA();
        }
        if (++this.su_count < 4) {
            this.currentState = BZip2CompressorInputStream.RAND_PART_A_STATE;
            return this.setupRandPartA();
        }
        this.su_z = (this.data.ll8[this.su_tPos] & 0xff);
        BZip2CompressorInputStream.checkBounds(this.su_tPos, this.data.tt.length, "su_tPos");
        this.su_tPos = this.data.tt[this.su_tPos];
        if (this.su_rNToGo == 0) {
            this.su_rNToGo = Rand.rNums(this.su_rTPos) - 1;
            if (++this.su_rTPos == 512) {
                this.su_rTPos = 0;
            }
        } else {
            this.su_rNToGo--;
        }
        this.su_j2 = 0;
        this.currentState = BZip2CompressorInputStream.RAND_PART_C_STATE;
        if (this.su_rNToGo == 1) {
            this.su_z ^= 1;
        }
        return this.setupRandPartC();
    }

    private setupRandPartC(): number {
        if (this.su_j2 < this.su_z) {
            this.crc.updateCRC(this.su_ch2);
            this.su_j2++;
            return this.su_ch2;
        }
        this.currentState = BZip2CompressorInputStream.RAND_PART_A_STATE;
        this.su_i2++;
        this.su_count = 0;
        return this.setupRandPartA();
    }

    private setupNoRandPartB(): number {
        if (this.su_ch2 != this.su_chPrev) {
            this.su_count = 1;
            return this.setupNoRandPartA();
        }
        if (++this.su_count >= 4) {
            BZip2CompressorInputStream.checkBounds(this.su_tPos, this.data.ll8.length, "su_tPos");
            this.su_z = (this.data.ll8[this.su_tPos] & 0xff);
            this.su_tPos = this.data.tt[this.su_tPos];
            this.su_j2 = 0;
            return this.setupNoRandPartC();
        }
        return this.setupNoRandPartA();
    }

    private setupNoRandPartC(): number {
        if (this.su_j2 < this.su_z) {
            let su_ch2Shadow: number = this.su_ch2;
            this.crc.updateCRC(su_ch2Shadow);
            this.su_j2++;
            this.currentState = BZip2CompressorInputStream.NO_RAND_PART_C_STATE;
            return su_ch2Shadow;
        }
        this.su_i2++;
        this.su_count = 0;
        return this.setupNoRandPartA();
    }

    public static matches(signature: Int8Array, length: number): boolean {
        return length >= 3 && signature[0] == 'B'.charCodeAt(0) &&
        signature[1] == 'Z'.charCodeAt(0) && signature[2] == 'h'.charCodeAt(0);
    }
}