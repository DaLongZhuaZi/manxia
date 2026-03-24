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
enum DecodeHintType {

    OTHER, /*(Object.class)*/

    PURE_BARCODE, /*(Void.class)*/

    POSSIBLE_FORMATS, /*(List.class)*/

    TRY_HARDER, /*(Void.class)*/

    CHARACTER_SET, /*(String.class)*/

    ALLOWED_LENGTHS, /*(Int32Array.class)*/

    ASSUME_CODE_39_CHECK_DIGIT, /*(Void.class)*/

    ASSUME_GS1, /*(Void.class)*/

    RETURN_CODABAR_START_END, /*(Void.class)*/

    NEED_RESULT_POINT_CALLBACK, /*(ResultPointCallback.class)*/

    ALLOWED_EAN_EXTENSIONS, /*(Int32Array.class)*/
}

export default DecodeHintType;
