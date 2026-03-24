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
import IndexIndicatorException from './IndexIndicatorException'
import ByteArrayInputStream from '../../util/ByteArrayInputStream'
import Check from './Check'
import DecoderUtil from './DecoderUtil'
import type FilterDecoder from './FilterDecoder'
import RawCoder from './RawCoder'
import ArrayCache from './ArrayCache'
import LZMA2Decoder from './LZMA2Decoder'
import DeltaDecoder from './DeltaDecoder'
import BCJDecoder from './BCJDecoder'
import CountingInputStream from './CountingInputStream'
import DataInputStream from "../DataInputStream";
import NumberTransform from "./NumberTransform";
import Long from "../../util/long/index"

export default class BlockInputStream extends InputStream {
    private inData: DataInputStream;
    private inCounted: CountingInputStream;
    private filterChain: InputStream;
    private check: Check;
    private verifyCheck: boolean;
    private uncompressedSizeInHeader: Long = Long.fromNumber(-1);
    private compressedSizeInHeader: Long = Long.fromNumber(-1);
    private compressedSizeLimit: Long = Long.fromNumber(0);
    private headerSize: number;
    private uncompressedSize: Long = Long.fromNumber(0);
    private endReached: boolean = false;
    private tempBuf = new Int8Array(1);
    private inputStream: InputStream

    constructor(inputStream: InputStream, check: Check, verifyCheck: boolean,
                memoryLimit: Number, unpaddedSizeInIndex: Long,
                uncompressedSizeInIndex: Long, arrayCache: ArrayCache) {
        super()
        this.check = check;
        this.verifyCheck = verifyCheck;
        this.inputStream = inputStream;
        this.inData = new DataInputStream(inputStream);
        let b: number = this.inData.readUnsignedByte();
        if (b == 0) {
            throw new IndexIndicatorException();
        }
        this.headerSize = 4 * (b + 1);
        let buf: Int8Array = new Int8Array(this.headerSize);
        buf[0] = NumberTransform.toByte(b);
        this.inData.readFullyCount(buf, 1, this.headerSize - 1);
        let Decoder = !DecoderUtil.isCRC32Valid(buf, 0, this.headerSize - 4, this.headerSize - 4);
        if (Decoder) {
            throw new Exception("XZ Block Header is corrupt");
        }
        if ((buf[1] & 60) != 0) {
            throw new Exception("Unsupported options in XZ Block Header");
        }
        let filterCount = (buf[1] & 3) + 1;
        let filterIDs: Array<Long> = new Array<Long>(filterCount);
        let filterProps: Array<Int8Array> = new Array<Int8Array>(filterCount);
        let bufStream: ByteArrayInputStream = new ByteArrayInputStream(buf, 2, this.headerSize - 6);
        try {
            this.compressedSizeLimit = Long.fromString('9223372036854775804').sub(this.headerSize).sub(check.getSize());
            if ((buf[1] & 64) != 0) {
                this.compressedSizeInHeader = DecoderUtil.decodeVLI(bufStream);
                if (this.compressedSizeInHeader == Long.fromNumber(0) || this.compressedSizeInHeader > this.compressedSizeLimit) {
                    throw new Exception();
                }

                this.compressedSizeLimit = this.compressedSizeInHeader;
            }

            if ((buf[1] & 128) != 0) {
                this.uncompressedSizeInHeader = DecoderUtil.decodeVLI(bufStream);
            }

            for (let i = 0; i < filterCount; ++i) {
                filterIDs[i] = DecoderUtil.decodeVLI(bufStream);
                let filterPropsSize = DecoderUtil.decodeVLI(bufStream);
                if (filterPropsSize.greaterThan(bufStream.available())) {
                    throw new Exception();
                }

                filterProps[i] = new Int8Array(filterPropsSize.toInt());
                bufStream.readBytes(filterProps[i]);
            }
        } catch (e) {
            throw new Exception("XZ Block Header is corrupt");
        }

        for (let i = bufStream.available(); i > 0; --i) {
            if (bufStream.read() != 0) {
                throw new Exception("Unsupported options in XZ Block Header");
            }
        }

        if (!unpaddedSizeInIndex.eq(-1)) {
            let headerAndCheckSize: number = this.headerSize + check.getSize();
            if (headerAndCheckSize >= unpaddedSizeInIndex.toNumber()) {
                throw new Exception("XZ Index does not match a Block Header");
            }

            let compressedSizeFromIndex: Long = Long.fromNumber(unpaddedSizeInIndex.toNumber() - headerAndCheckSize);
            if (compressedSizeFromIndex > this.compressedSizeLimit || this.compressedSizeInHeader != Long.fromNumber(-1) && this.compressedSizeInHeader != compressedSizeFromIndex) {
                throw new Exception("XZ Index does not match a Block Header");
            }

            if (this.uncompressedSizeInHeader != Long.fromNumber(-1) && this.uncompressedSizeInHeader != uncompressedSizeInIndex) {
                throw new Exception("XZ Index does not match a Block Header");
            }

            this.compressedSizeLimit = compressedSizeFromIndex;
            this.compressedSizeInHeader = compressedSizeFromIndex;
            this.uncompressedSizeInHeader = uncompressedSizeInIndex;
        }

        let filters: Array<FilterDecoder> = new Array<FilterDecoder>(filterIDs.length);

        for (let i = 0; i < filters.length; ++i) {
            if (filterIDs[i].eq(33)) {
                filters[i] = new LZMA2Decoder(filterProps[i]);
            } else if (filterIDs[i].eq(3)) {
                filters[i] = new DeltaDecoder(filterProps[i]);
            } else if (BCJDecoder.isBCJFilterID(filterIDs[i])) {
                filters[i] = new BCJDecoder(filterIDs[i], filterProps[i]);
            } else {
                throw new Exception("Unknown Filter ID " + filterIDs[i]);
            }
        }

        RawCoder.validate(filters);
        if (memoryLimit >= 0) {
            let memoryNeeded = 0;

            for (let i = 0;  i < filters.length; ++i) {
                memoryNeeded += filters[i].getMemoryUsage();
            }

            if (memoryNeeded > memoryLimit) {
                throw new Exception();
            }
        }

        this.inCounted = new CountingInputStream(this.inputStream);
        this.filterChain = this.inCounted;

        for (let i = filters.length - 1; i >= 0; --i) {
            this.filterChain = filters[i].getInputStream(this.filterChain, arrayCache);
        }
    }

