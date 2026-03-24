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
import Long from "./long/index";
import ByteBuffer from './ByteBuffer';

export default class Bits {
    static putLong(bb: ByteBuffer, bi: number, x: Long, bigEndian: boolean): void {
        if (bigEndian)
        this.putLongB(bb, bi, x);
        else
        this.putLongL(bb, bi, x);
    }

    static putLongB(bb: ByteBuffer, bi: number, x: Long): void {
        bb._put(bi, Bits.long7(x));
        bb._put(bi + 1, Bits.long6(x));
        bb._put(bi + 2, Bits.long5(x));
        bb._put(bi + 3, Bits.long4(x));
        bb._put(bi + 4, Bits.long3(x));
        bb._put(bi + 5, Bits.long2(x));
        bb._put(bi + 6, Bits.long1(x));
        bb._put(bi + 7, Bits.long0(x));
    }

    static putLongL(bb: ByteBuffer, bi: number, x: Long): void {
        bb._put(bi + 7, Bits.long7(x));
        bb._put(bi + 6, Bits.long6(x));
        bb._put(bi + 5, Bits.long5(x));
        bb._put(bi + 4, Bits.long4(x));
        bb._put(bi + 3, Bits.long3(x));
        bb._put(bi + 2, Bits.long2(x));
        bb._put(bi + 1, Bits.long1(x));
        bb._put(bi, Bits.long0(x));
    }

    private static long7(x: Long): number {
        return x.shiftRight(56).toNumber();
    }

    private static long6(x: Long): number {
        return x.shiftRight(48).toNumber();
    }

    private static long5(x: Long): number {
        return x.shiftRight(40).toNumber();
    }

    private static long4(x: Long): number {
        return x.shiftRight(32).toNumber();
    }

    private static long3(x: Long): number {
        return x.shiftRight(24).toNumber();
    }

    private static long2(x: Long): number {
        return x.shiftRight(16).toNumber();
    }

    private static long1(x: Long): number {
        return x.shiftRight(8).toNumber();
    }

    private static long0(x: Long): number {
        return x.toNumber();
    }
}