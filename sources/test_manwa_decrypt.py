#!/usr/bin/env python3
"""
测试 Manwa 图片 AES 解密
使用与 Kotlin 版本相同的参数:
- 算法: AES/CBC/NoPadding
- 密钥: my2ecret782ecret (16字节)
- IV: 与密钥相同
"""

import requests
from Crypto.Cipher import AES

# 测试图片URL (从日志中获取)
TEST_URL = "https://mwappimgs.cc/static/upload3/book/id/159321/31227327/0b7c8b644362081b7985daf6c8b79522_zb.webp?v=20220724"

# AES 参数
KEY = b"my2ecret782ecret"  # 16 bytes
IV = KEY  # IV 同密钥

def test_decrypt():
    print("=" * 60)
    print("Manwa 图片解密测试")
    print("=" * 60)
    
    # 1. 下载加密图片
    print(f"\n1. 下载图片: {TEST_URL[:80]}...")
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Referer": "https://manwa.me/"
    }
    
    try:
        response = requests.get(TEST_URL, headers=headers, timeout=30)
        response.raise_for_status()
    except Exception as e:
        print(f"❌ 下载失败: {e}")
        return
    
    encrypted_data = response.content
    print(f"   下载完成, 大小: {len(encrypted_data)} 字节")
    
    # 2. 显示加密数据头
    print(f"\n2. 加密数据头 (前16字节):")
    print(f"   HEX: {encrypted_data[:16].hex(' ')}")
    print(f"   ASCII: {repr(encrypted_data[:16])}")
    
    # 3. AES 解密
    print(f"\n3. 执行 AES-CBC 解密...")
    print(f"   密钥: {KEY}")
    print(f"   IV: {IV}")
    
    try:
        cipher = AES.new(KEY, AES.MODE_CBC, IV)
        decrypted_data = cipher.decrypt(encrypted_data)
    except Exception as e:
        print(f"❌ 解密失败: {e}")
        return
    
    print(f"   解密完成, 大小: {len(decrypted_data)} 字节")
    
    # 4. 显示解密数据头
    print(f"\n4. 解密数据头 (前16字节):")
    print(f"   HEX: {decrypted_data[:16].hex(' ')}")
    print(f"   ASCII: {repr(decrypted_data[:16])}")
    
    # 5. 检查是否是有效的 WebP 文件
    is_webp = decrypted_data[:4] == b'RIFF' and decrypted_data[8:12] == b'WEBP'
    is_png = decrypted_data[:8] == b'\x89PNG\r\n\x1a\n'
    is_jpeg = decrypted_data[:2] == b'\xff\xd8'
    
    print(f"\n5. 文件格式检测:")
    print(f"   是否 WebP: {is_webp} (期望: RIFF....WEBP)")
    print(f"   是否 PNG:  {is_png}")
    print(f"   是否 JPEG: {is_jpeg}")
    
    # 6. 保存解密后的文件
    output_file = "decrypted_test.webp"
    with open(output_file, "wb") as f:
        f.write(decrypted_data)
    print(f"\n6. 已保存解密文件: {output_file}")
    
    if is_webp:
        print("\n✅ 解密成功! 文件是有效的 WebP 格式")
    else:
        print("\n❌ 解密后的数据不是有效的图片格式!")
        print("   可能的原因:")
        print("   - 密钥或IV不正确")
        print("   - 该图片实际上没有加密")
        print("   - 使用了不同的加密方式")

if __name__ == "__main__":
    test_decrypt()
