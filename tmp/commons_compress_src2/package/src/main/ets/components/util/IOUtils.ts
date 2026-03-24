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
import { LinkOption } from './LinkOption';
import InputStream from './InputStream';
import OutputStream from './OutputStream';
import ByteArrayOutputStream from './ByteArrayOutputStream';
import IllegalArgumentException from './IllegalArgumentException';
import IndexOutOfBoundsException from './IndexOutOfBoundsException';
import Long from "./long/index";
import { LogUtil } from '../LogUtil';

export default class IOUtils {
    public static readonly EMPTY_LINK_OPTIONS: Array<LinkOption> = [];
    private static readonly COPY_BUF_SIZE: number = 8192;
    private static readonly SKIP_BUF_SIZE: number = 4096;
    private static SKIP_BUF: Int8Array = new Int8Array(IOUtils.SKIP_BUF_SIZE);

    public static readFull(input: InputStream, array: Int8Array, offset?: number, len?: number): number {
        offset = offset == undefined ? 0 : offset;
        len = len == undefined ? array.length - offset : len;

        if (len < 0 || offset < 0 || len + offset > array.length || len + offset < 0) {
            throw new IndexOutOfBoundsException();
        }
        let count = 0, x = 0;
        while (count != len) {
            x = input.readBytesOffset(array, offset + count, len - count);
            if (x == -1) {
                break;
            }
            count += x;
        }
        return count;
    }

    public static skip(input: InputStream, numToSkip: Long): Long {
        let available: Long = numToSkip;
        while (numToSkip.gt(0)) {
            let skipped: Long = Long.fromNumber(input.skip(numToSkip.toNumber()));
            if (skipped.eq(0)) {
                break;
            }
            numToSkip = numToSkip.sub(skipped);
        }

        while (numToSkip.gt(0)) {
            let read: number = IOUtils.readFull(input, IOUtils.SKIP_BUF, 0, Math.min(numToSkip.toNumber(), IOUtils.SKIP_BUF_SIZE));
            if (read < 1) {
                break;
            }
            numToSkip = numToSkip.sub(read);
        }
        return available.sub(numToSkip);
    }

    public static readRange(input: InputStream, len: number): Int8Array {
        let output: ByteArrayOutputStream = new ByteArrayOutputStream(len);
        IOUtils.copyRangeLong(input, Long.fromNumber(len), output);
        return output.toByteArray();
    }

    public static copyRangeLong(input: InputStream, len: Long, output: OutputStream,
                                buffersize?: number): Long {
        buffersize = buffersize == undefined ? IOUtils.COPY_BUF_SIZE : buffersize

        if (buffersize < 1) {
            throw new IllegalArgumentException("buffersize must be bigger than 0");
        }
        let buffer: Int8Array = new Int8Array(Math.min(buffersize, len.toNumber()));
        let n: number = 0;
        let count: Long = Long.fromNumber(0);
        while (count.lessThan(len) && -1 != (n = input.readBytesOffset(buffer, 0, Math.min(len.sub(count).toNumber(), buffer.length)))) {
            output.writeBytesOffset(buffer, 0, n);
            count = count.add(n);
        }
        return count;
    }

    public static copyOfArray(original: Array<number>, newLength: number): Array<number> {
        if (original.length <= newLength) {
            const newArray = new Array<number>(newLength);
            for (let i = 0; i < original.length; i++){
                newArray[i] = original[i];
            }
            return newArray;
        }
        return original.slice(0, newLength);
    }

    public static copyStream(input: InputStream, output: OutputStream, buffersize?: number): Long {
        LogUtil.info('copyStream');
        buffersize = buffersize == undefined ? IOUtils.COPY_BUF_SIZE : buffersize

        if (buffersize < 1) {
            LogUtil.error('buffersize must be bigger than 0.');
            throw new IllegalArgumentException("buffersize must be bigger than 0");
        }
        let buffer: Int8Array = new Int8Array(buffersize);
        let n: number = 0;
        let count: Long = Long.fromNumber(0);
        while (-1 != (n = input.readBytes(buffer))) {
            output.writeBytesOffset(buffer, 0, n);
            count = count.add(n);
        }
        return count;
    }

    public static toByteArray(input: InputStream): Int8Array {
        let output: ByteArrayOutputStream = new ByteArrayOutputStream();
        IOUtils.copyStream(input, output);
        return output.toByteArray();
    }
}