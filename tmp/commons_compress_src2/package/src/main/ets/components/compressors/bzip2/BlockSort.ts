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
import { Data } from './BZip2CompressorOutputStream';
import BZip2Constants from './BZip2Constants';
import Long from "../../util/long/index";

export default class BlockSort {
    private static QSORT_STACK_SIZE: number = 1000;
    private static FALLBACK_QSORT_STACK_SIZE: number = 100;
    private static STACK_SIZE: number =
            BlockSort.QSORT_STACK_SIZE < BlockSort.FALLBACK_QSORT_STACK_SIZE
            ? BlockSort.FALLBACK_QSORT_STACK_SIZE : BlockSort.QSORT_STACK_SIZE;
    private workDone: number;
    private workLimit: number;
    private firstAttempt: boolean;
    private stack_ll: Int32Array = new Int32Array(BlockSort.STACK_SIZE); // 4000 byte
    private stack_hh: Int32Array = new Int32Array(BlockSort.STACK_SIZE); // 4000 byte
    private stack_dd: Int32Array = new Int32Array(BlockSort.QSORT_STACK_SIZE); // 4000 byte

    private mainSort_runningOrder: Int32Array = new Int32Array(256); // 1024 byte
    private mainSort_copy: Int32Array = new Int32Array(256); // 1024 byte
    private mainSort_bigDone: Array<boolean> = new Array<boolean>(256); // 256 byte

    private ftab: Int32Array = new Int32Array(65537); // 262148 byte

    private quadrant: Int32Array;

    constructor(data: Data) {
        this.quadrant = data.sfmap;
    }

    blockSort(data: Data, last: number): void {
        this.workLimit = BlockSort.WORK_FACTOR * last;
        this.workDone = 0;
        this.firstAttempt = true;

        if (last + 1 < 10000) {
            this.fallbackSort(data, last);
        } else {
            this.mainSort(data, last);

            if (this.firstAttempt && (this.workDone > this.workLimit)) {
                this.fallbackSort(data, last);
            }
        }

        let fmap: Int32Array = data.fmap;
        data.origPtr = -1;
        for (let i: number = 0; i <= last; i++) {
            if (fmap[i] == 0) {
                data.origPtr = i;
                break;
            }
        }

    }

    fallbackSort(data: Data, last: number): void {
        data.block[0] = data.block[last + 1];
        this.fallbackSort3(data.fmap, data.block, last + 1);
        for (let i: number = 0; i < last + 1; i++) {
            --data.fmap[i];
        }
        for (let i: number = 0; i < last + 1; i++) {
            if (data.fmap[i] == -1) {
                data.fmap[i] = last;
                break;
            }
        }
    }

    private fallbackSimpleSort(fmap: Int32Array,
                               eclass: Int32Array,
                               lo: number,
                               hi: number): void {
        if (lo == hi) {
            return;
        }

        let j: number;
        if (hi - lo > 3) {
            for (let i: number = hi - 4; i >= lo; i--) {
                let tmp: number = fmap[i];
                let ec_tmp: number = eclass[tmp];
                for (j = i + 4; j <= hi && ec_tmp > eclass[fmap[j]];
                     j += 4) {
                    fmap[j - 4] = fmap[j];
                }
                fmap[j - 4] = tmp;
            }
        }

        for (let i: number = hi - 1; i >= lo; i--) {
            let tmp: number = fmap[i];
            let ec_tmp: number = eclass[tmp];
            for (j = i + 1; j <= hi && ec_tmp > eclass[fmap[j]]; j++) {
                fmap[j - 1] = fmap[j];
            }
            fmap[j-1] = tmp;
        }
    }

    private static FALLBACK_QSORT_SMALL_THRESH: number = 10;

    private fswap(fmap: Int32Array, zz1: number, zz2: number): void {
        let zztmp: number = fmap[zz1];
        fmap[zz1] = fmap[zz2];
        fmap[zz2] = zztmp;
    }

    private fvswap(fmap: Int32Array, yyp1: number, yyp2: number, yyn: number): void {
        while (yyn > 0) {
            this.fswap(fmap, yyp1, yyp2);
            yyp1++;
            yyp2++;
            yyn--;
        }
    }

    private fmin(a: number, b: number): number {
        return a < b ? a : b;
    }

