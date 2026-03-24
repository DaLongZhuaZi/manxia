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
export default class ByteOrder {
    private name: string;

    constructor(name: string) {
        this.name = name;
    }

    public static BIG_ENDIAN: ByteOrder = new ByteOrder("BIG_ENDIAN");
    public static LITTLE_ENDIAN: ByteOrder = new ByteOrder("LITTLE_ENDIAN");

    public static nativeOrder(): ByteOrder {

        return ByteOrder.BIG_ENDIAN;
    }

    public toString(): string {
        return this.name;
    }
}