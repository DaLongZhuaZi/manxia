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
export default class NumberTransform {
    private static array = new Int8Array(1)
    private static shortArray = new Int16Array(1)

    public  static toByte(num) {
        NumberTransform.array[0] = num;
        return NumberTransform.array[0];
    }

    public  static toShort(num) {
        NumberTransform.shortArray[0] = num;
        return NumberTransform.shortArray[0];
    }
}