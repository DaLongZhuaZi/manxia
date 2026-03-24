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
import Exception from '../../util/Exception'
import DeltaDecoder from './delta/DeltaDecoder'

export default class DeltaInputStream extends InputStream {
    public static DISTANCE_MIN: number = 1;
    public static DISTANCE_MAX: number = 256;
    private input: InputStream;
    private delta: DeltaDecoder;
    private exception: Exception = null;
    private tempBuf: Int8Array = new Int8Array(1);

    constructor(inputStream: InputStream, distance: number) {
        super()
        if (inputStream == null) {
            throw new Exception();
        } else {
            this.input = inputStream;
            this.delta = new DeltaDecoder(distance);
        }
    }

    public read(): number {
        return this.readBytesOffset(this.tempBuf, 0, 1) == -1 ? -1 : this.tempBuf[0] & 255;
    }

    public readBytesOffset(buf: Int8Array, off: number, len: number): number {
        if (len == 0) {
            return 0;
        } else if (this.input == null) {
            throw new Exception("Stream closed");
        } else if (this.exception != null) {
            throw this.exception;
        } else {
            let size: number;
            try {
                size = this.input.readBytesOffset(buf, off, len);
            } catch (e) {
                this.exception = e;
                throw e;
            }

            if (size == -1) {
                return -1;
            } else {
                this.delta.decode(buf, off, size);
                return size;
            }
        }
    }

    public available(): number{
        if (this.input == null) {
            throw new Exception("Stream closed");
        } else if (this.exception != null) {
            throw this.exception;
        } else {
            return this.input.available();
        }
    }

    public close(): void{
        if (this.input != null) {
            try {
                this.input.close();
            } finally {
                this.input = null;
            }
        }

    }
}
