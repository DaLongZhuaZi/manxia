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
import Long from "../../util/long/index";
import TarArchiveStructSparse from './TarArchiveStructSparse';
import InputStream from '../../util/InputStream';
import Exception from '../../util/Exception';
import IOUtils from '../../util/IOUtils';
import System from '../../util/System';
import TarConstants from './TarConstants';
import type ZipEncoding from '../zip/ZipEncoding';
import ZipEncodingHelper from '../zip/ZipEncodingHelper';
import ByteArrayOutputStream from '../../util/ByteArrayOutputStream';
import IllegalArgumentException from '../../util/IllegalArgumentException';
import buffer from "@ohos.buffer";

class ZipEncodingUtil implements ZipEncoding {
    public canEncode(name: string): boolean
    {
        return true;
    }

    public encode(name: string): Int8Array {
        let length: number = name.length;
        let buf: Int8Array = new Int8Array(length);

        for (let i = 0; i < length; ++i) {
            buf[i] = name.charCodeAt(i);
        }
        return buf;
    }

    public decode(buffer: Int8Array): string {
        let result: string = "";
        for (let b of buffer) {
            if (b == 0) {
                break;
            }
            result = result + String.fromCharCode(b & 0xFF);
        }
        return result;
    }
}

export default class TarUtils {
    private static BYTE_MASK: number = 255;
    public static DEFAULT_ENCODING: ZipEncoding = ZipEncodingHelper.getZipEncoding(null);
    static FALLBACK_ENCODING: ZipEncoding = new ZipEncodingUtil();

    public static parsePaxHeaders(inputStream: InputStream,
                                  sparseHeaders: Array<TarArchiveStructSparse>, globalPaxHeaders: Map<string, string>,
                                  headerSize: Long): Map<string, string> {
        let headers: Map<string, string> = new Map<string, string>(globalPaxHeaders);
        let offset: Long = null;
        let totalRead: number = 0;
        let ch: number;
        label110:
        while (true) { // get length
            let len: number = 0;
            for (let read = 0; (ch = inputStream.read()) != -1; len += ch-48){
                ++read;
                ++totalRead;
                if (ch == 10) { // blank line in header
                    break;
                }
                if (ch == 32) { // End of length string
                    let coll: ByteArrayOutputStream = new ByteArrayOutputStream();
                    while (true){
                        if ((ch = inputStream.read()) == -1){
                            continue label110;
                        }
                        ++read;
                        ++totalRead;
                        if (totalRead < 0 || (headerSize.greaterThanOrEqual(0) && headerSize.lessThanOrEqual(totalRead))) {
                            continue label110;
                        }
                        if (ch == 61) { // end of keyword
                            let keyword: string = coll.toString('UTF-8');
                            // Get rest of entry
                            let restLen: number = len - read;
                            if (restLen <= 1) { // only NL
                                headers.delete(keyword);
                            } else {
                                if (headerSize.greaterThanOrEqual(0) && restLen > headerSize.sub(totalRead).toNumber()) {
                                    throw new Exception("Paxheader value size " + restLen
                                        + " exceeds size of header record");
                                }
                                let rest: Int8Array = IOUtils.readRange(inputStream, restLen);
                                let got: number = rest.length;
                                if (got != restLen) {
                                    throw new Exception("Failed to read "
                                        + "Paxheader. Expected "
                                        + restLen
                                        + " bytes, read "
                                        + got);
                                }
                                totalRead += restLen;
                                if (rest[restLen - 1] != 10) {
                                    throw new Exception("Failed to read Paxheader."
                                        + "Value should end with a newline");
                                }
                                let value: string = buffer.from(new Uint8Array(rest.subarray(0, restLen - 1))).toString()
                                headers.set(keyword, value);
                                if (keyword == "GNU.sparse.offset") {
                                    if (offset != null) {
                                        sparseHeaders.push(new TarArchiveStructSparse(offset, Long.fromNumber(0)));
                                    }
                                    try {
                                        offset = Long.fromString(value);
                                    } catch (ex) {
                                        throw new Exception("Failed to read Paxheader."
                                            + "GNU.sparse.offset contains a non-numeric value");
                                    }
                                    if (offset.lessThan(0)) {
                                        throw new Exception("Failed to read Paxheader."
                                            + "GNU.sparse.offset contains negative value");
                                    }
                                }

                                if (keyword == "GNU.sparse.numbytes") {
                                    if (offset == null) {
                                        throw new Exception("Failed to read Paxheader." +
                                            "GNU.sparse.offset is expected before GNU.sparse.numbytes shows up.");
                                    }
                                    let numbytes: Long;
                                    try {
                                        numbytes = Long.fromString(value);
                                    } catch (ex) {
                                        throw new Exception("Failed to read Paxheader."
                                            + "GNU.sparse.numbytes contains a non-numeric value.");
                                    }
                                    if (numbytes.lessThan(0)) {
                                        throw new Exception("Failed to read Paxheader."
                                            + "GNU.sparse.numbytes contains negative value");
                                    }
                                    sparseHeaders.push(new TarArchiveStructSparse(offset, numbytes));
                                    offset = null;
                                }

                            }
                            continue label110;
                        }
                        coll.write(ch);
                    }
                    break; // Processed single header
                }
                if (ch < 48 || ch > 57) {
                    throw new Exception("Failed to read Paxheader. Encountered a non-number while reading length");
                }

                len *= 10;
            }
            if (ch == -1) { // EOF
                break;
            }
        }
        if (offset != null) {
            sparseHeaders.push(new TarArchiveStructSparse(offset, Long.fromNumber(0)));
        }
        return headers;
    }