    private fpush(sp: number, lz: number, hz: number): void {
        this.stack_ll[sp] = lz;
        this.stack_hh[sp] = hz;
    }

    private fpop(sp: number): Int32Array {
        return new Int32Array([this.stack_ll[sp], this.stack_hh[sp]]);
    }

    private fallbackQSort3(fmap: Int32Array,
                           eclass: Int32Array,
                           loSt: number,
                           hiSt: number): void {
        let lo: number, unLo: number, ltLo: number, hi: number, unHi: number, gtHi: number, n: number;

        let r: Long = Long.fromNumber(0);
        let sp: number = 0;
        this.fpush(sp++, loSt, hiSt);

        while (sp > 0) {
            let s: Int32Array = this.fpop(--sp);
            lo = s[0];
            hi = s[1];

            if (hi - lo < BlockSort.FALLBACK_QSORT_SMALL_THRESH) {
                this.fallbackSimpleSort(fmap, eclass, lo, hi);
                continue;
            }

            r = r.mul(7621).add(1).rem(32768);
            let r3: Long = r.rem(3);
            let med: Long;
            if (r3.eq(0)) {
                med = Long.fromNumber(eclass[fmap[lo]]);
            } else if (r3.eq(1)) {
                med = Long.fromNumber(eclass[fmap[(lo + hi) >>> 1]]);
            } else {
                med = Long.fromNumber(eclass[fmap[hi]]);
            }

            unLo = ltLo = lo;
            unHi = gtHi = hi;

            while (true) {
                while (true) {
                    if (unLo > unHi) {
                        break;
                    }
                    n = eclass[fmap[unLo]] - med.toNumber();
                    if (n == 0) {
                        this.fswap(fmap, unLo, ltLo);
                        ltLo++;
                        unLo++;
                        continue;
                    }
                    if (n > 0) {
                        break;
                    }
                    unLo++;
                }
                while (true) {
                    if (unLo > unHi) {
                        break;
                    }
                    n = eclass[fmap[unHi]] - med.toNumber();
                    if (n == 0) {
                        this.fswap(fmap, unHi, gtHi);
                        gtHi--;
                        unHi--;
                        continue;
                    }
                    if (n < 0) {
                        break;
                    }
                    unHi--;
                }
                if (unLo > unHi) {
                    break;
                }
                this.fswap(fmap, unLo, unHi);
                unLo++;
                unHi--;
            }

            if (gtHi < ltLo) {
                continue;
            }

            n = this.fmin(ltLo - lo, unLo - ltLo);
            this.fvswap(fmap, lo, unLo - n, n);
            let m: number = this.fmin(hi - gtHi, gtHi - unHi);
            this.fvswap(fmap, unHi + 1, hi - m + 1, m);

            n = lo + unLo - ltLo - 1;
            m = hi - (gtHi - unHi) + 1;

            if (n - lo > hi - m) {
                this.fpush(sp++, lo, n);
                this.fpush(sp++, m, hi);
            } else {
                this.fpush(sp++, m, hi);
                this.fpush(sp++, lo, n);
            }
        }
    }

    private eclass: Int32Array;

    private getEclass(): Int32Array {
        if (this.eclass == null) {
            this.eclass = new Int32Array(this.quadrant.length / 2);
        }
        return this.eclass;
    }

