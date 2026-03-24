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

import { int } from '../../util/CustomTypings'
import DumpArchiveConstants from './DumpArchiveConstants'
import Long from "../../util/long/index"
import ByteUtils from './ByteUtils'
import type ZipEncoding from '../zip/ZipEncoding'
import Arrays from '../../util/Arrays'


export default class DumpArchiveUtil {
    constructor() {
    }

    public static calculateChecksum(buffer: Int8Array): int {
        let calc: int = 0;

        for (let i: int = 0; i < 256; i++) {
            calc = Long.fromNumber(calc + this.convert32(buffer, 4 * i)).toInt();
        }

        return DumpArchiveConstants.CHECKSUM - (calc - this.convert32(buffer, 28));
    }

    public static verify(buffer: Int8Array): boolean {
        let magic: int = this.convert32(buffer, 24);

        if (magic != DumpArchiveConstants.NFS_MAGIC) {
            return false;
        }

        let checksum: int = this.convert32(buffer, 28);

        return checksum == this.calculateChecksum(buffer);
    }

    public static getIno(buffer: Int8Array): int {
        return this.convert32(buffer, 20);
    }

    public static convert64(buffer: Int8Array, offset: int): Long {
        return ByteUtils.fromLittleEndian(buffer, offset, 8);
    }

    public static convert32(buffer: Int8Array, offset: int): int {
        return ByteUtils.fromLittleEndian(buffer, offset, 4).toNumber();
    }

    public static convert16(buffer: Int8Array, offset: int): int {
        return ByteUtils.fromLittleEndian(buffer, offset, 2).toInt();
    }

    static decode(encoding: ZipEncoding, b: Int8Array, offset: int, len: int): string{
        let data: Int8Array = new Int8Array(Arrays.copyOfRangeInt(new Int32Array(b), offset, offset + len).buffer)
        return encoding.decode(data);
    }
}
