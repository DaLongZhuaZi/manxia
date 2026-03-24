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
import Exception from '../../util/Exception'
import ArrayCache from './ArrayCache'
import FinishableOutputStream from './FinishableOutputStream'
import LZEncoder from './lz/LZEncoder'
import LZMA2Options from './LZMA2Options'
import RangeEncoderToBuffer from './rangecoder/RangeEncoderToBuffer'
import LZMAEncoder from './lzma/LZMAEncoder'
import NumberTransform from './NumberTransform'

export default class LZMA2OutputStream extends FinishableOutputStream {
    static COMPRESSED_SIZE_MAX: number = 65536;
    private arrayCache: ArrayCache;
    private out: FinishableOutputStream;
    private lz: LZEncoder;
    private rc: RangeEncoderToBuffer;
    private lzma: LZMAEncoder;
    private props: number;
    private dictResetNeeded: boolean = true;
    private stateResetNeeded: boolean = true;
    private propsNeeded: boolean = true;
    private pendingSize: number = 0;
    private finished: boolean = false;
    private exception: Exception = null;
    private chunkHeader: Int8Array = new Int8Array(6);
    private tempBuf: Int8Array = new Int8Array(1);

    private static getExtraSizeBefore(dictSize: number): number {
        return 65536 > dictSize ? 65536 - dictSize : 0;
    }

    static getMemoryUsage(options: LZMA2Options): number {
        let dictSize: number = options.getDictSize();
        let extraSizeBefore: number = this.getExtraSizeBefore(dictSize);
        return 70 + LZMAEncoder.getMemoryUsage(options.getMode(), dictSize, extraSizeBefore, options.getMatchFinder());
    }

    constructor(out: FinishableOutputStream, options: LZMA2Options, arrayCache: ArrayCache) {
        super()
        if (out == null) {
            throw new Exception();
        } else {
            this.arrayCache = arrayCache;
            this.out = out;
            this.rc = new RangeEncoderToBuffer(LZMA2OutputStream.COMPRESSED_SIZE_MAX, arrayCache);
            let dictSize: number = options.getDictSize();
            let extraSizeBefore: number = LZMA2OutputStream.getExtraSizeBefore(dictSize);
            this.lzma = LZMAEncoder.getInstance(this.rc, options.getLc(), options.getLp(),
            options.getPb(), options.getMode(), dictSize, extraSizeBefore,
            options.getNiceLen(), options.getMatchFinder(), options.getDepthLimit(),
                this.arrayCache);
            this.lz = this.lzma.getLZEncoder();
            let presetDict: Int8Array = options.getPresetDict();
            if (presetDict != null && presetDict.length > 0) {
                this.lz.setPresetDict(dictSize, presetDict);
                this.dictResetNeeded = false;
            }

            this.props = (options.getPb() * 5 + options.getLp()) * 9 + options.getLc();
        }
    }

    public write(b: number): void {
        this.tempBuf[0] = b;
        this.writeBytesOffset(this.tempBuf, 0, 1);
    }

    public writeBytesOffset(buf: Int8Array, off: number, len: number): void {
        if (off >= 0 && len >= 0 && off + len >= 0 && off + len <= buf.length) {
            if (this.exception != null) {
                throw this.exception;
            } else if (this.finished) {
                throw new Exception("Stream finished or closed");
            } else {
                try {
                    while (len > 0) {
                        let used: number = this.lz.fillWindow(buf, off, len);
                        off += used;
                        len -= used;
                        this.pendingSize += used;
                        if (this.lzma.encodeForLZMA2()) {
                            this.writeChunk();
                        }
                    }

                } catch (e) {
                    this.exception = e;
                    throw e;
                }
            }
        } else {
            throw new Exception('IndexOutOfBoundsException');
        }
    }

