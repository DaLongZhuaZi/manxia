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
import System from '../../util/System'
import Exception from '../../util/Exception'
import FinishableOutputStream from './FinishableOutputStream'
import ArrayCache from './ArrayCache'
import DataOutputStream from '../DataOutputStream'

export default class UncompressedLZMA2OutputStream extends FinishableOutputStream {
    private arrayCache: ArrayCache;
    private out: FinishableOutputStream;
    private outData: DataOutputStream;
    private uncompBuf: Int8Array;
    private uncompPos: number = 0;
    private dictResetNeeded: boolean = true;
    private finished: boolean = false;
    private exception: Exception = null;
    private tempBuf: Int8Array = new Int8Array(1);

    static getMemoryUsage(): number {
        return 70;
    }

    constructor(out: FinishableOutputStream, arrayCache: ArrayCache) {
        super()
        if (out == null) {
            throw new Exception();
        } else {
            this.out = out;
            this.outData = new DataOutputStream(out);
            this.arrayCache = arrayCache;
            this.uncompBuf = arrayCache.getByteArray(65536, false);
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
                        let copySize: number = Math.min(65536 - this.uncompPos, len);
                        System.arraycopy(buf, off, this.uncompBuf, this.uncompPos, copySize);
                        len -= copySize;
                        this.uncompPos += copySize;
                        if (this.uncompPos == 65536) {
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
        this.outData.writeByte(this.dictResetNeeded ? 1 : 2);
        this.outData.writeShort(this.uncompPos - 1);
        this.outData.writeBytesOffset(this.uncompBuf, 0, this.uncompPos);
        this.uncompPos = 0;
        this.dictResetNeeded = false;
    }

    private writeEndMarker(): void {
        if (this.exception != null) {
            throw this.exception;
        } else if (this.finished) {
            throw new Exception("Stream finished or closed");
        } else {
            try {
                if (this.uncompPos > 0) {
                    this.writeChunk();
                }

                this.out.write(0);
            } catch (e) {
                this.exception = e;
                throw e;
            }

            this.finished = true;
            this.arrayCache.putArrayInt8Array(this.uncompBuf);
        }
    }

    public flush(): void {
        if (this.exception != null) {
            throw this.exception;
        } else if (this.finished) {
            throw new Exception("Stream finished or closed");
        } else {
            try {
                if (this.uncompPos > 0) {
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
