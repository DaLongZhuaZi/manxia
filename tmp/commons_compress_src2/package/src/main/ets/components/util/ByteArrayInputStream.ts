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
import InputStream from './InputStream'
import Exception from './Exception'
import System from './System'

export default class ByteArrayInputStream extends InputStream {
    protected buf: Int8Array;
    protected pos: number;
    protected markpos: number = 0;
    protected count: number = 0;

    constructor(buf: Int8Array, offset: number, length: number | undefined) {
        super()
        this.buf = buf;
        this.pos = offset;
        if (length === undefined) {
            this.count = buf.length;
        } else {
            this.count = Math.min(offset + length, buf.length);
        }
        this.markpos = offset;
    }

    public read(): number {
        return (this.pos < this.count) ? (this.buf[this.pos++] & 0xff) : -1;
    }

    public readBytesOffset(b: Int8Array, off: number, len: number) {
        if (b == null) {
            throw new Exception();
        } else if (off < 0 || len < 0 || len > b.length - off) {
            throw new Exception();
        }

        if (this.pos >= this.count) {
            return -1;
        }

        let avail = this.count - this.pos;
        if (len > avail) {
            len = avail;
        }
        if (len <= 0) {
            return 0;
        }
        System.arraycopy(this.buf, this.pos, b, off, len);
        this.pos += len;
        return len;
    }

    public skip(n: number): number {
        let k = this.count - this.pos;
        if (n < k) {
            k = n < 0 ? 0 : n;
        }

        this.pos += k;
        return k;
    }

    public available(): number {
        let avail = this.count - this.pos;
        return avail
    }

    public markSupported(): boolean {
        return true;
    }

    public markPos(readAheadLimit: number) {
        this.markpos = this.pos;
    }

    public resetPos() {
        this.pos = this.markpos;
    }
}
