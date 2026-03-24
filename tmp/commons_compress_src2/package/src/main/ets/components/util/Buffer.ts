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
import Long from "./long/index";
import IllegalArgumentException from './IllegalArgumentException';
import IndexOutOfBoundsException from './IndexOutOfBoundsException';
import Exception from './Exception';

export default class Buffer {
    static SPLITERATOR_CHARACTERISTICS: number = 0x00000040 | 0x00004000 | 0x00000010;
    private mark: number = -1;
    private position: number = 0;
    private limit: number = 0;
    private capacity: number = 0;
    address: Long;

    constructor(mark: number, pos: number, lim: number, cap: number) {
        if (cap < 0)
        throw new IllegalArgumentException("Negative capacity: " + cap);
        this.capacity = cap;
        this.limits(lim);
        this.positions(pos);
        if (mark >= 0) {
            if (mark > pos)
            throw new IllegalArgumentException("mark > position: ("
            + mark + " > " + pos + ")");
            this.mark = mark;
        }
    }

    public capacities(): number {
        return this.capacity;
    }

    public positionValue(): number {
        return this.position;
    }

    public positions(newPosition: number): Buffer {
        if ((newPosition > this.limit) || (newPosition < 0))
        throw new IllegalArgumentException();
        this.position = newPosition;
        if (this.mark > this.position) this.mark = -1;
        return this;
    }

    public limitValue(): number {
        return this.limit;
    }

    public limits(newLimit: number): Buffer {
        if ((newLimit > this.capacity) || (newLimit < 0))
        throw new IllegalArgumentException();
        this.limit = newLimit;
        if (this.position > newLimit) this.position = newLimit;
        if (this.mark > newLimit) this.mark = -1;
        return this;
    }

    public marks(): Buffer {
        this.mark = this.position;
        return this;
    }

    public reset(): Buffer {
        let m: number = this.mark;
        if (m < 0)
        throw new Exception();
        this.position = m;
        return this;
    }

    public clear(): Buffer {
        this.position = 0;
        this.limit = this.capacity;
        this.mark = -1;
        return this;
    }

    public flip(): Buffer {
        this.limit = this.position;
        this.position = 0;
        this.mark = -1;
        return this;
    }

    public rewind(): Buffer {
        this.position = 0;
        this.mark = -1;
        return this;
    }

    public remaining(): number {
        return this.limit - this.position;
    }

    public hasRemaining(): boolean {
        return this.position < this.limit;
    }

    nextGetIndex(): number {
        let p: number = this.position;
        if (p >= this.limit)
        throw new Exception();
        this.position = p + 1;
        return p;
    }

    nextPutIndex(): number {
        let p: number = this.position;
        if (p >= this.limit)
        throw new Exception();
        this.position = p + 1;
        return p;
    }

    nextPutIndexes(nb: number): number {
        let p: number = this.position;
        if (this.limit - p < nb)
        throw new Exception();
        this.position = p + nb;
        return p;
    }

    checkIndex(i: number, nb: number): number {
        if ((i < 0) || (nb > this.limit - i))
        throw new IndexOutOfBoundsException();
        return i;
    }

    markValue(): number {
        return this.mark;
    }

    truncate(): void {
        this.mark = -1;
        this.position = 0;
        this.limit = 0;
        this.capacity = 0;
    }

    discardMark(): void {
        this.mark = -1;
    }

    static checkBounds(off: number, len: number, size: number): void {
        if ((off | len | (off + len) | (size - (off + len))) < 0)
        throw new IndexOutOfBoundsException();
    }
}