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
export default class BZip2Constants {
    static BASEBLOCKSIZE: number = 100000;
    static MAX_ALPHA_SIZE: number = 258;
    static MAX_CODE_LEN: number = 23;
    static RUNA: number = 0;
    static RUNB: number = 1;
    static N_GROUPS: number = 6;
    static G_SIZE: number = 50;
    static N_ITERS: number = 4;
    static MAX_SELECTORS: number = (2 + (900000 / BZip2Constants.G_SIZE));
    static NUM_OVERSHOOT_BYTES: number = 20;
}