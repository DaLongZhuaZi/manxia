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
import BZip2Constants from './BZip2Constants';
import BlockSort from './BlockSort';
import CompressorOutputStream from '../CompressorOutputStream';
import OutputStream from '../../util/OutputStream';
import Exception from '../../util/Exception';
import IllegalArgumentException from '../../util/IllegalArgumentException';
import IndexOutOfBoundsException from '../../util/IndexOutOfBoundsException';
import Long from "../../util/long/index";

class Data {
    inUse: Array<boolean> = new Array<boolean>(256); // 256 byte
    unseqToSeq: Int8Array = new Int8Array(256); // 256 byte
    mtfFreq: Int32Array = new Int32Array(BZip2Constants.MAX_ALPHA_SIZE); // 1032 byte
    selector: Int8Array = new Int8Array(BZip2Constants.MAX_SELECTORS); // 18002 byte
    selectorMtf: Int8Array = new Int8Array(BZip2Constants.MAX_SELECTORS); // 18002 byte
    generateMTFValues_yy: Int8Array = new Int8Array(256); // 256 byte
    static sendMTFValues_len: Array<Int8Array> = new Array<Int8Array>(BZip2Constants.N_GROUPS); // 1548 MAX_ALPHA_SIZE
    static sendMTFValues_rfreq: Array<Int32Array> = new Array<Int32Array>(BZip2Constants.N_GROUPS); // 6192
    sendMTFValues_fave: Int32Array = new Int32Array(BZip2Constants.N_GROUPS); // 24 byte
    sendMTFValues_cost: Int16Array = new Int16Array(BZip2Constants.N_GROUPS); // 12 byte
    static sendMTFValues_code: Array<Int32Array> = new Array<Int32Array>(BZip2Constants.N_GROUPS); // 6192 MAX_ALPHA_SIZE
    sendMTFValues2_pos: Int8Array = new Int8Array(BZip2Constants.N_GROUPS); // 6 byte
    sentMTFValues4_inUse16: Array<boolean> = new Array<boolean>(16); // 16 byte
    heap: Int32Array = new Int32Array(BZip2Constants.MAX_ALPHA_SIZE + 2); // 1040 byte
    weight: Int32Array = new Int32Array(BZip2Constants.MAX_ALPHA_SIZE * 2); // 2064 byte
    parent: Int32Array = new Int32Array(BZip2Constants.MAX_ALPHA_SIZE * 2); // 2064 byte
    block: Int8Array; // 900021 byte
    fmap: Int32Array; // 3600000 byte
    sfmap: Int32Array; // 3600000 byte
    origPtr: number;

    constructor(blockSize100k: number) {
        let n: number = blockSize100k * BZip2Constants.BASEBLOCKSIZE;
        this.block = new Int8Array(n + 1 + BZip2Constants.NUM_OVERSHOOT_BYTES);
        this.fmap = new Int32Array(n);
        this.sfmap = new Int32Array(2 * n);
    }

    static staticInit() {
        for (let i = 0; i < BZip2Constants.N_GROUPS; i++) {
            Data.sendMTFValues_len[i] = new Int8Array(BZip2Constants.MAX_ALPHA_SIZE);
            Data.sendMTFValues_rfreq[i] = new Int32Array(BZip2Constants.MAX_ALPHA_SIZE);
            Data.sendMTFValues_code[i] = new Int32Array(BZip2Constants.MAX_ALPHA_SIZE);
        }
    }
}

Data.staticInit()

class BZip2CompressorOutputStream extends CompressorOutputStream {
    public static MIN_BLOCKSIZE: number = 1;
    public static MAX_BLOCKSIZE: number = 9;
    private static GREATER_ICOST: number = 15;
    private static LESSER_ICOST: number = 0;

