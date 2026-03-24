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
import LZMACoder from './LZMACoder'
import LZDecoder from '../lz/LZDecoder'
import RangeDecoder from '../rangecoder/RangeDecoder'
import LiteralCoder from './LiteralCoder'
import LiteralSubcoder from './LiteralSubcoder'
import NumberTransform from '../NumberTransform'
import LengthCoder from './LengthCoder'
import StateClass from './StateClass'

export default class LZMADecoder extends LZMACoder {
    private lz: LZDecoder;
    private rc: RangeDecoder;
    private literalDecoder: LiteralDecoder;
    private matchLenDecoder: LengthDecoder;
    private repLenDecoder: LengthDecoder ;

    constructor(lz: LZDecoder, rc: RangeDecoder, lc: number, lp: number, pb: number) {
        super(pb);
        this.lz = lz;
        this.rc = rc;
        this.literalDecoder = new LiteralDecoder(lc, lp, this, lz, rc, this.stateClass);
        this.matchLenDecoder = new LengthDecoder(this.rc);
        this.repLenDecoder = new LengthDecoder(this.rc);
        this.reset();
    }

    public reset() {
        super.reset();
        this.literalDecoder.reset();
        this.matchLenDecoder.reset();
        this.repLenDecoder.reset();
    }

    public endMarkerDetected(): boolean {
        return this.reps[0] == -1;
    }

    public decode() {
        this.lz.repeatPending();

        while (this.lz.hasSpace()) {
            let posState = this.lz.getPos() & this.posMask;
            if (this.rc.decodeBit(this.isMatch[this.stateClass.get()], posState) == 0) {
                this.literalDecoder.decode();
            } else {
                let len = this.rc.decodeBit(this.isRep, this.stateClass.get()) == 0
                    ? this.decodeMatch(posState)
                    : this.decodeRepMatch(posState);
                this.lz.repeat(this.reps[0], len);
            }
        }

        this.rc.normalize();
    }

    private decodeMatch(posState: number): number {
        this.stateClass.updateMatch();
        this.reps[3] = this.reps[2];
        this.reps[2] = this.reps[1];
        this.reps[1] = this.reps[0];
        let len = this.matchLenDecoder.decode(posState);
        let distSlot = this.rc.decodeBitTree(this.distSlots[this.getDistState(len)]);
        if (distSlot < 4) {
            this.reps[0] = distSlot;
        } else {
            let limit = (distSlot >> 1) - 1;
            this.reps[0] = (2 | distSlot & 1) << limit;

            if (distSlot < 14) {
                this.reps[0] |= this.rc.decodeReverseBitTree(this.distSpecial[distSlot - LZMACoder.DIST_MODEL_START]);
            } else {
                this.reps[0] |= this.rc.decodeDirectBits(limit - 4) << 4;
                this.reps[0] |= this.rc.decodeReverseBitTree(this.distAlign);
            }
        }

        return len;
    }

    private decodeRepMatch(posState: number): number{
        if (this.rc.decodeBit(this.isRep0, this.stateClass.get()) == 0) {
            if (this.rc.decodeBit(this.isRep0Long[this.stateClass.get()], posState) == 0) {
                this.stateClass.updateShortRep();
                return 1;
            }
        } else {
            let tmp;
            if (this.rc.decodeBit(this.isRep1, this.stateClass.get()) == 0) {
                tmp = this.reps[1];
            } else {
                if (this.rc.decodeBit(this.isRep2, this.stateClass.get()) == 0) {
                    tmp = this.reps[2];
                } else {
                    tmp = this.reps[3];
                    this.reps[3] = this.reps[2];
                }

                this.reps[2] = this.reps[1];
            }

            this.reps[1] = this.reps[0];
            this.reps[0] = tmp;
        }

        this.stateClass.updateLongRep();
        return this.repLenDecoder.decode(posState);
    }
}

class LengthDecoder extends LengthCoder {
    private rc: RangeDecoder;

    constructor(rc: RangeDecoder) {
        super()
        this.rc = rc
    }

    decode(posState: number): number {
        if (this.rc.decodeBit(this.choice, 0) == 0) {
            return this.rc.decodeBitTree(this.low[posState]) + 2;
        } else {
            return this.rc.decodeBit(this.choice, 1) == 0 ? this.rc.decodeBitTree(this.mid[posState]) + 2 + 8 : this.rc.decodeBitTree(this.high) + 2 + 8 + 8;
        }
    }
}

class LiteralDecoder extends LiteralCoder {
    private subdecoders: Array<LiteralSubdecoder>;
    private lz: LZDecoder;

    constructor(lc: number, lp: number, lzmaCoder: LZMACoder, lz: LZDecoder, rc: RangeDecoder, stateClass: StateClass) {
        super(lc, lp);
        this.lz = lz
        this.subdecoders = new Array<LiteralSubdecoder>(1 << (lc + lp));
        for (let i = 0; i < this.subdecoders.length; ++i)
        this.subdecoders[i] = new LiteralSubdecoder(lzmaCoder, lz, rc, stateClass);
    }

    reset() {
        for (let i = 0; i < this.subdecoders.length; ++i) {
            this.subdecoders[i].reset();
        }

    }

    decode() {
        let i = this.getSubcoderIndex(this.lz.getByte(0), this.lz.getPos());
        this.subdecoders[i].decode();
    }
}

class LiteralSubdecoder extends LiteralSubcoder {
    stateClass: StateClass ;
    private rc: RangeDecoder;
    private lz: LZDecoder;
    private lzmaCoder: LZMACoder;

    constructor(lzmaCoder: LZMACoder, lz: LZDecoder, rc: RangeDecoder, stateClass: StateClass) {
        super()
        this.lzmaCoder = lzmaCoder;
        this.lz = lz;
        this.rc = rc;
        this.stateClass = stateClass;
    }

    decode(): void {
        let symbolnum: number = 1;
        if (this.stateClass.isLiteral()) {
            do {
                symbolnum = symbolnum << 1 | this.rc.decodeBit(this.probs, symbolnum);
            } while (symbolnum < 256);
        } else {
            let matchByte = this.lz.getByte(this.lzmaCoder.reps[0]);
            let offset = 256;

            do {
                matchByte <<= 1;
                let matchBit = matchByte & offset;
                let bit = this.rc.decodeBit(this.probs, offset + matchBit + symbolnum);
                symbolnum = symbolnum << 1 | bit;
                offset &= 0 - bit ^ ~matchBit;
            } while (symbolnum < 256);
        }

        this.lz.putByte(NumberTransform.toByte(symbolnum));
        this.stateClass.updateLiteral();
    }
}