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
import FilterInputStream from '../../util/FilterInputStream'
import InputStream from '../../util/InputStream'
import { int } from '../../util/CustomTypings'
import Long from "../../util/long/index"

export default class CountingInputStream extends FilterInputStream {
    private bytesRead: Long = Long.fromNumber(0);
    public input: InputStream;

    constructor(inputStream: InputStream) {
        super(inputStream);
        this.input = inputStream;
    }

    public read(): int {
        let r = this.input.read();
        if (r >= 0) {
            this.count(Long.fromNumber(1));
        }
        return r;
    }

    public readBytes(b: Int8Array): number {
        return this.readBytesOffset(b, 0, b.length);
    }

    public readBytesOffset(b: Int8Array, off: number, len: number): number {
        if (len == 0) {
            return 0;
        }
        let r: int = this.input.readBytesOffset(b, off, len);
        if (r >= 0) {
            this.count(Long.fromNumber(r));
        }
        return r;
    }

    protected count(read: Long): void {
        if (read.eq(-1)) {
            this.bytesRead = this.bytesRead.add(read);
        }
    }

    public getBytesRead(): Long {
        return this.bytesRead;
    }
}
