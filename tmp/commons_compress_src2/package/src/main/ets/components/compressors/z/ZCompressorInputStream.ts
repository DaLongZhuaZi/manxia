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


import Long from "../../util/long/index"
import LZWInputStream from '../lzw/LZWInputStream'
import InputStream from '../../util/InputStream'
import ByteOrder from '../../util/ByteOrder'
import Exception from '../../util/Exception'

export default class ZCompressorInputStream extends LZWInputStream {
    private static MAGIC_1: number = 0x1f;
    private static MAGIC_2: number = 0x9d;
    private static BLOCK_MODE_MASK: number = 0x80;
    private static MAX_CODE_SIZE_MASK: number = 0x1f;
    private blockMode: boolean;
    private maxCodeSize: number;
    private totalCodesRead: Long = Long.fromNumber(0);

    constructor(inputStream: InputStream, memoryLimitInKb: number) {
        super(inputStream, ByteOrder.LITTLE_ENDIAN);
        let firstByte: Long = this.ins.readBits(8);
        let secondByte: Long = this.ins.readBits(8);
        let thirdByte: Long = this.ins.readBits(8);
        if (firstByte.notEquals(ZCompressorInputStream.MAGIC_1) || secondByte.notEquals(ZCompressorInputStream.MAGIC_2)
        || thirdByte.lessThan(0)) {
            throw new Exception("Input is not in .Z format");
        }
        this.blockMode = thirdByte.and(ZCompressorInputStream.BLOCK_MODE_MASK).notEquals(0);
        this.maxCodeSize = thirdByte.and(ZCompressorInputStream.MAX_CODE_SIZE_MASK).toNumber();
        if (this.blockMode) {
            this.setClearCode(LZWInputStream.DEFAULT_CODE_SIZE);
        }
        this.initializeTablesd(this.maxCodeSize, memoryLimitInKb);
        this.clearEntries();
    }

    private clearEntries(): void {
        this.setTableSize((1 << 8) + (this.blockMode ? 1 : 0));
    }

    protected readNextCode(): number {
        let code: number = super.readNextCode();
        if (code >= 0) {
            this.totalCodesRead = this.totalCodesRead.add(1);
        }
        return code;
    }

    private reAlignReading(): void {

        let codeReadsToThrowAway: Long = Long.fromNumber(8).sub(this.totalCodesRead.rem(8));
        if (codeReadsToThrowAway.equals(8)) {
            codeReadsToThrowAway = Long.fromNumber(0);
        }
        for (let i: Long = Long.fromNumber(0); i.lessThan(codeReadsToThrowAway); i = i.add(1)) {
            this.readNextCode();
        }
        this.ins.clearBitCache();
    }

    protected addEntries(previousCode: number, character: number): number {
        let maxTableSize: number = 1 << this.getCodeSize();
        let r: number = this.addEntry(previousCode, character, maxTableSize);
        if (this.getTableSize() == maxTableSize && this.getCodeSize() < this.maxCodeSize) {
            this.reAlignReading();
            this.incrementCodeSize();
        }
        return r;
    }

    protected decompressNextSymbol(): number {

        let code: number = this.readNextCode();
        if (code < 0) {
            return -1;
        }
        if (this.blockMode && code == this.getClearCode()) {
            this.clearEntries();
            this.reAlignReading();
            this.resetCodeSize();
            this.resetPreviousCode();
            return 0;
        }
        let addedUnfinishedEntry: boolean = false;
        if (code == this.getTableSize()) {
            this.addRepeatOfPreviousCode();
            addedUnfinishedEntry = true;
        } else if (code > this.getTableSize()) {
            throw new Exception('Invalid bit code');
        }
        return this.expandCodeToOutputStack(code, addedUnfinishedEntry);
    }

    public static matches(signature: number[], length: number): boolean {
        return length > 3 && signature[0] == ZCompressorInputStream.MAGIC_1 && signature[1] == ZCompressorInputStream.MAGIC_2;
    }
}
