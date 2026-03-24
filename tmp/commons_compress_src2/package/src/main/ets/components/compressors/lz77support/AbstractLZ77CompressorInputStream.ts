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
import Exception from '../../util/Exception'
import InputStream from '../../util/InputStream'
import Arrays from '../../util/Arrays'
import IOUtils from '../../util/IOUtils'
import System from '../../util/System'
import type InputStreamStatistics from '../../util/InputStreamStatistics'
import { int } from '../../util/CustomTypings'
import Long from "../../util/long/index"
import CompressorInputStream from './CompressorInputStream'
import CountingInputStream from './CountingInputStream'

export default class AbstractLZ77CompressorInputStream extends CompressorInputStream
implements InputStreamStatistics {
    private windowSize: int;
    private buf: Int8Array;
    private writeIndex: int;
    private readIndex: int;
    private in: CountingInputStream;
    private bytesRemaining: Long;
    private backReferenceOffset: int;
    private size: int;
    private oneByte: Int8Array = new Int8Array(1);

    constructor(is: InputStream, windowSize: int) {
        super()
        this.in = new CountingInputStream(is);
        if (windowSize <= 0) {
            throw new Exception();
        }
        this.windowSize = windowSize;
        this.buf = new Int8Array(3 * windowSize);
        this.writeIndex = this.readIndex = 0;
        this.bytesRemaining = Long.fromNumber(0);
    }

    public read(): int {
        return this.readBytesOffset(this.oneByte, 0, 1) == -1 ? -1 : this.oneByte[0] & 0xFF;
    }

    public close(): void {
        this.in.close();
    }

    public available(): int {
        return this.writeIndex - this.readIndex;
    }

    public getSize(): int {
        return this.size;
    }

    public prefill(data: Int8Array): void {
        if (this.writeIndex != 0) {
            throw new Exception();
        }

        let len: int = Math.min(this.windowSize, data.length);

        System.arraycopy(data, data.length - len, this.buf, 0, len);
        this.writeIndex += len;
        this.readIndex += len;
    }

    public getCompressedCount(): Long {
        return this.in.getBytesRead();
    }

    public startLiteral(length: Long): void {
        if (length.lt(0)) {
            throw new Exception();
        }
        this.bytesRemaining = length;
    }

    protected hasMoreDataInBlock(): boolean {
        return this.bytesRemaining.gt(0);
    }

    protected readLiteral(b: Int8Array, off: int, len: int): int {
        let avail: int = this.available();
        if (len > avail) {
            this.tryToReadLiteral(len - avail);
        }
        return this.readFromBuffer(b, off, len);
    }

    private tryToReadLiteral(bytesToRead: int): void {
        let reallyTryToRead: int = Math.min(Math.min(bytesToRead, this.bytesRemaining.toInt()),
            this.buf.length - this.writeIndex);
        let bytesRead: int = reallyTryToRead > 0
            ? IOUtils.readFull(this.in, this.buf, this.writeIndex, reallyTryToRead)
            : 0 /* happens for bytesRemaining == 0 */
        ;
        this.count(Long.fromNumber(bytesRead));
        if (reallyTryToRead != bytesRead) {
            throw new Exception();
        }
        this.writeIndex += reallyTryToRead;
        this.bytesRemaining = this.bytesRemaining.sub(reallyTryToRead);
    }

    private readFromBuffer(b: Int8Array, off: int, len: int): int {
        let readable: int = Math.min(len, this.available());
        if (readable > 0) {
            System.arraycopy(this.buf, this.readIndex, b, off, readable);
            this.readIndex += readable;
            if (this.readIndex > 2 * this.windowSize) {
                this.slideBuffer();
            }
        }
        this.size += readable;
        return readable;
    }

    private slideBuffer(): void {
        System.arraycopy(this.buf, this.windowSize, this.buf, 0, this.windowSize * 2);
        this.writeIndex -= this.windowSize;
        this.readIndex -= this.windowSize;
    }

    public startBackReference(offset: int, length: Long): void {
        if (offset <= 0 || offset > this.writeIndex) {
            throw new Exception();
        }
        if (length.lt(0)) {
            throw new Exception();
        }
        this.backReferenceOffset = offset;
        this.bytesRemaining = length;
    }

    protected readBackReference(b: Int8Array, off: int, len: int): int {
        let avail: int = this.available();
        if (len > avail) {
            this.tryToCopy(len - avail);
        }
        return this.readFromBuffer(b, off, len);
    }

    private tryToCopy(bytesToCopy: int): void {

        let copy: int = Math.min(Math.min(bytesToCopy, this.bytesRemaining.toNumber()),
            this.buf.length - this.writeIndex);
        if (copy == 0) {

        } else if (this.backReferenceOffset == 1) { // pretty common special case
            let last: number = this.buf[this.writeIndex - 1];
            Arrays.fillWithin(this.buf, this.writeIndex, this.writeIndex + copy, last);
            this.writeIndex += copy;
        } else if (copy < this.backReferenceOffset) {
            System.arraycopy(this.buf, this.writeIndex - this.backReferenceOffset, this.buf, this.writeIndex, copy);
            this.writeIndex += copy;
        } else {

            let fullRots: int = copy / this.backReferenceOffset;
            for (let i: int = 0; i < fullRots; i++) {
                System.arraycopy(this.buf, this.writeIndex - this.backReferenceOffset, this.buf, this.writeIndex, this.backReferenceOffset);
                this.writeIndex += this.backReferenceOffset;
            }

            let pad: int = copy - (this.backReferenceOffset * fullRots);
            if (pad > 0) {
                System.arraycopy(this.buf, this.writeIndex - this.backReferenceOffset, this.buf, this.writeIndex, pad);
                this.writeIndex += pad;
            }
        }
        this.bytesRemaining = this.bytesRemaining.sub(copy);
    }

    public readOneByte(): int {
        let b: int = this.in.read();
        if (b != -1) {
            this.count(Long.fromNumber(1));
            return b & 0xFF;
        }
        return -1;
    }
}
