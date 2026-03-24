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
import OutputStream from '../../util/OutputStream'
import FinishableOutputStream from './FinishableOutputStream'
import type FilterEncoder from './FilterEncoder'
import FilterOptions from './FilterOptions'
import ArrayCache from './ArrayCache'
import StreamFlags from './StreamFlags'
import RawCoder from './RawCoder'
import Check from './Check'
import XZ from './XZ'
import IndexEncoder from './IndexEncoder'
import BlockOutputStream from './BlockOutputStream'
import EncoderUtil from './EncoderUtil'
import NumberTransform from './NumberTransform'
import Long from "../../util/long/index"

export default class XZOutputStream extends FinishableOutputStream {
    private arrayCache: ArrayCache;
    private out: OutputStream;
    private streamFlags: StreamFlags = new StreamFlags();
    private check: Check;
    private index: IndexEncoder = new IndexEncoder();
    private blockEncoder: BlockOutputStream;
    private filters: Array<FilterEncoder>;
    private filtersSupportFlushing: boolean;
    private exception: Exception = null;
    private finished: boolean = false;
    private tempBuf: Int8Array = new Int8Array(1);

    constructor(out: OutputStream, filterOptions: Array<FilterOptions>, checkType: number, arrayCache: ArrayCache) {
        super()
        this.arrayCache = arrayCache;
        this.out = out;
        this.updateFilter(filterOptions);
        this.streamFlags.checkType = checkType;
        this.check = Check.getInstance(checkType);
        this.encodeStreamHeader();
    }

    public updateFilters(filterOptions: FilterOptions) {
        let opts: Array<FilterOptions> = new Array<FilterOptions>(1);
        opts[0] = filterOptions;
        this.updateFilter(opts);
    }

    public updateFilter(filterOptions: Array<FilterOptions>) {
        if (this.blockEncoder != null) {
            throw new Exception("Changing filter options in the middle of a XZ Block not implemented");
        } else if (filterOptions.length >= 1 && filterOptions.length <= 4) {
            this.filtersSupportFlushing = true;
            let newFilters: Array<FilterEncoder> = new Array<FilterEncoder>(filterOptions.length);

            for (let i = 0; i < filterOptions.length; ++i) {
                newFilters[i] = filterOptions[i].getFilterEncoder();
                this.filtersSupportFlushing = this.filtersSupportFlushing && newFilters[i].supportsFlushing();
            }

            RawCoder.validate(newFilters);
            this.filters = newFilters;
        } else {
            throw new Exception("XZ filter chain must be 1-4 filters");
        }
    }

    public write(b: number): void {
        this.tempBuf[0] = b;
        this.writeBytesOffset(this.tempBuf, 0, 1);
    }

    public writeBytesOffset(buf: Int8Array, off: number, len: number) {
        if (off >= 0 && len >= 0 && off + len >= 0 && off + len <= buf.length) {
            if (this.exception != null) {
                throw this.exception;
            } else if (this.finished) {
                throw new Exception("Stream finished or closed");
            } else {
                try {
                    if (this.blockEncoder == undefined) {
                        this.blockEncoder = new BlockOutputStream(this.out, this.filters, this.check, this.arrayCache);
                    }

                    this.blockEncoder.writeBytesOffset(buf, off, len);
                } catch (e) {
                    this.exception = e;
                    throw e;
                }
            }
        } else {
            throw new Exception();
        }
    }

    public endBlock() {
        if (this.exception != null) {
            throw this.exception;
        } else if (this.finished) {
            throw new Exception("Stream finished or closed");
        } else {
            if (this.blockEncoder != null) {
                try {
                    this.blockEncoder.finish();
                    this.index.add(this.blockEncoder.getUnpaddedSize(), this.blockEncoder.getUncompressedSize());
                    this.blockEncoder = null;
                } catch (e) {
                    this.exception = e;
                    throw e;
                }
            }

        }
    }

    public flush() {
        if (this.exception != null) {
            throw this.exception;
        } else if (this.finished) {
            throw new Exception("Stream finished or closed");
        } else {
            try {
                if (this.blockEncoder != null) {
                    if (this.filtersSupportFlushing) {
                        this.blockEncoder.flush();
                    } else {
                        this.endBlock();
                        this.out.flush();
                    }
                } else {
                    this.out.flush();
                }

            } catch (e) {
                this.exception = e;
                throw e;
            }
        }
    }

    public finish() {
        if (!this.finished) {
            this.endBlock();

            try {
                this.index.encode(this.out);
                this.encodeStreamFooter();
            } catch (e) {
                this.exception = e;
                throw e;
            }

            this.finished = true;
        }

    }

    public close() {
        if (this.out != null) {
            try {
                this.finish();
            } catch (e) {
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
            throw this.exception;
        }
    }

    private encodeStreamFlags(buf: Int8Array, off: number): void {
        buf[off] = 0;
        buf[off + 1] = NumberTransform.toByte(this.streamFlags.checkType);
    }

    private encodeStreamHeader(): void {
        this.out.writeBytes(XZ.HEADER_MAGIC);
        let buf = new Int8Array(2);
        this.encodeStreamFlags(buf, 0);
        this.out.writeBytes(buf);
        EncoderUtil.writeCRC32(this.out, buf);
    }

    private encodeStreamFooter() {
        let buf = new Int8Array(6);
        let backwardSize: Long = this.index.getIndexSize().div(4).sub(1);

        for (let i = 0; i < 4; ++i) {
            buf[i] = NumberTransform.toByte(backwardSize.shiftRightUnsigned(i * 8).toInt());
        }

        this.encodeStreamFlags(buf, 4);
        EncoderUtil.writeCRC32(this.out, buf);
        this.out.writeBytes(buf);
        this.out.writeBytes(XZ.FOOTER_MAGIC);
    }
}