    private static hbMakeCodeLengths(len: Int8Array, freq: Int32Array,
                                     dat: Data, alphaSize: number,
                                     maxLen: number): void {

        let heap: Int32Array = dat.heap;
        let weight: Int32Array = dat.weight;
        let parent: Int32Array = dat.parent;

        for (let i: number = alphaSize; --i >= 0; ) {
            weight[i + 1] = (freq[i] == 0 ? 1 : freq[i]) << 8;
        }

        for (let tooLong = true; tooLong; ) {
            tooLong = false;
            let nNodes: number = alphaSize;
            let nHeap: number = 0;
            heap[0] = 0;
            weight[0] = 0;
            parent[0] = -2;

            for (let i: number = 1; i <= alphaSize; i++) {
                parent[i] = -1;
                nHeap++;
                heap[nHeap] = i;

                let zz: number = nHeap;
                let tmp: number = heap[zz];
                while (weight[tmp] < weight[heap[zz >> 1]]) {
                    heap[zz] = heap[zz >> 1];
                    zz >>= 1;
                }
                heap[zz] = tmp;
            }

            while (nHeap > 1) {
                let n1: number = heap[1];
                heap[1] = heap[nHeap];
                nHeap--;

                let yy: number = 0;
                let zz: number = 1;
                let tmp: number = heap[1];

                while (true) {
                    yy = zz << 1;

                    if (yy > nHeap) {
                        break;
                    }

                    if ((yy < nHeap)
                    && (weight[heap[yy + 1]] < weight[heap[yy]])) {
                        yy++;
                    }

                    if (weight[tmp] < weight[heap[yy]]) {
                        break;
                    }

                    heap[zz] = heap[yy];
                    zz = yy;
                }

                heap[zz] = tmp;

                let n2: number = heap[1];
                heap[1] = heap[nHeap];
                nHeap--;

                yy = 0;
                zz = 1;
                tmp = heap[1];

                while (true) {
                    yy = zz << 1;

                    if (yy > nHeap) {
                        break;
                    }

                    if ((yy < nHeap)
                    && (weight[heap[yy + 1]] < weight[heap[yy]])) {
                        yy++;
                    }

                    if (weight[tmp] < weight[heap[yy]]) {
                        break;
                    }

                    heap[zz] = heap[yy];
                    zz = yy;
                }

                heap[zz] = tmp;
                nNodes++;
                parent[n1] = parent[n2] = nNodes;

                let weight_n1: number = weight[n1];
                let weight_n2: number = weight[n2];
                weight[nNodes] = ((weight_n1 & 0xffffff00)
                + (weight_n2 & 0xffffff00))
                | (1 + (((weight_n1 & 0x000000ff)
                > (weight_n2 & 0x000000ff))
                    ? (weight_n1 & 0x000000ff)
                    : (weight_n2 & 0x000000ff)));

                parent[nNodes] = -1;
                nHeap++;
                heap[nHeap] = nNodes;

                tmp = 0;
                zz = nHeap;
                tmp = heap[zz];
                let weight_tmp: number = weight[tmp];
                while (weight_tmp < weight[heap[zz >> 1]]) {
                    heap[zz] = heap[zz >> 1];
                    zz >>= 1;
                }
                heap[zz] = tmp;

            }

            for (let i: number = 1; i <= alphaSize; i++) {
                let j: number = 0;
                let k: number = i;

                for (let parent_k: number; (parent_k = parent[k]) >= 0; ) {
                    k = parent_k;
                    j++;
                }

                len[i - 1] = j;
                if (j > maxLen) {
                    tooLong = true;
                }
            }

            if (tooLong) {
                for (let i: number = 1; i < alphaSize; i++) {
                    let j: number = weight[i] >> 8;
                    j = 1 + (j >> 1);
                    weight[i] = j << 8;
                }
            }
        }
    }

    private last: number = 0;
    private blockSize100k: number = 0;
    private bsBuff: number = 0;
    private bsLive: number = 0;
    private crc: CRC = new CRC();
    private nInUse: number = 0;
    private nMTF: number = 0;
    private currentChar: number = -1;
    private runLength: number = 0;
    private blockCRC: number = 0;
    private combinedCRC: number = 0;
    private allowableBlockSize: number = 0;
    private data: Data;
    private blockSorter: BlockSort;
    private out: OutputStream;
    private closed: boolean;

    public static chooseBlockSize(inputLength: Long): number {
        return (inputLength.greaterThan(0)) ? Math
                                                  .min((inputLength.div(132000)).add(1).toNumber(), 9) : BZip2CompressorOutputStream.MAX_BLOCKSIZE;
    }

