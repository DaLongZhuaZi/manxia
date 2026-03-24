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
import InputStream from '../../../util/InputStream';

export default class Decoder {
    static kTopMask: number = ~((1 << 24) - 1);
    static kNumBitModelTotalBits: number = 11;
    static kBitModelTotal: number = (1 << Decoder.kNumBitModelTotalBits);
    static kNumMoveBits: number = 5;
    Range: number;
    Code: number;
    Stream: InputStream;

    public SetStream(stream: InputStream): void
    {
        this.Stream = stream;
    }

    public ReleaseStream(): void
    {
        this.Stream = null;
    }

    public Init(): void
    {
        this.Code = 0;
        this.Range = -1;
        for (let i = 0; i < 5; i++)
        this.Code = (this.Code << 8) | this.Stream.read();
    }

    public DecodeDirectBits(numTotalBits: number): number
    {
        let result: number = 0;
        for (let i = numTotalBits; i != 0; i--) {
            this.Range >>>= 1;
            let t: number = ((this.Code - this.Range) >>> 31);
            this.Code -= this.Range & (t - 1);
            result = (result << 1) | (1 - t);

            if ((this.Range & Decoder.kTopMask) == 0) {
                this.Code = (this.Code << 8) | this.Stream.read();
                this.Range <<= 8;
            }
        }
        return result;
    }

    public DecodeBit(probs: Int16Array, index: number): number
    {
        let prob: number = probs[index];
        let newBound: number = (this.Range >>> Decoder.kNumBitModelTotalBits) * prob;
        if ((this.Code ^ 0x80000000) < (newBound ^ 0x80000000)) {
            this.Range = newBound;
            probs[index] = (prob + ((Decoder.kBitModelTotal - prob) >>> Decoder.kNumMoveBits));
            if ((this.Range & Decoder.kTopMask) == 0) {
                this.Code = (this.Code << 8) | this.Stream.read();
                this.Range <<= 8;
            }
            return 0;
        }
        else {
            this.Range -= newBound;
            this.Code -= newBound;
            probs[index] = (prob - ((prob) >>> Decoder.kNumMoveBits));
            if ((this.Range & Decoder.kTopMask) == 0) {
                this.Code = (this.Code << 8) | this.Stream.read();
                this.Range <<= 8;
            }
            return 1;
        }
    }

    public static InitBitModels(probs: Int16Array): void
    {
        for (let i = 0; i < probs.length; i++)
        probs[i] = (Decoder.kBitModelTotal >>> 1);
    }
}
