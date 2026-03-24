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
import TarArchiveEntry from './TarArchiveEntry';
import TarArchiveSparseEntry from './TarArchiveSparseEntry';
import ArchiveInputStream from '../ArchiveInputStream';
import type ArchiveEntry from '../ArchiveEntry';
import InputStream from '../../util/InputStream';
import IOUtils from '../../util/IOUtils';
import Integer from '../../util/Integer';
import Exception from '../../util/Exception';
import IllegalStateException from '../../util/IllegalStateException';
import ByteArrayOutputStream from '../../util/ByteArrayOutputStream';
import Long from "../../util/long/index";
import System from '../../util/System';
import TarUtils from './TarUtils';
import TarArchiveStructSparse from './TarArchiveStructSparse';
import TarConstants from './TarConstants';
import ArchiveUtils from '../../util/ArchiveUtils';
import BoundedInputStream from '../../util/BoundedInputStream';
import type ZipEncoding from '../zip/ZipEncoding';
import ZipEncodingHelper from '../zip/ZipEncodingHelper';
import TarArchiveSparseZeroInputStream from './TarArchiveSparseZeroInputStream';

export default class TarArchiveInputStream extends ArchiveInputStream {
    private static SMALL_BUFFER_SIZE: number = 256;
    private smallBuf: Int8Array = new Int8Array(TarArchiveInputStream.SMALL_BUFFER_SIZE);
    private recordSize: number;
    private recordBuffer: Int8Array;
    private blockSize: number;
    private hasHitEOF: boolean;
    private entrySize: Long;
    private entryOffset: Long;
    private inputStream: InputStream;
    private sparseInputStreams: Array<InputStream>;
    private currentSparseInputStreamIndex: number;
    private currEntry: TarArchiveEntry;
    private zipEncoding: ZipEncoding;
    encoding: string;
    private globalPaxHeaders: Map<string, string> = new Map<string, string>();
    private globalSparseHeaders: Array<TarArchiveStructSparse> = new Array<TarArchiveStructSparse>();
    private lenient: boolean;

    constructor(inputStream: InputStream, blockSize: number, recordSize: number,
                encoding: string, lenient: boolean) {
        super();
        this.inputStream = inputStream;
        this.hasHitEOF = false;
        this.encoding = encoding;
        this.zipEncoding = ZipEncodingHelper.getZipEncoding(encoding);
        this.recordSize = recordSize;
        this.recordBuffer = new Int8Array(recordSize);
        this.blockSize = blockSize;
        this.lenient = lenient;
    }

    public close(): void {

        if (this.sparseInputStreams != null) {
            let stream: InputStream;
            for (stream of this.sparseInputStreams) {
                stream.close();
            }
        }
        this.inputStream.close();
    }

    public getRecordSize(): number {
        return this.recordSize;
    }

    public available(): number {
        if (this.isDirectory()) {
            return 0;
        }

        if (this.currEntry.getRealSize().sub(this.entryOffset).toNumber() > Integer.MAX_VALUE) {
            return Integer.MAX_VALUE;
        }
        return this.currEntry.getRealSize().sub(this.entryOffset).toNumber();
    }

    public skip(n: number): number {
        if (n <= 0 || this.isDirectory()) {
            return 0;
        }

        let availableOfInputStream: Long = Long.fromNumber(this.inputStream.available());
        let available: Long = this.currEntry.getRealSize().sub(this.entryOffset.toNumber());
        let numToSkip: Long = Long.fromNumber(Math.min(n, available.toNumber()));
        let skipped: Long;

        if (!this.currEntry.isSparse()) {
            skipped = IOUtils.skip(this.inputStream, numToSkip);

            skipped = this.getActuallySkipped(availableOfInputStream, skipped, numToSkip);
        } else {
            skipped = this.skipSparse(numToSkip);
        }

        this.count(skipped.toNumber());
        this.entryOffset = this.entryOffset.add(skipped);
        return skipped.toNumber();
    }

    private skipSparse(n: Long): Long {
        if (this.sparseInputStreams == null || this.sparseInputStreams.length == 0) {
            return Long.fromNumber(this.inputStream.skip(n.toNumber()));
        }

        let bytesSkipped: Long = Long.fromNumber(0);

        while (bytesSkipped.lessThan(n) && this.currentSparseInputStreamIndex < this.sparseInputStreams.length) {
            let currentInputStream: InputStream = this.sparseInputStreams[this.currentSparseInputStreamIndex];
            bytesSkipped = bytesSkipped.add(currentInputStream.skip(n.sub(bytesSkipped).toNumber()));

            if (bytesSkipped.lessThan(n)) {
                this.currentSparseInputStreamIndex++;
            }
        }

        return bytesSkipped;
    }

