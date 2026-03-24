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

export default class IntReader {
    private byteBuffer: Int8Array;
    private intBuffer: Int32Array;

    constructor() {

    }

    static init(ir: IntReader, byteBuffer: Int8Array, intBuffer: Int32Array): void {
        ir.byteBuffer = byteBuffer;
        ir.intBuffer = intBuffer;
    }

    static convert(ir: IntReader, intLen: number): void {
        for (let i: number = 0; i < intLen; ++i) {
            ir.intBuffer[i] = ir.byteBuffer[i * 4] & 255
            | (ir.byteBuffer[i * 4 + 1] & 255) << 8
            | (ir.byteBuffer[i * 4 + 2] & 255) << 16
            | (ir.byteBuffer[i * 4 + 3] & 255) << 24;
        }
    }
}
