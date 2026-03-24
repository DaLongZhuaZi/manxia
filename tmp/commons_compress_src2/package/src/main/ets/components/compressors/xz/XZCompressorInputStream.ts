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
import XZ from './XZ';
import CompressorInputStream from '../CompressorInputStream';
import InputStream from '../../util/InputStream';
import Exception from '../../util/Exception';
import IOUtils from '../../util/IOUtils';
import XZInputStream from './XZInputStream';
import SingleXZInputStream from './SingleXZInputStream';
import ArrayCache from './ArrayCache'
import Long from "../../util/long/index";

export default class XZCompressorInputStream extends CompressorInputStream {
    private countingStream: InputStream;
    private input: InputStream;

    public static matches(signature: Int8Array, length: number): boolean {
        if (length < XZ.HEADER_MAGIC.length) {
            return false;
        }

        for (let i = 0; i < XZ.HEADER_MAGIC.length; ++i) {
            if (signature[i] != XZ.HEADER_MAGIC[i]) {
                return false;
            }
        }

        return true;
    }

    constructor(inputStream: InputStream, decompressConcatenated: boolean, memoryLimitInKb: number) {
        super()
        this.countingStream = inputStream;
        if (decompressConcatenated) {
            this.input = new XZInputStream(this.countingStream, memoryLimitInKb, decompressConcatenated, ArrayCache.getDefaultCache());
        } else {
            this.input = new SingleXZInputStream(this.countingStream, memoryLimitInKb, true, ArrayCache.getDefaultCache());
        }
    }

    public read(): number {
        try {
            let ret: number = this.input.read();
            this.counts(Long.fromNumber(ret == -1 ? -1 : 1));
            return ret;
        } catch (e) {
            throw new Exception(e);
        }
    }

    public readBytesOffset(buf: Int8Array, off: number, len: number): number {
        if (len == 0) {
            return 0;
        }
        try {
            let ret: number = this.input.readBytesOffset(buf, off, len);
            this.counts(Long.fromNumber(ret));
            return ret;
        } catch (e) {
            throw new Exception(e);
        }
    }

    public skips(n: Long): Long {
        try {
            return IOUtils.skip(this.input, n);
        } catch (e) {
            throw new Exception(e);
        }
    }

    public available(): number{
        return this.input.available();
    }

    public close(): any{
        this.input.close();
    }

    public getCompressedCount(): number {
        return this.countingStream.read();
    }
}
