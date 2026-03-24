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
import RangeEncoder from './RangeEncoder'
import ArrayCache from '../ArrayCache'
import OutputStream from '../../../util/OutputStream'

export default class RangeEncoderToBuffer extends RangeEncoder {
    private buf: Int8Array;
    private bufPos: number;

    constructor(bufSize: number, arrayCache: ArrayCache) {
        super()
        this.buf = arrayCache.getByteArray(bufSize, false);
        this.reset();
    }

    public putArraysToCache(arrayCache: ArrayCache): void {
        arrayCache.putArrayInt8Array(this.buf);
    }

    public reset(): void {
        super.reset();
        this.bufPos = 0;
    }

    public getPendingSize(): number {
        return this.bufPos + this.cacheSize.toInt() + 5 - 1;
    }

    public finish(): number {
        try {
            super.finish();
        } catch (e) {
            throw new Error();
        }

        return this.bufPos;
    }

    public writeBytesOffset(out: OutputStream): void {
        out.writeBytesOffset(this.buf, 0, this.bufPos);
    }

    writeByte(b: number): void {
        this.buf[this.bufPos++] = b;
    }
}
