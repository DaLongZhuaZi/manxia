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
import TarArchiveStructSparse from './TarArchiveStructSparse';
import type ArchiveEntry from '../ArchiveEntry';
import type EntryStreamOffsets from '../EntryStreamOffsets';
import TarConstants from './TarConstants';
import TarUtils from './TarUtils';
import Long from "../../util/long/index";
import File from '../../util/File';
import IOUtils from '../../util/IOUtils';
import ArchiveUtils from '../../util/ArchiveUtils';
import Exception from '../../util/Exception';
import { LinkOption } from '../../util/LinkOption';
import type ZipEncoding from '../zip/ZipEncoding';
import IllegalArgumentException from '../../util/IllegalArgumentException';

export default class TarArchiveEntry implements ArchiveEntry, TarConstants, EntryStreamOffsets {
    SIZE_UNKNOWN: number = -1;
    OFFSET_UNKNOWN: number = -1;
    private static EMPTY_TAR_ARCHIVE_ENTRY_ARRAY: Array<TarArchiveEntry> = new Array<TarArchiveEntry>(0);
    public static UNKNOWN: Long = Long.fromNumber(-1);
    private name: string = "";
    private preserveAbsolutePath: boolean;
    private mode: number;
    private userId: Long = Long.fromNumber(0);
    private groupId: Long = Long.fromNumber(0);
    private size: Long = Long.fromNumber(0);
    private modTime: Long;
    private checkSumOK: boolean;
    private linkFlag: number;
    private linkName: string = "";
    private magic: string = TarConstants.MAGIC_POSIX;
    private version: string = TarConstants.VERSION_POSIX;
    private userName: string;
    private groupName: string = "";
    private devMajor: number;
    private devMinor: number;
    private sparseHeaders: Array<TarArchiveStructSparse>;
    private isExtended: boolean;
    private realSize: Long;
    private paxGNUSparse: boolean;
    private paxGNU1XSparse: boolean;
    private starSparse: boolean;
    private file: File;
    private linkOptions: Array<LinkOption>;
    private extraPaxHeaders: Map<string, string> = new Map<string, string>();
    public static MAX_NAMELEN: number = 31;
    public static DEFAULT_DIR_MODE: number = 0o40755;
    public static DEFAULT_FILE_MODE: number = 0o100644;
    public static MILLIS_PER_SECOND: number = 1000;
    private dataOffset: Long = Long.fromNumber(-1);

    constructor() {
    }

    public tarArchiveEntryFile(file: File, fileName: string): void {
        let normalizedName: string = TarArchiveEntry.normalizeFileName(fileName, false);
        this.file = file;
        this.linkOptions = IOUtils.EMPTY_LINK_OPTIONS;
        try {
            this.readFileMode(this.file, normalizedName);
        } catch (e) {
            if (!file.isDirectory()) {
                this.size = Long.fromNumber(file.length());
            }
        }

        this.userName = "";
        try {
            this.readOsSpecificProperties(this.file);
        } catch (e) {
            this.modTime = file.lastModified().divide(TarArchiveEntry.MILLIS_PER_SECOND);
        }
        this.preserveAbsolutePath = false;
    }

    private tarArchiveEntryPath(preserveAbsolutePath: boolean): void {
        this.userName = "";
        this.file = null;
        this.linkOptions = IOUtils.EMPTY_LINK_OPTIONS;
        this.preserveAbsolutePath = preserveAbsolutePath;
    }

    public tarArchiveEntryBuf(headerBuf: Int8Array, encoding: ZipEncoding, lenient: boolean): void {
        this.tarArchiveEntryPath(false);
        this.parseTarEncoding(headerBuf, encoding, false, lenient);
    }

    public tarArchiveEntryLinkFlag(name: string, linkFlag: number): void {
        this.tarArchiveEntryPreserveAbsolutePath(name, linkFlag, false);
    }

    public tarArchiveEntryPreserveAbsolutePath(name: string, linkFlag: number, preserveAbsolutePath: boolean): void {
        this.tarArchiveEntryPreserveAbsolutePath2(name, preserveAbsolutePath);
        this.linkFlag = linkFlag;
        if (linkFlag == TarConstants.LF_GNUTYPE_LONGNAME) {
            this.magic = TarConstants.MAGIC_GNU;
            this.version = TarConstants.VERSION_GNU_SPACE;
        }
    }

