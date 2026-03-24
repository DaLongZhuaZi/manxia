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
import type ArchiveEntry from '../ArchiveEntry';
import IllegalArgumentException from '../../util/IllegalArgumentException';
import Long from "../../util/long/index";
import { LogUtil } from '../../LogUtil';

export default class ArArchiveEntry implements ArchiveEntry {
    SIZE_UNKNOWN: number = -1;
    public static HEADER: string = "!<arch>\n";
    public static TRAILER: string = `\`${String.fromCharCode(0o12)}`;
    private name: string;
    private userId: number;
    private groupId: number;
    private mode: number;
    public static DEFAULT_MODE: number = 33188;
    private lastModified: Long = Long.fromNumber(0);
    private length: Long;

    constructor(name: string, length: Long, userId: number, groupId: number,
                mode: number, lastModified: Long) {
        this.name = name;
        if (length.lessThan(0)) {
            LogUtil.error('length must not be negative.');
            throw new IllegalArgumentException("length must not be negative");
        }
        this.length = length;
        this.userId = userId;
        this.groupId = groupId;
        this.mode = mode;
        this.lastModified = lastModified;
    }

    public getSize(): Long {
        return this.getLength();
    }

    public getName(): string {
        return this.name;
    }

    public getUserId(): number {
        return this.userId;
    }

    public getGroupId(): number {
        return this.groupId;
    }

    public getMode(): number {
        return this.mode;
    }

    public getLastModified(): Long {
        return this.lastModified;
    }

    public getLastModifiedDate(): Date {
        return new Date(1000 * this.getLastModified().toNumber());
    }

    public getLength(): Long {
        return this.length;
    }

    public isDirectory(): boolean {
        return false;
    }

    public equals(o: any): boolean {
        if (this === o) {
            return true;
        }
        if (o == null || !(o instanceof ArArchiveEntry)) {
            return false;
        }
        let other: ArArchiveEntry = o as ArArchiveEntry;
        if (this.name == null) {
            return other.name == null;
        }
        return this.name == other.name;
    }
}