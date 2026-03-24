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

export default abstract class RangeEncoder extends RangeCoder {
    private static MOVE_REDUCING_BITS: number = 4;
    private static BIT_PRICE_SHIFT_BITS: number = 4;
    private static prices = new Int32Array(128);
    private low: Long;
    private range: number;
    cacheSize: Long = Long.fromNumber(0);
    private cache: number;

    constructor() {
        super()
    }

    public reset(): void {
        this.low = Long.fromNumber(0);
        this.range = -1;
        this.cache = 0;
        this.cacheSize = Long.fromNumber(1);
    }

    public getPendingSize(): number {
        throw new Error();
    }

    public finish(): number  {
        for (let i = 0; i < 5; ++i) {
            this.shiftLow();
        }
        let ber = -1
        return ber;
    }

    abstract writeByte(b: number): void;

    private shiftLow(): void {
        let lowHi: number = this.low.shiftRightUnsigned(32).toInt();
        if (lowHi != 0 || this.low.lt(Long.fromNumber(4278190080))) {
            let temp: number = this.cache;
            do {
                this.writeByte(temp + lowHi);
                temp = 255;
                this.cacheSize = this.cacheSize.subtract(1)
            } while (!this.cacheSize.eq(0));

            this.cache = NumberTransform.toByte(this.low.shiftRightUnsigned(24).toNumber());
        }

        this.cacheSize = this.cacheSize.add(1);
        this.low = this.low.and(Long.fromString('16777215')).shiftLeft(8);
    }

    public encodeBit(probs: Int16Array, index: number, bit: number): void {
        let prob: number = probs[index];
        let bound: number = (this.range >>> RangeCoder.BIT_MODEL_TOTAL_BITS) * prob;
        if (bit == 0) {
            this.range = bound;
            probs[index] = prob + ((RangeCoder.BIT_MODEL_TOTAL - prob) >>> RangeCoder.MOVE_BITS);
        } else {
            this.low = this.low.add(Long.fromNumber(bound).and(Long.fromString('4294967295')));
            this.range = Long.fromString(this.range + "").sub(bound).toInt();
            probs[index] = prob - (prob >>> RangeCoder.MOVE_BITS);
        }

        if ((Long.fromNumber(this.range).and(Long.fromString('-16777216'))).eq(0)) {
            this.range = this.range << RangeCoder.SHIFT_BITS;
            this.shiftLow();
        }

    }

    public static getBitPrice(prob: number, bit: number): number {
        bit == 0 || bit == 1;

        return this.prices[(prob ^ -bit & 2047) >>> 4];
    }

    public encodeBitTree(probs: Int16Array, symbolNum: number): void {
        let index: number = 1;
        let mask: number = probs.length;

        do {
            mask >>>= 1;
            let bit: number = symbolNum & mask;
            this.encodeBit(probs, index, bit);
            index <<= 1;
            if (bit != 0) {
                index |= 1;
            }
        } while (mask != 1);

    }

    public static getBitTreePrice(probs: Int16Array, symbol: number): number {
        let price: number = 0;
        symbol |= probs.length;

        do {
            let bit: number = symbol & 1;
            symbol >>>= 1;
            price += this.getBitPrice(probs[symbol], bit);
        } while (symbol != 1);

        return price;
    }

    public encodeReverseBitTree(probs: Int16Array, symbol: number): void {
        let index: number = 1;
        symbol |= probs.length;

        do {
            let bit: number = symbol & 1;
            symbol >>>= 1;
            this.encodeBit(probs, index, bit);
            index = index << 1 | bit;
        } while (symbol != 1);

    }

    public static getReverseBitTreePrice(probs: Int16Array, symbol: number): number {
        let price: number = 0;
        let index: number = 1;
        symbol |= probs.length;

        do {
            let bit: number = symbol & 1;
            symbol >>>= 1;
            price += RangeEncoder.getBitPrice(probs[index], bit);
            index = index << 1 | bit;
        } while (symbol != 1);

        return price;
    }

    public encodeDirectBits(value: number, count: number): void {
        do {
            this.range >>>= 1;
            --count;
            this.low = this.low.add(this.range & 0 - (value >>> count & 1));
            if ((this.range & -16777216) == 0) {
                this.range <<= 8;
                this.shiftLow();
            }
        } while (count != 0);

    }

    public static getDirectBitsPrice(count: number): number {
        return count << 4;
    }

    static pricesRangeEncoder() {
        for (let i: number = 8; i < 2048; i += 16) {
            let w: number = i;
            let bitCount: number = 0;

            for (let j: number = 0; j < 4; ++j) {
                w *= w

                for (bitCount <<= 1; (w & -65536) != 0; bitCount) {
                    w >>>= 1;
                }
            }

            this.prices[i >> 4] = 161 - bitCount;
        }

    }
}

RangeEncoder.pricesRangeEncoder()