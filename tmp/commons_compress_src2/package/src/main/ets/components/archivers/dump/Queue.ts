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

import MyArray from './MyArray'

export default class Queue<T> {
    public myArray: MyArray<T>;

    constructor(capacity = 10) {
        this.myArray = new MyArray<T>(capacity);
    }

    public enqueue(elementField: any) {
        this.myArray.push(elementField);
    }

    public dequeue() {
        return this.myArray.shift();
    }

    public getFront() {
        return this.myArray.getFirst();
    }

    public getSize() {
        return this.myArray.getSize();
    }

    public getCapacity() {
        return this.myArray.getCapacity();
    }

    public isEmpty() {
        return this.myArray.isEmpty();
    }

    public toString() {
        let arrInfo = `Queue: size = ${this.getSize()}，capacity = ${this.getCapacity()}，\n`;
        arrInfo += `data = front  [`;
        for (var i = 0; i < this.myArray.size - 1; i++) {
            arrInfo += `${this.myArray.data[i]}, `;
        }
        if (!this.isEmpty()) {
            arrInfo += `${this.myArray.data[this.myArray.size - 1]}`;
        }
        arrInfo += `]  tail`;

        return arrInfo;
    }
}


