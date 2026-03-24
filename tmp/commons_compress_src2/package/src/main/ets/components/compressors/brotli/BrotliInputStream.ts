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
import InputStream from '../../util/InputStream';
import States from './State';
import Exception from '../../util/Exception';
import System from '../../util/System';
import Decode from './Decode'

export default class BrotliInputStream extends InputStream {
    public static DEFAULT_INTERNAL_BUFFER_SIZE: number = 16384;
    private buffer: Int8Array;
    private remainingBufferBytes: number;
    private bufferOffset: number;
    private state: States;

    constructor(source: InputStream, byteReadBufferSize: number, customDictionary?: Int8Array) {
        super();
        this.state = new States();
        byteReadBufferSize = 16384;
        if (byteReadBufferSize <= 0) {
            throw new Exception("Bad buffer size:" + byteReadBufferSize);
        } else if (source == null) {
            throw new Exception("source is null");
        }
        this.buffer = new Int8Array(byteReadBufferSize);
        this.remainingBufferBytes = 0;
        this.bufferOffset = 0;
        try {
            States.setInput(this.state, source);
        } catch (var5) {
            throw new Exception("Brotli decoder initialization failed");
        }
        if (customDictionary != null) {
            Decode.setCustomDictionary(this.state, customDictionary);
        }
    }

    public close(): void {
        States.close(this.state);
    }

    public read(): number {
        if (this.bufferOffset >= this.remainingBufferBytes) {
            this.remainingBufferBytes = this.readBytesOffset(this.buffer, 0, this.buffer.length);
            this.bufferOffset = 0;
            if (this.remainingBufferBytes == -1) {
                return -1;
            }
        }
        return this.buffer[this.bufferOffset++] & 255;
    }

    public readBytesOffset(destBuffer: Int8Array, destOffset: number, destLen: number): number {

        if (destOffset < 0) {
            throw new Exception("Bad offset: " + destOffset);
        } else if (destLen < 0) {
            throw new Exception("Bad length: " + destLen);
        } else if (destOffset + destLen > destBuffer.length) {
            throw new Exception("Buffer overflow: " + (destOffset + destLen) + " > " + destBuffer.length);
        } else if (destLen == 0) {
            return 0;
        }
        let copyLen: number = Math.max(this.remainingBufferBytes - this.bufferOffset, 0);
        if (copyLen != 0) {
            copyLen = Math.min(copyLen, destLen);
            System.arraycopy(this.buffer, this.bufferOffset, destBuffer, destOffset, copyLen);
            this.bufferOffset += copyLen;
            destOffset += copyLen;
            destLen -= copyLen;
            if (destLen == 0) {
                return copyLen;
            }
        }
        try {
            this.state.output = destBuffer;
            this.state.outputOffset = destOffset;
            this.state.outputLength = destLen;
            this.state.outputUsed = 0;
            Decode.decompress(this.state);
            if (this.state.outputUsed == 0) {
                return -1;
            }
            return this.state.outputUsed + copyLen;
        } catch (var6) {
            throw new Exception("Brotli stream decoding failed");
        }
    }
}