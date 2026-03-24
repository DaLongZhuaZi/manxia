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

export default class TarConstants {
    static DEFAULT_RCDSIZE: number = 512;
    static DEFAULT_BLKSIZE: number = TarConstants.DEFAULT_RCDSIZE * 20;
    static FORMAT_OLDGNU: number = 2;
    static FORMAT_POSIX: number = 3;
    static FORMAT_XSTAR: number = 4;
    static NAMELEN: number = 100;
    static MODELEN: number = 8;
    static UIDLEN: number = 8;
    static GIDLEN: number = 8;
    static MAXID: Long = Long.fromString('7777777');
    static CHKSUMLEN: number = 8;
    static CHKSUM_OFFSET: number = 148;
    static SIZELEN: number = 12;
    static MAXSIZE: Long = Long.fromString('77777777777');
    static MAGIC_OFFSET: number = 257;
    static MAGICLEN: number = 6;
    static VERSION_OFFSET: number = 263;
    static VERSIONLEN: number = 2;
    static MODTIMELEN: number = 12;
    static UNAMELEN: number = 32;
    static GNAMELEN: number = 32;
    static DEVLEN: number = 8;
    static PREFIXLEN: number = 155;
    static ATIMELEN_GNU: number = 12;
    static CTIMELEN_GNU: number = 12;
    static OFFSETLEN_GNU: number = 12;
    static LONGNAMESLEN_GNU: number = 4;
    static PAD2LEN_GNU: number = 1;
    static SPARSELEN_GNU: number = 96;
    static ISEXTENDEDLEN_GNU: number = 1;
    static REALSIZELEN_GNU: number = 12;
    static SPARSE_OFFSET_LEN: number = 12;
    static SPARSE_NUMBYTES_LEN: number = 12;
    static SPARSE_HEADERS_IN_OLDGNU_HEADER: number = 4;
    static SPARSE_HEADERS_IN_EXTENSION_HEADER: number = 21;
    static SPARSELEN_GNU_SPARSE: number = 504;
    static ISEXTENDEDLEN_GNU_SPARSE: number = 1;
    static LF_OLDNORM: number = 0;
    static LF_NORMAL: number = '0'.charCodeAt(0);
    static LF_LINK: number = '1'.charCodeAt(0);
    static LF_SYMLINK: number = '2'.charCodeAt(0);
    static LF_CHR: number = '3'.charCodeAt(0);
    static LF_BLK: number = '4'.charCodeAt(0);
    static LF_DIR: number = '5'.charCodeAt(0);
    static LF_FIFO: number = '6'.charCodeAt(0);
    static LF_CONTIG: number = '7'.charCodeAt(0);
    static LF_GNUTYPE_LONGLINK: number = 'K'.charCodeAt(0);
    static LF_GNUTYPE_LONGNAME: number = 'L'.charCodeAt(0);
    static LF_GNUTYPE_SPARSE: number = 'S'.charCodeAt(0);
    static LF_PAX_EXTENDED_HEADER_LC: number = 'x'.charCodeAt(0);
    static LF_PAX_EXTENDED_HEADER_UC: number = 'X'.charCodeAt(0);
    static LF_PAX_GLOBAL_EXTENDED_HEADER: number = 'g'.charCodeAt(0);
    static MAGIC_POSIX: string = "ustar\0";
    static VERSION_POSIX: string = "00";
    static MAGIC_GNU: string = "ustar ";
    static VERSION_GNU_SPACE: string = " \0";
    static VERSION_GNU_ZERO: string = "0\0";
    static MAGIC_ANT: string = "ustar\0";
    static VERSION_ANT: string = "\0\0";
    static GNU_LONGLINK: string = "././@LongLink"; // TODO rename as LONGLINK_GNU ?
    static MAGIC_XSTAR: string = "tar\0";
    static XSTAR_MAGIC_OFFSET: number = 508;
    static XSTAR_MAGIC_LEN: number = 4;
    static PREFIXLEN_XSTAR: number = 131;
    static ATIMELEN_XSTAR: number = 12;
    static CTIMELEN_XSTAR: number = 12;
}