    public tarArchiveEntryPreserveAbsolutePath2(name: string, preserveAbsolutePath: boolean): void {
        this.tarArchiveEntryPath(preserveAbsolutePath);

        this.name = TarArchiveEntry.normalizeFileName(name, preserveAbsolutePath);
        let isDir: boolean = name.endsWith("/");

        this.name = name;
        this.mode = isDir ? TarArchiveEntry.DEFAULT_DIR_MODE : TarArchiveEntry.DEFAULT_FILE_MODE;
        this.linkFlag = isDir ? TarConstants.LF_DIR : TarConstants.LF_NORMAL;
        this.modTime = Long.fromNumber(Date.now() / TarArchiveEntry.MILLIS_PER_SECOND);
        this.userName = "";
    }

    public tarArchiveEntryLinkOptions(file: File, fileName: string, ...linkOptions: LinkOption[]): void {
        let normalizedName: string = TarArchiveEntry.normalizeFileName(fileName, false);
        this.file = file;
        this.linkOptions = linkOptions == null ? IOUtils.EMPTY_LINK_OPTIONS : linkOptions;

        this.readFileMode(file, normalizedName, ...linkOptions);

        this.userName = "";
        this.readOsSpecificProperties(file);
        this.preserveAbsolutePath = false;
    }

    private readOsSpecificProperties(file: File, ...options: LinkOption[]): void {
        this.setModTime(file.lastModified());
        this.userName = "";
        this.groupName = "";
        this.userId = Long.fromNumber(file.getUid());
        this.groupId = Long.fromNumber(file.getGid());
    }

    private readFileMode(file: File, normalizedName: string, ...linkOptions: LinkOption[]): void {
        if (file.isDirectory()) {
            this.mode = TarArchiveEntry.DEFAULT_DIR_MODE;
            this.linkFlag = TarConstants.LF_DIR;

            let nameLength: number = normalizedName.length;
            if (nameLength == 0 || normalizedName.charAt(nameLength - 1) != '/') {
                this.name = normalizedName + "/";
            } else {
                this.name = normalizedName;
            }
        } else {
            this.mode = TarArchiveEntry.DEFAULT_FILE_MODE;
            this.linkFlag = TarConstants.LF_NORMAL;
            this.name = normalizedName;
            this.size = Long.fromNumber(file.length());
        }
    }

    public equals(it: TarArchiveEntry): boolean {
        return it != null && this.getName() == it.getName();
    }

    public equalsObject(it: any): boolean {
        if (it == null || !(it instanceof TarArchiveEntry)) {
            return false;
        }
        return this.equals(it as TarArchiveEntry);
    }

    public isDescendent(desc: TarArchiveEntry): boolean {
        return desc.getName().startsWith(this.getName());
    }

    public getName(): string {
        return this.name;
    }

    public setName(name: string): void {
        this.name = TarArchiveEntry.normalizeFileName(name, this.preserveAbsolutePath);
    }

    public setMode(mode: number): void {
        this.mode = mode;
    }

    public getLinkName(): string {
        return this.linkName;
    }

    public setLinkName(link: string): void {
        this.linkName = link;
    }

    public setUserId(userId: number): void {
        this.setUserIdLong(Long.fromNumber(userId));
    }

    public getLongUserId(): Long {
        return this.userId;
    }

    public setUserIdLong(userId: Long): void {
        this.userId = userId;
    }

    public setGroupId(groupId: number): void {
        this.setGroupIdLong(Long.fromNumber(groupId));
    }

    public getLongGroupId(): Long {
        return this.groupId;
    }

    public setGroupIdLong(groupId: Long): void {
        this.groupId = groupId;
    }

    public getUserName(): string {
        return this.userName;
    }

    public setUserName(userName: string): void {
        this.userName = userName;
    }

    public getGroupName(): string {
        return this.groupName;
    }

    public setGroupName(groupName: string): void {
        this.groupName = groupName;
    }

    public setIds(userId: number, groupId: number): void {
        this.setUserId(userId);
        this.setGroupId(groupId);
    }

    public setNames(userName: string, groupName: string): void {
        this.setUserName(userName);
        this.setGroupName(groupName);
    }

    public setModTime(time: Long): void {
        if (time.notEquals(0)) {
            this.modTime = time.divide(TarArchiveEntry.MILLIS_PER_SECOND);
        }
    }

