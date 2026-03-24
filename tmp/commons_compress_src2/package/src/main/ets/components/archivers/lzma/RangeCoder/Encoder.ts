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
import OutputStream from '../../../util/OutputStream';
import Long from "../../../util/long/index";

export default class Encoder {
    static kTopMask: number = ~((1 << 24) - 1);
    static kNumBitModelTotalBits: number = 11;
    static kBitModelTotal: number = (1 << Encoder.kNumBitModelTotalBits);
    static kNumMoveBits: number = 5;
    Stream: OutputStream;
    Low: Long;
    Range: number;
    _cacheSize: number;
    _cache: number;
    _position: Long;

    public SetStream(stream: OutputStream): void
    {
        this.Stream = stream;
    }

    public ReleaseStream(): void
    {
        this.Stream = null;
    }

    public Init(): void
    {
        this._position = Long.fromNumber(0);
        this.Low = new Long(0, 0, true);
        this.Range = -1;
        this._cacheSize = 1;
        this._cache = 0;
    }

    public FlushData(): void
    {
        for (let i = 0; i < 5; i++)
        this.ShiftLow();
    }

    public FlushStream(): void
    {
        this.Stream.flush();
    }

    public ShiftLow(): void
    {
        let LowHi = this.Low.shiftRightUnsigned(32).toInt();
        if (LowHi != 0 || this.Low.lessThan(0xFF000000)) {
            this._position = this._position.add(this._cacheSize);
            let temp: number = this._cache;
            do
            {
                this.Stream.write(temp + LowHi);
                temp = 0xFF;
            }
            while (--this._cacheSize != 0);
            this._cache = this.Low.toInt() >>> 24;
        }
        this._cacheSize++;
        this.Low = this.Low.and(0xFFFFFF).shiftLeft(8).toSigned();
    }

    public EncodeDirectBits(v: number, numTotalBits: number): void
    {
        for (let i = numTotalBits - 1; i >= 0; i--) {
            this.Range >>>= 1;
            if (((v >>> i) & 1) == 1)
            this.Low = this.Low.add(this.Range).toSigned();
            if ((this.Range & Encoder.kTopMask) == 0) {
                this.Range <<= 8;
                this.ShiftLow();
            }
        }
    }

    public GetProcessedSizeAdd(): number
    {
        return this._position.add(this._cacheSize + 4).toNumber();
    }

    static kNumMoveReducingBits: number = 2;
    public static kNumBitPriceShiftBits: number = 6;

    public static InitBitModels(probs: Int16Array): void
    {
        for (let i = 0; i < probs.length; i++)
        probs[i] = (Encoder.kBitModelTotal >>> 1);
    }

    public Encode(probs: Int16Array, index: number, symbolValue: number): void
    {
        let prob: number = probs[index];
        let newBound: number = Long.fromNumber((this.Range >>> Encoder.kNumBitModelTotalBits) * prob).getLowBits();
        if (symbolValue == 0) {
            this.Range = newBound;
            probs[index] = parseInt((prob + ((Encoder.kBitModelTotal - prob) >>> Encoder.kNumMoveBits)) + '');
        } else {
            this.Low = this.Low.add(Long.fromNumber(0xFFFFFFFF).and(newBound)).toSigned();
            this.Range -= newBound;
            probs[index] = parseInt((prob - ((prob) >>> Encoder.kNumMoveBits)) + '');
        }
        if ((this.Range & Encoder.kTopMask) == 0) {
            this.Range <<= 8;
            this.ShiftLow();
        }
    }

    private static ProbPrices: Int32Array = new Int32Array(Encoder.kBitModelTotal >>> Encoder.kNumMoveReducingBits);

    public static staticInit(): void
    {
        let kNumBits: number = (Encoder.kNumBitModelTotalBits - Encoder.kNumMoveReducingBits);
        for (let i = kNumBits - 1; i >= 0; i--) {
            let start: number = 1 << (kNumBits - i - 1);
            let end: number = 1 << (kNumBits - i);
            for (let j = start; j < end; j++)
            Encoder.ProbPrices[j] = (i << Encoder.kNumBitPriceShiftBits) +
            (((end - j) << Encoder.kNumBitPriceShiftBits) >>> (kNumBits - i - 1));
        }
    }

    static GetPrice(Prob: number, symbolValue: number): number
    {
        return Encoder.ProbPrices[(((Prob - symbolValue) ^ ((-symbolValue))) & (Encoder.kBitModelTotal - 1)) >>> Encoder.kNumMoveReducingBits];
    }

    static GetPriceReducingBits(Prob: number): number
    {
        return Encoder.ProbPrices[Prob >>> Encoder.kNumMoveReducingBits];
    }

    static GetPriceModelTotal(Prob: number): number
    {
        return Encoder.ProbPrices[(Encoder.kBitModelTotal - Prob) >>> Encoder.kNumMoveReducingBits];
    }
}

Encoder.staticInit()