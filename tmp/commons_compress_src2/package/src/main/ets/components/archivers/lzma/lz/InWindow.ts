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
import InputStream from '../../../util/InputStream';


export default class InWindow {
    _bufferBase: Int8Array;
    _stream: InputStream;
    _posLimit: number;
    _streamEndWasReached: Boolean;
    _pointerToLastSafePosition: number;
    _bufferOffset: number;
    _blockSize: number;
    _pos: number;
    _keepSizeBefore: number;
    _keepSizeAfter: number;
    _streamPos: number;

    public MoveBlock(): void
    {
        let offset = this._bufferOffset + this._pos - this._keepSizeBefore;
        if (offset > 0)
        offset--;

        let numBytes = this._bufferOffset + this._streamPos - offset;

        for (let i = 0; i < numBytes; i++)
        this._bufferBase[i] = this._bufferBase[offset + i];
        this._bufferOffset -= offset;
    }

    public ReadBlock(): void
    {
        if (this._streamEndWasReached)
        return;
        while (true) {
            let size = (0 - this._bufferOffset) + this._blockSize - this._streamPos;
            if (size == 0)
            return;
            let numReadBytes = this._stream.readBytesOffset(this._bufferBase, this._bufferOffset + this._streamPos, size);
            if (numReadBytes == -1) {
                this._posLimit = this._streamPos;
                let pointerToPostion = this._bufferOffset + this._posLimit;
                if (pointerToPostion > this._pointerToLastSafePosition)
                this._posLimit = this._pointerToLastSafePosition - this._bufferOffset;

                this._streamEndWasReached = true;
                return;
            }
            this._streamPos += numReadBytes;
            if (this._streamPos >= this._pos + this._keepSizeAfter)
            this._posLimit = this._streamPos - this._keepSizeAfter;
        }
    }

    Free(): void {
        this._bufferBase = null;
    }

    public Create(keepSizeBefore: number, keepSizeAfter: number, keepSizeReserv: number): void
    {
        this._keepSizeBefore = keepSizeBefore;
        this._keepSizeAfter = keepSizeAfter;
        let blockSize = keepSizeBefore + keepSizeAfter + keepSizeReserv;
        if (this._bufferBase == null || this._blockSize != blockSize) {
            this.Free();
            this._blockSize = blockSize;
            this._bufferBase = new Int8Array(this._blockSize);
        }
        this._pointerToLastSafePosition = this._blockSize - keepSizeAfter;
    }

    public SetStream(stream: InputStream): void {
        this._stream = stream;
    }

    public ReleaseStream(): void {
        this._stream = null;
    }

    public Init(): void
    {
        this._bufferOffset = 0;
        this._pos = 0;
        this._streamPos = 0;
        this._streamEndWasReached = false;
        this.ReadBlock();
    }

    public MovePos(): void
    {
        this._pos++;
        if (this._pos > this._posLimit) {
            let pointerToPostion = this._bufferOffset + this._pos;
            if (pointerToPostion > this._pointerToLastSafePosition)
            this.MoveBlock();
            this.ReadBlock();
        }
    }

    public GetIndexByte(index: number): number {
        return this._bufferBase[this._bufferOffset + this._pos + index];
    }

    public GetMatchLen(index: number, distance: number, limit: number): number
    {
        if (this._streamEndWasReached)
        if ((this._pos + index) + limit > this._streamPos)
        limit = this._streamPos - (this._pos + index);
        distance++;
        let pby: number = this._bufferOffset + this._pos + index;

        let i: number;
        for (i = 0; i < limit && this._bufferBase[pby + i] == this._bufferBase[pby + i - distance]; i++);
        return i;
    }

    public GetNumAvailableBytes(): number{
        return this._streamPos - this._pos;
    }

    public ReduceOffsets(subValue: number): void
    {
        this._bufferOffset += subValue;
        this._posLimit -= subValue;
        this._pos -= subValue;
        this._streamPos -= subValue;
    }
}