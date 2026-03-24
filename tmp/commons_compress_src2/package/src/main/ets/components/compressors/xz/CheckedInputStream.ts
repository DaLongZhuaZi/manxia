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
/**
 * An input stream that also maintains a checksum of the data being read.
 * The checksum can then be used to verify the integrity of the input data.
 *
 * @see         Checksum
 * @author      David Connelly
 */
import InputStream from '../../util/InputStream'
import type Checksum from './Checksum'
import Long from "../../util/long/index"

export default class CheckedInputStream extends InputStream {
    private cksum: Checksum;
    private input: InputStream;

    constructor(input: InputStream, cksum: Checksum) {
        super();
        this.cksum = cksum;
        this.input = input
    }

    public read(): number {
        let b: number = this.input.read();
        if (b != -1) {
            this.cksum.update(b);
        }
        return b;
    }

    public readBytesOffset(buf: Int8Array, off: number, len: number): number {
        len = this.input.readBytesOffset(buf, off, len);
        if (len != -1) {
            this.cksum.updates(buf, off, len);
        }
        return len;
    }

    public skips(n: Long): Long {
        let buf: Int8Array = new Int8Array(512);
        let total: Long = Long.fromNumber(0);
        while (total < n) {
            let len: number = n.sub(total).toNumber();
            len = this.readBytesOffset(buf, 0, len < buf.length ? len : buf.length);
            if (len == -1) {
                return total;
            }
            total = total.add(len);
        }
        return total;
    }

    public getChecksum(): Checksum {
        return this.cksum;
    }
}
