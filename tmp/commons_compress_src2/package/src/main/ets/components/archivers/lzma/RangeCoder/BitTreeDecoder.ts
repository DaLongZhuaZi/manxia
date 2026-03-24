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
import Decoder from './Decoder';

export default class BitTreeDecoder {
    Models: Int16Array;
    NumBitLevels: number;

    constructor(numBitLevels: number) {
        this.NumBitLevels = numBitLevels;
        this.Models = new Int16Array(1 << numBitLevels);
    }

    public Init(): void
    {
        Decoder.InitBitModels(this.Models);
    }

    public Decode(rangeDecoder: Decoder): number
    {
        let m: number = 1;
        for (let bitIndex: number = this.NumBitLevels; bitIndex != 0; bitIndex--)
        m = (m << 1) + rangeDecoder.DecodeBit(this.Models, m);
        return m - (1 << this.NumBitLevels);
    }

    public ReverseDecode(rangeDecoder: Decoder): number
    {
        let m: number = 1;
        let symbolValue: number = 0;
        for (let bitIndex = 0; bitIndex < this.NumBitLevels; bitIndex++) {
            let bit: number = rangeDecoder.DecodeBit(this.Models, m);
            m <<= 1;
            m += bit;
            symbolValue |= (bit << bitIndex);
        }
        return symbolValue;
    }

    public static ReverseDecode(Models: Int16Array, startIndex: number,
                                rangeDecoder: Decoder, NumBitLevels: number): number
    {
        let m: number = 1;
        let symbolValue: number = 0;
        for (let bitIndex = 0; bitIndex < NumBitLevels; bitIndex++) {
            let bit = rangeDecoder.DecodeBit(Models, startIndex + m);
            m <<= 1;
            m += bit;
            symbolValue |= (bit << bitIndex);
        }
        return symbolValue;
    }
}