    fallbackSort3(fmap: Int32Array, block: Int8Array, nblock: number): void {
        let ftab: Int32Array = new Int32Array(257);
        let H: number, i: number, j: number, k: number, l: number, r: number, cc: number, cc1: number;
        let nNotDone: number;
        let nBhtab: number;
        let eclass: Int32Array = this.getEclass();

        for (i = 0; i < nblock; i++) {
            eclass[i] = 0;
        }

        for (i = 0; i < nblock; i++) {
            ftab[block[i] & 0xff]++;
        }
        for (i = 1; i < 257; i++) {
            ftab[i] += ftab[i - 1];
        }

        for (i = 0; i < nblock; i++) {
            j = block[i] & 0xff;
            k = ftab[j] - 1;
            ftab[j] = k;
            fmap[k] = i;
        }

        nBhtab = 64 + nblock;

        // Analog java BitSet class
        let bhtab: Array<boolean> = new Array<boolean>(nBhtab);
        for (i = 0; i < nBhtab; i++) {
            bhtab[i] = false;
        }
        for (i = 0; i < 256; i++) {
            bhtab[ftab[i]] = true;
        }


        for (i = 0; i < 32; i++) {
            bhtab[nblock + 2 * i] = true;
            bhtab[nblock + 2 * i + 1] = false;
        }

        H = 1;
        while (true) {

            j = 0;
            for (i = 0; i < nblock; i++) {
                if (bhtab[i]) {
                    j = i;
                }
                k = fmap[i] - H;
                if (k < 0) {
                    k += nblock;
                }
                eclass[k] = j;
            }

            nNotDone = 0;
            r = -1;
            while (true) {

                k = r + 1;
                for (let index = k; index < bhtab.length; index++) {
                    if (!bhtab[index]) {
                        k = index;
                        break;
                    }
                    if (index == (bhtab.length - 1)) {
                        k = -1;
                    }
                }
                l = k - 1;
                if (l >= nblock) {
                    break;
                }
                for (let index = k + 1; index < bhtab.length; index++) {
                    if (bhtab[index]) {
                        k = index;
                        break;
                    }
                    if (index == (bhtab.length - 1)) {
                        k = -1;
                    }
                }
                r = k - 1;
                if (r >= nblock) {
                    break;
                }

                /*-- LBZ2: now [l, r] bracket current bucket --*/
                if (r > l) {
                    nNotDone += (r - l + 1);
                    this.fallbackQSort3(fmap, eclass, l, r);

                    /*-- LBZ2: scan bucket and generate header bits-- */
                    cc = -1;
                    for (i = l; i <= r; i++) {
                        cc1 = eclass[fmap[i]];
                        if (cc != cc1) {
                            bhtab[i] = true;
                            cc = cc1;
                        }
                    }
                }
            }

            H *= 2;
            if (H > nblock || nNotDone == 0) {
                break;
            }
        }
    }

    private static INCS: Int32Array = new Int32Array([1, 4, 13, 40, 121, 364, 1093, 3280,
    9841, 29524, 88573, 265720, 797161,
    2391484]);