    public static parsePAX1XSparseHeaders(inputStream: InputStream, recordSize: number): Array<TarArchiveStructSparse> {
        // for 1.X PAX Headers
        let sparseHeaders: Array<TarArchiveStructSparse> = new Array<TarArchiveStructSparse>();
        let bytesRead: Long = Long.fromNumber(0);

        let readResult: BigInt64Array = this.readLineOfNumberForPax1X(inputStream);
        let sparseHeadersCount: Long = Long.fromString(readResult[0].toLocaleString());
        if (sparseHeadersCount.lessThan(0)) {
            throw new Exception("Corrupted TAR archive. Negative value in sparse headers block");
        }
        bytesRead = bytesRead.add(readResult[1].toLocaleString());
        for (;; ) {
            if (!sparseHeadersCount.gt(0)) {
                sparseHeadersCount = sparseHeadersCount.sub(1);
                break;
            }
            sparseHeadersCount = sparseHeadersCount.sub(1);

            readResult = this.readLineOfNumberForPax1X(inputStream);
            let sparseOffset: Long = Long.fromString(readResult[0].toLocaleString());
            if (sparseOffset.lessThan(0)) {
                throw new Exception("Corrupted TAR archive."
                + " Sparse header block offset contains negative value");
            }
            bytesRead = bytesRead.add(readResult[1].toLocaleString());

            readResult = this.readLineOfNumberForPax1X(inputStream);
            let sparseNumbytes: Long = Long.fromString(readResult[0].toLocaleString());
            if (sparseNumbytes.lessThan(0)) {
                throw new Exception("Corrupted TAR archive."
                + " Sparse header block numbytes contains negative value");
            }
            bytesRead = bytesRead.add(readResult[1].toLocaleString());
            sparseHeaders.push(new TarArchiveStructSparse(sparseOffset, sparseNumbytes));
        }

        // skip the rest of this record data
        let bytesToSkip: Long = Long.fromNumber(recordSize - bytesRead.toNumber() % recordSize);
        IOUtils.skip(inputStream, bytesToSkip);
        return sparseHeaders;
    }

    private static readLineOfNumberForPax1X(inputStream: InputStream): BigInt64Array {
        let numberValue: number;
        let result: Long = Long.fromNumber(0);
        let bytesRead: Long = Long.fromNumber(0);

        while ((numberValue = inputStream.read()) != '\n'.charCodeAt(0)) {
            bytesRead = bytesRead.add(1);
            if (numberValue == -1) {
                throw new Exception("Unexpected EOF when reading parse information of 1.X PAX format");
            }
            if (numberValue < '0'.charCodeAt(0) || numberValue > '9'.charCodeAt(0)) {
                throw new Exception("Corrupted TAR archive. Non-numeric value in sparse headers block");
            }
            result = result.multiply(10).add(numberValue - '0'.charCodeAt(0));
        }
        bytesRead = bytesRead.add(1);
        let int64List: BigInt64Array = new BigInt64Array(2);
        int64List[0] = BigInt(result.toNumber()).valueOf();
        int64List[1] = BigInt(bytesRead.toNumber()).valueOf();
        return int64List;
    }

