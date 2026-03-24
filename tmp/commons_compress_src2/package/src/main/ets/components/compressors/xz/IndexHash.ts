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
import CheckedInputStream from './CheckedInputStream';
import InputStream from '../../util/InputStream'
import DataInputStream from '../DataInputStream'
import IndexBase from './IndexBase'
import { SHA256, CRC32 } from './Check'
import Check from './Check'
import ByteBuffer from '../../util/ByteBuffer'
import Newcrc32 from './Newcrc32'
import DecoderUtil from './DecoderUtil'
import Arrays from '../../util/Arrays'
import Long from "../../util/long/index"

export default class IndexHash extends IndexBase {
    private hash: Check;

    constructor() {
        super(new Exception());
        try {
            this.hash = new SHA256();
        } catch (e) {
            this.hash = new CRC32();
        }

    }

    public add(unpaddedSize: Long, uncompressedSize: Long): void {
        super.add(unpaddedSize, uncompressedSize);
        let buf: ByteBuffer = ByteBuffer.allocate(16);
        buf.putLong(unpaddedSize);
        buf.putLong(uncompressedSize);
        this.hash.updateI(buf.array());
    }

    public validate(inputStream: InputStream) {
        let crc32: Newcrc32 = new Newcrc32();
        crc32.update(0);
        let inChecked: CheckedInputStream = new CheckedInputStream(inputStream, crc32);
        let storedRecordCount: Long = DecoderUtil.decodeVLI(inChecked);
        if (!storedRecordCount.eq(this.recordCount)) {
            throw new Exception("XZ Block Header or the start of XZ Index is corrupt");
        }
        let stored: IndexHash = new IndexHash();
        for (let i: Long = Long.fromNumber(0); i.lessThan(this.recordCount); i = i.add(1)) {
            let unpaddedSize: Long = DecoderUtil.decodeVLI(inChecked);
            let uncompressedSize: Long = DecoderUtil.decodeVLI(inChecked);

            try {
                stored.add(unpaddedSize, uncompressedSize);
            } catch (e) {
                throw new Exception("XZ Index is corrupt");
            }

            if (stored.blocksSum.greaterThan(this.blocksSum)
            || stored.uncompressedSum.greaterThan(this.uncompressedSum)
            || stored.indexListSize.greaterThan(this.indexListSize)) {
                throw new Exception("XZ Index is corrupt");
            }
        }

        if (!stored.blocksSum.eq(this.blocksSum)
        || !stored.uncompressedSum.eq(this.uncompressedSum)
        || !stored.indexListSize.eq(this.indexListSize)
        || !Arrays.equals(stored.hash.finish(), this.hash.finish()))
        throw new Exception("XZ Index is corrupt");

        let inData: DataInputStream = new DataInputStream(inChecked);
        for (let i: number = this.getIndexPaddingSize(); i > 0; --i)
        if (inData.readUnsignedByte() != 0x00)
        throw new Exception("XZ Index is corrupt");

        let value: Long = crc32.getValue();
        for (let i: number = 0; i < 4; ++i) {
            let val = value.shiftRightUnsigned(i * 8)
            if (!(val.and(255)).eq(inData.readUnsignedByte()))
            throw new Exception("XZ Index is corrupt");
        }
    }
}
