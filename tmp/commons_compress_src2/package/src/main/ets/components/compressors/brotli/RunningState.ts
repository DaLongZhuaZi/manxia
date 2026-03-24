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

export default class RunningState {
    static UNINITIALIZED: number = 0;
    static BLOCK_START: number = 1;
    static COMPRESSED_BLOCK_START: number = 2;
    static MAIN_LOOP: number = 3;
    static READ_METADATA: number = 4;
    static COPY_UNCOMPRESSED: number = 5;
    static INSERT_LOOP: number = 6;
    static COPY_LOOP: number = 7;
    static COPY_WRAP_BUFFER: number = 8;
    static TRANSFORM: number = 9;
    static FINISHED: number = 10;
    static CLOSED: number = 11;
    static WRITE: number = 12;

    constructor() {

    }
}