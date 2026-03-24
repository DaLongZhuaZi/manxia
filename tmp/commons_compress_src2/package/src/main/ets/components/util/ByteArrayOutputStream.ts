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
import IOUtils from './IOUtils';
import OutputStream from './OutputStream';
import Integer from './Integer';
import IllegalArgumentException from './IllegalArgumentException';
import IndexOutOfBoundsException from './IndexOutOfBoundsException'
import OutOfMemoryError from './OutOfMemoryError';
import System from './System'
import buffer from '@ohos.buffer';


export default class ByteArrayOutputStream extends OutputStream {
    public constructor(size: number = 32) {
        super();
        if (size < 0) {
            throw new IllegalArgumentException('Negative initial size: ' + size);
        }
        this.buf = new Array<number>(size);
    }

    private ensureCapacity(minCapacity: number): void {
        // overflow-conscious code
        if (minCapacity - this.buf.length > 0)
        this.grow(minCapacity);
    }

    private grow(minCapacity: number): void {
        // overflow-conscious code
        let oldCapacity: number = this.buf.length;
        let newCapacity: number = oldCapacity << 1;
        if (newCapacity - minCapacity < 0)
        newCapacity = minCapacity;
        if (newCapacity < 0) {
            if (minCapacity < 0) // overflow
            throw new OutOfMemoryError();
            newCapacity = Integer.MAX_VALUE;
        }
        this.buf = IOUtils.copyOfArray(this.buf, newCapacity);
    }

    public /*synchronized*/
    write(b: number): void {
        this.ensureCapacity(this.count + 1);
        this.buf[this.count] = /*(byte)*/
        b;
        this.count += 1;
    }

    public writeTo(out: OutputStream): void {
        out.writeBytesOffset(new Int8Array(this.buf), 0, this.count);
    }

    public writeBytesOffset(b: Int8Array, off: /*int*/
    number, len: /*int*/
    number): void {
        if ((off < 0) || (off > b.length) || (len < 0) ||
        ((off + len) - b.length > 0)) {
            throw new IndexOutOfBoundsException();
        }
        this.ensureCapacity(this.count + len);
        System.arraycopy(b, off, this.buf, this.count, len);
        this.count += len;
    }

    public reset(): void {
        this.count = 0;
    }

    public toByteArray(): Int8Array {
        return new Int8Array(this.buf);
    }

    public toByteArrays(): Int8Array {
        let copy: Int8Array = new Int8Array(this.count);
        System.arraycopy(this.buf, 0, copy, 0, Math.min(this.buf.length, this.count));
        return copy;
    }

    public size(): number {
        return this.count;
    }

    toString(param?: number | string) {
        if (!param) {
            return this.toString_void();
        }
        if (typeof param === 'string') {
            return this.toString_string(param);
        }
        return this.toString_number(param);
    }

    public toString_void(): string {
        return this.buf.toString();
    }

    public toString_string(charsetName: string): string {
        let bufArr = this.trimTrailingZeros(this.buf)
        let uint8Array = new Uint8Array(bufArr)
        return buffer.from(uint8Array).toString(charsetName)
    }

    private trimTrailingZeros(arr: number[]): number[]{
        let result: number[] = [];
        let foundNonZero = false;
        for (let num = arr.length - 1; num >= 0; num--){
            if (arr[num] !== 0 && arr[num] !== undefined || foundNonZero){
                result.unshift(arr[num]);
                foundNonZero = true;
            }
        }
        return result;
    }

    public toString_number(hibyte: number): string {
        return this.buf.toString();
    }

    public close(): void {
    }
}
