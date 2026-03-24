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
import StateClass from './StateClass'
import LZMACoder from './LZMACoder'

export default class Optimum {
    private static INFINITY_PRICE: number = 1 << 30;
    state: StateClass = new StateClass();
    reps: Int32Array = new Int32Array(LZMACoder.REPS);
    price: number;
    optPrev: number;
    backPrev: number;
    prev1IsLiteral: boolean;
    hasPrev2: boolean;
    optPrev2: number;
    backPrev2: number;

    reset(): void {
        this.price = Optimum.INFINITY_PRICE;
    }

    set1(newPrice: number, optCur: number, back: number): void {
        this.price = newPrice;
        this.optPrev = optCur;
        this.backPrev = back;
        this.prev1IsLiteral = false;
    }

    set2(newPrice: number, optCur: number, back: number): void {
        this.price = newPrice;
        this.optPrev = optCur + 1;
        this.backPrev = back;
        this.prev1IsLiteral = true;
        this.hasPrev2 = false;
    }

    set3(newPrice: number, optCur: number, back2: number, len2: number, back: number): void  {
        this.price = newPrice;
        this.optPrev = optCur + len2 + 1;
        this.backPrev = back;
        this.prev1IsLiteral = true;
        this.hasPrev2 = true;
        this.optPrev2 = optCur;
        this.backPrev2 = back2;
    }
}