    private mainSimpleSort(dataShadow: Data, lo: number, hi: number, d: number, lastShadow: number): boolean {
        let bigN: number = hi - lo + 1;
        if (bigN < 2) {
            return this.firstAttempt && (this.workDone > this.workLimit);
        }

        let hp: number = 0;
        while (BlockSort.INCS[hp] < bigN) {
            hp++;
        }

        let fmap: Int32Array = dataShadow.fmap;
        let quadrant: Int32Array = this.quadrant;
        let block: Int8Array = dataShadow.block;
        let lastPlus1: number = lastShadow + 1;
        let firstAttemptShadow: boolean = this.firstAttempt;
        let workLimitShadow: number = this.workLimit;
        let workDoneShadow: number = this.workDone;


        HP: while (--hp >= 0) {
            let h: number = BlockSort.INCS[hp];
            let mj: number = lo + h - 1;

            for (let i: number = lo + h; i <= hi; ) {
                // copy
                for (let k: number = 3; (i <= hi) && (--k >= 0); i++) {
                    let v: number = fmap[i];
                    let vd: number = v + d;
                    let j: number = i;


                    let onceRunned: boolean = false;
                    let a: number = 0;

                    HAMMER: while (true) {
                        if (onceRunned) {
                            fmap[j] = a;
                            if ((j -= h) <= mj) { //NOSONAR
                                break HAMMER;
                            }
                        } else {
                            onceRunned = true;
                        }

                        a = fmap[j - h];
                        let i1: number = a + d;
                        let i2: number = vd;

                        if (block[i1 + 1] == block[i2 + 1]) {
                            if (block[i1 + 2] == block[i2 + 2]) {
                                if (block[i1 + 3] == block[i2 + 3]) {
                                    if (block[i1 + 4] == block[i2 + 4]) {
                                        if (block[i1 + 5] == block[i2 + 5]) {
                                            if (block[(i1 += 6)] == block[(i2 += 6)]) { //NOSONAR
                                                let x: number = lastShadow;
                                                X: while (x > 0) {
                                                    x -= 4;
                                                    if (block[i1 + 1] == block[i2 + 1]) {
                                                        if (quadrant[i1] == quadrant[i2]) {
                                                            if (block[i1 + 2] == block[i2 + 2]) {
                                                                if (quadrant[i1 + 1] == quadrant[i2 + 1]) {
                                                                    if (block[i1 + 3] == block[i2 + 3]) {
                                                                        if (quadrant[i1 + 2] == quadrant[i2 + 2]) {
                                                                            if (block[i1 + 4] == block[i2 + 4]) {
                                                                                if (quadrant[i1 + 3] == quadrant[i2 + 3]) {
                                                                                    if ((i1 += 4) >= lastPlus1) { //NOSONAR
                                                                                        i1 -= lastPlus1;
                                                                                    }
                                                                                    if ((i2 += 4) >= lastPlus1) { //NOSONAR
                                                                                        i2 -= lastPlus1;
                                                                                    }
                                                                                    workDoneShadow++;
                                                                                    continue X;
                                                                                }
                                                                                if ((quadrant[i1 + 3] > quadrant[i2 + 3])) {
                                                                                    continue HAMMER;
                                                                                }
                                                                                break HAMMER;
                                                                            }
                                                                            if ((block[i1 + 4] & 0xff) > (block[i2 + 4] & 0xff)) {
                                                                                continue HAMMER;
                                                                            }
                                                                            break HAMMER;
                                                                        }
                                                                        if ((quadrant[i1 + 2] > quadrant[i2 + 2])) {
                                                                            continue HAMMER;
                                                                        }
                                                                        break HAMMER;
                                                                    }
                                                                    if ((block[i1 + 3] & 0xff) > (block[i2 + 3] & 0xff)) {
                                                                        continue HAMMER;
                                                                    }
                                                                    break HAMMER;
                                                                }
                                                                if ((quadrant[i1 + 1] > quadrant[i2 + 1])) {
                                                                    continue HAMMER;
                                                                }
                                                                break HAMMER;
                                                            }
                                                            if ((block[i1 + 2] & 0xff) > (block[i2 + 2] & 0xff)) {
                                                                continue HAMMER;
                                                            }
                                                            break HAMMER;
                                                        }
                                                        if ((quadrant[i1] > quadrant[i2])) {
                                                            continue HAMMER;
                                                        }
                                                        break HAMMER;
                                                    }
                                                    if ((block[i1 + 1] & 0xff) > (block[i2 + 1] & 0xff)) {
                                                        continue HAMMER;
                                                    }
                                                    break HAMMER;

                                                }
                                                break HAMMER;
                                            } // while x > 0
                                            if ((block[i1] & 0xff) > (block[i2] & 0xff)) {
                                                continue HAMMER;
                                            }
                                            break HAMMER;
                                        }
                                        if ((block[i1 + 5] & 0xff) > (block[i2 + 5] & 0xff)) {
                                            continue HAMMER;
                                        }
                                        break HAMMER;
                                    }
                                    if ((block[i1 + 4] & 0xff) > (block[i2 + 4] & 0xff)) {
                                        continue HAMMER;
                                    }
                                    break HAMMER;
                                }
                                if ((block[i1 + 3] & 0xff) > (block[i2 + 3] & 0xff)) {
                                    continue HAMMER;
                                }
                                break HAMMER;
                            }
                            if ((block[i1 + 2] & 0xff) > (block[i2 + 2] & 0xff)) {
                                continue HAMMER;
                            }
                            break HAMMER;
                        }
                        if ((block[i1 + 1] & 0xff) > (block[i2 + 1] & 0xff)) {
                            continue HAMMER;
                        }
                        break HAMMER;

                    }

                    fmap[j] = v;
                }

                if (firstAttemptShadow && (i <= hi)
                && (workDoneShadow > workLimitShadow)) {
                    break HP;
                }
            }
        }

        this.workDone = workDoneShadow;
        return firstAttemptShadow && (workDoneShadow > workLimitShadow);
    }

    private static vswap(fmap: Int32Array, p1: number, p2: number, n: number): void {
        n += p1;
        while (p1 < n) {
            let t: number = fmap[p1];
            fmap[p1++] = fmap[p2];
            fmap[p2++] = t;
        }
    }

    private static med3(a: number, b: number, c: number): number {
        return (a < b) ? (b < c ? b : a < c ? c : a) : (b > c ? b : a > c ? c
                                                                          : a);
    }

    private static SMALL_THRESH: number = 20;
    private static DEPTH_THRESH: number = 10;
    private static WORK_FACTOR: number = 30;

