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
import IndexOutOfBoundsException from './IndexOutOfBoundsException';
import NullPointerException from './NullPointerException';
import fs from '@ohos.file.fs';


export default class OutputStream {
    protected writer: any;
    protected buf: number[] = new Array<number>();
    count: number = 0;

    constructor() {
    }

    setFilePath(path: string) {
        this.writer = fs.openSync(path, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
    }

    public write(b: /*int*/
    number): void {
        if (this.writer != null) {
            this.buf[this.count] = b;
            this.count += 1;
        }
    };

    public writeBytes(b: Int8Array): void {
        this.writeBytesOffset(b, 0, b.length);
    }

    public writeBytesOffset(b: Int8Array, off: /*int*/
    number, len: /*int*/
    number): void {
        if (b == null) {
            throw new NullPointerException();
        } else if ((off < 0) || (off > b.byteLength) || (len < 0) ||
        ((off + len) > b.byteLength) || ((off + len) < 0)) {
            throw new IndexOutOfBoundsException();
        } else if (len === 0) {
            return;
        }
        for (let i = 0; i < len; i++) {
            this.write(b[off + i]);
        }
    }

    public flush(): void {
    }

    public close(): void {
        if (this.writer != null) {
            let data = new Int8Array(this.buf);
            fs.writeSync(this.writer.fd, data.buffer);
            fs.closeSync(this.writer);
            this.writer = null;
        }
    }
}
