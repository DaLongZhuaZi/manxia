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
import Exception from './Exception';
import OutputStream from './OutputStream';


export default class FilterOutputStream extends OutputStream {
    protected out: OutputStream;

    constructor(out: OutputStream) {
        super()
        this.out = out;
    }

    public write(b: number): void {
        this.out.write(b);
    }

    public writeBytes(b: Int8Array): void {
        this.writeBytesOffset(b, 0, b.length);
    }

    public writeBytesOffset(b: Int8Array, off: number, len: number): void {
        if ((off | len | (b.length - (len + off)) | (off + len)) < 0)
        throw new Exception();

        for (let i = 0; i < len; i++) {
            this.write(b[off + i]);
        }
    }

    public flush(): void {
        this.out.flush();
    }

    public close(): void{
        let ostream: OutputStream = this.out
        try {
            this.flush();
        } catch (e) {
            throw new Exception(e);
        }
        ostream.close()
    }
}
