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
import MyMaxHeap from './MyMaxHeap'

export default class PriorityQueue<T> extends MyMaxHeap<T> {
    private maxHeap: MyMaxHeap<T>

    constructor() {
        super()
        this.maxHeap = new MyMaxHeap<T>();
    }

    public enqueue(elementField: any) {
        this.maxHeap.add(elementField);
    }

    public dequeue() {
        return this.maxHeap.extractMax();
    }

    public getFront() {
        return this.maxHeap.findMax();
    }

    public getSize() {
        return this.maxHeap.size();
    }

    public isEmpty() {
        return this.maxHeap.isEmpty();
    }

    public updateCompare(compareMethod) {
        // 传入参数可以替换掉原堆中实现的compare方法
        this.maxHeap.compare = compareMethod;
    }

    public replaceFront(elementField: any) {
        return this.maxHeap.replace(elementField);
    }
}