    constructor(out: OutputStream, blockSize: number) {
        super();
        if (blockSize < 1) {
            throw new IllegalArgumentException("blockSize(" + blockSize + ") < 1");
        }
        if (blockSize > 9) {
            throw new IllegalArgumentException("blockSize(" + blockSize + ") > 9");
        }

        this.blockSize100k = blockSize;
        this.out = out;

        this.allowableBlockSize = (this.blockSize100k * BZip2Constants.BASEBLOCKSIZE) - 20;
        this.init();
    }

    public write(b: number): void {
        if (this.closed) {
            throw new Exception("Closed");
        }
        this.write0(b);
    }

    private writeRun(): void {
        let lastShadow: number = this.last;

        if (lastShadow < this.allowableBlockSize) {
            let currentCharShadow: number = this.currentChar;
            let dataShadow: Data = this.data;
            dataShadow.inUse[currentCharShadow] = true;
            let ch: number = currentCharShadow;

            let runLengthShadow: number = this.runLength;
            this.crc.updateCRCRepeat(currentCharShadow, runLengthShadow);

            switch (runLengthShadow) {
                case 1:
                    dataShadow.block[lastShadow + 2] = ch;
                    this.last = lastShadow + 1;
                    break;

                case 2:
                    dataShadow.block[lastShadow + 2] = ch;
                    dataShadow.block[lastShadow + 3] = ch;
                    this.last = lastShadow + 2;
                    break;

                case 3: {
                    let block: Int8Array = dataShadow.block;
                    block[lastShadow + 2] = ch;
                    block[lastShadow + 3] = ch;
                    block[lastShadow + 4] = ch;
                    this.last = lastShadow + 3;
                }
                    break;

                default: {
                    runLengthShadow -= 4;
                    dataShadow.inUse[runLengthShadow] = true;
                    let block: Int8Array = dataShadow.block;
                    block[lastShadow + 2] = ch;
                    block[lastShadow + 3] = ch;
                    block[lastShadow + 4] = ch;
                    block[lastShadow + 5] = ch;
                    block[lastShadow + 6] = runLengthShadow;
                    this.last = lastShadow + 5;
                }
                    break;

            }
        } else {
            this.endBlock();
            this.initBlock();
            this.writeRun();
        }
    }

    protected finalize(): void {
        if (!this.closed) {
            throw new Exception("Unclosed BZip2CompressorOutputStream detected, will *not* close it");
        }
    }

    public finish(): void {
        if (!this.closed) {
            this.closed = true;
            try {
                if (this.runLength > 0) {
                    this.writeRun();
                }
                this.currentChar = -1;
                this.endBlock();
                this.endCompression();
            } finally {
                this.out = null;
                this.blockSorter = null;
                this.data = null;
            }
        }
    }

    public close(): void {
        if (!this.closed) {
            let outShadow: OutputStream;
            try {
                outShadow = this.out;
                this.finish();
            } catch (e) {
            } finally {
                if (outShadow != null) {
                    outShadow.close();
                }
            }
        }
    }

    public flush(): void {
        let outShadow: OutputStream = this.out;
        if (outShadow != null) {
            outShadow.flush();
        }
    }

    private init(): void {
        this.bsPutUByte('B'.charCodeAt(0));
        this.bsPutUByte('Z'.charCodeAt(0));

        this.data = new Data(this.blockSize100k);
        this.blockSorter = new BlockSort(this.data);


        this.bsPutUByte('h'.charCodeAt(0));
        this.bsPutUByte('0'.charCodeAt(0) + this.blockSize100k);

        this.combinedCRC = 0;
        this.initBlock();
    }

    private initBlock(): void {

        this.crc.initializeCRC();
        this.last = -1;

        let inUse: Array<boolean> = this.data.inUse;
        for (let i: number = 256; --i >= 0; ) {
            inUse[i] = false;
        }

    }

