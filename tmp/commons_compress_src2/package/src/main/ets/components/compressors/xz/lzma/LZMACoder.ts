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
import RangeCoder from '../rangecoder/RangeCoder'
import StateClass from './StateClass'
import LengthCoder from './LengthCoder'

export default abstract class LZMACoder {
    static POS_STATES_MAX: number = 1 << 4;
    static MATCH_LEN_MIN: number = 2;
    static MATCH_LEN_MAX: number = LZMACoder.MATCH_LEN_MIN + LengthCoder.LOW_SYMBOLS
    + LengthCoder.MID_SYMBOLS
    + LengthCoder.HIGH_SYMBOLS - 1;
    static DIST_STATES: number = 4;
    static DIST_SLOTS: number = 1 << 6;
    static DIST_MODEL_START: number = 4;
    static DIST_MODEL_END: number = 14;
    static FULL_DISTANCES: number = 1 << (LZMACoder.DIST_MODEL_END / 2);
    static ALIGN_BITS: number = 4;
    static ALIGN_SIZE: number = 1 << LZMACoder.ALIGN_BITS;
    static ALIGN_MASK: number = LZMACoder.ALIGN_SIZE - 1;
    static REPS: number = 4;
    posMask: number;
    reps: Int32Array = new Int32Array(LZMACoder.REPS);
    stateClass: StateClass = new StateClass();
    isMatch: Array<Int16Array> = new Array<Int16Array>(StateClass.STATES);
    isRep: Int16Array = new Int16Array(StateClass.STATES);
    isRep0: Int16Array = new Int16Array(StateClass.STATES);
    isRep1: Int16Array = new Int16Array(StateClass.STATES);
    isRep2: Int16Array = new Int16Array(StateClass.STATES);
    isRep0Long: Array<Int16Array> = new Array<Int16Array>(StateClass.STATES);
    distSlots: Array<Int16Array> = new Array<Int16Array>(StateClass.STATES);
    distSpecial: Array<Int16Array> = [new Int16Array(2), new Int16Array(2),
    new Int16Array(4), new Int16Array(4),
    new Int16Array(8), new Int16Array(8),
    new Int16Array(16), new Int16Array(16),
    new Int16Array(32), new Int16Array(32)];
    distAlign: Int16Array = new Int16Array(LZMACoder.ALIGN_SIZE);

    initMatchArray() {
        for (let i = 0;i < this.isMatch.length; i++) {
            this.isMatch[i] = new Int16Array(LZMACoder.POS_STATES_MAX);
        }
    }

    initRep0LongArray() {
        for (let i = 0;i < this.isRep0Long.length; i++) {
            this.isRep0Long[i] = new Int16Array(LZMACoder.POS_STATES_MAX);
        }
    }

    initSlotsArray() {
        for (let i = 0;i < this.distSlots.length; i++) {
            this.distSlots[i] = new Int16Array(LZMACoder.DIST_SLOTS);
        }
    }

    getDistState(len: number): number {
        return len < LZMACoder.DIST_STATES + LZMACoder.MATCH_LEN_MIN
            ? len - LZMACoder.MATCH_LEN_MIN
            : LZMACoder.DIST_STATES - 1;
    }

    constructor(pb: number) {
        this.posMask = (1 << pb) - 1;
        this.initMatchArray()
        this.initSlotsArray()
        this.initRep0LongArray()
    }

    reset(): void {
        this.reps[0] = 0;
        this.reps[1] = 0;
        this.reps[2] = 0;
        this.reps[3] = 0;
        this.stateClass.reset();

        for (let i = 0; i < this.isMatch.length; ++i) {
            RangeCoder.initProbs(this.isMatch[i]);
        }

        RangeCoder.initProbs(this.isRep);
        RangeCoder.initProbs(this.isRep0);
        RangeCoder.initProbs(this.isRep1);
        RangeCoder.initProbs(this.isRep2);

        for (let i = 0; i < this.isRep0Long.length; ++i) {
            RangeCoder.initProbs(this.isRep0Long[i]);
        }

        for (let i = 0; i < this.distSlots.length; ++i) {
            RangeCoder.initProbs(this.distSlots[i]);
        }

        for (let i = 0; i < this.distSpecial.length; ++i) {
            RangeCoder.initProbs(this.distSpecial[i]);
        }

        RangeCoder.initProbs(this.distAlign);
    }
}
