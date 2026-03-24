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

import Long from "../../util/long/index"
import { int } from '../../util/CustomTypings'
import IllegalArgumentException from '../../util/IllegalArgumentException'

export default class ByteUtils {
    public static EMPTY_BYTE_ARRAY: Int8Array = new Int8Array(0)

    public static fromLittleEndian(bytes: Int8Array, off: int, length: int): Long {
        this.checkReadLength(length);
        let l: Long = Long.fromNumber(0);
        for (let i: int = 0; i < length; i++) {
            l = l.or(Long.fromNumber(0xff).and(bytes[off + i]).shiftLeft(8 * i));
        }
        return l;
    }

    private static checkReadLength(length: int): void {
        if (length > 8) {
            throw new IllegalArgumentException("Can't read more than eight bytes into a long value");
        }
    }
}