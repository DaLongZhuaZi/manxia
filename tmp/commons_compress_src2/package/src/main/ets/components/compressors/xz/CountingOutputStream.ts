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
import FinishableOutputStream from './FinishableOutputStream'
import Long from "../../util/long/index"
import OutputStream from '../../util/OutputStream'

export default class CountingOutputStream extends FinishableOutputStream {
    private out: OutputStream;
    private size: Long = Long.fromNumber(0) ;

    constructor(out: OutputStream) {
        super()
        this.out = out;
    }

    public write(b: number): void {
        this.out.write(b);
        if (this.size.greaterThanOrEqual(0)) {
            this.size = this.size.add(1);
        }

    }

    public writeBytesOffset(buf: Int8Array, off: number, len: number): void{
        this.out.writeBytesOffset(buf, off, len);
        if (this.size.greaterThanOrEqual(0)) {
            this.size = this.size.add(len);
        }

    }

    public flush(): void {
        this.out.flush();
    }

    public close(): void {
        this.out.close();
    }

    public getSize(): Long {
        return this.size;
    }
}