    public markSupported(): boolean {
        return false;
    }

    public mark(markLimit: number): void {
    }

    public reset(): void {
    }

    public getNextTarEntry(): TarArchiveEntry {
        if (this.isAtEOF()) {
            return null;
        }

        if (this.currEntry != null) {

            IOUtils.skip(this, Long.MAX_VALUE);

            this.skipRecordPadding();
        }

        let headerBuf: Int8Array = this.getRecord();

        if (headerBuf == null) {
            this.currEntry = null;
            return null;
        }

        try {
            this.currEntry = new TarArchiveEntry();
            this.currEntry.tarArchiveEntryBuf(headerBuf, this.zipEncoding, this.lenient);
        } catch (e) {
            throw new Exception("Error detected parsing the header");
        }

        this.entryOffset = Long.fromNumber(0);
        this.entrySize = this.currEntry.getSize();

        if (this.currEntry.isGNULongLinkEntry()) {
            let longLinkData: Int8Array = this.getLongNameData();
            if (longLinkData == null) {
                return null;
            }
            this.currEntry.setLinkName(this.zipEncoding.decode(longLinkData));
        }

        if (this.currEntry.isGNULongNameEntry()) {
            let longNameData: Int8Array = this.getLongNameData();
            if (longNameData == null) {

                return null;
            }

            let name: string = this.zipEncoding.decode(longNameData);
            this.currEntry.setName(name);
            if (this.currEntry.isDirectory() && !name.endsWith("/")) {
                this.currEntry.setName(name + "/");
            }
        }

        if (this.currEntry.isGlobalPaxHeader()) {
            this.readGlobalPaxHeaders();
        }

        try {
            if (this.currEntry.isPaxHeader()) {
                this.paxHeaders();
            } else if (this.globalPaxHeaders.size != 0) {
                this.applyPaxHeadersToCurrentEntry(this.globalPaxHeaders, this.globalSparseHeaders);
            }
        } catch (e) {
            throw new Exception("Error detected parsing the pax header");
        }

        if (this.currEntry.isOldGNUSparse()) {
            this.readOldGNUSparse();
        }


        this.entrySize = this.currEntry.getSize();

        return this.currEntry;
    }

    private skipRecordPadding(): void {
        if (!this.isDirectory() && this.entrySize.greaterThan(0) && this.entrySize.rem(this.recordSize).toNumber() != 0) {
            let available: Long = Long.fromNumber(this.inputStream.available());
            let numRecords: Long = this.entrySize.divide(this.recordSize).add(1);
            let padding: Long = numRecords.multiply(this.recordSize).sub(this.entrySize);
            let skipped: Long = IOUtils.skip(this.inputStream, padding);

            skipped = this.getActuallySkipped(available, skipped, padding);

            this.count(skipped.toNumber());
        }
    }

    private getActuallySkipped(available: Long, skipped: Long, expected: Long): Long {
        let actuallySkipped: Long = skipped;
        if (actuallySkipped.notEquals(expected)) {
            throw new Exception("Truncated TAR archive");
        }
        return actuallySkipped;
    }

    protected getLongNameData(): Int8Array {
        let longName: ByteArrayOutputStream = new ByteArrayOutputStream();
        let length: number = 0;
        while ((length = this.readBytes(this.smallBuf)) >= 0) {
            longName.writeBytesOffset(this.smallBuf, 0, length);
        }
        this.getNextEntry();
        if (this.currEntry == null) {
            return null;
        }
        let longNameData: Int8Array = longName.toByteArray();
        length = longNameData.length;
        while (length > 0 && longNameData[length - 1] == 0) {
            --length;
        }
        if (length != longNameData.length) {
            let l: Int8Array = new Int8Array(length);
            System.arraycopy(longNameData, 0, l, 0, length);
            longNameData = l;
        }
        return longNameData;
    }

    private getRecord(): Int8Array {
        let headerBuf: Int8Array = this.readRecord();
        this.setAtEOF(this.isEOFRecord(headerBuf));
        if (this.isAtEOF() && headerBuf != null) {
            this.tryToConsumeSecondEOFRecord();
            this.consumeRemainderOfLastBlock();
            headerBuf = null;
        }
        return headerBuf;
    }

    protected isEOFRecord(record: Int8Array): boolean {
        return record == null || ArchiveUtils.isArrayZero(record, this.recordSize);
    }