    public read() {
        return this.readBytesOffset(this.tempBuf, 0, 1) == -1 ? -1 : this.tempBuf[0] & 255;
    }

    public readBytesOffset(buf: Int8Array, off: number, len: number) {
        if (this.endReached) {
            return -1;
        } else {
            let ret = this.filterChain.readBytesOffset(buf, off, len);
            if (ret > 0) {
                if (this.verifyCheck) {
                    this.check.updates(buf, off, ret);
                }

                this.uncompressedSize = this.uncompressedSize.add(Long.fromNumber(ret));
                let compressedSize: Long = this.inCounted.getSize();
                if (compressedSize.lessThan(0) || compressedSize.greaterThan(this.compressedSizeLimit)
                || this.uncompressedSize.lessThan(0)
                || (!this.uncompressedSizeInHeader.eq(-1))
                && this.uncompressedSize.greaterThan(this.uncompressedSizeInHeader)) {
                    throw new Exception();
                }

                if (ret < len || this.uncompressedSize.eq(this.uncompressedSizeInHeader)) {
                    if (this.filterChain.read() != -1) {
                        throw new Exception();
                    }

                    this.validate();
                    this.endReached = true;
                }
            } else if (ret == -1) {
                this.validate();
                this.endReached = true;
            }
            return ret;
        }
    }

    private validate() {
        let compressedSize = this.inCounted.getSize();
        if ((!this.compressedSizeInHeader.eq(-1) && !this.compressedSizeInHeader.eq(compressedSize))
        || (!this.uncompressedSizeInHeader.eq(-1) && !this.uncompressedSizeInHeader.eq(this.uncompressedSize))) {
            throw new Exception();
        }

        while (!(compressedSize.and(3)).eq(0)) {
            compressedSize = compressedSize.add(1)
            if (this.inData.readUnsignedByte() != 0) {
                throw new Exception();
            }
        }
        compressedSize = compressedSize.add(1)
        let storedArray = new Int8Array(this.check.getSize());
        this.inData.readFully(storedArray);

        if (this.verifyCheck && !BlockInputStream.equals(this.check.finish(), storedArray)) {
            throw new Exception("Integrity check (" + this.check.getName() + ") does not match");
        }
    }

    public static equals(a: Int8Array, a2: Int8Array): boolean {
        if (a == a2)
        return true;
        if (a == null || a2 == null)
        return false;

        let length: number = a.length;
        if (a2.length != length)
        return false;

        for (let i = 0; i < length; i++)
        if (a[i] != a2[i])
        return false;

        return true;
    }

    public available() {
        return this.filterChain.available();
    }

    public close() {
        try {
            this.filterChain.close();
        } catch (e) {

        }

        this.filterChain = null;
    }

    public getUnpaddedSize(): Long {
        let getSize = this.inCounted.getSize().add(this.headerSize).add(this.check.getSize())
        return getSize;
    }

    public getUncompressedSize(): Long {
        return this.uncompressedSize;
    }
}