    public static parseFromPAX01SparseHeaders(sparseMap: string): Array<TarArchiveStructSparse> {
        let sparseHeaders: Array<TarArchiveStructSparse> = new Array<TarArchiveStructSparse>();
        let sparseHeaderStrings: string[] = sparseMap.split(",");
        if (sparseHeaderStrings.length % 2 == 1) {
            throw new Exception("Corrupted TAR archive. Bad format in GNU.sparse.map PAX Header");
        }

        for (let i = 0; i < sparseHeaderStrings.length; i += 2) {
            let sparseOffset: Long;
            try {
                sparseOffset = Long.fromString(sparseHeaderStrings[i]);
            } catch (ex) {
                throw new Exception("Corrupted TAR archive."
                + " Sparse struct offset contains a non-numeric value");
            }
            if (sparseOffset.lessThan(0)) {
                throw new Exception("Corrupted TAR archive."
                + " Sparse struct offset contains negative value");
            }
            let sparseNumbytes: Long;
            try {
                sparseNumbytes = Long.fromString(sparseHeaderStrings[i + 1]);
            } catch (ex) {
                throw new Exception("Corrupted TAR archive."
                + " Sparse struct numbytes contains a non-numeric value");
            }
            if (sparseNumbytes.lessThan(0)) {
                throw new Exception("Corrupted TAR archive."
                + " Sparse struct numbytes contains negative value");
            }
            sparseHeaders.push(new TarArchiveStructSparse(sparseOffset, sparseNumbytes));
        }
        return sparseHeaders;
    }

    public static formatNameBytes(name: string, buf: Int8Array, offset: number, length: number): number {
        try {
            return this.formatNameBytesEncoding(name, buf, offset, length, TarUtils.DEFAULT_ENCODING);
        } catch (ex) { // NOSONAR
            try {
                return this.formatNameBytesEncoding(name, buf, offset, length,
                    TarUtils.FALLBACK_ENCODING);
            } catch (ex2) {
                // impossible
                throw new Exception(ex2); //NOSONAR
            }
        }
    }

    public static formatNameBytesEncoding(name: string, buf: Int8Array, offset: number,
                                          length: number,
                                          encoding: ZipEncoding): number {
        let len: number = name.length;
        let b: Int8Array = encoding.encode(name);
        while (b.length > length && len > 0) {
            b = encoding.encode(name.substring(0, --len));
        }
        let limit: number = b.length;
        System.arraycopy(b, 0, buf, offset, limit);

        // Pad any remaining output bytes with NUL
        for (let i: number = limit; i < length; ++i) {
            buf[offset + i] = 0;
        }
        return offset + length;
    }

    static readSparseStructs(buffer: Int8Array, offset: number, entries: number): Array<TarArchiveStructSparse> {
        let sparseHeaders: Array<TarArchiveStructSparse> = new Array<TarArchiveStructSparse>();
        for (let i = 0; i < entries; i++) {
            try {
                let sparseHeader: TarArchiveStructSparse = this.parseSparse(buffer,
                    offset + i * (TarConstants.SPARSE_OFFSET_LEN + TarConstants.SPARSE_NUMBYTES_LEN));

                if (sparseHeader.getOffset().lessThan(0)) {
                    throw new Exception("Corrupted TAR archive, sparse entry with negative offset");
                }
                if (sparseHeader.getNumbytes().lessThan(0)) {
                    throw new Exception("Corrupted TAR archive, sparse entry with negative numbytes");
                }
                sparseHeaders.push(sparseHeader);
            } catch (ex) {
                // thrown internally by parseOctalOrBinary
                throw new Exception("Corrupted TAR archive, sparse entry is invalid" + ex);
            }
        }
        return sparseHeaders;
    }

    public static computeCheckSum(buf: Int8Array): Long {
        let sum: Long = Long.fromNumber(0);
        let element: number;
        for (element of buf) {
            sum = sum.add(TarUtils.BYTE_MASK & element);
        }
        return sum;
    }

    public static formatCheckSumOctalBytes(value: Long, buf: Int8Array, offset: number, length: number): number {
        let idx: number = length - 2; // for NUL and space
        this.formatUnsignedOctalString(value, buf, offset, idx);
        buf[offset + idx++] = 0; // Trailing null
        buf[offset + idx] = ' '.charCodeAt(0); // Trailing space
        return offset + length;
    }

