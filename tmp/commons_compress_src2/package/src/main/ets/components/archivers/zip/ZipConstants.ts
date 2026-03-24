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

export default class ZipConstants {
    static LOCSIG: Long = Long.fromNumber(0x04034b50);
    static EXTSIG: Long = Long.fromNumber(0x08074b50);
    static CENSIG: Long = Long.fromNumber(0x02014b50);
    static ENDSIG: Long = Long.fromNumber(0x06054b50);
    static LOCHDR: int = 30;
    static EXTHDR: int = 16;
    static CENHDR: int = 46;
    static ENDHDR: int = 22;
    static LOCVER: int = 4; // version needed to extract
    static LOCFLG: int = 6; // general purpose bit flag
    static LOCHOW: int = 8; // compression method
    static LOCTIM: int = 10; // modification time
    static LOCCRC: int = 14; // uncompressed file crc-32 value
    static LOCSIZ: int = 18; // compressed size
    static LOCLEN: int = 22; // uncompressed size
    static LOCNAM: int = 26; // filename length
    static LOCEXT: int = 28; // extra field length

    static EXTCRC: int = 4; // uncompressed file crc-32 value
    static EXTSIZ: int = 8; // compressed size
    static EXTLEN: int = 12; // uncompressed size


    static CENVEM: int = 4; // version made by
    static CENVER: int = 6; // version needed to extract
    static CENFLG: int = 8; // encrypt, decrypt flags
    static CENHOW: int = 10; // compression method
    static CENTIM: int = 12; // modification time
    static CENCRC: int = 16; // uncompressed file crc-32 value
    static CENSIZ: int = 20; // compressed size
    static CENLEN: int = 24; // uncompressed size
    static CENNAM: int = 28; // filename length
    static CENEXT: int = 30; // extra field length
    static CENCOM: int = 32; // comment length
    static CENDSK: int = 34; // disk number start
    static CENATT: int = 36; // internal file attributes
    static CENATX: int = 38; // external file attributes
    static CENOFF: int = 42; // LOC header offset

    static ENDSUB: int = 8; // number of entries on this disk
    static ENDTOT: int = 10; // total number of entries
    static ENDSIZ: int = 12; // central directory size in bytes
    static ENDOFF: int = 16; // offset of first CEN header
    static ENDCOM: int = 20; // zip file comment length
}
