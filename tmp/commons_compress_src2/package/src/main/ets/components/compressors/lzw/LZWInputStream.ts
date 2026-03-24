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


import CompressorInputStream from '../CompressorInputStream'
import type InputStreamStatistics from '../../util/InputStreamStatistics'
import BitInputStream from '../../util/BitInputStream'
import InputStream from '../../util/InputStream'
import ByteOrder from '../../util/ByteOrder'
import Long from "../../util/long/index"
import System from '../../util/System'
import Exception from '../../util/Exception'


export default abstract class LZWInputStream extends CompressorInputStream implements InputStreamStatistics {
    protected static DEFAULT_CODE_SIZE: number = 9;
    protected static UNUSED_PREFIX: number = -1;
    private oneByte: Int8Array = new Int8Array(1);
    protected ins: BitInputStream;
    private clearCode: number = -1;
    private codeSize: number = LZWInputStream.DEFAULT_CODE_SIZE;
    private previousCodeFirstChar: number = 0;
    private previousCode: number = LZWInputStream.UNUSED_PREFIX;
    private tableSize: number = 0;
    private prefixes: Int32Array;
    private characters: Int8Array;
    private outputStack: Int8Array;
    private outputStackLocation: number;

    constructor(inputStream: InputStream, byteOrder: ByteOrder) {
        super();
        this.ins = new BitInputStream(inputStream, byteOrder);
    }

    public close(): void {
        this.ins.close();
    }

    public read(): number {
        let ret: number = this.readBytes(this.oneByte);
        if (ret < 0) {
            return ret;
        }
        return 0xff & this.oneByte[0];
    }

    public readBytesOffset(b: Int8Array, off: number, len: number): number {
        if (len == 0) {
            return 0;
        }
        let bytesRead: number = this.readFromStack(b, off, len);
        while (len - bytesRead > 0) {
            let result: number = this.decompressNextSymbol();
            if (result < 0) {
                if (bytesRead > 0) {
                    this.counts(Long.fromNumber(bytesRead));
                    return bytesRead;
                }
                return result;
            }
            bytesRead += this.readFromStack(b, off + bytesRead, len - bytesRead);
        }
        this.counts(Long.fromNumber(bytesRead));
        return bytesRead;
    }

    public getCompressedCount(): Long {
        return this.ins.getBytesRead();
    }

    protected abstract decompressNextSymbol(): number;

    protected abstract addEntries(previousCode: number, character: number): number

    protected setClearCode(codeSize: number): void {
        this.clearCode = (1 << (codeSize - 1));
    }

    protected initializeTablesd(maxCodeSize: number, memoryLimitInKb: number): void {
        if (maxCodeSize <= 0) {
            throw new Exception("maxCodeSize is " + maxCodeSize
            + ", must be bigger than 0");
        }

        if (memoryLimitInKb > -1) {
            let maxTableSize: number = 1 << maxCodeSize;
            let memoryUsageInBytes: Long = Long.fromNumber(maxTableSize * 6);
            let memoryUsageInKb: Long = memoryUsageInBytes.shiftRight(10);

            if (memoryUsageInKb.toNumber() > memoryLimitInKb) {
                throw new Exception("memoryUsageInKb");
            }
        }
        this.initializeTables(maxCodeSize);
    }

    protected initializeTables(maxCodeSize: number): void {
        if (maxCodeSize <= 0) {

        }
        let maxTableSize: number = 1 << maxCodeSize;
        this.prefixes = new Int32Array(maxTableSize);
        this.characters = new Int8Array(maxTableSize);
        this.outputStack = new Int8Array(maxTableSize);
        this.outputStackLocation = maxTableSize;
        let max: number = 1 << 8;
        for (let i: number = 0; i < max; i++) {
            this.prefixes[i] = -1;
            this.characters[i] = i;
        }
    }

    protected readNextCode(): number {
        if (this.codeSize > 31) {
            throw new Exception("Code size must not be bigger than 31");
        }
        return this.ins.readBits(this.codeSize).toInt();
    }

    protected addEntry(previousCode: number, character: number, maxTableSize: number): number {
        if (this.tableSize < maxTableSize) {
            this.prefixes[this.tableSize] = previousCode;
            this.characters[this.tableSize] = character;
            return this.tableSize++;
        }
        return -1;
    }

    /**
     * Add entry for repeat of previousCode we haven't added, yet.
     * @return new code for a repeat of the previous code or -1 if
     * maxTableSize has been reached already
     * @throws IOException on error
     */
    protected addRepeatOfPreviousCode(): number {
        if (this.previousCode == -1) {

        }
        return this.addEntries(this.previousCode, this.previousCodeFirstChar);
    }

    protected expandCodeToOutputStack(code: number, addedUnfinishedEntry: boolean): number {
        for (let entry: number = code; entry >= 0; entry = this.prefixes[entry]) {
            this.outputStack[--this.outputStackLocation] = this.characters[entry];
        }
        if (this.previousCode != -1 && !addedUnfinishedEntry) {
            this.addEntries(this.previousCode, this.outputStack[this.outputStackLocation]);
        }
        this.previousCode = code;
        this.previousCodeFirstChar = this.outputStack[this.outputStackLocation];
        return this.outputStackLocation;
    }

    private readFromStack(b: Int8Array, off: number, len: number): number {
        let remainingInStack: number = this.outputStack.length - this.outputStackLocation;
        if (remainingInStack > 0) {
            let maxLength: number = Math.min(remainingInStack, len);
            System.arraycopy(this.outputStack, this.outputStackLocation, b, off, maxLength);
            this.outputStackLocation += maxLength;
            return maxLength;
        }
        return 0;
    }

    protected getCodeSize(): number {
        return this.codeSize;
    }

    protected resetCodeSize(): void {
        this.setCodeSize(LZWInputStream.DEFAULT_CODE_SIZE);
    }

    protected setCodeSize(cs: number): void {
        this.codeSize = cs;
    }

    protected incrementCodeSize(): void {
        this.codeSize++;
    }

    protected resetPreviousCode(): void {
        this.previousCode = -1;
    }

    protected getPrefix(offset: number): number {
        return this.prefixes[offset];
    }

    protected setPrefix(offset: number, value: number): void {
        this.prefixes[offset] = value;
    }

    protected getPrefixesLength(): number {
        return this.prefixes.length;
    }

    protected getClearCode(): number {
        return this.clearCode;
    }

    protected getTableSize(): number {
        return this.tableSize;
    }

    protected setTableSize(newSize: number): void  {
        this.tableSize = newSize;
    }
}