    public static formatUnsignedOctalString(value: Long, buffer: Int8Array, offset: number, length: number): void {
        let remaining: number = length;
        remaining--;
        if (value.equals(0)) {
            buffer[offset + remaining--] = '0'.charCodeAt(0);
        } else {
            let val: Long = value;
            for (; remaining >= 0 && val.notEquals(0); --remaining) {
                // CheckStyle:MagicNumber OFF
                buffer[offset + remaining] = val.and(7).add('0'.charCodeAt(0)).toNumber();
                val = val.shiftRightUnsigned(3);
                // CheckStyle:MagicNumber ON
            }
            if (val.notEquals(0)) {
                throw new IllegalArgumentException
                (value.toNumber() + "=" + value.toString() + " will not fit in octal number buffer of length " + length);
            }
        }

        for (; remaining >= 0; --remaining) { // leading zeros
            buffer[offset + remaining] = '0'.charCodeAt(0);
        }
    }

    public static formatLongOctalBytes(value: Long, buf: Int8Array, offset: number, length: number): number {
        let idx: number = length - 1; // For space
        this.formatUnsignedOctalString(value, buf, offset, idx);
        buf[offset + idx] = ' '.charCodeAt(0); // Trailing space
        return offset + length;
    }

    public static parseName(buffer: Int8Array, offset: number, length: number): string {
        try {
            return this.parseNameEncoding(buffer, offset, length, TarUtils.DEFAULT_ENCODING);
        } catch (ex) { // NOSONAR
            try {
                return this.parseNameEncoding(buffer, offset, length, TarUtils.FALLBACK_ENCODING);
            } catch (ex2) {
                // impossible
                throw new Exception('impossible'); //NOSONAR
            }
        }
    }

    public static parseNameEncoding(buffer: Int8Array, offset: number, length: number, encoding: ZipEncoding): string {
        let len: number = 0;
        for (let i: number = offset; len < length && buffer[i] != 0; i++) {
            len++;
        }
        if (len > 0) {
            let b: Int8Array = new Int8Array(len);
            System.arraycopy(buffer, offset, b, 0, len);
            return encoding.decode(b);
        }
        return "";
    }

    public static parseOctalOrBinary(buffer: Int8Array, offset: number, length: number): Long {

        if ((buffer[offset] & 0x80) == 0) {
            return this.parseOctal(buffer, offset, length);
        }
        let negative: boolean = (buffer[offset] == 0xff);
        if (length < 9) {
            return this.parseBinaryLong(buffer, offset, length, negative);
        }
        return this.parseBinaryBigInteger(buffer, offset, length, negative);
    }

    private static parseBinaryLong(buffer: Int8Array, offset: number, length: number, negative: boolean): Long {
        if (length >= 9) {
            throw new IllegalArgumentException("At offset " + offset + ", "
            + length + " byte binary number"
            + " exceeds maximum signed long"
            + " value");
        }
        let val: Long = Long.fromNumber(0);
        for (let i: number = 1; i < length; i++) {
            val = val.shiftLeft(8).add(buffer[offset + i] & 0xff);
        }
        if (negative) {
            // 2's complement
            val = val.sub(1);
            val = val.xor(Long.fromNumber(Math.pow(2.0, (length - 1) * 8.0) - 1));
        }
        return negative ? Long.fromNumber(-val.toNumber()) : val;
    }

    public static parseOctal(buffer: Int8Array, offset: number, length: number): Long {
        let result: Long = Long.fromNumber(0);
        let end: number = offset + length;
        let start: number = offset;

        if (length < 2) {
            throw new IllegalArgumentException("Length " + length + " must be at least 2");
        }

        if (buffer[start] == 0) {
            return Long.fromNumber(0);
        }

        // Skip leading spaces
        while (start < end) {
            if (buffer[start] != ' '.charCodeAt(0)) {
                break;
            }
            start++;
        }

        let trailer: number = buffer[end - 1];
        while (start < end && (trailer == 0 || trailer == ' '.charCodeAt(0))) {
            end--;
            trailer = buffer[end - 1];
        }

        for (; start < end; start++) {
            let currentByte: number = buffer[start];
            // CheckStyle:MagicNumber OFF
            if (currentByte < '0'.charCodeAt(0) || currentByte > '7'.charCodeAt(0)) {
                throw new IllegalArgumentException('parseOctal illegalArgumentException');
            }
            result = result.shiftLeft(3).add(currentByte - '0'.charCodeAt(0)); // convert from ASCII
            // CheckStyle:MagicNumber ON
        }
        return result;
    }

