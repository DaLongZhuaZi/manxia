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
export default class StateClass {
    static STATES: number = 12;
    private static LIT_STATES: number = 7;
    private static LIT_LIT: number = 0;
    private static MATCH_LIT_LIT: number = 1;
    private static REP_LIT_LIT: number = 2;
    private static SHORTREP_LIT_LIT: number = 3;
    private static MATCH_LIT: number = 4;
    private static REP_LIT: number = 5;
    private static SHORTREP_LIT: number = 6;
    private static LIT_MATCH: number = 7;
    private static LIT_LONGREP: number = 8;
    private static LIT_SHORTREP: number = 9;
    private static NONLIT_MATCH: number = 10;
    private static NONLIT_REP: number = 11;
    private state: number = 0;

    constructor() {
    }

    reset(): void {
        this.state = StateClass.LIT_LIT;
    }

    get(): number {
        return this.state;
    }

    set(other: StateClass): void {
        this.state = other.state;
    }

    updateLiteral(): void {
        if (this.state <= StateClass.SHORTREP_LIT_LIT)
        this.state = StateClass.LIT_LIT;
        else if (this.state <= StateClass.LIT_SHORTREP)
        this.state -= 3;
        else
        this.state -= 6;
    }

    updateMatch(): void {
        this.state = this.state < StateClass.LIT_STATES ? StateClass.LIT_MATCH : StateClass.NONLIT_MATCH;
    }

    updateLongRep(): void {
        this.state = this.state < StateClass.LIT_STATES ? StateClass.LIT_LONGREP : StateClass.NONLIT_REP;
    }

    updateShortRep(): void {
        this.state = this.state < StateClass.LIT_STATES ? StateClass.LIT_SHORTREP : StateClass.NONLIT_REP;
    }

    isLiteral(): boolean {
        return this.state < StateClass.LIT_STATES;
    }
}