    private endBlock(): void {
        this.blockCRC = this.crc.getFinalCRC();
        this.combinedCRC = (this.combinedCRC << 1) | (this.combinedCRC >>> 31);
        this.combinedCRC ^= this.blockCRC;

        if (this.last == -1) {
            return;
        }


        this.blockSort();

        this.bsPutUByte(0x31);
        this.bsPutUByte(0x41);
        this.bsPutUByte(0x59);
        this.bsPutUByte(0x26);
        this.bsPutUByte(0x53);
        this.bsPutUByte(0x59);

        this.bsPutInt(this.blockCRC);

        this.bsW(1, 0);

        this.moveToFrontCodeAndSend();
    }

    private endCompression(): void {

        this.bsPutUByte(0x17);
        this.bsPutUByte(0x72);
        this.bsPutUByte(0x45);
        this.bsPutUByte(0x38);
        this.bsPutUByte(0x50);
        this.bsPutUByte(0x90);

        this.bsPutInt(this.combinedCRC);
        this.bsFinishedWithStream();
    }

    public getBlockSize(): number {
        return this.blockSize100k;
    }

    public writeBytesOffset(buf: Int8Array, offs: number, len: number): void {
        if (offs < 0) {
            throw new IndexOutOfBoundsException("offs(" + offs + ") < 0.");
        }
        if (len < 0) {
            throw new IndexOutOfBoundsException("len(" + len + ") < 0.");
        }
        if (offs + len > buf.length) {
            throw new IndexOutOfBoundsException("offs(" + offs + ") + len("
            + len + ") > buf.length("
            + buf.length + ").");
        }
        if (this.closed) {
            throw new Exception("Stream closed");
        }

        for (let hi: number = offs + len; offs < hi; ) {
            this.write0(buf[offs++]);
        }
    }

    private write0(b: number): void {
        if (this.currentChar != -1) {
            b &= 0xff;
            if (this.currentChar == b) {
                if (++this.runLength > 254) {
                    this.writeRun();
                    this.currentChar = -1;
                    this.runLength = 0;
                }
                // else nothing to do
            } else {
                this.writeRun();
                this.runLength = 1;
                this.currentChar = b;
            }
        } else {
            this.currentChar = b & 0xff;
            this.runLength++;
        }
    }

    private static hbAssignCodes(code: Int32Array, length: Int8Array,
                                 minLen: number, maxLen: number,
                                 alphaSize: number): void {
        let vec: number = 0;
        for (let n: number = minLen; n <= maxLen; n++) {
            for (let i = 0; i < alphaSize; i++) {
                if ((length[i] & 0xff) == n) {
                    code[i] = vec;
                    vec++;
                }
            }
            vec <<= 1;
        }
    }

    private bsFinishedWithStream(): void {
        while (this.bsLive > 0) {
            let ch: number = this.bsBuff >> 24;
            this.out.write(ch); // write 8-bit
            this.bsBuff <<= 8;
            this.bsLive -= 8;
        }
    }

    private bsW(n: number, v: number): void {
        let outShadow: OutputStream = this.out;
        let bsLiveShadow: number = this.bsLive;
        let bsBuffShadow: number = this.bsBuff;

        while (bsLiveShadow >= 8) {
            outShadow.write(bsBuffShadow >> 24); // write 8-bit
            bsBuffShadow <<= 8;
            bsLiveShadow -= 8;
        }

        this.bsBuff = bsBuffShadow | (v << (32 - bsLiveShadow - n));
        this.bsLive = bsLiveShadow + n;
    }

    private bsPutUByte(c: number): void {
        this.bsW(8, c);
    }

    private bsPutInt(u: number): void {
        this.bsW(8, (u >> 24) & 0xff);
        this.bsW(8, (u >> 16) & 0xff);
        this.bsW(8, (u >> 8) & 0xff);
        this.bsW(8, u & 0xff);
    }

