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
import DataInputStream from '../DataInputStream';
import InputStream from '../../util/InputStream';
import Exception from '../../util/Exception'
import SingleXZInputStream from './SingleXZInputStream';
import ArrayCache from './ArrayCache'

export default class XZInputStream extends InputStream {
    private arrayCache: ArrayCache;
    private memoryLimit: number;
    private input: InputStream;
    private xzIn: SingleXZInputStream;
    private verifyCheck: boolean;
    private endReached: boolean;
    private exception: Exception;
    private tempBuf;

    constructor(inputStream: InputStream, memoryLimit: number, verifyCheck: boolean, arrayCache: ArrayCache) {
        super();
        this.endReached = false;
        this.exception = null;
        this.tempBuf = new Int8Array(1);
        this.arrayCache = arrayCache;
        this.input = inputStream;
        this.memoryLimit = memoryLimit;
        this.verifyCheck = verifyCheck;
        this.xzIn = new SingleXZInputStream(inputStream, memoryLimit, verifyCheck, arrayCache);
    }

    public read(): number {
        let myRead = this.readBytesOffset(this.tempBuf, 0, 1) == -1 ? -1 : this.tempBuf[0] & 255;
        return myRead
    }

    public readBytesOffset(buf: Int8Array, off: number, len: number) {
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
                        if (this.xzIn == null) {
                            this.prepareNextStream();
                            if (this.endReached) {
                                return size == 0 ? -1 : size;
                            }
                        }

                        let ret: number = this.xzIn.readBytesOffset(buf, off, len);
                        if (ret > 0) {
                            size += ret;
                            off += ret;
                            len -= ret;
                        } else if (ret == -1) {
                            this.xzIn = null;
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

    private prepareNextStream() {
        let inData: DataInputStream = new DataInputStream(this.input);
        let buf = new Int8Array(12);

        do {
            let ret: number = inData.readBytesOffset(buf, 0, 1);
            if (ret == -1) {
                this.endReached = true;
                return;
            }

            inData.readBytesOffset(buf, 1, 3);
        } while (buf[0] == 0 && buf[1] == 0 && buf[2] == 0 && buf[3] == 0);

        inData.readBytesOffset(buf, 4, 8);

        try {
            this.xzIn = new SingleXZInputStream(this.input, this.memoryLimit, this.verifyCheck, this.arrayCache);
        } catch (e) {
            throw new Exception("Garbage after a valid XZ Stream");
        }
    }

    public available(): number {
        if (this.input == null) {
            throw new Exception("Stream closed");
        } else if (this.exception != null) {
            throw this.exception;
        } else {
            return this.xzIn == null ? 0 : this.xzIn.available();
        }
    }

    public close() {
        this.xzClose(true);
    }

    public xzClose(closeInput: boolean) {
        if (this.input != null) {
            if (this.xzIn != null) {
                this.xzIn.xzClose(false);
                this.xzIn = null;
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
