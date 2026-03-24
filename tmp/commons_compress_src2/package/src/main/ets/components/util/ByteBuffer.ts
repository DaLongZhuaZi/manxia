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
import Bits from './Bits';
import Buffer from './Buffer';
import Long from "./long/index";
import ByteOrder from './ByteOrder';
import Exception from './Exception';
import IllegalArgumentException from './IllegalArgumentException';

export default class ByteBuffer extends Buffer {
    hb: Int8Array;
    offset: number;

    constructor(mark: number, pos: number, lim: number, cap: number, // package-private
                hb: Int8Array, offset: number) {
        super(mark, pos, lim, cap);
        this.hb = hb;
        this.offset = offset;
    }

    public static allocate(capacity: number): ByteBuffer {
        if (capacity < 0)
        throw new IllegalArgumentException();
        return new ByteBuffer(-1, 0, capacity, capacity, new Int8Array(capacity), 0);
    }

    public hasArray(): boolean {
        return this.hb != null;
    }

    public array(): Int8Array {
        if (this.hb == null)
        throw new Exception();
        return this.hb;
    }

    public arrayOffset(): number {
        if (this.hb == null)
        throw new Exception();
        return this.offset;
    }

    public put(x: number): ByteBuffer {
        this.hb[this.ix(this.nextPutIndex())] = x;
        return this;
    }

    public _put(i: number, b: number): void { // package-private
        this.hb[i] = b;
    }

    protected ix(i: number): number {
        return i + this.offset;
    }

    public putBytesOffset(src: Int8Array, offset: number, length: number): ByteBuffer {
        Buffer.checkBounds(offset, length, src.length);
        if (length > this.remaining())
        throw new Exception();
        let end: number = offset + length;
        for (let i = offset; i < end; i++)
        this.put(src[i]);
        return this;
    }

    public putByteBuffer(src: ByteBuffer): ByteBuffer {
        if (src == this)
        throw new IllegalArgumentException();
        let n: number = src.remaining();
        if (n > this.remaining())
        throw new Exception();
        for (let i: number = 0; i < n; i++)
        this.put(src.get());
        return this;
    }

    public get(): number {
        return this.hb[this.ix(this.nextGetIndex())];
    }

    bigEndian: boolean = true;
    nativeByteOrder: boolean = true;

    public order(bo: ByteOrder): ByteBuffer {
        this.bigEndian = (bo == ByteOrder.BIG_ENDIAN);
        this.nativeByteOrder = (this.bigEndian == true);
        return this;
    }

    public putLong(x: Long): ByteBuffer {
        Bits.putLong(this, this.ix(this.nextPutIndexes(8)), x, this.bigEndian);
        return this;
    }
}