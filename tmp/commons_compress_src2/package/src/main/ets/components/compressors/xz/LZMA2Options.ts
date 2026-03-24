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
import FilterOptions from './FilterOptions'
import Exception from '../../util/Exception'
import InputStream from '../../util/InputStream'
import UncompressedLZMA2OutputStream from './UncompressedLZMA2OutputStream'
import LZMA2OutputStream from './LZMA2OutputStream'
import LZMA2InputStream from './LZMA2InputStream'
import type FilterEncoder from './FilterEncoder'
import ArrayCache from './ArrayCache'
import FinishableOutputStream from './FinishableOutputStream'
import LZMA2Encoder from './LZMA2Encoder'
import LZMAEncoder from './lzma/LZMAEncoder'
import LZEncoder from './lz/LZEncoder'

export default class LZMA2Options extends FilterOptions {
    public static PRESET_MIN: number = 0;
    public static PRESET_MAX: number = 9;
    public static PRESET_DEFAULT: number = 6;
    public static DICT_SIZE_MIN: number = 4096;
    public static DICT_SIZE_MAX: number = 768 << 20;
    public static DICT_SIZE_DEFAULT: number = 8 << 20;
    public static LC_LP_MAX: number = 4;
    public static LC_DEFAULT: number = 3;
    public static LP_DEFAULT: number = 0;
    public static PB_MAX: number = 4;
    public static PB_DEFAULT: number = 2;
    public static MODE_UNCOMPRESSED: number = 0;
    public static MODE_FAST: number = LZMAEncoder.MODE_FAST;
    public static MODE_NORMAL: number = LZMAEncoder.MODE_NORMAL;
    public static NICE_LEN_MIN: number = 8;
    public static NICE_LEN_MAX: number = 273;
    public static MF_HC4 = LZEncoder.MF_HC4;
    public static MF_BT4 = LZEncoder.MF_BT4;
    private static presetToDictSize: Int32Array = new Int32Array([
        1 << 18, 1 << 20, 1 << 21, 1 << 22, 1 << 22,
        1 << 23, 1 << 23, 1 << 24, 1 << 25, 1 << 26]);
    private static presetToDepthLimit: Int32Array = new Int32Array([4, 8, 24, 48]);
    private dictSize: number = 0;
    private presetDict = null;
    private lc: number = 0;
    private lp: number = 0;
    private pb: number = 0;
    private mode: number = 0;
    private niceLen: number = 0;
    private mf: number = 0;
    private depthLimit: number = 0;

    public constructor() {
        super()
        try {
            this.setPreset(LZMA2Options.PRESET_DEFAULT);
        } catch (e) {
            false;
            throw new Exception();
        }
    }

    public setPreset(preset: number): void {
        if (preset >= 0 && preset <= 9) {
            this.lc = LZMA2Options.LC_DEFAULT;
            this.lp = LZMA2Options.LP_DEFAULT;
            this.pb = LZMA2Options.PB_DEFAULT;
            this.dictSize = LZMA2Options.presetToDictSize[preset];
            if (preset <= 3) {
                this.mode = LZMA2Options.MODE_FAST;
                this.mf = LZMA2Options.MF_HC4;
                this.niceLen = preset <= 1 ? 128 : LZMA2Options.NICE_LEN_MAX;
                this.depthLimit = LZMA2Options.presetToDepthLimit[preset];
            } else {
                this.mode = LZMA2Options.MODE_NORMAL;
                this.mf = LZMA2Options.MF_BT4;
                this.niceLen = preset == 4 ? 16 : (preset == 5 ? 32 : 64);
                this.depthLimit = 0;
            }

        } else {
            throw new Exception("Unsupported preset: " + preset);
        }
    }

