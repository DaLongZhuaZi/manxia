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
import InWindow from './InWindow';

export default class BinTree extends InWindow {
    _cyclicBufferPos: number;
    _cyclicBufferSize: number = 0;
    _matchMaxLen: number;
    _son: Int32Array;
    _hash: Int32Array;
    _cutValue: number = 0xFF;
    _hashMask: number;
    _hashSizeSum: number = 0;
    HASH_ARRAY: boolean = true;
    static kHash2Size: number = 1 << 10;
    static kHash3Size: number = 1 << 16;
    static kBT2HashSize: number = 1 << 16;
    static kStartMaxLen: number = 1;
    static kHash3Offset: number = BinTree.kHash2Size;
    static kEmptyHashValue: number = 0;
    static kMaxValForNormalize: number = (1 << 30) - 1;
    kNumHashDirectBytes: number = 0;
    kMinMatchCheck: number = 4;
    kFixHashSize: number = BinTree.kHash2Size + BinTree.kHash3Size;
    static CrcTable: Int32Array = new Int32Array(256);

    public SetType(numHashBytes: number): void
    {
        this.HASH_ARRAY = (numHashBytes > 2);
        if (this.HASH_ARRAY) {
            this.kNumHashDirectBytes = 0;
            this.kMinMatchCheck = 4;
            this.kFixHashSize = BinTree.kHash2Size + BinTree.kHash3Size;
        }
        else {
            this.kNumHashDirectBytes = 2;
            this.kMinMatchCheck = 2 + 1;
            this.kFixHashSize = 0;
        }
    }

    public Init(): void
    {
        super.Init();
        for (let i = 0; i < this._hashSizeSum; i++)
        this._hash[i] = BinTree.kEmptyHashValue;
        this._cyclicBufferPos = 0;
        this.ReduceOffsets(-1);
    }

    public MovePos(): void
    {
        if (++this._cyclicBufferPos >= this._cyclicBufferSize)
        this._cyclicBufferPos = 0;
        super.MovePos();
        if (this._pos == BinTree.kMaxValForNormalize)
        this.Normalize();
    }

    public BinTreeCreate(historySize: number, keepAddBufferBefore: number, matchMaxLen: number, keepAddBufferAfter: number): boolean
    {
        if (historySize > BinTree.kMaxValForNormalize - 256)
        return false;
        this._cutValue = 16 + (matchMaxLen >> 1);

        let windowReservSize = (historySize + keepAddBufferBefore +
        matchMaxLen + keepAddBufferAfter) / 2 + 256;

        super.Create(historySize + keepAddBufferBefore, matchMaxLen + keepAddBufferAfter, windowReservSize);

        this._matchMaxLen = matchMaxLen;

        let cyclicBufferSize: number = historySize + 1;
        if (this._cyclicBufferSize != cyclicBufferSize)
        this._son = new Int32Array((this._cyclicBufferSize = cyclicBufferSize) * 2);

        let hs: number = BinTree.kBT2HashSize;

        if (this.HASH_ARRAY) {
            hs = historySize - 1;
            hs |= (hs >> 1);
            hs |= (hs >> 2);
            hs |= (hs >> 4);
            hs |= (hs >> 8);
            hs >>= 1;
            hs |= 0xFFFF;
            if (hs > (1 << 24))
            hs >>= 1;
            this._hashMask = hs;
            hs++;
            hs += this.kFixHashSize;
        }
        if (hs != this._hashSizeSum)
        this._hash = new Int32Array(this._hashSizeSum = hs);
        return true;
    }

