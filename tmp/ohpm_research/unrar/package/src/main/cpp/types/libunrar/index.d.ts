/**
 * 判断文件是否加密
 * path:文件路径
 * number:返回值 0代表没加密，1代表加密
 */
export const isEncrypted: (path: string) => number;

/**
 * 解压文件
 * path:文件包路径
 * dest:要解压文件存放的路径
 * password:密码.
 * string:返回值，解压成功则返回解压成功，否则返回失败
 */
export const extract: (path: string, dest: string, password?: string) => string;
export function RarFiles_Extract(path: string, dest: string, password?: string);