    protected readRecord(): Int8Array {
        let readNow: number = IOUtils.readFull(this.inputStream, this.recordBuffer);
        this.count(readNow);
        if (readNow != this.recordSize) {
            return null;
        }

        return this.recordBuffer;
    }

    private readGlobalPaxHeaders(): void {
        this.globalPaxHeaders = TarUtils.parsePaxHeaders(this, this.globalSparseHeaders, this.globalPaxHeaders, this.entrySize);
        this.getNextEntry();

        if (this.currEntry == null) {
            throw new Exception("Error detected parsing the pax header");
        }
    }

    private paxHeaders(): void {
        let sparseHeaders: Array<TarArchiveStructSparse> = new Array<TarArchiveStructSparse>();
        let headers: Map<string, string> = TarUtils.parsePaxHeaders(this, sparseHeaders, this.globalPaxHeaders, this.entrySize);


        if (headers.has("GNU.sparse.map")) {
            sparseHeaders = TarUtils.parseFromPAX01SparseHeaders(headers.get("GNU.sparse.map"));
        }
        this.getNextEntry();
        if (this.currEntry == null) {
            throw new Exception("premature end of tar archive. Didn't find any entry after PAX header.");
        }
        this.applyPaxHeadersToCurrentEntry(headers, sparseHeaders);

        if (this.currEntry.isPaxGNU1XSparse()) {
            sparseHeaders = TarUtils.parsePAX1XSparseHeaders(this.inputStream, this.recordSize);
            this.currEntry.setSparseHeaders(sparseHeaders);
        }

        this.buildSparseInputStreams();
    }

    private applyPaxHeadersToCurrentEntry(headers: Map<string, string>, sparseHeaders: Array<TarArchiveStructSparse>): void {
        this.currEntry.updateEntryFromPaxHeaders(headers);
        this.currEntry.setSparseHeaders(sparseHeaders);
    }

    private readOldGNUSparse(): void {
        if (this.currEntry.isExtendedFollows()) {
            let entry: TarArchiveSparseEntry;
            do {
                let headerBuf: Int8Array = this.getRecord();
                if (headerBuf == null) {
                    throw new Exception("premature end of tar archive. Didn't find extended_header after header with extended flag.");
                }
                entry = new TarArchiveSparseEntry(headerBuf);
                Array.prototype.push.apply(this.currEntry.getSparseHeaders(), entry.getSparseHeaders());
            } while (entry.isExtendedFollows());
        }

        this.buildSparseInputStreams();
    }

    private isDirectory(): boolean {
        return this.currEntry != null && this.currEntry.isDirectory();
    }

    public getNextEntry(): ArchiveEntry {
        return this.getNextTarEntry();
    }

    private tryToConsumeSecondEOFRecord(): void {
        let shouldReset: boolean = true;
        let marked: boolean = this.inputStream.markSupported();
        if (marked) {
            this.inputStream.mark(this.recordSize);
        }
        try {
            shouldReset = !this.isEOFRecord(this.readRecord());
        } finally {
            if (shouldReset && marked) {
                this.pushedBackBytes(Long.fromNumber(this.recordSize));
                this.inputStream.reset();
            }
        }
    }

    public readBytesOffset(buf: Int8Array, offset: number, numToRead: number): number {
        if (numToRead == 0) {
            return 0;
        }
        let totalRead: number = 0;

        if (this.isAtEOF() || this.isDirectory()) {
            return -1;
        }

        if (this.currEntry == null) {
            throw new IllegalStateException("No current tar entry");
        }

        if (this.entryOffset.low >= this.currEntry.getRealSize().low) {
            return -1;
        }

        numToRead = Math.min(numToRead, this.available());

        if (this.currEntry.isSparse()) {
            totalRead = this.readSparse(buf, offset, numToRead);
        } else {
            totalRead = this.inputStream.readBytesOffset(buf, offset, numToRead);
        }

        if (totalRead == -1) {
            if (numToRead > 0) {
                throw new Exception("Truncated TAR archive");
            }
            this.setAtEOF(true);
        } else {
            this.count(totalRead);
            this.entryOffset = this.entryOffset.add(totalRead);
        }

        return totalRead;
    }

