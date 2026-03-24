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
import System from '../../util/System'

export default class Utils {
    private static BYTE_ZEROES: Int8Array = new Int8Array(1024);
    private static INT_ZEROES: Int8Array = new Int8Array(1024);

    constructor() {
    }

    static fillWithZeroes(dest: Int8Array, offset: number, length: number): void {
        let step: number;
        for (let cursor: number = 0; cursor < length; cursor += step) {
            step = Math.min(cursor + 1024, length) - cursor;
            System.arraycopy(Utils.BYTE_ZEROES, 0, dest, offset + cursor, step);
        }
    }

    static fillWithZeroesd(dest: Int32Array, offset: number, length: number): void {
        let step: number;
        for (let cursor: number = 0; cursor < length; cursor += step) {
            step = Math.min(cursor + 1024, length) - cursor;
            System.arraycopy(Utils.INT_ZEROES, 0, dest, offset + cursor, step);
        }
    }
}