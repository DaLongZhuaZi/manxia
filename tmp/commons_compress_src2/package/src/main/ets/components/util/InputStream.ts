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

export default class InputStream {
    MAX_SKIP_BUFFER_SIZE: number = 2048;
    _readerPosition: number = 0;
    _endPosition: number = 0;
    _fileInt8Array: Uint8Array;
    _path: string;
    _markPos: number;
    _markLimit: number;

    constructor() {
    }

    setFilePath(path: string) {
        this._path = path;
        let stat = fs.statSync(path)
        let size = stat.size;
        let contentBuffer = new ArrayBuffer(size);
        const reader = fs.openSync(path, fs.OpenMode.READ_ONLY);
        fs.readSync(reader.fd, contentBuffer);
        this._endPosition = size;
        this._fileInt8Array = new Uint8Array(contentBuffer);
        fs.closeSync(reader);
    }

    public read(): number {
        if (this._readerPosition >= this._endPosition
        || this._endPosition == 0 || this._fileInt8Array == null) {
            return -1;
        }
        let readValue: number = this._fileInt8Array[this._readerPosition]
        this._readerPosition++;
        return readValue;
    }

    public readBytes(b: Int8Array): number {
        return this.readBytesOffset(b, 0, b.length);
    }

    public readBytesOffset(b: Int8Array, off: number, len: number): number {
        if (b == null) {
            throw new NullPointerException();
        } else if (off < 0 || len < 0 || len > b.byteLength - off) {
            throw new IndexOutOfBoundsException();
        } else if (len == 0) {
            return 0;
        }

        let c = this.read();
        if (c == -1) {
            return -1;
        }
        b[off] = c;
        let i = 1;
        for (; i < len; i++) {
            c = this.read();
            if (c == -1) {
                break;
            }
            b[off + i] = c;
        }
        return i;
    }

    public skip(n: number): number {
        let remaining = n;
        let nr;
        if (n <= 0) {
            return 0;
        }
        const size = Math.min(this.MAX_SKIP_BUFFER_SIZE, remaining);
        const skipBuffer = new Int8Array(size);
        while (remaining > 0) {
            nr = this.readBytesOffset(skipBuffer, 0, Math.min(size, remaining));
            if (nr < 0) {
                break;
            }
            remaining -= nr;
        }
        return n - remaining;
    }

    public available(): number {
        return this._readerPosition;
    }

    public getBytesCount(): number {
        return this._readerPosition;
    }

    public markSupported(): boolean {
        return true;
    }

    public close(): void {
        this._fileInt8Array = null;
        this._readerPosition = 0;
        this._endPosition = 0;
        this._path = null;
        this._markPos = 0;
    }

    public mark(readlimit: number): void {
        if (this._fileInt8Array != null) {
            this._markPos = this._readerPosition;
            this._markLimit = readlimit;
        }
    }

    public reset(): void {
        if (this._fileInt8Array != null && typeof (this._markPos) != 'undefined') {
            this._readerPosition = this._markPos;
        }
    }
}