    public GetMatches(distances: Int32Array): number
    {
        let lenLimit: number;
        if (this._pos + this._matchMaxLen <= this._streamPos)
        lenLimit = this._matchMaxLen;
        else {
            lenLimit = this._streamPos - this._pos;
            if (lenLimit < this.kMinMatchCheck) {
                this.MovePos();
                return 0;
            }
        }

        let offset: number = 0;
        let matchMinPos: number = (this._pos > this._cyclicBufferSize) ? (this._pos - this._cyclicBufferSize) : 0;
        let cur = this._bufferOffset + this._pos;
        let maxLen = BinTree.kStartMaxLen; // to avoid items for len < hashSize;
        let hashValue: number;
        let hash2Value: number = 0;
        let hash3Value = 0;

        if (this.HASH_ARRAY) {
            let temp = BinTree.CrcTable[this._bufferBase[cur] & 0xFF] ^ (this._bufferBase[cur + 1] & 0xFF);
            hash2Value = temp & (BinTree.kHash2Size - 1);
            temp ^= ((this._bufferBase[cur + 2] & 0xFF) << 8);
            hash3Value = temp & (BinTree.kHash3Size - 1);
            hashValue = (temp ^ (BinTree.CrcTable[this._bufferBase[cur + 3] & 0xFF] << 5)) & this._hashMask;
        }
        else
        hashValue = ((this._bufferBase[cur] & 0xFF) ^ ((this._bufferBase[cur + 1] & 0xFF) << 8));

        let curMatch: number = this._hash[this.kFixHashSize + hashValue];
        if (this.HASH_ARRAY) {
            let curMatch2: number = this._hash[hash2Value];
            let curMatch3 = this._hash[BinTree.kHash3Offset + hash3Value];
            this._hash[hash2Value] = this._pos;
            this._hash[BinTree.kHash3Offset + hash3Value] = this._pos;
            if (curMatch2 > matchMinPos)
            if (this._bufferBase[this._bufferOffset + curMatch2] == this._bufferBase[cur]) {
                distances[offset++] = maxLen = 2;
                distances[offset++] = this._pos - curMatch2 - 1;
            }
            if (curMatch3 > matchMinPos)
            if (this._bufferBase[this._bufferOffset + curMatch3] == this._bufferBase[cur]) {
                if (curMatch3 == curMatch2)
                offset -= 2;
                distances[offset++] = maxLen = 3;
                distances[offset++] = this._pos - curMatch3 - 1;
                curMatch2 = curMatch3;
            }
            if (offset != 0 && curMatch2 == curMatch) {
                offset -= 2;
                maxLen = BinTree.kStartMaxLen;
            }
        }

        this._hash[this.kFixHashSize + hashValue] = this._pos;

        let ptr0: number = (this._cyclicBufferPos << 1) + 1;
        let ptr1: number = (this._cyclicBufferPos << 1);

        let len0: number, len1: number;
        len0 = len1 = this.kNumHashDirectBytes;

        if (this.kNumHashDirectBytes != 0) {
            if (curMatch > matchMinPos) {
                if (this._bufferBase[this._bufferOffset + curMatch + this.kNumHashDirectBytes] !=
                this._bufferBase[cur + this.kNumHashDirectBytes]) {
                    distances[offset++] = maxLen = this.kNumHashDirectBytes;
                    distances[offset++] = this._pos - curMatch - 1;
                }
            }
        }

        let count: number = this._cutValue;

        while (true) {
            if (curMatch <= matchMinPos || count-- == 0) {
                this._son[ptr0] = this._son[ptr1] = BinTree.kEmptyHashValue;
                break;
            }
            let delta: number = this._pos - curMatch;
            let cyclicPos: number = ((delta <= this._cyclicBufferPos) ?
                (this._cyclicBufferPos - delta) :
                (this._cyclicBufferPos - delta + this._cyclicBufferSize)) << 1;

            let pby1: number = this._bufferOffset + curMatch;
            let len: number = Math.min(len0, len1);
            if (this._bufferBase[pby1 + len] == this._bufferBase[cur + len]) {
                while (++len != lenLimit)
                if (this._bufferBase[pby1 + len] != this._bufferBase[cur + len])
                break;
                if (maxLen < len) {
                    distances[offset++] = maxLen = len;
                    distances[offset++] = delta - 1;
                    if (len == lenLimit) {
                        this._son[ptr1] = this._son[cyclicPos];
                        this._son[ptr0] = this._son[cyclicPos + 1];
                        break;
                    }
                }
            }
            if ((this._bufferBase[pby1 + len] & 0xFF) < (this._bufferBase[cur + len] & 0xFF)) {
                this._son[ptr1] = curMatch;
                ptr1 = cyclicPos + 1;
                curMatch = this._son[ptr1];
                len1 = len;
            }
            else {
                this._son[ptr0] = curMatch;
                ptr0 = cyclicPos;
                curMatch = this._son[ptr0];
                len0 = len;
            }
        }
        this.MovePos();
        return offset;
    }

