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
import InputStream from '../util/InputStream';
import Exception from '../util/Exception';
import type DataInput from './DataInput';
import Long from "../util/long/index";

export default class DataInputStream extends InputStream {
    data: DataInput
    protected inputStream: InputStream;

    constructor(inputStream: InputStream) {
        super();
        this.inputStream = inputStream
    }

    private bytearr: Int8Array = new Int8Array(80);
    private chararr: Int32Array = new Int32Array(80);

    public readBytes(b: Int8Array): number {
        return this.inputStream.readBytesOffset(b, 0, b.length);
    }

    public readBytesOffset(b: Int8Array, off: number, len: number): number {
        return this.inputStream.readBytesOffset(b, off, len);
    }

    public readFully(b: Int8Array): void {
        this.readFullyCount(b, 0, b.length);
    }

    public readFullyCount(b: Int8Array, off: number, len: number): void {
        if (len < 0)
        throw new Exception();
        let n: number = 0;
        while (n < len) {
            let count: number = this.inputStream.readBytesOffset(b, off + n, len - n);
            if (count < 0)
            throw new Exception();
            n += count;
        }
    }

    public skipBytes(n: number): number {
        let total: number = 0;
        let cur: number = 0;

        while ((total < n) && ((cur = this.skip(n - total)) > 0)) {
            total += cur;
        }

        return total;
    }

    public readBoolean(): boolean {
        let ch: number = this.inputStream.read();
        if (ch < 0)
        throw new Exception();
        return (ch != 0);
    }

    public readByte(): Int8Array {
        let ch = this.inputStream.read();
        if (ch < 0)
        throw new Exception();
        return new Int8Array(ch);
    }

    public readUnsignedByte(): number {
        let ch = this.inputStream.read();
        if (ch < 0)
        throw new Exception();
        return ch;
    }

    public readShort(): number {
        let ch1 = this.inputStream.read();
        let ch2 = this.inputStream.read();
        if ((ch1 | ch2) < 0)
        throw new Exception();
        return (ch1 << 8) + (ch2 << 0);
    }

    public readUnsignedShort(): number {
        let ch1 = this.inputStream.read();
        let ch2 = this.inputStream.read();
        if ((ch1 | ch2) < 0)
        throw new Exception();
        return (ch1 << 8) + (ch2 << 0);
    }

    public readChar(): number {
        let ch1 = this.inputStream.read();
        let ch2 = this.inputStream.read();
        if ((ch1 | ch2) < 0)
        throw new Exception();
        return (ch1 << 8) + (ch2 << 0);
    }

    public readInt(): number {
        let ch1 = this.inputStream.read();
        let ch2 = this.inputStream.read();
        let ch3 = this.inputStream.read();
        let ch4 = this.inputStream.read();
        if ((ch1 | ch2 | ch3 | ch4) < 0)
        throw new Exception();
        return ((ch1 << 24) + (ch2 << 16) + (ch3 << 8) + (ch4 << 0));

    }

    private readBuffer: Int8Array = new Int8Array(8);

    public readLong(): Long{
        this.readFullyCount(this.readBuffer, 0, 8);
        return Long.fromNumber(this.readBuffer[0] << 56)
            .add((this.readBuffer[1] & 255) << 48)
            .add((this.readBuffer[2] & 255) << 40)
            .add((this.readBuffer[3] & 255) << 32)
            .add((this.readBuffer[4] & 255) << 24)
            .add((this.readBuffer[5] & 255) << 16)
            .add((this.readBuffer[6] & 255) << 8)
            .add((this.readBuffer[7] & 255) << 0);

    }

    private lineBuffer: Int32Array = new Int32Array(0);

    public readUTF(): string {
        return DataInputStream.readUTFData(this.data);
    }

    public static stringValue(value, offset, count): string {
        throw new Exception("Use StringFactory instead.");
    }

    public  static readUTFData(indata: DataInput): string{
        let utflen = indata.readUnsignedShort();
        let bytearr: Int8Array = null;
        let chararr: Int32Array = null;
        if (indata instanceof DataInputStream) {
            let dis: DataInputStream = indata;
            if (dis.bytearr.length < utflen) {
                dis.bytearr = new Int8Array(utflen * 2);
                dis.chararr = new Int32Array(utflen * 2);
            }
            chararr = dis.chararr;
            bytearr = dis.bytearr;
        } else {
            bytearr = new Int8Array(utflen);
            chararr = new Int32Array(utflen);
        }

        let c;
        let char2;
        let char3;
        let count = 0;
        let chararr_count: number = 0;

        indata.readFully(bytearr, 0, utflen);

        while (count < utflen) {
            c = bytearr[count] & 0xff;
            if (c > 127) break;
            count++;
            chararr[chararr_count++] = c;
        }

        while (count < utflen) {
            c = bytearr[count] & 0xff;
            switch (c >> 4) {
                case 0:
                case 1:
                case 2:
                case 3:
                case 4:
                case 5:
                case 6:
                case 7:
                /* 0xxxxxxx*/
                    count++;
                    chararr[chararr_count++] = c;
                    break;
                case 12:
                case 13:
                /* 110x xxxx   10xx xxxx*/
                    count += 2;
                    if (count > utflen)
                    throw new Exception(
                        "malformed input: partial character at end");
                    char2 = bytearr[count - 1];
                    if ((char2 & 0xC0) != 0x80)
                    throw new Exception(
                        "malformed input around byte " + count);
                    chararr[chararr_count++] = (((c & 0x1F) << 6) |
                    (char2 & 0x3F));
                    break;
                case 14:
                    count += 3;
                    if (count > utflen)
                    throw new Exception(
                        "malformed input: partial character at end");
                    char2 = bytearr[count - 2];
                    char3 = bytearr[count - 1];
                    if (((char2 & 0xC0) != 0x80) || ((char3 & 0xC0) != 0x80))
                    throw new Exception(
                        "malformed input around byte " + (count - 1));
                    chararr[chararr_count++] = (((c & 0x0F) << 12) |
                    ((char2 & 0x3F) << 6) |
                    ((char3 & 0x3F) << 0));
                    break;
                default:
                    throw new Exception("malformed input around byte " + count);
            }
        }
        return DataInputStream.stringValue(chararr, 0, chararr_count);
    }
}
