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
import Long from "../../util/long/index"


export default class ZipConstants64 {
    static ZIP64_ENDSIG: Long = Long.fromNumber(0x06064b50); // "PK\006\006"
    static ZIP64_LOCSIG: Long = Long.fromNumber(0x07064b50); // "PK\006\007"
    static ZIP64_ENDHDR: int = 56; // ZIP64 end header size
    static ZIP64_LOCHDR: int = 20; // ZIP64 end loc header size
    static ZIP64_EXTHDR: int = 24; // EXT header size
    static ZIP64_EXTID: int = 0x0001; // Extra field Zip64 header ID

    static ZIP64_MAGICCOUNT: int = 0xFFFF;
    static ZIP64_MAGICVAL: Long = Long.fromNumber(0xFFFFFFFF);
    static ZIP64_ENDLEN: int = 4; // size of zip64 end of central dir
    static ZIP64_ENDVEM: int = 12; // version made by
    static ZIP64_ENDVER: int = 14; // version needed to extract
    static ZIP64_ENDNMD: int = 16; // number of this disk
    static ZIP64_ENDDSK: int = 20; // disk number of start
    static ZIP64_ENDTOD: int = 24; // total number of entries on this disk
    static ZIP64_ENDTOT: int = 32; // total number of entries
    static ZIP64_ENDSIZ: int = 40; // central directory size in bytes
    static ZIP64_ENDOFF: int = 48; // offset of first CEN header
    static ZIP64_ENDEXT: int = 56; // zip64 extensible data sector

    static ZIP64_LOCDSK: int = 4; // disk number start
    static ZIP64_LOCOFF: int = 8; // offset of zip64 end
    static ZIP64_LOCTOT: int = 16; // total number of disks

    static ZIP64_EXTCRC: int = 4; // uncompressed file crc-32 value
    static ZIP64_EXTSIZ: int = 8; // compressed size, 8-byte
    static ZIP64_EXTLEN: int = 16; // uncompressed size, 8-byte

    static EFS: int = 0x800; // If this bit is set the filename and
    static EXTID_ZIP64: int = 0x0001; // Zip64
    static EXTID_NTFS: int = 0x000a; // NTFS
    static EXTID_UNIX: int = 0x000d; // UNIX
    static EXTID_EXTT: int = 0x5455; // Info-ZIP Extended Timestamp


    static EXTT_FLAG_LMT: int = 0x1; // LastModifiedTime
    static EXTT_FLAG_LAT: int = 0x2; // LastAccessTime
    static EXTT_FLAT_CT: int = 0x4; // CreationTime

    private ZipConstants64() {
    }
}
