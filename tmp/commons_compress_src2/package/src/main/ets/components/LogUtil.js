/*
 * The MIT License (MIT)
 * Copyright (C) 2023 Huawei Device Co., Ltd.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 */
import hilog from '@ohos.hilog';

export class LogUtil {
    static DOMAIN = 0x0001;
    static TAG = '[CommonCompress]: ';

    static debug(message, ...args) {
        hilog.debug(LogUtil.DOMAIN, LogUtil.TAG, message, args);
    }

    static info(message, ...args) {
        hilog.info(LogUtil.DOMAIN, LogUtil.TAG, message, args);
    }

    static log(message, ...args) {
        hilog.debug(LogUtil.DOMAIN, LogUtil.TAG, message, args);
    }

    static warn(message, ...args) {
        hilog.warn(LogUtil.DOMAIN, LogUtil.TAG, message, args);
    }

    static error(message, ...args) {
        hilog.error(LogUtil.DOMAIN, LogUtil.TAG, message, args);
    }
}