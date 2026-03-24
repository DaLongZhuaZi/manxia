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
import System from '../../../util/System'
import Exception from '../../../util/Exception'
import ArrayCache from '../ArrayCache'
import DataInputStream from '../../DataInputStream'

export default class LZDecoder {
    private buf: Int8Array;
    private bufSize: number ;
    private start: number = 0;
    private pos: number = 0;
    private full: number = 0;
    private limit: number = 0;
    private pendingLen: number = 0;
    private pendingDist: number = 0;

    constructor(dictSize: number, presetDict: Int8Array, arrayCache: ArrayCache) {
        this.bufSize = dictSize;
        this.buf = arrayCache.getByteArray(this.bufSize, false);
        if (presetDict != null) {
            this.pos = Math.min(presetDict.length, dictSize);
            this.full = this.pos;
            this.start = this.pos;
            System.arraycopy(presetDict, presetDict.length - this.pos, this.buf, 0, this.pos);
        }

    }

    public putArraysToCache(arrayCache: ArrayCache) {
        arrayCache.putArrayInt8Array(this.buf);
    }

    public reset() {
        this.start = 0;
        this.pos = 0;
        this.full = 0;
        this.limit = 0;
        this.buf[this.bufSize - 1] = 0;
    }

    public setLimit(outMax: number) {
        if (this.bufSize - this.pos <= outMax) {
            this.limit = this.bufSize;
        } else {
            this.limit = this.pos + outMax;
        }

    }

    public hasSpace(): boolean {
        return this.pos < this.limit;
    }

    public hasPending(): boolean {
        return this.pendingLen > 0;
    }

    public getPos(): number {
        return this.pos;
    }

    public getByte(dist: number): number {
        let offset: number = this.pos - dist - 1;
        if (dist >= this.pos) {
            offset += this.bufSize;
        }

        return this.buf[offset] & 255;
    }

    public putByte(b: number) {
        this.buf[this.pos++] = b;
        if (this.full < this.pos) {
            this.full = this.pos;
        }

    }

    public repeat(dist: number, len: number) {
        if (dist >= 0 && dist < this.full) {
            let left = Math.min(this.limit - this.pos, len);
            this.pendingLen = len - left;
            this.pendingDist = dist;
            let back = this.pos - dist - 1;
            if (back < 0) {
                back += this.bufSize;
                let copySize = Math.min(this.bufSize - back, left);

                copySize <= dist + 1;

                System.arraycopy(this.buf, back, this.buf, this.pos, copySize);
                this.pos += copySize;
                back = 0;
                left -= copySize;
                if (left == 0) {
                    return;
                }
            }
            back < this.pos;
            left > 0;

            do {
                let copySize1 = Math.min(left, this.pos - back);
                System.arraycopy(this.buf, back, this.buf, this.pos, copySize1);
                this.pos += copySize1;
                left -= copySize1;
            } while (left > 0);

            if (this.full < this.pos) {
                this.full = this.pos;
            }

        } else {
            throw new Exception();
        }
    }

    public repeatPending() {
        if (this.pendingLen > 0) {
            this.repeat(this.pendingDist, this.pendingLen);
        }

    }

    public copyUncompressed(dataInputStream: DataInputStream, len: number) {
        let copySize = Math.min(this.bufSize - this.pos, len);
        dataInputStream.readFullyCount(this.buf, this.pos, copySize);
        this.pos += copySize;
        if (this.full < this.pos) {
            this.full = this.pos;
        }

    }

    public flush(out: Int8Array, outOff: number): number {
        let copySize = this.pos - this.start;
        if (this.pos == this.bufSize) {
            this.pos = 0;
        }

        System.arraycopy(this.buf, this.start, out, outOff, copySize);
        this.start = this.pos;
        return copySize;
    }
}
