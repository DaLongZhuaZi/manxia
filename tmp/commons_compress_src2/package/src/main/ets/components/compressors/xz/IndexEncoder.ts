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
import OutputStream from '../../util/OutputStream'
import IndexBase from './IndexBase'
import IndexRecord from './IndexRecord'
import Newcrc32 from './Newcrc32'
import CheckedOutputStream from './CheckedOutputStream'
import EncoderUtil from './EncoderUtil'
import NumberTransform from "./NumberTransform";
import Long from "../../util/long/index"

export default class IndexEncoder extends IndexBase {
    private records: Array<IndexRecord> = new Array<IndexRecord>();

    constructor() {
        super(new Exception("XZ Stream or its Index has grown too big"));
    }

    public add(unpaddedSize: Long, uncompressedSize: Long): void {
        super.add(unpaddedSize, uncompressedSize);
        this.records.push(new IndexRecord(unpaddedSize, uncompressedSize));
    }

    public encode(out: OutputStream): void {
        let crc32 = new Newcrc32();
        let outChecked: CheckedOutputStream = new CheckedOutputStream(out, crc32);

        outChecked.write(0x00);

        EncoderUtil.encodeVLI(outChecked, this.recordCount);


        for (let record = 0; record < this.records.length; ++record) {
            EncoderUtil.encodeVLI(outChecked, this.records[record].unpadded);
            EncoderUtil.encodeVLI(outChecked, this.records[record].uncompressed);
        }

        for (let i = this.getIndexPaddingSize(); i > 0; --i)
        outChecked.write(0x00);

        let value: Long = crc32.getValue();
        for (let i = 0; i < 4; ++i) {
            let byteValue = value.shiftRightUnsigned(i * 8).toInt()
            out.write(NumberTransform.toByte(byteValue));
        }

    }
}