    public static verifyCheckSum(header: Int8Array): boolean {
        let storedSum: Long = this.parseOctal(header, TarConstants.CHKSUM_OFFSET, TarConstants.CHKSUMLEN);
        let unsignedSum: Long = Long.fromNumber(0);
        let signedSum: Long = Long.fromNumber(0);

        for (let i = 0; i < header.length; i++) {
            let b: number = header[i];
            if (TarConstants.CHKSUM_OFFSET <= i && i < TarConstants.CHKSUM_OFFSET + TarConstants.CHKSUMLEN) {
                b = ' '.charCodeAt(0);
            }
            unsignedSum = unsignedSum.add(0xff & b);
            signedSum = signedSum.add(b);
        }
        return storedSum.equals(unsignedSum) || storedSum.equals(signedSum);
    }

    public static parseBoolean(buffer: Int8Array, offset: number): boolean {
        return buffer[offset] == 1;
    }

    public static formatLongOctalOrBinaryBytes(
        value: Long, buf: Int8Array, offset: number, length: number): number {

        let maxAsOctalChar: Long = length == TarConstants.UIDLEN ? TarConstants.MAXID : TarConstants.MAXSIZE;

        let negative: boolean = value.lessThan(0);
        if (!negative && value.lessThanOrEqual(maxAsOctalChar)) { // OK to store as octal chars
            return this.formatLongOctalBytes(value, buf, offset, length);
        }

        if (length < 9) {
            this.formatLongBinary(value, buf, offset, length, negative);
        } else {
            this.formatBigIntegerBinary(value, buf, offset, length, negative);
        }

        buf[offset] = (negative ? 0xff : 0x80);
        return offset + length;
    }

    private static formatLongBinary(value: Long, buf: Int8Array,
                                    offset: number, length: number,
                                    negative: boolean): void {
        let bits: number = (length - 1) * 8;
        let max: Long = Long.fromNumber(1).shiftLeft(bits);
        let val: Long = Long.fromNumber(Math.abs(value.toNumber())); // Long.MIN_VALUE stays Long.MIN_VALUE
        if (val.lessThan(0) || val.greaterThanOrEqual(max)) {
            throw new IllegalArgumentException("Value " + value.toNumber() +
            " is too large for " + length + " byte field.");
        }
        if (negative) {
            val = val.xor(max.sub(1));
            val = val.add(1);
            val = val.or(Long.fromNumber(0xff).shiftLeft(bits));
        }
        for (let i = offset + length - 1; i >= offset; i--) {
            buf[i] = val.toInt();
            val = val.shiftRight(8);
        }
    }

    private static formatBigIntegerBinary(value: Long, buf: Int8Array,
                                          offset: number,
                                          length: number,
                                          negative: boolean): void {
        let b: number[] = value.toBytes();
        let len: number = b.length;
        if (len > length - 1) {
            throw new IllegalArgumentException("Value " + value.toNumber() +
            " is too large for " + length + " byte field.");
        }
        let off: number = offset + length - len;
        System.arraycopy(b, 0, buf, off, len);
        let fill: number = negative ? 0xff : 0;
        for (let i = offset + 1; i < off; i++) {
            buf[i] = fill;
        }
    }

    public static parseSparse(buffer: Int8Array, offset: number): TarArchiveStructSparse {
        let sparseOffset: Long = this.parseOctalOrBinary(buffer, offset, TarConstants.SPARSE_OFFSET_LEN);
        let sparseNumbytes: Long = this.parseOctalOrBinary(buffer, offset + TarConstants.SPARSE_OFFSET_LEN,
            TarConstants.SPARSE_NUMBYTES_LEN);

        return new TarArchiveStructSparse(sparseOffset, sparseNumbytes);
    }

    private static parseBinaryBigInteger(buffer: Int8Array, offset: number, length: number, negative: boolean): Long {
        let remainder: Int8Array = new Int8Array(length - 1);
        System.arraycopy(buffer, offset + 1, remainder, 0, length - 1);
        let val: Long = Long.fromBytes(Array.from(remainder));

        if (negative) {
            val = val.add(-1).not();
        }
        if (val.getNumBitsAbs() > 63) {
            throw new IllegalArgumentException("At offset " + offset + ", "
            + length + " byte binary number"
            + " exceeds maximum signed long"
            + " value");
        }
        return negative ? Long.fromNumber(0).sub(val) : val;
    }
}