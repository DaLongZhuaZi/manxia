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
import ArrayCache from '../ArrayCache'
import Exception from '../../../util/Exception'
import RangeDecoder from './RangeDecoder'
import InputStream from '../../../util/InputStream'
import DataInputStream from '../../DataInputStream'
import Long from "../../../util/long/index"

export default class RangeDecoderFromBuffer extends RangeDecoder {
    private static INIT_SIZE: number = 5;
    private buf: Int8Array;
    private pos: number;
    private Input: InputStream;

    constructor(inputSizeMax: number, arrayCache: ArrayCache) {
        super()
        this.buf = arrayCache.getByteArray(inputSizeMax - 5, false);
        this.pos = this.buf.length;
    }

    public putArraysToCache(arrayCache: ArrayCache): void {
        arrayCache.putArrayInt8Array(this.buf);
    }

    public prepareInputBuffer(datain: DataInputStream, len: number): void {
        if (len < RangeDecoderFromBuffer.INIT_SIZE) {
            throw new Exception();
        }


        if (datain.readUnsignedByte() != 0x00)
        throw new Exception();

        this.code = datain.readInt();
        this.range = -1;
        len -= RangeDecoderFromBuffer.INIT_SIZE;
        this.pos = this.buf.length - len;
        datain.readFullyCount(this.buf, this.pos, len);
    }

    public isFinished(): boolean {
        return this.pos == this.buf.length && this.code == 0;
    }

    public normalize(): void {
        if (Long.fromNumber(this.range).and(Long.fromString('-16777216')).eq(0)) {
            try {
                this.code = this.code << 8 | this.buf[this.pos++] & 255;
                this.range <<= 8;
            } catch (e) {
                throw new Exception();
            }
        }

    }
}