    public setModTimeDate(time: Date): void {
        this.modTime = Long.fromNumber(time.getTime() / TarArchiveEntry.MILLIS_PER_SECOND);
    }

    public getModTime(): Date {
        return new Date(this.modTime.multiply(TarArchiveEntry.MILLIS_PER_SECOND).toString());
    }

    public getLastModifiedDate(): Date {
        return this.getModTime();
    }

    public isCheckSumOK(): boolean {
        return this.checkSumOK;
    }

    public getFile(): File {
        if (this.file == null) {
            return null;
        }
        return this.file;
    }

    public getPath(): string {
        return this.file.getPath();
    }

    public getMode(): number {
        return this.mode;
    }

    public getSize(): Long {
        return this.size;
    }

    public setSparseHeaders(sparseHeaders: Array<TarArchiveStructSparse>): void {
        this.sparseHeaders = sparseHeaders;
    }

    public getSparseHeaders(): Array<TarArchiveStructSparse> {
        return this.sparseHeaders;
    }

    public isPaxGNU1XSparse(): boolean {
        return this.paxGNU1XSparse;
    }

    public setSize(size: Long): void {
        if (size.lessThan(0)) {
            throw new IllegalArgumentException("Size is out of range: " + size);
        }
        this.size = size;
    }

    public getDevMajor(): number {
        return this.devMajor;
    }

    public setDevMajor(devNo: number): void {
        if (devNo < 0) {
            throw new IllegalArgumentException("Major device number is out of "
            + "range: " + devNo);
        }
        this.devMajor = devNo;
    }

    public getDevMinor(): number {
        return this.devMinor;
    }

    public setDevMinor(devNo: number): void {
        if (devNo < 0) {
            throw new IllegalArgumentException("Minor device number is out of "
            + "range: " + devNo);
        }
        this.devMinor = devNo;
    }

    public isExtendedFollows(): boolean {
        return this.isExtended;
    }

    public getRealSize(): Long {
        if (!this.isSparse()) {
            return this.getSize();
        }
        return this.realSize;
    }

    public isGNUSparse(): boolean {
        return this.isOldGNUSparse() || this.isPaxGNUSparse();
    }

    public isOldGNUSparse(): boolean {
        return this.linkFlag == TarConstants.LF_GNUTYPE_SPARSE;
    }

    public isPaxGNUSparse(): boolean {
        return this.paxGNUSparse;
    }

    public isStarSparse(): boolean {
        return this.starSparse;
    }

    public isGNULongLinkEntry(): boolean {
        return this.linkFlag == TarConstants.LF_GNUTYPE_LONGLINK;
    }

    public isGNULongNameEntry(): boolean {
        return this.linkFlag == TarConstants.LF_GNUTYPE_LONGNAME;
    }

    public isPaxHeader(): boolean {
        return this.linkFlag == TarConstants.LF_PAX_EXTENDED_HEADER_LC
        || this.linkFlag == TarConstants.LF_PAX_EXTENDED_HEADER_UC;
    }

    public isGlobalPaxHeader(): boolean {
        return this.linkFlag == TarConstants.LF_PAX_GLOBAL_EXTENDED_HEADER;
    }

    public isDirectory(): boolean {
        if (this.file != null) {
            return this.file.isDirectory();
        }

        if (this.linkFlag == TarConstants.LF_DIR) {
            return true;
        }

        return!this.isPaxHeader() && !this.isGlobalPaxHeader() && this.getName().endsWith("/");
    }

    public isFile(): boolean {
        if (this.file != null) {
            return this.file.isFile();
        }
        if (this.linkFlag == TarConstants.LF_OLDNORM || this.linkFlag == TarConstants.LF_NORMAL) {
            return true;
        }
        return!this.getName().endsWith("/");
    }

    public isSymbolicLink(): boolean {
        return this.linkFlag == TarConstants.LF_SYMLINK;
    }

    public isLink(): boolean {
        return this.linkFlag == TarConstants.LF_LINK;
    }

    public isCharacterDevice(): boolean {
        return this.linkFlag == TarConstants.LF_CHR;
    }

    public isBlockDevice(): boolean {
        return this.linkFlag == TarConstants.LF_BLK;
    }

    public isFIFO(): boolean {
        return this.linkFlag == TarConstants.LF_FIFO;
    }

    public isSparse(): boolean {
        return this.isGNUSparse() || this.isStarSparse();
    }

