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


import type InputStreamStatistics from '../../util/InputStreamStatistics';
import CompressorInputStream from '../CompressorInputStream';
import InputStream from '../../util/InputStream';
import BrotliInputStream from './BrotliInputStream';
import Long from "../../util/long/index";
import IOUtils from '../../util/IOUtils'

export default class BrotliCompressorInputStream extends CompressorInputStream
implements InputStreamStatistics {
    private countingStream: InputStream;
    private decIS: BrotliInputStream;

    constructor(ins: InputStream) {
        super();
        this.countingStream = ins;
        this.decIS = new BrotliInputStream(this.countingStream, 16384);
    }

    public available(): number {
        return this.decIS.available();
    }

    public close(): void {
        this.decIS.close();
    }

    public readBytes(b: Int8Array): number {
        return this.decIS.readBytes(b);
    }

    public skip(n: number): number {
        let st: Long = Long.fromNumber(n)
        return IOUtils.skip(this.decIS, st).toNumber();
    }

    public mark(readlimit: number): void {
        this.decIS.mark(readlimit);
    }

    public markSupported(): boolean {
        return this.decIS.markSupported();
    }

    public read(): number {

        let ret: number = this.decIS.read();
        this.counts(Long.fromNumber(ret == -1 ? 0 : 1));
        return ret;
    }

    public readBytesOffset(buf: Int8Array, off: number, len: number): number {
        let ret: number = this.decIS.readBytesOffset(buf, off, len);
        this.counts(Long.fromNumber(ret));
        return ret;
    }

    public toString(): string {
        return this.decIS.toString();
    }

    public reset(): void {
        this.decIS.reset();
    }

    public getCompressedCount(): Long {
        return Long.fromNumber(this.countingStream.getBytesCount());
    }
}
