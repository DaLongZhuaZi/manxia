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

export default class MyArray<T> {
    public data: Array<T> = Array<T>()
    public size: number = 0

    constructor(capacity = 10) {
        this.data = new Array(capacity);
        this.size = 0;
    }

    public getSize() {
        return this.size;
    }

    public getCapacity() {
        return this.data.length;
    }

    public isEmpty() {
        return this.size === 0;
    }

    public resize(capacity) {

        let newArray = new Array(capacity);
        for (var i = 0; i < this.size; i++) {
            newArray[i] = this.data[i];
        }
        this.data = newArray;
    }

    public insert(index, element) {

        // 先判断数组是否已满
        if (this.size == this.getCapacity()) {
            this.resize(this.size * 2);
        }

        if (index < 0 || index > this.size) {
            throw new Error("insert error. require  index < 0 or index > size.");
        }

        for (let i = this.size - 1; i >= index; i--) {
            this.data[i + 1] = this.data[i];
        }

        this.data[index] = element;
        this.size++;
    }

    public unshift(element) {
        this.insert(0, element);
    }

    public push(element) {
        this.insert(this.size, element);
    }

    public add(element) {
        if (this.size == this.getCapacity()) {

            this.resize(this.size * 2);
        }

        this.data[this.size] = element;
        // 维护size
        this.size++;
    }

    get(index) {

        if (index < 0 || index >= this.size) {
            throw new Error("get error. index < 0 or index >= size.");
        }
        return this.data[index];
    }

    public getFirst() {
        return this.get(0);
    }

    public getLast() {
        return this.get(this.size - 1);
    }

    public set(index, newElement) {

        if (index < 0 || index >= this.size) {
            throw new Error("set error. index < 0 or index >= size.");
        }
        this.data[index] = newElement;
    }

    public contain(element) {
        for (var i = 0; i < this.size; i++) {
            if (this.data[i] === element) {
                return true;
            }
        }
        return false;
    }

    public find(element) {
        for (var i = 0; i < this.size; i++) {
            if (this.data[i] === element) {
                return i;
            }
        }
        return -1;
    }

    public findAll(element) {

        let myarray = new MyArray(this.size);

        for (var i = 0; i < this.size; i++) {
            if (this.data[i] === element) {
                myarray.push(i);
            }
        }

        return myarray;
    }

    public remove(index) {

        if (index < 0 || index >= this.size) {
            throw new Error("remove error. index < 0 or index >= size.");
        }

        let element = this.data[index];
        for (let i = index; i < this.size - 1; i++) {
            this.data[i] = this.data[i + 1];
        }

        this.size--;
        this.data[this.size] = null;
        if (Math.floor(this.getCapacity() / 4) === this.size) {

            this.resize(Math.floor(this.getCapacity() / 2));
        }

        return element;
    }

    public shift() {
        return this.remove(0);
    }

    public pop() {
        return this.remove(this.size - 1);
    }

    public removeElement(element) {

        let index = this.find(element);
        if (index !== -1) {
            this.remove(index);
        }
    }

    public removeAllElement(element) {
        let index = this.find(element);
        while (index != -1) {
            this.remove(index);
            index = this.find(element);
        }
    }

    public swap(indexA, indexB) {
        if (indexA < 0 || indexA >= this.size || indexB < 0 || indexB >= this.size)
        throw new Error("Index is Illegal."); // 索引越界异常

        let temp = this.data[indexA];
        this.data[indexA] = this.data[indexB];
        this.data[indexB] = temp;
    }

    public toString(): string {
        let arrInfo = `Array: size = ${this.getSize()}，capacity = ${this.getCapacity()}，\n`;
        arrInfo += `data = [`;
        for (var i = 0; i < this.size - 1; i++) {
            arrInfo += `${this.data[i]}, `;
        }
        if (!this.isEmpty()) {
            arrInfo += `${this.data[this.size - 1]}`;
        }
        arrInfo += `]`;

        return arrInfo;
    }
}