    private writeChunk(): void {
        let compressedSize: number = this.rc.finish();
        let uncompressedSize: number = this.lzma.getUncompressedSize();


        if (compressedSize + 2 < uncompressedSize) {
            this.writeLZMA(uncompressedSize, compressedSize);
        } else {
            this.lzma.reset();
            uncompressedSize = this.lzma.getUncompressedSize();

            this.writeUncompressed(uncompressedSize);
        }

        this.pendingSize -= uncompressedSize;
        this.lzma.resetUncompressedSize();
        this.rc.reset();
    }

    private writeLZMA(uncompressedSize: number, compressedSize: number): void{
        let control: number;
        if (this.propsNeeded) {
            if (this.dictResetNeeded) {
                control = 224;
            } else {
                control = 192;
            }
        } else if (this.stateResetNeeded) {
            control = 160;
        } else {
            control = 128;
        }

        control = control | uncompressedSize - 1 >>> 16;
        this.chunkHeader[0] = control;
        this.chunkHeader[1] = ((uncompressedSize - 1) >>> 8);
        this.chunkHeader[2] = (uncompressedSize - 1);
        this.chunkHeader[3] = ((compressedSize - 1) >>> 8);
        this.chunkHeader[4] = (compressedSize - 1);
        if (this.propsNeeded) {
            this.chunkHeader[5] = this.props;
            this.out.writeBytesOffset(this.chunkHeader, 0, 6);
        } else {
            this.out.writeBytesOffset(this.chunkHeader, 0, 5);
        }

        this.rc.writeBytesOffset(this.out);
        this.propsNeeded = false;
        this.stateResetNeeded = false;
        this.dictResetNeeded = false;
    }

    private writeUncompressed(uncompressedSize: number): void {
        while (uncompressedSize > 0) {
            let chunkSize: number = Math.min(uncompressedSize, 65536);
            this.chunkHeader[0] = NumberTransform.toByte(this.dictResetNeeded ? 1 : 2);
            this.chunkHeader[1] = NumberTransform.toByte((chunkSize - 1) >>> 8);
            this.chunkHeader[2] = NumberTransform.toByte(chunkSize - 1);
            this.out.writeBytesOffset(this.chunkHeader, 0, 3);
            this.lz.copyUncompressed(this.out, uncompressedSize, chunkSize);
            uncompressedSize -= chunkSize;
            this.dictResetNeeded = false;
        }

        this.stateResetNeeded = true;
    }

    private writeEndMarker(): void {
        !this.finished;

        if (this.exception != null) {
            throw this.exception;
        } else {
            this.lz.setFinishing();

            try {
                while (this.pendingSize > 0) {
                    this.lzma.encodeForLZMA2();
                    this.writeChunk();
                }

                this.out.write(0);
            } catch (e) {
                this.exception = e;
                throw e;
            }

            this.finished = true;
            this.lzma.putArraysToCache(this.arrayCache);
            this.lzma = null;
            this.lz = null;
            this.rc.putArraysToCache(this.arrayCache);
            this.rc = null;
        }
    }

    public flush(): void {
        if (this.exception != null) {
            throw this.exception;
        } else if (this.finished) {
            throw new Exception("Stream finished or closed");
        } else {
            try {
                this.lz.setFlushing();

                while (this.pendingSize > 0) {
                    this.lzma.encodeForLZMA2();
                    this.writeChunk();
                }

                this.out.flush();
            } catch (e) {
                this.exception = e;
                throw e;
            }
        }
    }

    public finish(): void {
        if (!this.finished) {
            this.writeEndMarker();

            try {
                this.out.finish();
            } catch (e) {
                this.exception = e;
                throw e;
            }
        }

    }

    public close(): void {
        if (this.out != null) {
            if (!this.finished) {
                try {
                    this.writeEndMarker();
                } catch (e) {
                }
            }

            try {
                this.out.close();
            } catch (e) {
                if (this.exception == null) {
                    this.exception = e;
                }
            }

            this.out = null;
        }

        if (this.exception != null) {
            throw this.exception;
        }
    }
}