    private mainQSort3(dataShadow: Data,
                       loSt: number, hiSt: number, dSt: number,
                       last: number): void {
        let stack_ll: Int32Array = this.stack_ll;
        let stack_hh: Int32Array = this.stack_hh;
        let stack_dd: Int32Array = this.stack_dd;
        let fmap: Int32Array = dataShadow.fmap;
        let block: Int8Array = dataShadow.block;

        stack_ll[0] = loSt;
        stack_hh[0] = hiSt;
        stack_dd[0] = dSt;

        for (let sp: number = 1; --sp >= 0; ) {
            let lo: number = stack_ll[sp];
            let hi: number = stack_hh[sp];
            let d: number = stack_dd[sp];

            if ((hi - lo < BlockSort.SMALL_THRESH) || (d > BlockSort.DEPTH_THRESH)) {
                if (this.mainSimpleSort(dataShadow, lo, hi, d, last)) {
                    return;
                }
            } else {
                let d1: number = d + 1;
                let med: number = BlockSort.med3(block[fmap[lo] + d1],
                    block[fmap[hi] + d1], block[fmap[(lo + hi) >>> 1] + d1]) & 0xff;

                let unLo: number = lo;
                let unHi: number = hi;
                let ltLo: number = lo;
                let gtHi: number = hi;

                while (true) {
                    while (unLo <= unHi) {
                        let n: number = (block[fmap[unLo] + d1] & 0xff)
                        - med;
                        if (n == 0) {
                            let temp: number = fmap[unLo];
                            fmap[unLo++] = fmap[ltLo];
                            fmap[ltLo++] = temp;
                        } else if (n < 0) {
                            unLo++;
                        } else {
                            break;
                        }
                    }

                    while (unLo <= unHi) {
                        let n: number = (block[fmap[unHi] + d1] & 0xff)
                        - med;
                        if (n == 0) {
                            let temp: number = fmap[unHi];
                            fmap[unHi--] = fmap[gtHi];
                            fmap[gtHi--] = temp;
                        } else if (n > 0) {
                            unHi--;
                        } else {
                            break;
                        }
                    }

                    if (unLo > unHi) {
                        break;
                    }
                    let temp: number = fmap[unLo];
                    fmap[unLo++] = fmap[unHi];
                    fmap[unHi--] = temp;
                }

                if (gtHi < ltLo) {
                    stack_ll[sp] = lo;
                    stack_hh[sp] = hi;
                    stack_dd[sp] = d1;
                    sp++;
                } else {
                    let n: number = ((ltLo - lo) < (unLo - ltLo)) ? (ltLo - lo)
                                                                  : (unLo - ltLo);
                    BlockSort.vswap(fmap, lo, unLo - n, n);
                    let m: number = ((hi - gtHi) < (gtHi - unHi)) ? (hi - gtHi)
                                                                  : (gtHi - unHi);
                    BlockSort.vswap(fmap, unLo, hi - m + 1, m);

                    n = lo + unLo - ltLo - 1;
                    m = hi - (gtHi - unHi) + 1;

                    stack_ll[sp] = lo;
                    stack_hh[sp] = n;
                    stack_dd[sp] = d;
                    sp++;

                    stack_ll[sp] = n + 1;
                    stack_hh[sp] = m - 1;
                    stack_dd[sp] = d1;
                    sp++;

                    stack_ll[sp] = m;
                    stack_hh[sp] = hi;
                    stack_dd[sp] = d;
                    sp++;
                }
            }
        }
    }

    private static SETMASK: number = (1 << 21);
    private static CLEARMASK: number = (~BlockSort.SETMASK);

