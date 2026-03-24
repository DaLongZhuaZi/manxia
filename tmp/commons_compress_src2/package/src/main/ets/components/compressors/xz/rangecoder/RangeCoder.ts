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
import Arrays from '../../../util/Arrays'

export default abstract class RangeCoder {
    static SHIFT_BITS: number = 8;
    static TOP_MASK: number = -16777216;
    static BIT_MODEL_TOTAL_BITS: number = 11;
    static BIT_MODEL_TOTAL: number = 2048;
    static PROB_INIT: number = 1024;
    static MOVE_BITS: number = 5;

    constructor() {
    }

    public static initProbs(probs: Int16Array): void {
        Arrays.fill(probs, RangeCoder.PROB_INIT);
    }
}
