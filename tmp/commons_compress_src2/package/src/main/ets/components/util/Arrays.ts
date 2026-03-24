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
import System from './System';
import IllegalArgumentException from './IllegalArgumentException';
import ArrayIndexOutOfBoundsException from './ArrayIndexOutOfBoundsException';

export default class Arrays {
    public static fill(a: Int32Array | Int16Array | Uint8Array | Int8Array | any[], val: number): void {
        for (let i = 0, len = a.length; i < len; i++)
        a[i] = val;
    }

    public static fillBoolean(a: Array<boolean>, val: boolean): void {
        for (let i = 0, len = a.length; i < len; i++)
        a[i] = val;
    }

    public static fillWithin(a: Int32Array | Uint8Array | Int8Array | any[], fromIndex: number, toIndex: number, val: number): void {
        Arrays.rangeCheck(a.length, fromIndex, toIndex);
        for (let i = fromIndex; i < toIndex; i++)
        a[i] = val;
    }

    public static fillByte(a: Int8Array, fromIndex: number, toIndex: number, val: number): void {
        Arrays.rangeCheck(a.length, fromIndex, toIndex);
        for (let i = fromIndex; i < toIndex; i++)
        a[i] = val;
    }

    static rangeCheck(arrayLength: number, fromIndex: number, toIndex: number): void {
        if (fromIndex > toIndex) {
            throw new IllegalArgumentException(
                'fromIndex(' + fromIndex + ') > toIndex(' + toIndex + ')');
        }
        if (fromIndex < 0) {
            throw new ArrayIndexOutOfBoundsException(fromIndex);
        }
        if (toIndex > arrayLength) {
            throw new ArrayIndexOutOfBoundsException(toIndex);
        }
    }

    public static asList<T = any>(...args: T[]): T[] {
        return args;
    }

    public static create<T = any>(rows: number, cols: number, value?: T): T[][] {

        let arr = Array.from({
            length: rows
        });

        return arr.map(x => Array.from<T>({
            length: cols
        }).fill(value));
    }

    public static createInt32Array(rows: number, cols: number, value?: number): Int32Array[] {

        let arr = Array.from({
            length: rows
        });

        return arr.map(x => Int32Array.from({
            length: cols
        }).fill(value));
    }

    public static equals(first: any, second: any): boolean {
        if (!first) {
            return false;
        }
        if (!second) {
            return false;
        }
        if (!first.length) {
            return false;
        }
        if (!second.length) {
            return false;
        }
        if (first.length !== second.length) {
            return false;
        }
        for (let i = 0, length = first.length; i < length; i++) {
            if (first[i] !== second[i]) {
                return false;
            }
        }
        return true;
    }

    public static hashCode(a: any) {
        if (a === null) {
            return 0;
        }
        let result = 1;
        for (const element of a) {
            result = 31 * result + element;
        }
        return result;
    }

    public static fillUint8Array(a: Uint8Array, value: number) {
        for (let i = 0; i !== a.length; i++) {
            a[i] = value;
        }
    }

    public static copyOf(original: Int32Array, newLength: number): Int32Array {
        return original.slice(0, newLength);
    }

    public static copyOfUint8Array(original: Uint8Array, newLength: number): Uint8Array {

        if (original.length <= newLength) {
            const newArray = new Uint8Array(newLength);
            newArray.set(original);
            return newArray;
        }

        return original.slice(0, newLength);
    }

    public static copyOfRangeInt(original: Int32Array, from: number, to: number): Int32Array {
        const newLength = to - from;
        const copy = new Int32Array(newLength);
        System.arraycopy(original, from, copy, 0, newLength);
        return copy;
    }

    public static copyOfRangeByte(original: Int8Array, from: number, to: number): Int8Array {
        const newLength = to - from;
        const copy = new Int8Array(newLength);
        System.arraycopy(original, from, copy, 0, newLength);
        return copy;
    }

    public static binarySearch(ar: Int32Array, el: number, comparator?: (a: number, b: number) => number): number {
        comparator = undefined === comparator ? Arrays.numberComparator : comparator;

        let m = 0;
        let n = ar.length - 1;
        while (m <= n) {
            const k = (n + m) >> 1;
            const cmp = comparator(el, ar[k]);
            if (cmp > 0) {
                m = k + 1;
            } else if (cmp < 0) {
                n = k - 1;
            } else {
                return k;
            }
        }
        return -m - 1;
    }

    public static numberComparator(a: number, b: number) {
        return a - b;
    }
}
