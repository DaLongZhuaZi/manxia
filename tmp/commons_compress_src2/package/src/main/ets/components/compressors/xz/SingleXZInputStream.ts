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
import InputStream from '../../util/InputStream';
import DataInputStream from '../DataInputStream'
import Exception from '../../util/Exception'
import ArrayCache from './ArrayCache'
import StreamFlags from './StreamFlags'
import Check from './Check'
import BlockInputStream from './BlockInputStream'
import IndexHash from './IndexHash'
import DecoderUtil from './DecoderUtil'

export default class SingleXZInputStream extends InputStream {
    private input: InputStream;
    private arrayCache: ArrayCache;
    private memoryLimit: number;
    private streamHeaderFlags: StreamFlags;
    private check: Check;
    private verifyCheck: boolean;
    private blockDecoder: BlockInputStream;
    private indexHash: IndexHash
    private endReached: boolean;
    private exception;
    private tempBuf;

    private readStreamHeader(inputStream: InputStream): Int8Array  {
        let streamHeader: Int8Array = new Int8Array(12);
        new DataInputStream(inputStream).readFully(streamHeader);
        return streamHeader;
    }

    constructor(input: InputStream, memoryLimit: number, verifyCheck: boolean, arrayCache: ArrayCache) {
        super();
        this.blockDecoder = null;
        this.indexHash = new IndexHash();
        this.endReached = false;
        this.exception = null;
        this.tempBuf = new Int8Array(1);
        this.arrayCache = arrayCache;
        this.input = input;
        this.memoryLimit = memoryLimit;
        this.verifyCheck = verifyCheck;
        this.streamHeaderFlags = DecoderUtil.decodeStreamHeader(this.readStreamHeader(input));
        this.check = Check.getInstance(this.streamHeaderFlags.checkType);
    }

    public getCheckType() {
        return this.streamHeaderFlags.checkType;
    }

    public getCheckName() {
        return this.check.getName();
    }

    public read() {
        return this.readBytesOffset(this.tempBuf, 0, 1) == -1 ? -1 : this.tempBuf[0] & 255;
    }

    public readBytesOffset(buf: Int8Array, off, len) {
        if (off >= 0 && len >= 0 && off + len >= 0 && off + len <= buf.length) {
            if (len == 0) {
                return 0;
            } else if (this.input == null) {
                throw new Exception("Stream closed");
            } else if (this.exception != null) {
                throw this.exception;
            } else if (this.endReached) {
                return -1;
            } else {
                let size: number = 0;

                try {
                    while (len > 0) {
                        if (this.blockDecoder == null) {
                            try {
                                this.blockDecoder = new BlockInputStream(this.input, this.check, this.verifyCheck, this.memoryLimit, Long.fromNumber(-1), Long.fromNumber(-1), this.arrayCache);
                            } catch (e) {
                                this.indexHash.validate(this.input);
                                this.validateStreamFooter();
                                this.endReached = true;
                                return size > 0 ? size : -1;
                            }
                        }

                        let ret = this.blockDecoder.readBytesOffset(buf, off, len);
                        if (ret > 0) {
                            size += ret;
                            off += ret;
                            len -= ret;
                        } else if (ret == -1) {
                            this.indexHash.add(this.blockDecoder.getUnpaddedSize(), this.blockDecoder.getUncompressedSize());
                            this.blockDecoder = null;
                        }
                    }
                } catch (e) {
                    this.exception = e;
                    if (size == 0) {
                        throw e;
                    }
                }

                return size;
            }
        } else {
            throw new Exception();
        }
    }

    private validateStreamFooter() {
        let buf: Int8Array = new Int8Array(DecoderUtil.STREAM_HEADER_SIZE);
        new DataInputStream(this.input).readFully(buf);
        let streamFooterFlags: StreamFlags = DecoderUtil.decodeStreamFooter(buf);
        if (!DecoderUtil.areStreamFlagsEqual(this.streamHeaderFlags, streamFooterFlags)
        || !this.indexHash.getIndexSize().eq(streamFooterFlags.backwardSize)) {
            throw new Exception("XZ Stream Footer does not match Stream Header");
        }
    }

    public available() {
        if (this.input == null) {
            throw new Exception("Stream closed");
        } else if (this.exception != null) {
            throw this.exception;
        } else {
            return this.blockDecoder == null ? 0 : this.blockDecoder.available();
        }
    }

    public close() {
        this.xzClose(true);
    }

    public xzClose(closeInput: boolean) {
        if (this.input != null) {
            if (this.blockDecoder != null) {
                this.blockDecoder.close();
                this.blockDecoder = null;
            }

            try {
                if (closeInput) {
                    this.input.close();
                }
            } finally {
                this.input = null;
            }
        }

    }
}
