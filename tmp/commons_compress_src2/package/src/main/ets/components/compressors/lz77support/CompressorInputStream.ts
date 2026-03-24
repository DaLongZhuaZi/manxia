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
import InputStream from '../../util/InputStream'
import Long from "../../util/long/index"
import { int } from '../../util/CustomTypings'

export default class CompressorInputStream extends InputStream {
    private bytesRead: Long = Long.fromNumber(0);

    protected countInt(read: int): void {
        this.count(Long.fromNumber(read));
    }

    protected count(read: Long): void {
        if (!read.eq(-1)) {
            this.bytesRead = this.bytesRead.add(read);
        }
    }

    protected pushedBackBytes(pushedBack: Long): void {
        this.bytesRead = this.bytesRead.sub(pushedBack);
    }

    public getCount(): int {
        return this.bytesRead.toInt();
    }

    public getBytesRead(): Long {
        return this.bytesRead;
    }

    public getUncompressedCount(): Long {
        return this.getBytesRead();
    }
}
