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
import InputStream from './InputStream'
import { int } from './CustomTypings'

export default class FilterInputStream extends InputStream {
    public input: InputStream;

    constructor(inputStream: InputStream) {
        super()
        this.input = inputStream;
    }

    public read(): int {
        return this.input.read();
    }

    public readBytes(b: Int8Array): int {
        return this.readBytesOffset(b, 0, b.length);
    }

    public readBytesOffset(b: Int8Array, off: int, len: int): int {
        return this.input.readBytesOffset(b, off, len);
    }

    public skip(n: number): number {
        return this.input.skip(n);
    }

    public available(): int {
        return this.input.available();
    }

    public close(): void {
        this.input.close();
    }

    public mark(readlimit: int): void {
        this.input.mark(readlimit);
    }

    public reset(): void {
        this.input.reset();
    }

    public markSupported(): boolean {
        return this.input.markSupported();
    }
}
