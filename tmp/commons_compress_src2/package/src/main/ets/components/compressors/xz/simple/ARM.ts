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

export default class ARM implements SimpleFilter {
    private isEncoder: boolean;
    private pos: number;

    constructor(isEncoder: boolean, startPos: number) {
        this.isEncoder = isEncoder;
        this.pos = startPos + 8;
    }

    public code(buf: Int8Array, off: number, len: number): number {
        let end = off + len - 4;
        let i;
        for (i = off; i <= end; i += 4) {
            if ((buf[i + 3] & 255) == 235) {
                let src = (buf[i + 2] & 255) << 16 | (buf[i + 1] & 255) << 8 | buf[i] & 255;
                src <<= 2;
                let dest;
                if (this.isEncoder) {
                    dest = src + (this.pos + i - off);
                } else {
                    dest = src - (this.pos + i - off);
                }

                dest >>>= 2;
                buf[i + 2] = (dest >>> 16);
                buf[i + 1] = (dest >>> 8);
                buf[i] = dest;
            }
        }

        i -= off;
        this.pos += i;
        return i;
    }
}
