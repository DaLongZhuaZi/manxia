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
import NumberTransform from '../NumberTransform'

export default class X86 implements SimpleFilter {
    private MASK_TO_ALLOWED_STATUS = [true, true, true, false, true, false, false, false];
    private MASK_TO_BIT_NUMBER = new Int32Array([0, 1, 2, 2, 3, 3, 3, 3]);
    private isEncoder: boolean;
    private pos: number;
    private prevMask: number = 0;

    private test86MSByte(by: number): boolean {
        let i = by & 255;
        return i == 0 || i == 255;
    }

    constructor(isEncoder: boolean, startPos: number) {
        this.isEncoder = isEncoder;
        this.pos = startPos + 5;
    }

    public code(buf: Int8Array, off: number, len: number): number {
        let prevPos: number = off - 1;
        let end: number = off + len - 5;
        let i;
        for (i = off; i <= end; ++i) {
            if ((buf[i] & 254) == 232) {
                prevPos = i - prevPos;
                if ((prevPos & -4) != 0) {
                    this.prevMask = 0;
                } else {
                    this.prevMask = this.prevMask << prevPos - 1 & 7;
                    if (this.prevMask != 0 && (!this.MASK_TO_ALLOWED_STATUS[this.prevMask] || this.test86MSByte(buf[i + 4 - this.MASK_TO_BIT_NUMBER[this.prevMask]]))) {
                        prevPos = i;
                        this.prevMask = this.prevMask << 1 | 1;
                        continue;
                    }
                }

                prevPos = i;
                if (!this.test86MSByte(buf[i + 4])) {
                    this.prevMask = this.prevMask << 1 | 1;
                } else {
                    let src = buf[i + 1] & 255 | (buf[i + 2] & 255) << 8 | (buf[i + 3] & 255) << 16 | (buf[i + 4] & 255) << 24;

                    let dest;
                    while (true) {
                        if (this.isEncoder) {
                            dest = src + (this.pos + i - off);
                        } else {
                            dest = src - (this.pos + i - off);
                        }

                        if (this.prevMask == 0) {
                            break;
                        }

                        let index = this.MASK_TO_BIT_NUMBER[this.prevMask] * 8;
                        if (!this.test86MSByte(dest >>> 24 - index)) {
                            break;
                        }

                        src = dest ^ (1 << 32 - index) - 1;
                    }

                    buf[i + 1] = NumberTransform.toByte(dest);
                    buf[i + 2] = NumberTransform.toByte(dest >>> 8);
                    buf[i + 3] = NumberTransform.toByte(dest >>> 16);
                    buf[i + 4] = NumberTransform.toByte(~((dest >>> 24 & 1) - 1));
                    i += 4;
                }
            }
        }

        prevPos = i - prevPos;
        this.prevMask = (prevPos & -4) != 0 ? 0 : this.prevMask << prevPos - 1;
        i -= off;
        this.pos += i;
        return i;
    }
}