    public setDictSize(dictSize: number): void{
        if (dictSize < 4096) {
            throw new Exception("LZMA2 dictionary size must be at least 4 KiB: " + dictSize + " B");
        } else if (dictSize > 805306368) {
            throw new Exception("LZMA2 dictionary size must not exceed 768 MiB: " + dictSize + " B");
        } else {
            this.dictSize = dictSize;
        }
    }

    public getDictSize(): number {
        return this.dictSize;
    }

    public setPresetDict(presetDict: Int8Array): void {
        this.presetDict = presetDict;
    }

    public getPresetDict(): Int8Array {
        return this.presetDict;
    }

    public setLcLp(lc: number, lp: number): void {
        if (lc >= 0 && lp >= 0 && lc <= 4 && lp <= 4 && lc + lp <= 4) {
            this.lc = lc;
            this.lp = lp;
        } else {
            throw new Exception("lc + lp must not exceed 4: " + lc + " + " + lp);
        }
    }

    public setLc(lc: number): void {
        this.setLcLp(lc, this.lp);
    }

    public setLp(lp: number): void {
        this.setLcLp(this.lc, lp);
    }

    public getLc(): number {
        return this.lc;
    }

    public getLp(): number {
        return this.lp;
    }

    public setPb(pb: number): void {
        if (pb >= 0 && pb <= 4) {
            this.pb = pb;
        } else {
            throw new Exception("pb must not exceed 4: " + pb);
        }
    }

    public getPb(): number {
        return this.pb;
    }

    public setMode(mode: number): void {
        if (mode >= 0 && mode <= 2) {
            this.mode = mode;
        } else {
            throw new Exception("Unsupported compression mode: " + mode);
        }
    }

    public getMode(): number {
        return this.mode;
    }

    public setNiceLen(niceLen: number): void {
        if (niceLen < 8) {
            throw new Exception("Minimum nice length of matches is 8 bytes: " + niceLen);
        } else if (niceLen > 273) {
            throw new Exception("Maximum nice length of matches is 273: " + niceLen);
        } else {
            this.niceLen = niceLen;
        }
    }

    public getNiceLen(): number {
        return this.niceLen;
    }

    public setMatchFinder(mf: number): void{
        if (mf != 4 && mf != 20) {
            throw new Exception("Unsupported match finder: " + mf);
        } else {
            this.mf = mf;
        }
    }

    public getMatchFinder(): number {
        return this.mf;
    }

    public setDepthLimit(depthLimit: number): void {
        if (depthLimit < 0) {
            throw new Exception("Depth limit cannot be negative: " + depthLimit);
        } else {
            this.depthLimit = depthLimit;
        }
    }

    public getDepthLimit(): number {
        return this.depthLimit;
    }

    public getEncoderMemoryUsage(): number {
        return this.mode == 0 ? UncompressedLZMA2OutputStream.getMemoryUsage() : LZMA2OutputStream.getMemoryUsage(this);
    }

    public getOutputStream(out: FinishableOutputStream, arrayCache: ArrayCache): FinishableOutputStream {
        if (this.mode == LZMA2Options.MODE_UNCOMPRESSED) {
            return new UncompressedLZMA2OutputStream(out, arrayCache);
        }
        return new LZMA2OutputStream(out, this, arrayCache);
    }

    public getDecoderMemoryUsage(): number {
        let d = this.dictSize - 1;
        d |= d >>> 2;
        d |= d >>> 3;
        d |= d >>> 4;
        d |= d >>> 8;
        d |= d >>> 16;
        return LZMA2InputStream.getMemoryUsage(d + 1);
    }

    public getInputStreamArray(input: InputStream, arrayCache: ArrayCache): InputStream {
        return new LZMA2InputStream(input, this.dictSize, this.presetDict, arrayCache);
    }

    getFilterEncoder(): FilterEncoder {
        return new LZMA2Encoder(this);
    }

    public clone(): any {
        try {
            return new Exception("Class doesn't implement Cloneable");
        } catch (e) {
            false;

            throw new Exception();
        }
    }
}
