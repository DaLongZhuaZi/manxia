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
import RangeCoder from '../rangecoder/RangeCoder'

export default abstract class LengthCoder {
    static LOW_SYMBOLS: number = 1 << 3;
    static MID_SYMBOLS: number = 1 << 3;
    static HIGH_SYMBOLS: number = 1 << 8;
    choice: Int16Array = new Int16Array(2);
    low: Array<Int16Array> = new Array<Int16Array>(LZMACoder.POS_STATES_MAX);
    mid: Array<Int16Array> = new Array<Int16Array>(LZMACoder.POS_STATES_MAX);
    high: Int16Array = new Int16Array(LengthCoder.HIGH_SYMBOLS);

    constructor() {
        this.initlowArray()
        this.initmidArray()
    }

    initlowArray() {
        for (let i = 0;i < this.low.length; i++) {
            this.low[i] = new Int16Array(LengthCoder.LOW_SYMBOLS);
        }
    }

    initmidArray() {
        for (let i = 0;i < this.mid.length; i++) {
            this.mid[i] = new Int16Array(LengthCoder.MID_SYMBOLS);
        }
    }

    reset(): void {
        RangeCoder.initProbs(this.choice);

        for (let i = 0; i < this.low.length; ++i)
        RangeCoder.initProbs(this.low[i]);

        for (let i = 0; i < this.low.length; ++i)
        RangeCoder.initProbs(this.mid[i]);

        RangeCoder.initProbs(this.high);
    }
}