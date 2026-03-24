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
import Long from "../util/long/index";
import OutputStream from '../util/OutputStream'
import type DataOutput from './DataOutput'

export default class DataOutputStream extends OutputStream implements DataOutput {
    protected written: number;
    private bytearr: number = null;
    private outputStream: OutputStream;

    constructor(out: OutputStream) {
        super();
        this.outputStream = out
    }

    private incCount(value: number): void {
        let temp: number = this.written + value;
        if (temp < 0) {
            temp = 0x7fffffff;
        }
        this.written = temp;
    }

    public write(b: number): void {
        this.outputStream.write(b);
        this.incCount(1);
    }

    public writeBytesOffset(b: Int8Array, off: number, len: number): void
    {
        this.outputStream.writeBytesOffset(b, off, len);
        this.incCount(len);
    }

    public flush(): void {
        this.outputStream.flush();
    }

    public writeBoolean(v: boolean): void {
        this.outputStream.write(v ? 1 : 0);
        this.incCount(1);
    }

    public writeByte(v: number): void {
        this.outputStream.write(v);
        this.incCount(1);
    }

    public writeShort(v: number): void {
        this.outputStream.write((v >>> 8) & 0xFF);
        this.outputStream.write((v >>> 0) & 0xFF);
        this.incCount(2);
    }

    public writeChar(v: number): void {
        this.outputStream.write((v >>> 8) & 0xFF);
        this.outputStream.write((v >>> 0) & 0xFF);
        this.incCount(2);
    }

    public writeInt(v: number): void {
        this.outputStream.write((v >>> 24) & 0xFF);
        this.outputStream.write((v >>> 16) & 0xFF);
        this.outputStream.write((v >>> 8) & 0xFF);
        this.outputStream.write((v >>> 0) & 0xFF);
        this.incCount(4);
    }

    private writeBuffer: Int8Array = new Int8Array(8);

    public writeLong(v: Long): void{
        this.writeBuffer[0] = v.shru(56).toNumber();
        this.writeBuffer[1] = v.shru(48).toNumber();
        this.writeBuffer[2] = v.shru(40).toNumber();
        this.writeBuffer[3] = v.shru(32).toNumber();
        this.writeBuffer[4] = v.shru(24).toNumber();
        this.writeBuffer[5] = v.shru(16).toNumber();
        this.writeBuffer[6] = v.shru(8).toNumber();
        this.writeBuffer[7] = v.shru(0).toNumber();
        this.outputStream.writeBytesOffset(this.writeBuffer, 0, 8);
        this.incCount(8);
    }

    public size(): number {
        return this.written;
    }
}
