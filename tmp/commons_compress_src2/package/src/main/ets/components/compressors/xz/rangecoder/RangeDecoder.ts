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
import RangeCoder from './RangeCoder'
import NumberTransform from '../NumberTransform'
import Long from "../../../util/long/index"

export default abstract class RangeDecoder extends RangeCoder {
    range: number = 0;
    code: number = 0;

    constructor() {
        super()
    }

    public abstract normalize(): void;

    public decodeBit(probs: Int16Array, index: number): number{
        this.normalize();
        let prob: number = probs[index];
        let bound = Long.fromNumber(this.range >>> RangeCoder.BIT_MODEL_TOTAL_BITS).multiply(prob).toInt()
        let bit: number;
        if ((Long.fromNumber(this.code).xor(-2147483648)).lessThan(Long.fromNumber(bound).xor(-2147483648))) {
            this.range = bound;
            probs[index] = NumberTransform.toShort(prob + (2048 - prob >>> 5));
            bit = 0;
        } else {
            this.range = Long.fromNumber(this.range).sub(bound).toInt();
            this.code = Long.fromNumber(this.code).sub(bound).toInt();
            probs[index] = NumberTransform.toShort((prob - (prob >>> 5)));
            bit = 1;
        }

        return bit;
    }

    public decodeBitTree(probs: Int16Array): number {
        let symbolnum: number = 1;

        do {
            symbolnum = symbolnum << 1 | this.decodeBit(probs, symbolnum);
        } while (symbolnum < probs.length);

        return symbolnum - probs.length;
    }

    public decodeReverseBitTree(probs: Int16Array): number {
        let symbolnum: number = 1;
        let i: number = 0;
        let result: number = 0;

        do {
            let bit: number = this.decodeBit(probs, symbolnum);
            symbolnum = symbolnum << 1 | bit;
            result |= bit << i++;
        } while (symbolnum < probs.length);

        return result;
    }

    public decodeDirectBits(count: number): number {
        let result: number = 0;

        do {
            this.normalize();
            this.range >>>= 1;
            let num: number = (this.code - this.range) >>> 31;
            this.code = Long.fromNumber(this.code).sub(Long.fromNumber(this.range).and(num - 1)).toInt();
            result = result << 1 | 1 - num;
        } while (--count != 0);

        return result;
    }
}