    public getDataOffset(): Long {
        return this.dataOffset;
    }

    public setDataOffset(dataOffset: Long): void {
        if (dataOffset.lessThan(0)) {
            throw new IllegalArgumentException("The offset can not be smaller than 0");
        }
        this.dataOffset = dataOffset;
    }

    public isStreamContiguous(): boolean {
        return true;
    }

    public getExtraPaxHeaders(): Map<string, string> {
        return this.extraPaxHeaders;
    }

    public clearExtraPaxHeaders(): void {
        this.extraPaxHeaders.clear();
    }

    public addPaxHeader(name: string, value: string): void {
        try {
            this.processPaxHeader(name, value);
        } catch (ex) {
            throw new IllegalArgumentException("Invalid input");
        }
    }

    public getExtraPaxHeader(name: string): string {
        return this.extraPaxHeaders.get(name);
    }

    updateEntryFromPaxHeaders(headers: Map<string, string>): void {
        headers.forEach((value, key) => {
            this.processPaxHeader3(key, value, headers);
        });
    }

    private processPaxHeader(key: string, val: string): void {
        this.processPaxHeader3(key, val, this.extraPaxHeaders);
    }

    private processPaxHeader3(key: string, val: string, headers: Map<string, string>): void {
        switch (key) {
            case "path":
                this.setName(val);
                break;
            case "linkpath":
                this.setLinkName(val);
                break;
            case "gid":
                this.setGroupIdLong(Long.fromString(val));
                break;
            case "gname":
                this.setGroupName(val);
                break;
            case "uid":
                this.setUserIdLong(Long.fromString(val));
                break;
            case "uname":
                this.setUserName(val);
                break;
            case "size":
                let size: Long = Long.fromString(val);
                if (size.lessThan(0)) {
                    throw new Exception("Corrupted TAR archive. Entry size is negative");
                }
                this.setSize(size);
                break;
            case "mtime":
                this.setModTime(Long.fromNumber(parseInt(val) * 1000));
                break;
            case "SCHILY.devminor":
                let devMinor: number = parseInt(val);
                if (devMinor < 0) {
                    throw new Exception("Corrupted TAR archive. Dev-Minor is negative");
                }
                this.setDevMinor(devMinor);
                break;
            case "SCHILY.devmajor":
                let devMajor: number = parseInt(val);
                if (devMajor < 0) {
                    throw new Exception("Corrupted TAR archive. Dev-Major is negative");
                }
                this.setDevMajor(devMajor);
                break;
            case "GNU.sparse.size":
                this.fillGNUSparse0xData(headers);
                break;
            case "GNU.sparse.realsize":
                this.fillGNUSparse1xData(headers);
                break;
            case "SCHILY.filetype":
                if ("sparse" === val) {
                    this.fillStarSparseData(headers);
                }
                break;
            default:
                this.extraPaxHeaders.set(key, val);
        }
    }

    public writeEntryHeader(outbuf: Int8Array): void {
        try {
            this.writeEntryHeaderEncoding(outbuf, TarUtils.DEFAULT_ENCODING, false);
        } catch (ex) {
            try {
                this.writeEntryHeaderEncoding(outbuf, TarUtils.FALLBACK_ENCODING, false);
            } catch (ex2) {
                throw new Exception(ex2);
            }
        }
    }

