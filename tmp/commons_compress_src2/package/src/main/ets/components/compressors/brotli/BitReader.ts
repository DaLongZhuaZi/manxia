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

import IntReader from './IntReader';
import InputStream from '../../util/InputStream';
import Long from "../../util/long/index";
import Exception from '../../util/Exception';
import System from '../../util/System';

export default class BitReader {
    private static CAPACITY: number = 1024;
    private static SLACK: number = 16;
    private static INT_BUFFER_SIZE: number = BitReader.CAPACITY + BitReader.SLACK; //1040
    private static BYTE_READ_SIZE: number = BitReader.CAPACITY << 2 //4096
    private static BYTE_BUFFER_SIZE: number = BitReader.INT_BUFFER_SIZE << 2; //4160;

    private byteBuffer: Int8Array = new Int8Array(BitReader.BYTE_BUFFER_SIZE);
    private intBuffer: Int32Array = new Int32Array(BitReader.INT_BUFFER_SIZE);
    private intReader: IntReader = new IntReader();
    private input: InputStream;
    private endOfStreamReached: boolean;
    accumulator: Long;
    bitOffsets: number;
    private intOffsets: number = 0;
    private tailBytes: number = 0;

    constructor() {

    }

    static readMoreInput(br: BitReader): void {
        if (br.intOffsets <= BitReader.CAPACITY - 9) {
            return;
        }
        if (br.endOfStreamReached) {
            if (BitReader.intAvailable(br) < -2) {
                throw new Exception("No more input");
            }
        }
        let readOffset: number = br.intOffsets << 2;
        let bytesRead: number = BitReader.BYTE_READ_SIZE - readOffset;
        System.arraycopy(br.byteBuffer, readOffset, br.byteBuffer, 0, bytesRead);
        br.intOffsets = 0;
        try {
            while (bytesRead < BitReader.BYTE_READ_SIZE) {
                let len: number = br.input.readBytesOffset(br.byteBuffer, bytesRead, BitReader.BYTE_READ_SIZE - bytesRead);
                if (len <= 0) {
                    br.endOfStreamReached = true;
                    br.tailBytes = bytesRead;
                    bytesRead += 3;
                    break;
                }
                bytesRead += len;
            }
        } catch (var4) {
            throw new Exception("Failed to read input");
        }
        IntReader.convert(br.intReader, bytesRead >> 2);
    }

    static checkHealth(br: BitReader, endOfStream: boolean): void {
        if (!br.endOfStreamReached) {
            return;
        }
        let byteOffset: number = (br.intOffsets << 2) + (br.bitOffsets + 7 >> 3) - 8;
        if (byteOffset > br.tailBytes) {
            throw new Exception("Read after end");
        } else if (endOfStream && byteOffset != br.tailBytes) {
            throw new Exception("Unused bytes after end");
        }
    }

    static fillBitWindow(br: BitReader): void {
        if (br.bitOffsets >= 32) {
            br.accumulator = Long.fromNumber(br.intBuffer[br.intOffsets++]).shl(32).or(br.accumulator.shru(32));
            br.bitOffsets -= 32;
        }
    }

    static readBits(br: BitReader, n: number): number {
        BitReader.fillBitWindow(br);
        let val: number = (br.accumulator.shru(br.bitOffsets)).and((1 << n) - 1).toInt();
        br.bitOffsets += n;
        return val;
    }

    static init(br: BitReader, input: InputStream): void {
        if (br.input != null) {
            throw new Exception("Bit reader already has associated input stream");
        }
        IntReader.init(br.intReader, br.byteBuffer, br.intBuffer);
        br.input = input;
        br.accumulator = Long.fromNumber(0);
        br.bitOffsets = 64;
        br.intOffsets = 1024;
        br.endOfStreamReached = false;
        BitReader.prepare(br);
    }

    private static prepare(br: BitReader): void {
        BitReader.readMoreInput(br);
        BitReader.checkHealth(br, false);
        BitReader.fillBitWindow(br);
        BitReader.fillBitWindow(br);
    }

    static reload(br: BitReader): void {
        if (br.bitOffsets == 64) {
            BitReader.prepare(br);
        }
    }

    static close(br: BitReader): void {
        let is: InputStream = br.input;
        br.input = null;
        if (is != null) {
            is.close();
        }
    }

    static jumpToByteBoundary(br: BitReader): void {
        let padding: number = 64 - br.bitOffsets & 7;
        if (padding != 0) {
            let paddingBits: number = BitReader.readBits(br, padding);
            if (paddingBits != 0) {
                throw new Exception("Corrupted padding bits");
            }
        }
    }

    static intAvailable(br: BitReader): number {
        let limit: number = 1024;
        if (br.endOfStreamReached) {
            limit = br.tailBytes + 3 >> 2;
        }
        return limit - br.intOffsets;
    }

    static copyBytes(br: BitReader, data: Int8Array, offset: number, length: number): void {
        if ((br.bitOffsets & 7) != 0) {
            throw new Exception("Unaligned copyBytes");
        }

        // Drain accumulator.
        while ((br.bitOffsets != 64) && (length != 0)) {
            data[offset++] = br.accumulator.shru(br.bitOffsets).toNumber();
            br.bitOffsets += 8;
            length--;
        }
        if (length == 0) {
            return;
        }

        let copyInts: number = Math.min(BitReader.intAvailable(br), length >> 2);
        if (copyInts > 0) {
            let readOffset: number = br.intOffsets << 2;
            System.arraycopy(br.byteBuffer, readOffset, data, offset, copyInts << 2);
            offset += copyInts << 2;
            length -= copyInts << 2;
            br.intOffsets += copyInts;
        }
        if (length == 0) {
            return;
        }

        if (BitReader.intAvailable(br) > 0) {
            BitReader.fillBitWindow(br);
            while (length != 0) {
                data[offset++] = br.accumulator.shru(br.bitOffsets).toNumber();
                br.bitOffsets += 8;
                length--;
            }
            BitReader.checkHealth(br, false);
            return;
        }

        try {
            while (length > 0) {
                let len: number = br.input.readBytesOffset(data, offset, length);
                if (len == -1) {
                    throw new Exception("Unexpected end of input");
                }
                offset += len;
                length -= len;
            }
        } catch (e) {
            throw new Exception("Failed to read input");
        }
    }
}