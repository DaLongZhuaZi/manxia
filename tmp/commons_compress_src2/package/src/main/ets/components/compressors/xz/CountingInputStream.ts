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
import CloseIgnoringInputStream from './CloseIgnoringInputStream'
import InputStream from '../../util/InputStream';
import Long from "../../util/long/index"

export default class CountingInputStream extends CloseIgnoringInputStream {
    private size: Long = Long.fromNumber(0);
    private inputStream: InputStream

    constructor(inputStream: InputStream) {
        super();
        this.inputStream = inputStream
    }

    public read(): number {
        let ret = this.inputStream.read();
        if (ret != -1 && this.size >= Long.fromNumber(0)) {
            this.size = this.size.add(1);
        }

        return ret;
    }

    public readBytesOffset(buf: Int8Array, off: number, len: number) {
        let ret: number = this.inputStream.readBytesOffset(buf, off, len);
        if (ret > 0 && this.size >= Long.fromNumber(0)) {
            this.size = this.size.add(Long.fromNumber(ret));
        }

        return ret;
    }

    public getSize(): Long {
        return this.size;
    }
}