    public writeEntryHeaderEncoding(outbuf: Int8Array, encoding: ZipEncoding, starMode: boolean): void {
        let offset: number = 0;
        offset = TarUtils.formatNameBytesEncoding(this.name, outbuf, offset, TarConstants.NAMELEN, encoding);
        offset = this.writeEntryHeaderField(Long.fromNumber(this.mode), outbuf, offset, TarConstants.MODELEN, starMode);
        offset = this.writeEntryHeaderField(this.userId, outbuf, offset, TarConstants.UIDLEN, starMode);
        offset = this.writeEntryHeaderField(this.groupId, outbuf, offset, TarConstants.GIDLEN, starMode);
        offset = this.writeEntryHeaderField(this.size, outbuf, offset, TarConstants.SIZELEN, starMode);
        offset = this.writeEntryHeaderField(this.modTime, outbuf, offset, TarConstants.MODTIMELEN, starMode);
        let csOffset: number = offset;
        for (let c: number = 0; c < TarConstants.CHKSUMLEN; ++c) {
            outbuf[offset++] = ' '.charCodeAt(0);
        }
        outbuf[offset++] = this.linkFlag;
        offset = TarUtils.formatNameBytesEncoding(this.linkName, outbuf, offset, TarConstants.NAMELEN, encoding);
        offset = TarUtils.formatNameBytes(this.magic, outbuf, offset, TarConstants.MAGICLEN);
        offset = TarUtils.formatNameBytes(this.version, outbuf, offset, TarConstants.VERSIONLEN);
        offset = TarUtils.formatNameBytesEncoding(this.userName, outbuf, offset, TarConstants.UNAMELEN, encoding);
        offset = TarUtils.formatNameBytesEncoding(this.groupName, outbuf, offset, TarConstants.GNAMELEN, encoding);
        offset = this.writeEntryHeaderField(Long.fromNumber(this.devMajor), outbuf, offset, TarConstants.DEVLEN, starMode);
        offset = this.writeEntryHeaderField(Long.fromNumber(this.devMinor), outbuf, offset, TarConstants.DEVLEN, starMode);
        while (offset < outbuf.length) {
            outbuf[offset++] = 0;
        }
        let chk: Long = TarUtils.computeCheckSum(outbuf);
        TarUtils.formatCheckSumOctalBytes(chk, outbuf, csOffset, TarConstants.CHKSUMLEN);
    }

    private writeEntryHeaderField(value: Long, outbuf: Int8Array, offset: number, length: number, starMode: boolean): number {
        if (!starMode && (value.lessThan(0) ||
        value.greaterThanOrEqual(Long.fromNumber(1).shiftLeft(3 * (length - 1))))) {
            return TarUtils.formatLongOctalBytes(Long.fromNumber(0), outbuf, offset, length);
        }
        return TarUtils.formatLongOctalOrBinaryBytes(value, outbuf, offset, length);
    }

    public parseTarHeader(header: Int8Array): void {
        try {
            this.parseTarEncoding(header, TarUtils.DEFAULT_ENCODING);
        } catch (ex) {
            try {
                this.parseTarEncoding(header, TarUtils.DEFAULT_ENCODING, true, false);
            } catch (ex2) {
                throw new Exception('not really possible');
            }
        }
    }

    private parseTarEncoding(header: Int8Array, encoding: ZipEncoding, oldStyle?: boolean, lenient?: boolean): void {
        try {
            oldStyle = oldStyle == undefined ? false : oldStyle;
            lenient = lenient == undefined ? false : lenient;
            this.parseTarHeaderUnwrapped(header, encoding, oldStyle, lenient);
        } catch (ex) {
            throw new Exception("Corrupted TAR archive." + ex);
        }
    }

