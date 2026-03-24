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
export default class CpioConstants {
    static MAGIC_NEW: string = "070701";
    static MAGIC_NEW_CRC: string = "070702";
    static MAGIC_OLD_ASCII: string = "070707";
    static MAGIC_OLD_BINARY: number = 0o70707;
    static FORMAT_NEW: number = 1;
    static FORMAT_NEW_CRC: number = 2;
    static FORMAT_OLD_ASCII: number = 4;
    static FORMAT_OLD_BINARY: number = 8;
    static FORMAT_NEW_MASK: number = 3;
    static FORMAT_OLD_MASK: number = 12;
    static S_IFMT: number = 0o170000;
    static C_ISSOCK: number = 0o140000;
    static C_ISLNK: number = 0o120000;
    static C_ISNWK: number = 0o110000;
    static C_ISREG: number = 0o100000;
    static C_ISBLK: number = 0o060000;
    static C_ISDIR: number = 0o040000;
    static C_ISCHR: number = 0o020000;
    static C_ISFIFO: number = 0o010000;
    static C_ISUID: number = 0o004000;
    static C_ISGID: number = 0o002000;
    static C_ISVTX: number = 0o001000;
    static C_IRUSR: number = 0o000400;
    static C_IWUSR: number = 0o000200;
    static C_IXUSR: number = 0o000100;
    static C_IRGRP: number = 0o000040;
    static C_IWGRP: number = 0o000020;
    static C_IXGRP: number = 0o000010;
    static C_IROTH: number = 0o000004;
    static C_IWOTH: number = 0o000002;
    static C_IXOTH: number = 0o000001;
    static CPIO_TRAILER: string = "TRAILER!!!";
    static BLOCK_SIZE: number = 512;
}
