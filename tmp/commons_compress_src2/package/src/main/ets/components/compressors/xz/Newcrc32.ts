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
import Long from "../../util/long/index";
import type Checksum from './Checksum';
import { crc32 } from './Jscrc32';

export default class Newcrc32 implements Checksum {
    private crc: number = 0;
    //这个表格的结果就是上面的。
    private static crc_table: Int32Array = Newcrc32.make_crc_table();

    private static make_crc_table(): Int32Array {
        let crc_table: Int32Array = new Int32Array(256);
        for (let n = 0; n < 256; n++) {
            let c = n;
            for (let k = 8; --k >= 0; ) {
                if ((c & 1) != 0)
                c = 0xedb88320 ^ (c >>> 1);
                else
                c = c >>> 1;
            }
            crc_table[n] = c;
        }
        return crc_table;
    }

    public getValue(): Long {
        return Long.fromNumber(this.crc).and(Long.fromString("4294967295"));
    }

    public reset(): void {
        this.crc = 0;
    }
    //这里处理的很不错，可以每次都及时返回结果。
    public update(bval: number): void {
        let c = ~this.crc;
        c = Newcrc32.crc_table[(c ^ bval) & 0xff] ^ (c >>> 8);
        this.crc = ~c;
    }

    public updateArray(b: Int8Array): void {
        this.crc = crc32(this.crc, b, 0, b.length);
    }

    public updates(buf: Int8Array, off: number, len: number): void {
        let c = ~this.crc;
        while (--len >= 0)
        c = Newcrc32.crc_table[(c ^ buf[off++]) & 0xff] ^ (c >>> 8);
        this.crc = ~c;
    }
}