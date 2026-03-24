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
import type SimpleFilter from './SimpleFilter'

export default class ARMThumb implements SimpleFilter {
    private isEncoder: boolean;
    private pos: number;

    constructor(isEncoder: boolean, startPos: number) {
        this.isEncoder = isEncoder;
        this.pos = startPos + 4;
    }

    public code(buf: Int8Array, off: number, len: number): number {
        let end = off + len - 4;
        let i;
        for (i = off; i <= end; i += 2) {
            if ((buf[i + 1] & 248) == 240 && (buf[i + 3] & 248) == 248) {
                let src = (buf[i + 1] & 7) << 19 | (buf[i] & 255) << 11 | (buf[i + 3] & 7) << 8 | buf[i + 2] & 255;
                src <<= 1;
                let dest;
                if (this.isEncoder) {
                    dest = src + (this.pos + i - off);
                } else {
                    dest = src - (this.pos + i - off);
                }

                dest >>>= 1;
                buf[i + 1] = (240 | dest >>> 19 & 7);
                buf[i] = (dest >>> 11);
                buf[i + 3] = (248 | dest >>> 8 & 7);
                buf[i + 2] = dest;
                i += 2;
            }
        }

        i -= off;
        this.pos += i;
        return i;
    }
}
