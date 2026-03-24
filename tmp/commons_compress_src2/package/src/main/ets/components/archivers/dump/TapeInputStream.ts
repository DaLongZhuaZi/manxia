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

import Long from "../../util/long/index"
import pako from 'pako'
import IOUtils from '../../util/IOUtils'
import System from '../../util/System'
import Arrays from '../../util/Arrays'
import Exception from '../../util/Exception'
import InputStream from '../../util/InputStream'
import FilterInputStream from '../../util/FilterInputStream'
import IllegalArgumentException from '../../util/IllegalArgumentException'
import DumpArchiveConstants from './DumpArchiveConstants'
import DumpArchiveUtil from './DumpArchiveUtil'
import { COMPRESSION_TYPE } from './Enumeration'
import DumpArchiveException from './DumpArchiveException'
import ShortFileException from './ShortFileException'
import UnsupportedCompressionAlgorithmException from './UnsupportedCompressionAlgorithmException'
import { int } from '../../util/CustomTypings'


export default class TapeInputStream extends FilterInputStream {
    private blockBuffer: Int8Array = new Int8Array(DumpArchiveConstants.TP_SIZE);
    private currBlkIdx: int = -1;
    private blockSize: int = DumpArchiveConstants.TP_SIZE;
    private RECORD_SIZE: int = DumpArchiveConstants.TP_SIZE;
    private readOffset: int = DumpArchiveConstants.TP_SIZE;
    private isCompressed: boolean;
    private bytesRead: Long = Long.fromNumber(0);

    constructor(inputStream: InputStream) {
        super(inputStream)
    }

    public resetBlockSize(recsPerBlock: int, isCompressed: boolean): void {
        this.isCompressed = isCompressed;

        if (recsPerBlock < 1) {
            throw new Exception("Block with " + recsPerBlock
            + " records found, must be at least 1");
        }
        this.blockSize = this.RECORD_SIZE * recsPerBlock;

        let oldBuffer: Int8Array = this.blockBuffer;
        this.blockBuffer = new Int8Array(this.blockSize);
        System.arraycopy(oldBuffer, 0, this.blockBuffer, 0, this.RECORD_SIZE);
        this.readFully(this.blockBuffer, this.RECORD_SIZE, this.blockSize - this.RECORD_SIZE);

        this.currBlkIdx = 0;
        this.readOffset = this.RECORD_SIZE;
    }

    public available(): int {
        if (this.readOffset < this.blockSize) {
            return this.blockSize - this.readOffset;
        }

        return this.input.available();
    }

    public read(): int {
        throw new IllegalArgumentException(
            "All reads must be multiple of record size (" + this.RECORD_SIZE +
            " bytes.");
    }

    public readBytesOffset(b: Int8Array, off: number, len: number): number {
        if (len == 0) {
            return 0;
        }
        if ((len % this.RECORD_SIZE) != 0) {
            throw new IllegalArgumentException(
                "All reads must be multiple of record size (" + this.RECORD_SIZE +
                " bytes.");
        }

        let bytes: number = 0;

        while (bytes < len) {

            if (this.readOffset == this.blockSize) {
                try {
                    this.readBlock(true);
                } catch (sfe) {
                    return -1;
                }
            }

            let n: int = 0;

            if ((this.readOffset + (len - bytes)) <= this.blockSize) {
                n = len - bytes;
            } else {
                n = this.blockSize - this.readOffset;
            }

            System.arraycopy(this.blockBuffer, this.readOffset, b, off, n);
            this.readOffset += n;
            bytes += n;
            off += n;
        }

        return bytes;
    }

    public skip(n: number): number {
        let len: Long = Long.fromNumber(n)
        if ((len.toInt() % this.RECORD_SIZE) != 0) {
            throw new IllegalArgumentException(
                "All reads must be multiple of record size (" + this.RECORD_SIZE +
                " bytes.");
        }

        let bytes: Long = Long.fromNumber(0);

        while (len.gt(bytes)) {
            if (this.readOffset == this.blockSize) {
                try {
                    this.readBlock((len.sub(bytes)).lt(this.blockSize));
                } catch (sfe) {
                    return -1;
                }
            }

            let n: Long = Long.fromNumber(0);

            if ((len.sub(bytes).add(this.readOffset)).le(this.blockSize)) {
                n = len.sub(bytes);
            } else {
                n = Long.fromNumber(this.blockSize - this.readOffset);
            }

            this.readOffset = n.add(this.readOffset).toInt();
            bytes = bytes.add(n);
        }

        return bytes.toInt();
    }

    public close(): void {
        if (this.input != null) {
            this.input.close();
        }
    }

    public peek(): Int8Array {
        if (this.readOffset == this.blockSize) {
            try {
                this.readBlock(true);
            } catch (sfe) {
                return null;
            }
        }

        let b: Int8Array = new Int8Array(this.RECORD_SIZE);
        System.arraycopy(this.blockBuffer, this.readOffset, b, 0, b.length);

        return b;
    }

    public readRecord(): Int8Array {
        let result: Int8Array = new Int8Array(this.RECORD_SIZE);

        if (-1 == this.readBytesOffset(result, 0, result.length)) {
            throw new ShortFileException();
        }

        return result;
    }

    private readBlock(decompress: boolean): void {
        if (this.input == null) {
            throw new Exception("Input buffer is closed");
        }

        if (!this.isCompressed || (this.currBlkIdx == -1)) {
            this.readFully(this.blockBuffer, 0, this.blockSize);
            this.bytesRead = this.bytesRead.add(this.blockSize);
        } else {
            this.readFully(this.blockBuffer, 0, 4);
            this.bytesRead = this.bytesRead.add(4);

            let h: int = DumpArchiveUtil.convert32(this.blockBuffer, 0);
            let compressed: boolean = (h & 0x01) == 0x01;

            if (!compressed) {
                this.readFully(this.blockBuffer, 0, this.blockSize);
                this.bytesRead = this.bytesRead.add(this.blockSize);
            } else {
                let flags: int = (h >> 1) & 0x07;
                let length: int = (h >> 4) & 0x0FFFFFFF;
                let compBuffer: Int8Array = this.readRange(length);
                this.bytesRead = this.bytesRead.add(length);

                if (!decompress) {
                    Arrays.fill(this.blockBuffer, 0);
                } else {
                    switch (COMPRESSION_TYPE[flags & 0x03]) {
                        case "ZLIB":

                            try {
                                let output = pako.inflate(compBuffer.buffer)
                                this.blockBuffer = output;
                                length = output.length

                                if (length != this.blockSize) {
                                    throw new ShortFileException();
                                }
                            } catch (e) {
                                throw new DumpArchiveException();
                            } finally {

                            }

                            break;

                        case "BZLIB":
                            throw new UnsupportedCompressionAlgorithmException(
                                "BZLIB2");

                        case "LZO":
                            throw new UnsupportedCompressionAlgorithmException(
                                "LZO");

                        default:
                            throw new UnsupportedCompressionAlgorithmException();
                    }
                }
            }
        }

        this.currBlkIdx++;
        this.readOffset = 0;
    }

    private readFully(b: Int8Array, off: int, len: int): void {
        let count: int = IOUtils.readFull(this.input, b, off, len);
        if (count < len) {
            throw new ShortFileException();
        }
    }

    private readRange(len: int): Int8Array {
        let ret: Int8Array = IOUtils.readRange(this.input, len);
        if (ret.length < len) {
            throw new ShortFileException();
        }
        return ret;
    }

    public getBytesRead(): Long {
        return this.bytesRead;
    }
}
