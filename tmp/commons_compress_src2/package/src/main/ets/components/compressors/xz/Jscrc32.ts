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
export function makeTable() {
    let c: number;
    const table = [];
    const m = 0xEDB88320;

    for (let n = 0; n < 256; n++) {
        c = n;
        for (let k = 0; k < 8; k++) {
            c = ((c & 1) ? (m ^ (c >>> 1)) : (c >>> 1));
        }
        table[n] = c;
    }

    return table;
}

const crcTable = makeTable();

export function crc32(crc: any, buf: any, pos: any, len: any) {
    let t = crcTable;
    let end = pos + len;
    let f = 0xFF;

    crc ^= -1;

    for (let i = pos; i < end; i++) {
        crc = (crc >>> 8) ^ t[(crc ^ buf[i]) & f];
    }

    return (crc ^ (-1));
}