    private sendMTFValues(): void {
        let len: Array<Int8Array> = Data.sendMTFValues_len;
        let alphaSize: number = this.nInUse + 2;

        for (let t: number = BZip2Constants.N_GROUPS; --t >= 0; ) {
            let len_t: Int8Array = len[t];
            for (let v: number = alphaSize; --v >= 0; ) {
                len_t[v] = BZip2CompressorOutputStream.GREATER_ICOST;
            }
        }


        let nGroups: number = (this.nMTF < 200) ? 2 : (this.nMTF < 600) ? 3
                                                                        : (this.nMTF < 1200) ? 4 : (this.nMTF < 2400) ? 5 : 6;


        this.sendMTFValues0(nGroups, alphaSize);


        let nSelectors: number = this.sendMTFValues1(nGroups, alphaSize);


        this.sendMTFValues2(nGroups, nSelectors);


        this.sendMTFValues3(nGroups, alphaSize);


        this.sendMTFValues4();


        this.sendMTFValues5(nGroups, nSelectors);


        this.sendMTFValues6(nGroups, alphaSize);


        this.sendMTFValues7();
    }

    private sendMTFValues0(nGroups: number, alphaSize: number): void {
        let len: Array<Int8Array> = Data.sendMTFValues_len;
        let mtfFreq: Int32Array = this.data.mtfFreq;

        let remF: number = this.nMTF;
        let gs: number = 0;

        for (let nPart: number = nGroups; nPart > 0; nPart--) {
            let tFreq: number = remF / nPart;
            let ge: number = gs - 1;
            let aFreq: number = 0;

            for (let a: number = alphaSize - 1; (aFreq < tFreq) && (ge < a); ) {
                aFreq += mtfFreq[++ge];
            }

            if ((ge > gs) && (nPart != nGroups) && (nPart != 1)
            && (((nGroups - nPart) & 1) != 0)) {
                aFreq -= mtfFreq[ge--];
            }

            let len_np: Int8Array = len[nPart - 1];
            for (let v: number = alphaSize; --v >= 0; ) {
                if ((v >= gs) && (v <= ge)) {
                    len_np[v] = BZip2CompressorOutputStream.LESSER_ICOST;
                } else {
                    len_np[v] = BZip2CompressorOutputStream.GREATER_ICOST;
                }
            }

            gs = ge + 1;
            remF -= aFreq;
        }
    }

    private sendMTFValues1(nGroups: number, alphaSize: number): number {
        let dataShadow: Data = this.data;
        let rfreq: Array<Int32Array> = Data.sendMTFValues_rfreq;
        let fave: Int32Array = dataShadow.sendMTFValues_fave;
        let cost: Int16Array = dataShadow.sendMTFValues_cost;
        let sfmap: Int32Array = dataShadow.sfmap;
        let selector: Int8Array = dataShadow.selector;
        let len: Array<Int8Array> = Data.sendMTFValues_len;
        let len_0: Int8Array = len[0];
        let len_1: Int8Array = len[1];
        let len_2: Int8Array = len[2];
        let len_3: Int8Array = len[3];
        let len_4: Int8Array = len[4];
        let len_5: Int8Array = len[5];
        let nMTFShadow: number = this.nMTF;

        let nSelectors: number = 0;

        for (let iter: number = 0; iter < BZip2Constants.N_ITERS; iter++) {
            for (let t: number = nGroups; --t >= 0; ) {
                fave[t] = 0;
                let rfreqt: Int32Array = rfreq[t];
                for (let i: number = alphaSize; --i >= 0; ) {
                    rfreqt[i] = 0;
                }
            }

            nSelectors = 0;

            for (let gs: number = 0; gs < this.nMTF; ) {


                let ge: number = Math.min(gs + BZip2Constants.G_SIZE - 1, nMTFShadow - 1);

                if (nGroups == BZip2Constants.N_GROUPS) {
                    // unrolled version of the else-block

                    let cost0: number = 0;
                    let cost1: number = 0;
                    let cost2: number = 0;
                    let cost3: number = 0;
                    let cost4: number = 0;
                    let cost5: number = 0;

                    for (let i: number = gs; i <= ge; i++) {
                        let icv: number = sfmap[i];
                        cost0 += len_0[icv] & 0xff;
                        cost1 += len_1[icv] & 0xff;
                        cost2 += len_2[icv] & 0xff;
                        cost3 += len_3[icv] & 0xff;
                        cost4 += len_4[icv] & 0xff;
                        cost5 += len_5[icv] & 0xff;
                    }

                    cost[0] = cost0;
                    cost[1] = cost1;
                    cost[2] = cost2;
                    cost[3] = cost3;
                    cost[4] = cost4;
                    cost[5] = cost5;

                } else {
                    for (let t: number = nGroups; --t >= 0; ) {
                        cost[t] = 0;
                    }

                    for (let i: number = gs; i <= ge; i++) {
                        let icv: number = sfmap[i];
                        for (let t: number = nGroups; --t >= 0; ) {
                            cost[t] += len[t][icv] & 0xff;
                        }
                    }
                }


                let bt: number = -1;
                for (let t: number = nGroups, bc = 999999999; --t >= 0; ) {
                    let cost_t: number = cost[t];
                    if (cost_t < bc) {
                        bc = cost_t;
                        bt = t;
                    }
                }

                fave[bt]++;
                selector[nSelectors] = bt;
                nSelectors++;


                let rfreq_bt: Int32Array = rfreq[bt];
                for (let i: number = gs; i <= ge; i++) {
                    rfreq_bt[sfmap[i]]++;
                }

                gs = ge + 1;
            }


            for (let t: number = 0; t < nGroups; t++) {
                BZip2CompressorOutputStream.hbMakeCodeLengths(len[t], rfreq[t], this.data, alphaSize, 20);
            }
        }

        return nSelectors;
    }