    public Skip(num: number): void
    {
        do
        {
            let lenLimit: number;
            if (this._pos + this._matchMaxLen <= this._streamPos)
            lenLimit = this._matchMaxLen;
            else {
                lenLimit = this._streamPos - this._pos;
                if (lenLimit < this.kMinMatchCheck) {
                    this.MovePos();
                    continue;
                }
            }

            let matchMinPos: number = (this._pos > this._cyclicBufferSize) ? (this._pos - this._cyclicBufferSize) : 0;
            let cur: number = this._bufferOffset + this._pos;

            let hashValue: number;

            if (this.HASH_ARRAY) {
                let temp: number = BinTree.CrcTable[this._bufferBase[cur] & 0xFF] ^ (this._bufferBase[cur + 1] & 0xFF);
                let hash2Value: number = temp & (BinTree.kHash2Size - 1);
                this._hash[hash2Value] = this._pos;
                temp ^= ((this._bufferBase[cur + 2] & 0xFF) << 8);
                let hash3Value: number = temp & (BinTree.kHash3Size - 1);
                this._hash[BinTree.kHash3Offset + hash3Value] = this._pos;
                hashValue = (temp ^ (BinTree.CrcTable[this._bufferBase[cur + 3] & 0xFF] << 5)) & this._hashMask;
            }
            else
            hashValue = ((this._bufferBase[cur] & 0xFF) ^ ((this._bufferBase[cur + 1] & 0xFF) << 8));

            let curMatch: number = this._hash[this.kFixHashSize + hashValue];
            this._hash[this.kFixHashSize + hashValue] = this._pos;

            let ptr0: number = (this._cyclicBufferPos << 1) + 1;
            let ptr1: number = (this._cyclicBufferPos << 1);

            let len0, len1;
            len0 = len1 = this.kNumHashDirectBytes;

            let count = this._cutValue;
            while (true) {
                if (curMatch <= matchMinPos || count-- == 0) {
                    this._son[ptr0] = this._son[ptr1] = BinTree.kEmptyHashValue;
                    break;
                }

                let delta: number = this._pos - curMatch;
                let cyclicPos: number = ((delta <= this._cyclicBufferPos) ?
                    (this._cyclicBufferPos - delta) :
                    (this._cyclicBufferPos - delta + this._cyclicBufferSize)) << 1;

                let pby1: number = this._bufferOffset + curMatch;
                let len: number = Math.min(len0, len1);
                if (this._bufferBase[pby1 + len] == this._bufferBase[cur + len]) {
                    while (++len != lenLimit)
                    if (this._bufferBase[pby1 + len] != this._bufferBase[cur + len])
                    break;
                    if (len == lenLimit) {
                        this._son[ptr1] = this._son[cyclicPos];
                        this._son[ptr0] = this._son[cyclicPos + 1];
                        break;
                    }
                }
                if ((this._bufferBase[pby1 + len] & 0xFF) < (this._bufferBase[cur + len] & 0xFF)) {
                    this._son[ptr1] = curMatch;
                    ptr1 = cyclicPos + 1;
                    curMatch = this._son[ptr1];
                    len1 = len;
                }
                else {
                    this._son[ptr0] = curMatch;
                    ptr0 = cyclicPos;
                    curMatch = this._son[ptr0];
                    len0 = len;
                }
            }
            this.MovePos();
        }
        while (--num != 0);
    }

    NormalizeLinks(items: Int32Array, numItems: number, subValue: number): void
    {
        for (let i = 0; i < numItems; i++) {
            let value: number = items[i];
            if (value <= subValue)
            value = BinTree.kEmptyHashValue;
            else
            value -= subValue;
            items[i] = value;
        }
    }

    Normalize(): void
    {
        let subValue: number = this._pos - this._cyclicBufferSize;
        this.NormalizeLinks(this._son, this._cyclicBufferSize * 2, subValue);
        this.NormalizeLinks(this._hash, this._hashSizeSum, subValue);
        this.ReduceOffsets(subValue);
    }

    public SetCutValue(cutValue: number): void {
        this._cutValue = cutValue;
    }

    public static staticInit(): void {
        for (let i = 0; i < 256; i++) {
            let r: number = i;
            for (let j = 0; j < 8; j++)
            if ((r & 1) != 0)
            r = (r >>> 1) ^ 0xEDB88320;
            else
            r >>>= 1;
            BinTree.CrcTable[i] = r;
        }
    }
}

BinTree.staticInit()