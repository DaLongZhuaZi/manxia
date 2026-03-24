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
import DataInputStream from '../DataInputStream'
import Exception from '../../util/Exception'
import InputStream from '../../util/InputStream'
import ArrayCache from './ArrayCache'
import LZDecoder from './lz/LZDecoder'
import LZMADecoder from './lzma/LZMADecoder'
import RangeDecoderFromBuffer from './rangecoder/RangeDecoderFromBuffer'

export default class LZMA2InputStream extends InputStream {
    public static DICT_SIZE_MIN: number = 4096;
    public static DICT_SIZE_MAX: number = 2147483632;
    private static COMPRESSED_SIZE_MAX: number = 65536;
    private arrayCache: ArrayCache;
    private dataIn: DataInputStream;
    private lz: LZDecoder;
    private rc: RangeDecoderFromBuffer;
    private lzma: LZMADecoder;
    private uncompressedSize: number;
    private isLZMAChunk: boolean;
    private needDictReset: boolean;
    private needProps: boolean;
    private endReached: boolean;
    private exception: Exception;
    private tempBuf;

    public static getMemoryUsage(dictSize: number): number {
        return 104 + this.getDictSize(dictSize) / 1024;
    }

    private static getDictSize(dictSize: number): number {
        if (dictSize >= 4096 && dictSize <= 2147483632) {
            return dictSize + 15 & -16;
        } else {
            throw new Exception("Unsupported dictionary size " + dictSize);
        }
    }

    constructor(inputStream: InputStream, dictSize: number, presetDict: Int8Array, arrayCache: ArrayCache) {
        super()
        this.uncompressedSize = 0;
        this.isLZMAChunk = false;
        this.needDictReset = true;
        this.needProps = true;
        this.endReached = false;
        this.exception = null;
        this.tempBuf = new Int8Array(1);
        if (inputStream == null) {
            throw new Exception();
        } else {
            this.arrayCache = arrayCache;
            this.dataIn = new DataInputStream(inputStream);
            this.rc = new RangeDecoderFromBuffer(65536, arrayCache);
            this.lz = new LZDecoder(LZMA2InputStream.getDictSize(dictSize), presetDict, arrayCache);
            if (presetDict != null && presetDict.length > 0) {
                this.needDictReset = false;
            }
        }
    }

    public read(): number {
        return this.readBytesOffset(this.tempBuf, 0, 1) == -1 ? -1 : this.tempBuf[0] & 255;
    }

    public readBytesOffset(buf: Int8Array, off: number, len: number): number {
        if (off >= 0 && len >= 0 && off + len >= 0 && off + len <= buf.length) {
            if (len == 0) {
                return 0;
            } else if (this.dataIn == null) {
                throw new Exception("Stream closed");
            } else if (this.exception != null) {
                throw this.exception;
            } else if (this.endReached) {
                return -1;
            } else {
                try {
                    let size = 0;

                    do {
                        do {
                            if (len <= 0) {
                                return size;
                            }

                            if (this.uncompressedSize == 0) {
                                this.decodeChunkHeader();
                                if (this.endReached) {
                                    return size == 0 ? -1 : size;
                                }
                            }

                            let copySizeMax = Math.min(this.uncompressedSize, len);
                            if (!this.isLZMAChunk) {
                                this.lz.copyUncompressed(this.dataIn, copySizeMax);
                            } else {
                                this.lz.setLimit(copySizeMax);
                                this.lzma.decode();
                            }

                            let copiedSize = this.lz.flush(buf, off);
                            off += copiedSize;
                            len -= copiedSize;
                            size += copiedSize;
                            this.uncompressedSize -= copiedSize;
                        } while (this.uncompressedSize != 0);
                    } while (this.rc.isFinished() && !this.lz.hasPending());

                    throw new Exception();
                } catch (e) {
                    this.exception = e;
                    throw e;
                }
            }
        } else {
            throw new Exception();
        }
    }

    private decodeChunkHeader() {
        let control = this.dataIn.readUnsignedByte();
        if (control == 0) {
            this.endReached = true;
            this.putArraysToCache();
        } else {
            if (control < 224 && control != 1) {
                if (this.needDictReset) {
                    throw new Exception();
                }
            } else {
                this.needProps = true;
                this.needDictReset = false;
                this.lz.reset();
            }

            if (control >= 128) {
                this.isLZMAChunk = true;
                this.uncompressedSize = (control & 31) << 16;
                this.uncompressedSize += this.dataIn.readUnsignedShort() + 1;
                let compressedSize = this.dataIn.readUnsignedShort() + 1;
                if (control >= 192) {
                    this.needProps = false;
                    this.decodeProps();
                } else {
                    if (this.needProps) {
                        throw new Exception();
                    }

                    if (control >= 160) {
                        this.lzma.reset();
                    }
                }

                this.rc.prepareInputBuffer(this.dataIn, compressedSize);
            } else {
                if (control > 2) {
                    throw new Exception();
                }

                this.isLZMAChunk = false;
                this.uncompressedSize = this.dataIn.readUnsignedShort() + 1;
            }

        }
    }

    private decodeProps() {
        let props = this.dataIn.readUnsignedByte();
        if (props > 224) {
            throw new Exception();
        } else {
            let pb = Math.floor(props / 45);
            props -= pb * 9 * 5;
            let lp = Math.floor(props / 9);
            let lc = props - lp * 9;
            if (lc + lp > 4) {
                throw new Exception();
            } else {
                this.lzma = new LZMADecoder(this.lz, this.rc, lc, lp, pb);
            }
        }
    }

    public available(): number {
        if (this.dataIn == null) {
            throw new Exception("Stream closed");
        } else if (this.exception != null) {
            throw this.exception;
        } else {
            return this.isLZMAChunk ? this.uncompressedSize : Math.min(this.uncompressedSize, this.dataIn.available());
        }
    }

    private putArraysToCache() {
        if (this.lz != null) {
            this.lz.putArraysToCache(this.arrayCache);
            this.lz = null;
            this.rc.putArraysToCache(this.arrayCache);
            this.rc = null;
        }

    }

    public close() {
        if (this.dataIn != null) {
            this.putArraysToCache();

            try {
                this.dataIn.close();
            } finally {
                this.dataIn = null;
            }
        }

    }
}
