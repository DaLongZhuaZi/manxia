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
import Exception from './Exception';
import OutputStream from './OutputStream';
import ByteBuffer from './ByteBuffer';
import ByteOrder from './ByteOrder';
import type WritableByteChannel from './WritableByteChannel';

class BufferAtATimeOutputChannel implements WritableByteChannel {
    private out: OutputStream;
    private closed: boolean = false;

    constructor(out: OutputStream) {
        this.out = out;
    }

    public writeByteBuffer(buffer: ByteBuffer): number {
        if (!this.isOpen()) {
            throw new Exception();
        }
        if (!buffer.hasArray()) {
            throw new Exception("Direct buffer somehow written to BufferAtATimeOutputChannel");
        }
        try {
            let pos: number = buffer.positionValue();
            let len: number = buffer.limitValue() - pos;
            this.out.writeBytesOffset(buffer.array(), buffer.arrayOffset() + pos, len);
            buffer.positions(buffer.limitValue());
            return len;
        } catch (e) {
            this.close();
        }
    }

    public isOpen(): boolean {
        return!this.closed;
    }

    public close(): void {
        if (this.closed == false) {
            this.closed = true;
            this.out.close();
        }
    }
}

export default class FixedLengthBlockOutputStream extends OutputStream implements WritableByteChannel {
    private out: WritableByteChannel;
    private blockSize: number;
    private buffer: ByteBuffer;
    private closed: boolean = false;

    constructor(os: OutputStream, blockSize: number) {
        super();
        this.out = new BufferAtATimeOutputChannel(os);
        this.buffer = ByteBuffer.allocate(blockSize);
        this.blockSize = blockSize;
    }

    private maybeFlush(): void {
        if (!this.buffer.hasRemaining()) {
            this.writeBlock();
        }
    }

    private writeBlock(): void {
        this.buffer.flip();
        let i: number = this.out.writeByteBuffer(this.buffer);
        let hasRemaining: boolean = this.buffer.hasRemaining();
        if (i != this.blockSize || hasRemaining) {
            let msg: string = `Failed to write ${this.blockSize} bytes atomically. Only wrote  ${i}`;
            throw new Exception(msg);
        }
        this.buffer.clear();
    }

    public write(b: number): void {
        if (!this.isOpen()) {
            throw new Exception();
        }
        this.buffer.put(b);
        this.maybeFlush();
    }

    public writeBytesOffset(b: Int8Array, offset: /*int*/
    number, length: /*int*/
    number): void {
        if (!this.isOpen()) {
            throw new Exception();
        }
        let off: number = offset;
        let len: number = length;
        while (len > 0) {
            let n: number = Math.min(len, this.buffer.remaining());
            this.buffer.putBytesOffset(b, off, n);
            this.maybeFlush();
            len -= n;
            off += n;
        }
    }

    public writeByteBuffer(src: ByteBuffer): number {
        if (!this.isOpen()) {
            throw new Exception();
        }
        let srcRemaining: number = src.remaining();

        if (srcRemaining < this.buffer.remaining()) {
            // if don't have enough bytes in src to fill up a block we must buffer
            this.buffer.putByteBuffer(src);
        } else {
            let srcLeft: number = srcRemaining;
            let savedLimit: number = src.limitValue();

            if (this.buffer.positionValue() != 0) {
                let n: number = this.buffer.remaining();
                src.limits(src.positionValue() + n);
                this.buffer.putByteBuffer(src);
                this.writeBlock();
                srcLeft -= n;
            }

            while (srcLeft >= this.blockSize) {
                src.limits(src.positionValue() + this.blockSize);
                this.out.writeByteBuffer(src);
                srcLeft -= this.blockSize;
            }
            // copy any remaining bytes into buffer
            src.limits(savedLimit);
            this.buffer.putByteBuffer(src);
        }
        return srcRemaining;
    }

    public isOpen(): boolean {
        if (!this.out.isOpen()) {
            this.closed = true;
        }
        return!this.closed;
    }

    public flushBlock(): void {
        if (this.buffer.positionValue() != 0) {
            this.padBlock();
            this.writeBlock();
        }
    }

    public close(): void {
        if (this.closed == false) {
            this.closed = true;
            try {
                this.flushBlock();
            } finally {
                this.out.close();
            }
        }
    }

    private padBlock(): void {
        this.buffer.order(ByteOrder.nativeOrder());
        let bytesToWrite: number = this.buffer.remaining();
        if (bytesToWrite > 8) {
            let align: number = this.buffer.positionValue() & 7;
            if (align != 0) {
                let limit: number = 8 - align;
                for (let i: number = 0; i < limit; i++) {
                    this.buffer.put(0);
                }
                bytesToWrite -= limit;
            }

            while (bytesToWrite >= 8) {
                this.buffer.putLong(Long.fromNumber(0));
                bytesToWrite -= 8;
            }
        }
        while (this.buffer.hasRemaining()) {
            this.buffer.put(0);
        }
    }
}