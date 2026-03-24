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

export enum SEGMENT_TYPE {
    TAPE = 1,
    INODE = 2,
    BITS = 3,
    ADDR = 4,
    END = 5,
    CLRI = 6
}

export enum COMPRESSION_TYPE {
    ZLIB,
    BZLIB,
    LZO
}

export enum TYPE {
    WHITEOUT = 14,
    SOCKET = 12,
    LINK = 10,
    FILE = 8,
    BLKDEV = 6,
    DIRECTORY = 4,
    CHRDEV = 2,
    FIFO = 1,
    UNKNOWN = 5
}

export enum PERMISSION {
    SETUID,
    SETGUI,
    STICKY,
    USER_READ,
    USER_WRITE,
    USER_EXEC,
    GROUP_READ,
    GROUP_WRITE,
    GROUP_EXEC,
    WORLD_READ,
    WORLD_WRITE,
    WORLD_EXEC
}