    private sendMTFValues2(nGroups: number, nSelectors: number): void {


        let dataShadow: Data = this.data;
        let pos: Int8Array = dataShadow.sendMTFValues2_pos;

        for (let i: number = nGroups; --i >= 0; ) {
            pos[i] = i;
        }

        for (let i: number = 0; i < nSelectors; i++) {
            let ll_i: number = dataShadow.selector[i];
            let tmp: number = pos[0];
            let j: number = 0;

            while (ll_i != tmp) {
                j++;
                let tmp2: number = tmp;
                tmp = pos[j];
                pos[j] = tmp2;
            }

            pos[0] = tmp;
            dataShadow.selectorMtf[i] = j;
        }
    }

    private sendMTFValues3(nGroups: number, alphaSize: number): void {
        let code: Array<Int32Array> = Data.sendMTFValues_code;
        let len: Array<Int8Array> = Data.sendMTFValues_len;

        for (let t: number = 0; t < nGroups; t++) {
            let minLen: number = 32;
            let maxLen: number = 0;
            let len_t: Int8Array = len[t];
            for (let i: number = alphaSize; --i >= 0; ) {
                let l: number = len_t[i] & 0xff;
                if (l > maxLen) {
                    maxLen = l;
                }
                if (l < minLen) {
                    minLen = l;
                }
            }

            // assert (maxLen <= 20) : maxLen;
            // assert (minLen >= 1) : minLen;

            BZip2CompressorOutputStream.hbAssignCodes(code[t], len[t], minLen, maxLen, alphaSize);
        }
    }

    private sendMTFValues4(): void {
        let inUse: Array<boolean> = this.data.inUse;
        let inUse16: Array<boolean> = this.data.sentMTFValues4_inUse16;

        for (let i: number = 16; --i >= 0; ) {
            inUse16[i] = false;
            let i16: number = i * 16;
            for (let j: number = 16; --j >= 0; ) {
                if (inUse[i16 + j]) {
                    inUse16[i] = true;
                    break;
                }
            }
        }

        for (let i: number = 0; i < 16; i++) {
            this.bsW(1, inUse16[i] ? 1 : 0);
        }

        let outShadow: OutputStream = this.out;
        let bsLiveShadow: number = this.bsLive;
        let bsBuffShadow: number = this.bsBuff;

        for (let i: number = 0; i < 16; i++) {
            if (inUse16[i]) {
                let i16: number = i * 16;
                for (let j: number = 0; j < 16; j++) {

                    while (bsLiveShadow >= 8) {
                        outShadow.write(bsBuffShadow >> 24); // write 8-bit
                        bsBuffShadow <<= 8;
                        bsLiveShadow -= 8;
                    }
                    if (inUse[i16 + j]) {
                        bsBuffShadow |= 1 << (32 - bsLiveShadow - 1);
                    }
                    bsLiveShadow++;
                }
            }
        }

        this.bsBuff = bsBuffShadow;
        this.bsLive = bsLiveShadow;
    }

