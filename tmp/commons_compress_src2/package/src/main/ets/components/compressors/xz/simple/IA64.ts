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

export default class IA64 implements SimpleFilter {
    private BRANCH_TABLE = new Int8Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 6, 6, 0, 0, 7, 7, 4, 4, 0, 0, 4, 4, 0, 0]);
    private isEncoder: boolean;
    private pos: number;

    constructor(isEncoder: boolean, startPos: number) {
        this.isEncoder = isEncoder;
        this.pos = startPos;
    }

    public code(buf: Int8Array, off: number, len: number): number {
        let end = off + len - 16;
        let i;
        for (i = off; i <= end; i += 16) {
            let instrTemplate = buf[i] & 31;
            let mask = this.BRANCH_TABLE[instrTemplate];
            let slot = 0;

            for (let bitPos = 5; slot < 3; bitPos += 41) {
                if ((mask >>> slot & 1) != 0) {
                    let bytePos: number = bitPos >>> 3;
                    let bitRes: number = bitPos & 7;
                    let instr: number = 0;

                    for (let j = 0; j < 6; ++j) {
                        instr |= (buf[i + bytePos + j] & 255) << 8 * j;
                    }

                    let instrNorm = instr >>> bitRes;
                    if (((instrNorm >>> 37) & 15) == 5 && (instrNorm >>> 9 & 7) == 0) {
                        let src = (instrNorm >>> 13 & 1048575);
                        src |= ((instrNorm >>> 36) & 1) << 20;
                        src <<= 4;
                        let dest;
                        if (this.isEncoder) {
                            dest = src + (this.pos + i - off);
                        } else {
                            dest = src - (this.pos + i - off);
                        }

                        dest >>>= 4;
                        instrNorm &= -77309403137;
                        instrNorm |= (dest & 1048575) << 13;
                        instrNorm |= (dest & 1048576) << 16;
                        instr &= ((1 << bitRes) - 1);
                        instr |= instrNorm << bitRes;

                        for (let j = 0; j < 6; ++j) {
                            buf[i + bytePos + j] = (instr >>> 8 * j);
                        }
                    }
                }

                ++slot;
            }
        }

        i -= off;
        this.pos += i;
        return i;
    }
}
