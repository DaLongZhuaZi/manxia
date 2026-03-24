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
import OutputStream from '../../util/OutputStream'
import Exception from '../../util/Exception'
import ByteArrayOutputStream from '../../util/ByteArrayOutputStream'
import CountingOutputStream from './CountingOutputStream'
import FinishableOutputStream from './FinishableOutputStream'
import EncoderUtil from './EncoderUtil'
import NumberTransform from "./NumberTransform";
import Check from './Check'
import type FilterEncoder from './FilterEncoder'
import ArrayCache from './ArrayCache'
import Long from "../../util/long/index"

export default class BlockOutputStream extends FinishableOutputStream {
    private out: OutputStream;
    private outCounted: CountingOutputStream;
    private filterChain: FinishableOutputStream;
    private check: Check;
    private headerSize: number;
    private compressedSizeLimit: Long;
    private uncompressedSize: Long = Long.fromNumber(0);
    private tempBuf: Int8Array = new Int8Array(1);

    constructor(out: OutputStream, filters: Array<FilterEncoder>, check: Check, arrayCache: ArrayCache) {
        super()
        this.out = out;
        this.check = check;
        this.outCounted = new CountingOutputStream(out);
        this.filterChain = this.outCounted;
        for (let i = filters.length - 1; i >= 0; --i) {
            this.filterChain = filters[i].getOutputStream(this.filterChain, arrayCache);
        }


        let bufStream: ByteArrayOutputStream = new ByteArrayOutputStream();
        bufStream.write(0);
        bufStream.write(filters.length - 1);

        for (let i: number = 0; i < filters.length; ++i) {
            EncoderUtil.encodeVLI(bufStream, filters[i].getFilterID());
            let filterProps: Int8Array = filters[i].getFilterProps();
            EncoderUtil.encodeVLI(bufStream, Long.fromNumber(filterProps.length)); //(long)var7.length
            bufStream.writeBytes(filterProps);
        }

        while ((bufStream.size() & 3) != 0) {
            bufStream.write(0);
        }

        let buf: Int8Array = bufStream.toByteArrays();
        this.headerSize = buf.length + 4;
        if (this.headerSize > 1024) {
            throw new Exception('UnsupportedOptionsException');
        }

        buf[0] = NumberTransform.toByte(buf.length / 4); //(byte)(var9.length / 4)
        out.writeBytes(buf);
        EncoderUtil.writeCRC32(out, buf);
        this.compressedSizeLimit =
        Long.fromString("9223372036854775804").subtract(this.headerSize).subtract(check.getSize());
    }

    public write(b: number): void{
        this.tempBuf[0] = NumberTransform.toByte(b); //(byte)var1
        this.writeBytesOffset(this.tempBuf, 0, 1);
    }

    public writeBytesOffset(buf: Int8Array, off: number, len: number): void {
        this.filterChain.writeBytesOffset(buf, off, len);
        this.check.updates(buf, off, len);
        this.uncompressedSize = this.uncompressedSize.add(len); //(long)var3
        this.validate();
    }

    public flush(): void {
        this.filterChain.flush();
        this.validate();
    }

    public finish(): void {
        this.filterChain.finish();
        this.validate();
        for (let i: Long = this.outCounted.getSize();!((i.and(3)).eqz()); i = i.add(1)) {
            this.out.write(0);
        }

        this.out.writeBytes(this.check.finish());
    }

    private validate(): void{
        let compressedSize: Long = this.outCounted.getSize();
        if (compressedSize.lessThan(0) || compressedSize.greaterThan(this.compressedSizeLimit)
        || this.uncompressedSize.lessThan(0)) {
            throw new Exception("XZ Stream has grown too big");
        }
    }

    public getUnpaddedSize(): Long {
        return this.outCounted.getSize()
            .add(this.check.getSize())
            .add(this.headerSize);
    }

    public getUncompressedSize(): Long  {
        return this.uncompressedSize;
    }
}
