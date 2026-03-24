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
import type SimpleFilter from './simple/SimpleFilter'
import System from '../../util/System'
import Exception from '../../util/Exception'

export default class SimpleInputStream extends InputStream {
    private static FILTER_BUF_SIZE: number = 4096;
    private inputStream: InputStream;
    private simpleFilter: SimpleFilter;
    private filterBuf = new Int8Array(4096);
    private pos: number = 0;
    private filtered: number = 0;
    private unfiltered: number = 0;
    private endReached: boolean = false;
    private exception = null;
    private tempBuf = new Int8Array(1);

    static getMemoryUsage(): number {
        return 5;
    }

    constructor(inputStream: InputStream, simpleFilter: SimpleFilter) {
        super()
        if (inputStream == null) {
            throw new Exception();
        } else {
            simpleFilter != null;

            this.inputStream = inputStream;
            this.simpleFilter = simpleFilter;
        }
    }

    public read(): number {
        return this.readBytesOffset(this.tempBuf, 0, 1) == -1 ? -1 : this.tempBuf[0] & 255;
    }

    public readBytesOffset(buf: Int8Array, off: number, len: number): number {
        if (off >= 0 && len >= 0 && off + len >= 0 && off + len <= buf.length) {
            if (len == 0) {
                return 0;
            } else if (this.inputStream == null) {
                throw new Exception("Stream closed");
            } else if (this.exception != null) {
                throw this.exception;
            } else {
                try {
                    let size = 0;

                    while (true) {
                        let copySize = Math.min(this.filtered, len);
                        System.arraycopy(this.filterBuf, this.pos, buf, off, copySize);
                        this.pos += copySize;
                        this.filtered -= copySize;
                        off += copySize;
                        len -= copySize;
                        size += copySize;
                        if (this.pos + this.filtered + this.unfiltered == 4096) {
                            System.arraycopy(this.filterBuf, this.pos, this.filterBuf, 0, this.filtered + this.unfiltered);
                            this.pos = 0;
                        }

                        if (len == 0 || this.endReached) {
                            return size > 0 ? size : -1;
                        }

                        let inSize = 4096 - (this.pos + this.filtered + this.unfiltered);
                        inSize = this.inputStream.readBytesOffset(this.filterBuf, this.pos + this.filtered + this.unfiltered, inSize);
                        if (inSize == -1) {
                            this.endReached = true;
                            this.filtered = this.unfiltered;
                            this.unfiltered = 0;
                        } else {
                            this.unfiltered += inSize;
                            this.filtered = this.simpleFilter.code(this.filterBuf, this.pos, this.unfiltered);
                            this.unfiltered -= this.filtered;
                        }
                    }
                } catch (e) {
                    this.exception = e;
                    throw e;
                }
            }
        } else {
            throw new Exception();
        }
    }

    public available() {
        if (this.inputStream == null) {
            throw new Exception("Stream closed");
        } else if (this.exception != null) {
            throw this.exception;
        } else {
            return this.filtered;
        }
    }

    public close() {
        if (this.inputStream != null) {
            try {
                this.inputStream.close();
            } finally {
                this.inputStream = null;
            }
        }

    }
}
