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
import Encoder from './Encoder';

export default class BitTreeEncoder {
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

    public Encode(rangeEncoder: Encoder, symbol: number): void
    {
        let m: number = 1;
        for (let bitIndex = this.NumBitLevels; bitIndex != 0; ) {
            bitIndex--;
            let bit: number = (symbol >>> bitIndex) & 1;
            rangeEncoder.Encode(this.Models, m, bit);
            m = (m << 1) | bit;
        }
    }

    public ReverseEncode(rangeEncoder: Encoder, symbolValue: number): void
    {
        let m: number = 1;
        for (let i = 0; i < this.NumBitLevels; i++) {
            let bit = symbolValue & 1;
            rangeEncoder.Encode(this.Models, m, bit);
            m = (m << 1) | bit;
            symbolValue >>= 1;
        }
    }

    public GetPrice(symbolValue: number): number
    {
        let price: number = 0;
        let m: number = 1;
        for (let bitIndex = this.NumBitLevels; bitIndex != 0; ) {
            bitIndex--;
            let bit: number = (symbolValue >>> bitIndex) & 1;
            price += Encoder.GetPrice(this.Models[m], bit);
            m = (m << 1) + bit;
        }
        return price;
    }

    public ReverseGetPrice(symbolValue: number): number
    {
        let price: number = 0;
        let m: number = 1;
        for (let i = this.NumBitLevels; i != 0; i--) {
            let bit: number = symbolValue & 1;
            symbolValue >>>= 1;
            price += Encoder.GetPrice(this.Models[m], bit);
            m = (m << 1) | bit;
        }
        return price;
    }

    public static ReverseGetPrice(Models: Int16Array, startIndex: number,
                                  NumBitLevels: number, symbolValue: number): number
    {
        let price: number = 0;
        let m: number = 1;
        for (let i = NumBitLevels; i != 0; i--) {
            let bit: number = symbolValue & 1;
            symbolValue >>>= 1;
            price += Encoder.GetPrice(Models[startIndex + m], bit);
            m = (m << 1) | bit;
        }
        return price;
    }

    public static ReverseEncode(Models: Int16Array, startIndex: number,
                                rangeEncoder: Encoder, NumBitLevels: number, symbolValue: number): void
    {
        let m: number = 1;
        for (let i: number = 0; i < NumBitLevels; i++) {
            let bit: number = symbolValue & 1;
            rangeEncoder.Encode(Models, startIndex + m, bit);
            m = (m << 1) | bit;
            symbolValue >>= 1;
        }
    }
}