    private sendMTFValues5(nGroups: number, nSelectors: number): void {
        this.bsW(3, nGroups);
        this.bsW(15, nSelectors);

        let outShadow: OutputStream = this.out;
        let selectorMtf: Int8Array = this.data.selectorMtf;

        let bsLiveShadow: number = this.bsLive;
        let bsBuffShadow: number = this.bsBuff;

        for (let i: number = 0; i < nSelectors; i++) {
            for (let j: number = 0, hj = selectorMtf[i] & 0xff; j < hj; j++) {
                // inlined: bsW(1, 1);
                while (bsLiveShadow >= 8) {
                    outShadow.write(bsBuffShadow >> 24);
                    bsBuffShadow <<= 8;
                    bsLiveShadow -= 8;
                }
                bsBuffShadow |= 1 << (32 - bsLiveShadow - 1);
                bsLiveShadow++;
            }


            while (bsLiveShadow >= 8) {
                outShadow.write(bsBuffShadow >> 24);
                bsBuffShadow <<= 8;
                bsLiveShadow -= 8;
            }

            bsLiveShadow++;
        }

        this.bsBuff = bsBuffShadow;
        this.bsLive = bsLiveShadow;
    }

    private sendMTFValues6(nGroups: number, alphaSize: number): void {
        let len: Array<Int8Array> = Data.sendMTFValues_len;
        let outShadow: OutputStream = this.out;

        let bsLiveShadow: number = this.bsLive;
        let bsBuffShadow: number = this.bsBuff;

        for (let t: number = 0; t < nGroups; t++) {
            let len_t: Int8Array = len[t];
            let curr: number = len_t[0] & 0xff;


            while (bsLiveShadow >= 8) {
                outShadow.write(bsBuffShadow >> 24); // write 8-bit
                bsBuffShadow <<= 8;
                bsLiveShadow -= 8;
            }
            bsBuffShadow |= curr << (32 - bsLiveShadow - 5);
            bsLiveShadow += 5;

            for (let i: number = 0; i < alphaSize; i++) {
                let lti: number = len_t[i] & 0xff;
                while (curr < lti) {

                    while (bsLiveShadow >= 8) {
                        outShadow.write(bsBuffShadow >> 24); // write 8-bit
                        bsBuffShadow <<= 8;
                        bsLiveShadow -= 8;
                    }
                    bsBuffShadow |= 2 << (32 - bsLiveShadow - 2);
                    bsLiveShadow += 2;

                    curr++;
                }

                while (curr > lti) {

                    while (bsLiveShadow >= 8) {
                        outShadow.write(bsBuffShadow >> 24); // write 8-bit
                        bsBuffShadow <<= 8;
                        bsLiveShadow -= 8;
                    }
                    bsBuffShadow |= 3 << (32 - bsLiveShadow - 2);
                    bsLiveShadow += 2;

                    curr--;
                }


                while (bsLiveShadow >= 8) {
                    outShadow.write(bsBuffShadow >> 24); // write 8-bit
                    bsBuffShadow <<= 8;
                    bsLiveShadow -= 8;
                }

                bsLiveShadow++;
            }
        }

        this.bsBuff = bsBuffShadow;
        this.bsLive = bsLiveShadow;
    }