    private parseTarHeaderUnwrapped(header: Int8Array, encoding: ZipEncoding, oldStyle: boolean, lenient: boolean): void {
        let offset: number = 0;

        this.name = oldStyle ? TarUtils.parseName(header, offset, TarConstants.NAMELEN)
                             : TarUtils.parseNameEncoding(header, offset, TarConstants.NAMELEN, encoding);
        offset += TarConstants.NAMELEN;
        this.mode = this.parseOctalOrBinary(header, offset, TarConstants.MODELEN, lenient).toNumber();
        offset += TarConstants.MODELEN;
        this.userId = this.parseOctalOrBinary(header, offset, TarConstants.UIDLEN, lenient);
        offset += TarConstants.UIDLEN;
        this.groupId = this.parseOctalOrBinary(header, offset, TarConstants.GIDLEN, lenient);
        offset += TarConstants.GIDLEN;
        this.size = TarUtils.parseOctalOrBinary(header, offset, TarConstants.SIZELEN);
        if (this.size.lessThan(0)) {
            throw new Exception("broken archive, entry with negative size");
        }
        offset += TarConstants.SIZELEN;
        this.modTime = this.parseOctalOrBinary(header, offset, TarConstants.MODTIMELEN, lenient);
        offset += TarConstants.MODTIMELEN;
        this.checkSumOK = TarUtils.verifyCheckSum(header);
        offset += TarConstants.CHKSUMLEN;
        this.linkFlag = header[offset++];
        this.linkName = oldStyle ? TarUtils.parseName(header, offset, TarConstants.NAMELEN)
                                 : TarUtils.parseNameEncoding(header, offset, TarConstants.NAMELEN, encoding);
        offset += TarConstants.NAMELEN;
        this.magic = TarUtils.parseName(header, offset, TarConstants.MAGICLEN);
        offset += TarConstants.MAGICLEN;
        this.version = TarUtils.parseName(header, offset, TarConstants.VERSIONLEN);
        offset += TarConstants.VERSIONLEN;
        this.userName = oldStyle ? TarUtils.parseName(header, offset, TarConstants.UNAMELEN)
                                 : TarUtils.parseNameEncoding(header, offset, TarConstants.UNAMELEN, encoding);
        offset += TarConstants.UNAMELEN;
        this.groupName = oldStyle ? TarUtils.parseName(header, offset, TarConstants.GNAMELEN)
                                  : TarUtils.parseNameEncoding(header, offset, TarConstants.GNAMELEN, encoding);
        offset += TarConstants.GNAMELEN;
        if (this.linkFlag == TarConstants.LF_CHR || this.linkFlag == TarConstants.LF_BLK) {
            this.devMajor = this.parseOctalOrBinary(header, offset, TarConstants.DEVLEN, lenient).toNumber();
            offset += TarConstants.DEVLEN;
            this.devMinor = this.parseOctalOrBinary(header, offset, TarConstants.DEVLEN, lenient).toNumber();
            offset += TarConstants.DEVLEN;
        } else {
            offset += 2 * TarConstants.DEVLEN;
        }

        let types: number = this.evaluateType(header);
        switch (types) {
            case TarConstants.FORMAT_OLDGNU: {
                offset += TarConstants.ATIMELEN_GNU;
                offset += TarConstants.CTIMELEN_GNU;
                offset += TarConstants.OFFSETLEN_GNU;
                offset += TarConstants.LONGNAMESLEN_GNU;
                offset += TarConstants.PAD2LEN_GNU;
                this.sparseHeaders = TarUtils.readSparseStructs(header, offset, TarConstants.SPARSE_HEADERS_IN_OLDGNU_HEADER);
                offset += TarConstants.SPARSELEN_GNU;
                this.isExtended = TarUtils.parseBoolean(header, offset);
                offset += TarConstants.ISEXTENDEDLEN_GNU;
                this.realSize = TarUtils.parseOctal(header, offset, TarConstants.REALSIZELEN_GNU);
                offset += TarConstants.REALSIZELEN_GNU;
                break;
            }
            case TarConstants.FORMAT_XSTAR: {
                let xstarPrefix: string = oldStyle
                    ? TarUtils.parseName(header, offset, TarConstants.PREFIXLEN_XSTAR)
                    : TarUtils.parseNameEncoding(header, offset, TarConstants.PREFIXLEN_XSTAR, encoding);
                if (xstarPrefix.length > 0) {
                    this.name = xstarPrefix + "/" + this.name;
                }
                break;
            }
            case TarConstants.FORMAT_POSIX:
            default: {
                let prefix: string = oldStyle
                    ? TarUtils.parseName(header, offset, TarConstants.PREFIXLEN)
                    : TarUtils.parseNameEncoding(header, offset, TarConstants.PREFIXLEN, encoding);
                if (this.isDirectory() && !this.name.endsWith("/")) {
                    this.name = this.name + "/";
                }
                if (prefix.length > 0) {
                    this.name = prefix + "/" + this.name;
                }
            }
        }
    }

    private parseOctalOrBinary(header: Int8Array, offset: number, length: number, lenient: boolean): Long {
        if (lenient) {
            try {
                return TarUtils.parseOctalOrBinary(header, offset, length);
            } catch (ex) { //NOSONAR
                return TarArchiveEntry.UNKNOWN;
            }
        }
        return TarUtils.parseOctalOrBinary(header, offset, length);
    }

    private evaluateType(header: Int8Array): number {
        if (ArchiveUtils.matchAsciiBuffer(TarConstants.MAGIC_GNU, header, TarConstants.MAGIC_OFFSET,
            TarConstants.MAGICLEN)) {
            return TarConstants.FORMAT_OLDGNU;
        }
        if (ArchiveUtils.matchAsciiBuffer(TarConstants.MAGIC_POSIX, header, TarConstants.MAGIC_OFFSET,
            TarConstants.MAGICLEN)) {
            if (ArchiveUtils.matchAsciiBuffer(TarConstants.MAGIC_XSTAR, header, TarConstants.XSTAR_MAGIC_OFFSET,
                TarConstants.XSTAR_MAGIC_LEN)) {
                return TarConstants.FORMAT_XSTAR;
            }
            return TarConstants.FORMAT_POSIX;
        }
        return 0;
    }

