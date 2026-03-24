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
import OutputStream from '../../../util/OutputStream';

export default class OutWindow {
    _buffer: Int8Array;
    _pos: number;
    _windowSize: number = 0;
    _streamPos: number;
    _stream: OutputStream;

    public Create(windowSize: number): void
    {
        if (this._buffer == null || this._windowSize != windowSize)
        this._buffer = new Int8Array(windowSize);
        this._windowSize = windowSize;
        this._pos = 0;
        this._streamPos = 0;
    }

    public SetStream(stream: OutputStream): void
    {
        this.ReleaseStream();
        this._stream = stream;
    }

    public ReleaseStream(): void
    {
        this.Flush();
        this._stream = null;
    }

    public Init(solid: boolean): void
    {
        if (!solid) {
            this._streamPos = 0;
            this._pos = 0;
        }
    }

    public Flush(): void
    {
        let size: number = this._pos - this._streamPos;
        if (size == 0)
        return;
        this._stream.writeBytesOffset(this._buffer, this._streamPos, size);
        if (this._pos >= this._windowSize)
        this._pos = 0;
        this._streamPos = this._pos;
    }

    public CopyBlock(distance: number, len: number): void
    {
        let pos: number = this._pos - distance - 1;
        if (pos < 0)
        pos += this._windowSize;
        for (; len != 0; len--) {
            if (pos >= this._windowSize)
            pos = 0;
            this._buffer[this._pos++] = this._buffer[pos++];
            if (this._pos >= this._windowSize)
            this.Flush();
        }
    }

    public PutByte(b: number): void
    {
        this._buffer[this._pos++] = b;
        if (this._pos >= this._windowSize)
        this.Flush();
    }

    public GetByte(distance: number): number
    {
        let pos: number = this._pos - distance - 1;
        if (pos < 0)
        pos += this._windowSize;
        return this._buffer[pos];
    }
}