    private readSparse(buf: Int8Array, offset: number, numToRead: number): number {
        if (this.sparseInputStreams == null || this.sparseInputStreams.length == 0) {
            return this.inputStream.readBytesOffset(buf, offset, numToRead);
        }

        if (this.currentSparseInputStreamIndex >= this.sparseInputStreams.length) {
            return -1;
        }

        let currentInputStream: InputStream = this.sparseInputStreams[this.currentSparseInputStreamIndex];
        let readLen: number = currentInputStream.readBytesOffset(buf, offset, numToRead);

        if (this.currentSparseInputStreamIndex == this.sparseInputStreams.length - 1) {
            return readLen;
        }

        if (readLen == -1) {
            this.currentSparseInputStreamIndex++;
            return this.readSparse(buf, offset, numToRead);
        }

        if (readLen < numToRead) {
            this.currentSparseInputStreamIndex++;
            let readLenOfNext: number = this.readSparse(buf, offset + readLen, numToRead - readLen);
            if (readLenOfNext == -1) {
                return readLen;
            }

            return readLen + readLenOfNext;
        }

        return readLen;
    }

    public canReadEntryData(ae: ArchiveEntry): boolean {
        return ae instanceof TarArchiveEntry;
    }

    public getCurrentEntry(): TarArchiveEntry {
        return this.currEntry;
    }

    protected setCurrentEntry(e: TarArchiveEntry): void {
        this.currEntry = e;
    }

    protected isAtEOF(): boolean {
        return this.hasHitEOF;
    }

    protected setAtEOF(b: boolean): void {
        this.hasHitEOF = b;
    }

    private consumeRemainderOfLastBlock(): void {
        let bytesReadOfLastBlock: Long = this.getBytesRead().rem(this.blockSize);
        if (bytesReadOfLastBlock.gt(0)) {
            let skipped: Long = IOUtils.skip(this.inputStream,
            Long.fromNumber(this.blockSize).sub(bytesReadOfLastBlock.toNumber()));
            this.count(skipped.toNumber());
        }
    }

    public static matches(signature: Int8Array, length: number): boolean {
        if (length < TarConstants.VERSION_OFFSET + TarConstants.VERSIONLEN) {
            return false;
        }

        if (ArchiveUtils.matchAsciiBuffer(TarConstants.MAGIC_POSIX,
            signature, TarConstants.MAGIC_OFFSET, TarConstants.MAGICLEN)
        &&
        ArchiveUtils.matchAsciiBuffer(TarConstants.VERSION_POSIX,
            signature, TarConstants.VERSION_OFFSET, TarConstants.VERSIONLEN)
        ) {
            return true;
        }
        if (ArchiveUtils.matchAsciiBuffer(TarConstants.MAGIC_GNU,
            signature, TarConstants.MAGIC_OFFSET, TarConstants.MAGICLEN)
        &&
        (
            ArchiveUtils.matchAsciiBuffer(TarConstants.VERSION_GNU_SPACE,
                signature, TarConstants.VERSION_OFFSET, TarConstants.VERSIONLEN)
            ||
            ArchiveUtils.matchAsciiBuffer(TarConstants.VERSION_GNU_ZERO,
                signature, TarConstants.VERSION_OFFSET, TarConstants.VERSIONLEN)
        )
        ) {
            return true;
        }

        return ArchiveUtils.matchAsciiBuffer(TarConstants.MAGIC_ANT,
            signature, TarConstants.MAGIC_OFFSET, TarConstants.MAGICLEN)
        &&
        ArchiveUtils.matchAsciiBuffer(TarConstants.VERSION_ANT,
            signature, TarConstants.VERSION_OFFSET, TarConstants.VERSIONLEN);
    }

    private buildSparseInputStreams(): void {
        this.currentSparseInputStreamIndex = -1;
        this.sparseInputStreams = new Array<InputStream>();

        let sparseHeaders: Array<TarArchiveStructSparse> = this.currEntry.getOrderedSparseHeaders();

        let zeroInputStream: InputStream = new TarArchiveSparseZeroInputStream();
        let offset: Long = Long.fromNumber(0);
        let sparseHeader: TarArchiveStructSparse;
        for (sparseHeader of sparseHeaders) {
            let zeroBlockSize: Long = sparseHeader.getOffset().sub(offset);
            if (zeroBlockSize.lessThan(0)) {
                throw new Exception("Corrupted struct sparse detected");
            }

            if (zeroBlockSize.gt(0)) {
                this.sparseInputStreams.push(new BoundedInputStream(zeroInputStream, sparseHeader.getOffset().sub(offset)));
            }

            if (sparseHeader.getNumbytes().greaterThan(0)) {
                this.sparseInputStreams.push(new BoundedInputStream(this.inputStream, sparseHeader.getNumbytes()));
            }

            offset = sparseHeader.getOffset().add(sparseHeader.getNumbytes());
        }

        if (this.sparseInputStreams.length != 0) {
            this.currentSparseInputStreamIndex = 0;
        }
    }
}