    fillGNUSparse0xData(headers: Map<string, string>): void {
        this.paxGNUSparse = true;
        this.realSize = Long.fromString(headers.get("GNU.sparse.size"));
        if (headers.has("GNU.sparse.name")) {
            this.name = headers.get("GNU.sparse.name");
        }
    }

    fillGNUSparse1xData(headers: Map<string, string>): void {
        this.paxGNUSparse = true;
        this.paxGNU1XSparse = true;
        if (headers.has("GNU.sparse.name")) {
            this.name = headers.get("GNU.sparse.name");
        }
        if (headers.has("GNU.sparse.realsize")) {
            try {
                this.realSize = Long.fromString(headers.get("GNU.sparse.realsize"));
            } catch (ex) {
                throw new Exception("Corrupted TAR archive. GNU.sparse.realsize header for "
                + this.name + " contains non-numeric value");
            }
        }
    }

    fillStarSparseData(headers: Map<string, string>): void {
        this.starSparse = true;
        if (headers.has("SCHILY.realsize")) {
            try {
                this.realSize = Long.fromString(headers.get("SCHILY.realsize"));
            } catch (ex) {
                throw new Exception("Corrupted TAR archive. SCHILY.realsize header for "
                + this.name + " contains non-numeric value");
            }
        }
    }

    private static normalizeFileName(fileName: string, preserveAbsolutePath: boolean): string {
        if (!preserveAbsolutePath) {
            let osname: string = 'linux';

            if (osname != null) {

                if (osname.startsWith("windows")) {
                    if (fileName.length > 2) {
                        let ch1: number = fileName.charCodeAt(0);
                        let ch2: number = fileName.charCodeAt(1);

                        if (ch2 == ':'.charCodeAt(0)
                        && (ch1 >= 'a'.charCodeAt(0) && ch1 <= 'z'.charCodeAt(0)
                        || ch1 >= 'A'.charCodeAt(0) && ch1 <= 'Z'.charCodeAt(0))) {
                            fileName = fileName.substring(2);
                        }
                    }
                } else if (osname.includes("netware")) {
                    let colon: number = fileName.indexOf(':');
                    if (colon != -1) {
                        fileName = fileName.substring(colon + 1);
                    }
                }
            }
        }

        fileName = fileName.replace(File.separator, '/');

        while (!preserveAbsolutePath && fileName.startsWith("/")) {
            fileName = fileName.substring(1);
        }
        return fileName;
    }

    public getOrderedSparseHeaders(): Array<TarArchiveStructSparse> {
        if (this.sparseHeaders == null || this.sparseHeaders.length == 0) {
            return new Array<TarArchiveStructSparse>(0);
        }
        let orderedAndFiltered: Array<TarArchiveStructSparse> = JSON.parse(JSON.stringify(this.sparseHeaders))
        orderedAndFiltered.filter(item => item.getOffset().greaterThan(0) || item.getNumbytes().greaterThan(0))
            .sort((itemFirst, itemSecond) => {
                return itemFirst.getOffset().sub(itemSecond.getOffset()).toNumber();
            });

        let numberOfHeaders: number = orderedAndFiltered.length;
        for (let i: number = 0; i < numberOfHeaders; i++) {
            let str: TarArchiveStructSparse = orderedAndFiltered[i];
            if (i + 1 < numberOfHeaders
            && str.getOffset().add(str.getNumbytes()).greaterThan(orderedAndFiltered[i + 1].getOffset())) {
                throw new Exception("Corrupted TAR archive. Sparse blocks for "
                + this.getName() + " overlap each other.");
            }
            if (str.getOffset().add(str.getNumbytes()).lessThan(0)) {
                throw new Exception("Unreadable TAR archive. Offset and numbytes for sparse block in "
                + this.getName() + " too large.");
            }
        }
        if (orderedAndFiltered.length != 0) {
            let last: TarArchiveStructSparse = orderedAndFiltered[numberOfHeaders - 1];
            if (last.getOffset().add(last.getNumbytes()).greaterThan(this.getRealSize())) {
                throw new Exception("Corrupted TAR archive. Sparse block extends beyond real size of the entry");
            }
        }
        return orderedAndFiltered;
    }
}
