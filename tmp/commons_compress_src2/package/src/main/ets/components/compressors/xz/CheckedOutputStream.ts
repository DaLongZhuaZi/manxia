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
import OutputStream from '../../util/OutputStream'
import type Checksum from './Checksum'

export default class CheckedOutputStream extends OutputStream {
    private cksum: Checksum;
    private out: OutputStream;

    constructor(out: OutputStream, cksum: Checksum) {
        super();
        this.cksum = cksum;
        this.out = out
    }

    public write(b: number): void {
        this.out.write(b);
        this.cksum.update(b);
    }

    public writeBytesOffset(b: Int8Array, off: number, len: number): void {
        this.out.writeBytesOffset(b, off, len);
        this.cksum.updates(b, off, len);
    }

    public getChecksum(): Checksum {
        return this.cksum;
    }
}