    private sendMTFValues7(): void {
        let dataShadow: Data = this.data;
        let len: Array<Int8Array> = Data.sendMTFValues_len;
        let code: Array<Int32Array> = Data.sendMTFValues_code;
        let outShadow: OutputStream = this.out;
        let selector: Int8Array = dataShadow.selector;
        let sfmap: Int32Array = dataShadow.sfmap;
        let nMTFShadow: number = this.nMTF;

        let selCtr: number = 0;

        let bsLiveShadow: number = this.bsLive;
        let bsBuffShadow: number = this.bsBuff;

        for (let gs: number = 0; gs < nMTFShadow; ) {
            let ge: number = Math.min(gs + BZip2Constants.G_SIZE - 1, nMTFShadow - 1);
            let selector_selCtr: number = selector[selCtr] & 0xff;
            let code_selCtr: Int32Array = code[selector_selCtr];
            let len_selCtr: Int8Array = len[selector_selCtr];

            while (gs <= ge) {
                let sfmap_i: number = sfmap[gs];


                while (bsLiveShadow >= 8) {
                    outShadow.write(bsBuffShadow >> 24);
                    bsBuffShadow <<= 8;
                    bsLiveShadow -= 8;
                }
                let n: number = len_selCtr[sfmap_i] & 0xFF;
                bsBuffShadow |= code_selCtr[sfmap_i] << (32 - bsLiveShadow - n);
                bsLiveShadow += n;

                gs++;
            }

            gs = ge + 1;
            selCtr++;
        }

        this.bsBuff = bsBuffShadow;
        this.bsLive = bsLiveShadow;
    }

    private moveToFrontCodeAndSend(): void {
        this.bsW(24, this.data.origPtr);
        this.generateMTFValues();
        this.sendMTFValues();
    }

    private blockSort(): void {
        this.blockSorter.blockSort(this.data, this.last);
    }

    private generateMTFValues(): void {
        let lastShadow: number = this.last;
        let dataShadow: Data = this.data;
        let inUse: Array<boolean> = dataShadow.inUse;
        let block: Int8Array = dataShadow.block;
        let fmap: Int32Array = dataShadow.fmap;
        let sfmap: Int32Array = dataShadow.sfmap;
        let mtfFreq: Int32Array = dataShadow.mtfFreq;
        let unseqToSeq: Int8Array = dataShadow.unseqToSeq;
        let yy: Int8Array = dataShadow.generateMTFValues_yy;


        let nInUseShadow: number = 0;
        for (let i: number = 0; i < 256; i++) {
            if (inUse[i]) {
                unseqToSeq[i] = nInUseShadow;
                nInUseShadow++;
            }
        }
        this.nInUse = nInUseShadow;

        let eob: number = nInUseShadow + 1;

        for (let i: number = eob; i >= 0; i--) {
            mtfFreq[i] = 0;
        }

        for (let i: number = nInUseShadow; --i >= 0; ) {
            yy[i] = i;
        }

        let wr: number = 0;
        let zPend: number = 0;

        for (let i: number = 0; i <= lastShadow; i++) {
            let ll_i: number = unseqToSeq[block[fmap[i]] & 0xff];
            let tmp: number = yy[0];
            let j: number = 0;

            while (ll_i != tmp) {
                j++;
                let tmp2: number = tmp;
                tmp = yy[j];
                yy[j] = tmp2;
            }
            yy[0] = tmp;

            if (j == 0) {
                zPend++;
            } else {
                if (zPend > 0) {
                    zPend--;
                    while (true) {
                        if ((zPend & 1) == 0) {
                            sfmap[wr] = BZip2Constants.RUNA;
                            wr++;
                            mtfFreq[BZip2Constants.RUNA]++;
                        } else {
                            sfmap[wr] = BZip2Constants.RUNB;
                            wr++;
                            mtfFreq[BZip2Constants.RUNB]++;
                        }

                        if (zPend < 2) {
                            break;
                        }
                        zPend = (zPend - 2) >> 1;
                    }
                    zPend = 0;
                }
                sfmap[wr] = (j + 1);
                wr++;
                mtfFreq[j + 1]++;
            }
        }

        if (zPend > 0) {
            zPend--;
            while (true) {
                if ((zPend & 1) == 0) {
                    sfmap[wr] = BZip2Constants.RUNA;
                    wr++;
                    mtfFreq[BZip2Constants.RUNA]++;
                } else {
                    sfmap[wr] = BZip2Constants.RUNB;
                    wr++;
                    mtfFreq[BZip2Constants.RUNB]++;
                }

                if (zPend < 2) {
                    break;
                }
                zPend = (zPend - 2) >> 1;
            }
        }

        sfmap[wr] = eob;
        mtfFreq[eob]++;
        this.nMTF = wr + 1;
    }
}

export { Data, BZip2CompressorOutputStream }