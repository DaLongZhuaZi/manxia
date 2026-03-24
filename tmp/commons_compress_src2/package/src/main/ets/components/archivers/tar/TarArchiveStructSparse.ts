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
import IllegalArgumentException from '../../util/IllegalArgumentException';
import Long from "../../util/long/index";

export default class TarArchiveStructSparse {
    private offset: Long;
    private numbytes: Long;

    constructor(offset: Long, numbytes: Long) {
        if (offset.lessThan(0)) {
            throw new IllegalArgumentException("offset must not be negative");
        }
        if (numbytes.lessThan(0)) {
            throw new IllegalArgumentException("numbytes must not be negative");
        }
        this.offset = offset;
        this.numbytes = numbytes;
    }

    public equals(o: any): boolean {
        if (this === o) {
            return true;
        }
        if (o == null || !(o instanceof TarArchiveStructSparse)) {
            return false;
        }
        let that: TarArchiveStructSparse = o as TarArchiveStructSparse;
        return this.offset.equals(that.offset) &&
        this.numbytes.equals(that.numbytes);
    }

    public toString(): string {
        return "TarArchiveStructSparse{" +
        "offset=" + this.offset.toString() +
        ", numbytes=" + this.numbytes.toString() +
        '}';
    }

    public getOffset(): Long {
        return this.offset;
    }

    public getNumbytes(): Long {
        return this.numbytes;
    }
}