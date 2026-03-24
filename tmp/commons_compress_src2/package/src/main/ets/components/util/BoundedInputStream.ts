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
import InputStream from './InputStream';
import Long from "./long/index";

export default class BoundedInputStream extends InputStream {
    private inputStream: InputStream;
    private bytesRemaining: Long;

    constructor(inputStream: InputStream, size: Long) {
        super();
        this.inputStream = inputStream;
        this.bytesRemaining = size;
    }

    public read(): number {
        if (this.bytesRemaining.greaterThan(0)) {
            this.bytesRemaining = this.bytesRemaining.sub(1);
            return this.inputStream.read();
        }
        return -1;
    }

    public readBytesOffset(b: Int8Array, off: number, len: number): number {
        if (len == 0) {
            return 0;
        }
        if (this.bytesRemaining.toNumber() == 0) {
            return -1;
        }
        let bytesToRead: number = len;
        if (this.bytesRemaining.lessThan(bytesToRead)) {
            bytesToRead = this.bytesRemaining.getLowBits();
        }
        let bytesRead: number = this.inputStream.readBytesOffset(b, off, bytesToRead);
        if (bytesRead >= 0) {
            this.bytesRemaining = this.bytesRemaining.sub(bytesRead);
        }
        return bytesRead;
    }

    public skip(n: number): number {
        let bytesToSkip: number = Math.min(this.bytesRemaining.toNumber(), n);
        let bytesSkipped: number = this.inputStream.skip(bytesToSkip);
        this.bytesRemaining = this.bytesRemaining.sub(bytesSkipped);
        return bytesSkipped;
    }

    public getBytesRemaining(): Long {
        return this.bytesRemaining;
    }
}