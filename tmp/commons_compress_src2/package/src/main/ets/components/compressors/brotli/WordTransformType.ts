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

export default class WordTransformType {
    static IDENTITY: number = 0;
    static OMIT_LAST_1: number = 1;
    static OMIT_LAST_2: number = 2;
    static OMIT_LAST_3: number = 3;
    static OMIT_LAST_4: number = 4;
    static OMIT_LAST_5: number = 5;
    static OMIT_LAST_6: number = 6;
    static OMIT_LAST_7: number = 7;
    static OMIT_LAST_8: number = 8;
    static OMIT_LAST_9: number = 9;
    static UPPERCASE_FIRST: number = 10;
    static UPPERCASE_ALL: number = 11;
    static OMIT_FIRST_1: number = 12;
    static OMIT_FIRST_2: number = 13;
    static OMIT_FIRST_3: number = 14;
    static OMIT_FIRST_4: number = 15;
    static OMIT_FIRST_5: number = 16;
    static OMIT_FIRST_6: number = 17;
    static OMIT_FIRST_7: number = 18;
    static OMIT_FIRST_8: number = 19;
    static OMIT_FIRST_9: number = 20;

    constructor() {
    }

    static getOmitFirst(type: number): number{
        return type >= 12 ? type - 12 + 1 : 0;
    }

    static getOmitLast(type: number): number{
        return type <= 9 ? type - 1 + 1 : 0;
    }
}