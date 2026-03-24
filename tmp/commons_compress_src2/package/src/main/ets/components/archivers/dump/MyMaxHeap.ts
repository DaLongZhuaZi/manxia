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

export default class MyMaxHeap<T> {
    public myArray: MyArray<T>

    constructor(capacity = 10) {
        this.myArray = new MyArray<T>(capacity);
    }

    public getCapacity() {
        return this.myArray.getCapacity();
    }

    public add(element) {

        this.myArray.push(element);

        this.siftUp(this.myArray.getSize() - 1);
    }

    public siftUp(index) {
        this.nonRecursiveSiftUp(index);
    }

    public recursiveSiftUp(index) {

        if (index <= 0) return;

        let currentValue = this.myArray.get(index);
        let parentIndex = this.calcParentIndex(index);
        let parentValue = this.myArray.get(parentIndex);
        if (this.compare(currentValue, parentValue) > 0) {
            this.swap(index, parentIndex);
            this.recursiveSiftUp(parentIndex);
        }
    }

    public nonRecursiveSiftUp(index) {
        if (index <= 0) return;

        let currentValue = this.myArray.get(index);
        let parentIndex = this.calcParentIndex(index);
        let parentValue = this.myArray.get(parentIndex);

        while (this.compare(currentValue, parentValue) > 0) {
            this.swap(index, parentIndex);
            index = parentIndex;
            if (index <= 0)
            break
            currentValue = this.myArray.get(index);
            parentIndex = this.calcParentIndex(index);
            parentValue = this.myArray.get(parentIndex);
        }
    }

    public findMax() {
        if (this.myArray.isEmpty())
        throw new Error("can not findMax when heap is empty.");
        return this.myArray.getFirst();
    }

    public extractMax() {

        let maxElement = this.findMax();

        let element = this.myArray.getLast();
        this.myArray.set(0, element);

        this.myArray.pop();

        this.siftDown(0);

        return maxElement;
    }

    public siftDown(index) {
        this.nonRecursiveSiftDown(index);
    }

    public recursiveSiftDown(index) {

        if (this.calcLeftChildIndex(index) >= this.myArray.getSize())
        return;

        let leftChildIndex = this.calcLeftChildIndex(index);
        let leftChildValue = this.myArray.get(leftChildIndex);
        let rightChildIndex = this.calcRightChildIndex(index);
        let rightChildValue = null;

        let maxIndex = leftChildIndex;
        if (rightChildIndex < this.myArray.getSize()) {
            rightChildValue = this.myArray.get(rightChildIndex);
            if (this.compare(leftChildValue, rightChildValue) < 0)
            maxIndex = rightChildIndex;
        }

        let maxValue = this.myArray.get(maxIndex);
        let currentValue = this.myArray.get(index);

        if (this.compare(maxValue, currentValue) > 0) {
            this.swap(maxIndex, index);
            this.recursiveSiftDown(maxIndex);
        }

    }

    public nonRecursiveSiftDown(index) {

        while (this.calcLeftChildIndex(index) < this.myArray.getSize()) {
            let leftChildIndex = this.calcLeftChildIndex(index);
            let leftChildValue = this.myArray.get(leftChildIndex);
            let rightChildIndex = this.calcRightChildIndex(index);
            let rightChildValue = null;
            let maxIndex = leftChildIndex;

            if (rightChildIndex < this.myArray.getSize()) {
                rightChildValue = this.myArray.get(rightChildIndex);
                if (this.compare(leftChildValue, rightChildValue) < 0)
                maxIndex = rightChildIndex;
            }

            let maxValue = this.myArray.get(maxIndex);
            let currentValue = this.myArray.get(index);

            if (this.compare(maxValue, currentValue) > 0) {
                this.swap(maxIndex, index);
                index = maxIndex;
                continue;
            } else
            break;
        }
    }

    public replace(element) {
        let maxElement = this.findMax();

        this.myArray.set(0, element);

        this.siftDown(0);

        return maxElement;
    }

    public heapify(array) {

        for (const element of array)
        this.myArray.push(element);

        let index = this.calcParentIndex(this.myArray.getSize() - 1);

        while (0 <= index)
        this.siftDown(index--);
    }

    public swap(indexA, indexB) {
        this.myArray.swap(indexA, indexB);
    }

    public calcParentIndex(index) {
        if (index === 0) // 索引为0是根节点，根节点没有父亲节点，小于0就更加不可以了
        throw new Error("index is 0. doesn't have parent.");
        return Math.floor((index - 1) / 2);
    }

    public calcLeftChildIndex(index) {
        return index * 2 + 1;
    }

    public calcRightChildIndex(index) {
        return index * 2 + 2;
    }

    public compare(elementA, elementB) {
        if (elementA === null || elementB === null)
        throw new Error("element is error. element can't compare.");
        if (elementA > elementB)
        return 1;
        else if (elementA < elementB)
        return -1;
        else
        return 0;
    }

    public size() {
        return this.myArray.getSize();
    }

    public isEmpty() {
        return this.myArray.isEmpty();
    }
}