    mainSort(dataShadow: Data, lastShadow: number): void {
        let runningOrder: Int32Array = this.mainSort_runningOrder;
        let copy: Int32Array = this.mainSort_copy;
        let bigDone: Array<boolean> = this.mainSort_bigDone;
        let ftab: Int32Array = this.ftab;
        let block: Int8Array = dataShadow.block;
        let fmap: Int32Array = dataShadow.fmap;
        let quadrant: Int32Array = this.quadrant;
        let workLimitShadow: number = this.workLimit;
        let firstAttemptShadow: boolean = this.firstAttempt;

        for (let i: number = 65537; --i >= 0; ) {
            ftab[i] = 0;
        }

        for (let i: number = 0; i < BZip2Constants.NUM_OVERSHOOT_BYTES; i++) {
            block[lastShadow + i + 2] = block[(i % (lastShadow + 1)) + 1];
        }
        for (let i: number = lastShadow + BZip2Constants.NUM_OVERSHOOT_BYTES + 1; --i >= 0; ) {
            quadrant[i] = 0;
        }
        block[0] = block[lastShadow + 1];

        // LBZ2: Complete the initial radix sort:

        let c1: number = block[0] & 0xff;
        for (let i: number = 0; i <= lastShadow; i++) {
            let c2: number = block[i + 1] & 0xff;
            ftab[(c1 << 8) + c2]++;
            c1 = c2;
        }

        for (let i: number = 1; i <= 65536; i++) {
            ftab[i] += ftab[i - 1];
        }

        c1 = block[1] & 0xff;
        for (let i: number = 0; i < lastShadow; i++) {
            let c2: number = block[i + 2] & 0xff;
            fmap[--ftab[(c1 << 8) + c2]] = i;
            c1 = c2;
        }

        fmap[--ftab[((block[lastShadow + 1] & 0xff) << 8) + (block[1] & 0xff)]] = lastShadow;

        for (let i: number = 256; --i >= 0; ) {
            bigDone[i] = false;
            runningOrder[i] = i;
        }

        for (let h: number = 364; h != 1; ) { //NOSONAR
            h /= 3;
            for (let i: number = h; i <= 255; i++) {
                let vv: number = runningOrder[i];
                let a: number = ftab[(vv + 1) << 8] - ftab[vv << 8];
                let b: number = h - 1;
                let j: number = i;
                for (let ro: number = runningOrder[j - h]; (ftab[(ro + 1) << 8] - ftab[ro << 8]) > a;
                     ro = runningOrder[j- h]) {
                    runningOrder[j] = ro;
                    j -= h;
                    if (j <= b) {
                        break;
                    }
                }
                runningOrder[j] = vv;
            }
        }


        for (let i: number = 0; i <= 255; i++) {

            let ss: number = runningOrder[i];

            for (let j: number = 0; j <= 255; j++) {
                let sb: number = (ss << 8) + j;
                let ftab_sb: number = ftab[sb];
                if ((ftab_sb & BlockSort.SETMASK) != BlockSort.SETMASK) {
                    let lo: number = ftab_sb & BlockSort.CLEARMASK;
                    let hi: number = (ftab[sb + 1] & BlockSort.CLEARMASK) - 1;
                    if (hi > lo) {
                        this.mainQSort3(dataShadow, lo, hi, 2, lastShadow);
                        if (firstAttemptShadow
                        && (this.workDone > workLimitShadow)) {
                            return;
                        }
                    }
                    ftab[sb] = ftab_sb | BlockSort.SETMASK;
                }
            }


            for (let j: number = 0; j <= 255; j++) {
                copy[j] = ftab[(j << 8) + ss] & BlockSort.CLEARMASK;
            }

            for (let j: number = ftab[ss << 8] & BlockSort.CLEARMASK, hj = (ftab[(ss + 1) << 8] & BlockSort.CLEARMASK);
                 j < hj; j++) {
                let fmap_j: number = fmap[j];
                c1 = block[fmap_j] & 0xff;
                if (!bigDone[c1]) {
                    fmap[copy[c1]] = (fmap_j == 0) ? lastShadow : (fmap_j - 1);
                    copy[c1]++;
                }
            }

            for (let j: number = 256; --j >= 0; ) {
                ftab[(j << 8) + ss] |= BlockSort.SETMASK;
            }

            bigDone[ss] = true;

            if (i < 255) {
                let bbStart: number = ftab[ss << 8] & BlockSort.CLEARMASK;
                let bbSize: number = (ftab[(ss + 1) << 8] & BlockSort.CLEARMASK) - bbStart;
                let shifts: number = 0;

                while ((bbSize >> shifts) > 65534) {
                    shifts++;
                }

                for (let j: number = 0; j < bbSize; j++) {
                    let a2update: number = fmap[bbStart + j];
                    let qVal: number = (j >> shifts);
                    quadrant[a2update] = qVal;
                    if (a2update < BZip2Constants.NUM_OVERSHOOT_BYTES) {
                        quadrant[a2update + lastShadow + 1] = qVal;
                    }
                }
            }

        }
    }
}
