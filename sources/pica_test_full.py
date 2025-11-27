#!/usr/bin/env python3
"""
PicaComic API 完整测试脚本
完全按照 Tachiyomi Kotlin 扩展的实现逻辑

关键发现：
1. Kotlin 版本使用自定义 DNS 解析，将 picaapi.picacomic.com 解析到分流服务器 IP
2. 签名格式: path + time + nonce + method + apiKey (全部小写)
3. 需要正确的 Host 头和 SNI
"""

import requests
import time
import hmac
import hashlib
import json
import random
import string
import ssl
import socket
from urllib.parse import urlparse
from requests.adapters import HTTPAdapter
from urllib3.util.ssl_ import create_urllib3_context
from urllib3.poolmanager import PoolManager

# ============== 配置 ==============
API_KEY = "C69BAF41DA5ABD1FFEDC6D2FEA56B"
SECRET_KEY = "~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn"
BASE_URL = "https://picaapi.picacomic.com"
INIT_URL = "http://68.183.234.72/init"

# 用户凭据
USERNAME = ""
PASSWORD = ""

# 基础请求头 (与 Kotlin 版本完全一致)
BASIC_HEADERS = {
    "api-key": API_KEY,
    "app-channel": "2",
    "app-version": "2.2.1.3.3.4",
    "app-uuid": "defaultUuid",
    "app-platform": "android",
    "app-build-version": "44",
    "User-Agent": "okhttp/3.8.1",
    "accept": "application/vnd.picacomic.com.v1+json",
    "image-quality": "high",
    "Content-Type": "application/json; charset=UTF-8",
}

# ============== 自定义 DNS 适配器 ==============
class HostHeaderSSLAdapter(HTTPAdapter):
    """
    自定义 HTTPS 适配器，支持将请求发送到指定 IP 但保持正确的 Host 头和 SNI
    模拟 Kotlin ChannelDns 的行为
    """
    def __init__(self, target_ip, target_host, *args, **kwargs):
        self.target_ip = target_ip
        self.target_host = target_host
        super().__init__(*args, **kwargs)
    
    def init_poolmanager(self, *args, **kwargs):
        # 创建自定义 SSL 上下文
        ctx = create_urllib3_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        kwargs['ssl_context'] = ctx
        return super().init_poolmanager(*args, **kwargs)
    
    def get_connection(self, url, proxies=None):
        # 修改连接目标为指定 IP
        parsed = urlparse(url)
        # 替换 host 为 IP
        conn = super().get_connection(url, proxies)
        return conn

# ============== 签名计算 ==============
def generate_nonce(length=32):
    """生成随机 nonce，与 Kotlin 版本一致"""
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

def compute_signature(path: str, method: str, timestamp: str, nonce: str) -> str:
    """
    计算 HMAC-SHA256 签名
    与 Kotlin 版本完全一致:
    raw = "$path$time$nonce${method}$apiKey".lowercase()
    
    注意: Kotlin 版本的 path 包含查询参数！
    url.substringAfter("$baseUrl/") 不会去掉查询参数
    """
    raw = f"{path}{timestamp}{nonce}{method}{API_KEY}".lower()
    signature = hmac.new(
        SECRET_KEY.encode('utf-8'),
        raw.encode('utf-8'),
        hashlib.sha256
    ).hexdigest()
    return signature

def get_pica_headers(url: str, method: str = "GET", token: str = None, include_query_in_signature: bool = True) -> dict:
    """
    构建 PicaComic API 请求头
    与 Kotlin picaHeaders() 方法一致
    
    关键发现: Kotlin 版本在签名时包含查询参数！
    """
    timestamp = str(int(time.time()))
    nonce = generate_nonce()
    
    # 从 URL 提取路径 (去掉 baseUrl 前缀)
    # Kotlin: url.substringAfter("$baseUrl/") - 这会保留查询参数！
    path = url.replace(BASE_URL + "/", "")
    
    # 根据参数决定是否在签名中包含查询参数
    if not include_query_in_signature and "?" in path:
        path = path.split("?")[0]
    
    signature = compute_signature(path, method, timestamp, nonce)
    
    headers = BASIC_HEADERS.copy()
    headers["time"] = timestamp
    headers["nonce"] = nonce
    headers["signature"] = signature
    
    if token:
        headers["authorization"] = token
    
    return headers

# ============== API 方法 ==============
def get_channel_addresses():
    """获取分流服务器地址"""
    print("=" * 50)
    print("获取分流服务器地址...")
    print("=" * 50)
    
    headers = {
        "Accept-Encoding": "gzip",
        "User-Agent": "okhttp/3.8.1"
    }
    
    try:
        response = requests.get(INIT_URL, headers=headers, timeout=10)
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"响应: {json.dumps(data, indent=2, ensure_ascii=False)}")
            return data.get("addresses", [])
        else:
            print(f"失败: {response.text}")
            return []
    except Exception as e:
        print(f"错误: {e}")
        return []

def login(username: str, password: str) -> str:
    """登录并获取 token"""
    print("\n" + "=" * 50)
    print(f"登录: {username}")
    print("=" * 50)
    
    url = f"{BASE_URL}/auth/sign-in"
    headers = get_pica_headers(url, "POST")
    
    payload = {
        "email": username,
        "password": password
    }
    
    print(f"URL: {url}")
    print(f"签名路径: auth/sign-in")
    print(f"时间戳: {headers['time']}")
    print(f"Nonce: {headers['nonce'][:8]}...")
    print(f"签名: {headers['signature'][:16]}...")
    
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=30)
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            if data.get("code") == 200:
                token = data.get("data", {}).get("token")
                if token:
                    print(f"✅ 登录成功! Token: {token[:30]}...")
                    return token
                else:
                    print(f"❌ 登录响应中没有 token: {json.dumps(data, indent=2)}")
            else:
                print(f"❌ 登录失败: {data.get('message')}")
        else:
            print(f"❌ 登录失败: {response.text}")
        return None
    except Exception as e:
        print(f"❌ 错误: {e}")
        return None

def get_popular_comics(token: str, page: int = 1):
    """获取热门漫画"""
    print("\n" + "=" * 50)
    print(f"获取热门漫画 (页码: {page})")
    print("=" * 50)
    
    url = f"{BASE_URL}/comics?page={page}&s=dd"
    headers = get_pica_headers(url, "GET", token)
    
    print(f"URL: {url}")
    print(f"签名路径: comics")
    
    try:
        response = requests.get(url, headers=headers, timeout=30)
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"响应 keys: {list(data.keys())}")
            
            if "data" in data:
                comics_data = data.get("data", {}).get("comics", {})
                if isinstance(comics_data, dict):
                    docs = comics_data.get("docs", [])
                    total = comics_data.get("total", 0)
                    pages = comics_data.get("pages", 0)
                    print(f"✅ 找到 {len(docs)} 个漫画 (总计: {total}, 页数: {pages})")
                    for comic in docs[:5]:
                        print(f"  - {comic.get('title')} (作者: {comic.get('author', 'N/A')})")
                    return docs
                else:
                    print(f"comics 不是字典: {type(comics_data)}")
            else:
                print(f"❌ 响应中没有 data 字段")
                print(f"完整响应: {json.dumps(data, indent=2, ensure_ascii=False)[:500]}")
        else:
            print(f"❌ 请求失败: {response.text[:500]}")
        return []
    except Exception as e:
        print(f"❌ 错误: {e}")
        import traceback
        traceback.print_exc()
        return []

def get_random_comics(token: str):
    """获取随机漫画 (最新更新)"""
    print("\n" + "=" * 50)
    print("获取随机漫画")
    print("=" * 50)
    
    url = f"{BASE_URL}/comics/random"
    headers = get_pica_headers(url, "GET", token)
    
    print(f"URL: {url}")
    print(f"签名路径: comics/random")
    
    try:
        response = requests.get(url, headers=headers, timeout=30)
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"响应 keys: {list(data.keys())}")
            
            if "data" in data:
                comics = data.get("data", {}).get("comics", [])
                if isinstance(comics, list):
                    print(f"✅ 找到 {len(comics)} 个随机漫画")
                    for comic in comics[:5]:
                        print(f"  - {comic.get('title')} (作者: {comic.get('author', 'N/A')})")
                    return comics
            else:
                print(f"❌ 响应中没有 data 字段")
                print(f"完整响应: {json.dumps(data, indent=2, ensure_ascii=False)[:500]}")
        else:
            print(f"❌ 请求失败: {response.text[:500]}")
        return []
    except Exception as e:
        print(f"❌ 错误: {e}")
        return []

def get_categories(token: str):
    """获取分类列表"""
    print("\n" + "=" * 50)
    print("获取分类列表")
    print("=" * 50)
    
    url = f"{BASE_URL}/categories"
    headers = get_pica_headers(url, "GET", token)
    
    print(f"URL: {url}")
    print(f"签名路径: categories")
    
    try:
        response = requests.get(url, headers=headers, timeout=30)
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            
            if "data" in data:
                categories = data.get("data", {}).get("categories", [])
                print(f"✅ 找到 {len(categories)} 个分类")
                for cat in categories[:10]:
                    if isinstance(cat, dict):
                        print(f"  - {cat.get('title', cat)}")
                    else:
                        print(f"  - {cat}")
                return categories
            else:
                print(f"❌ 响应中没有 data 字段")
                print(f"完整响应: {json.dumps(data, indent=2, ensure_ascii=False)[:500]}")
        else:
            print(f"❌ 请求失败: {response.text[:500]}")
        return []
    except Exception as e:
        print(f"❌ 错误: {e}")
        return []

def get_leaderboard(token: str, tt: str = "H24"):
    """获取排行榜"""
    print("\n" + "=" * 50)
    print(f"获取排行榜 (tt={tt})")
    print("=" * 50)
    
    url = f"{BASE_URL}/comics/leaderboard?tt={tt}&ct=VC"
    headers = get_pica_headers(url, "GET", token)
    
    print(f"URL: {url}")
    print(f"签名路径: comics/leaderboard")
    
    try:
        response = requests.get(url, headers=headers, timeout=30)
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"响应 keys: {list(data.keys())}")
            
            if "data" in data:
                comics = data.get("data", {}).get("comics", [])
                if isinstance(comics, list):
                    print(f"✅ 找到 {len(comics)} 个排行榜漫画")
                    for comic in comics[:5]:
                        print(f"  - {comic.get('title')} (作者: {comic.get('author', 'N/A')})")
                    return comics
            else:
                print(f"❌ 响应中没有 data 字段")
                print(f"完整响应: {json.dumps(data, indent=2, ensure_ascii=False)[:500]}")
        else:
            print(f"❌ 请求失败: {response.text[:500]}")
        return []
    except Exception as e:
        print(f"❌ 错误: {e}")
        return []

def search_comics(token: str, keyword: str, page: int = 1):
    """搜索漫画"""
    print("\n" + "=" * 50)
    print(f"搜索漫画: '{keyword}' (页码: {page})")
    print("=" * 50)
    
    url = f"{BASE_URL}/comics/advanced-search?page={page}"
    headers = get_pica_headers(url, "POST", token)
    
    payload = {
        "keyword": keyword,
        "categories": [],
        "sort": "dd"
    }
    
    print(f"URL: {url}")
    print(f"签名路径: comics/advanced-search")
    
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=30)
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"响应 keys: {list(data.keys())}")
            
            if "data" in data:
                comics_data = data.get("data", {}).get("comics", {})
                if isinstance(comics_data, dict):
                    docs = comics_data.get("docs", [])
                    total = comics_data.get("total", 0)
                    print(f"✅ 找到 {len(docs)} 个漫画 (总计: {total})")
                    for comic in docs[:5]:
                        print(f"  - {comic.get('title')} (作者: {comic.get('author', 'N/A')})")
                    return docs
            else:
                print(f"❌ 响应中没有 data 字段")
                print(f"完整响应: {json.dumps(data, indent=2, ensure_ascii=False)[:500]}")
        else:
            print(f"❌ 请求失败: {response.text[:500]}")
        return []
    except Exception as e:
        print(f"❌ 错误: {e}")
        return []

def get_comic_detail(token: str, comic_id: str):
    """获取漫画详情"""
    print("\n" + "=" * 50)
    print(f"获取漫画详情: {comic_id}")
    print("=" * 50)
    
    url = f"{BASE_URL}/comics/{comic_id}"
    headers = get_pica_headers(url, "GET", token)
    
    print(f"URL: {url}")
    print(f"签名路径: comics/{comic_id}")
    
    try:
        response = requests.get(url, headers=headers, timeout=30)
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            
            if "data" in data:
                comic = data.get("data", {}).get("comic", {})
                if comic:
                    print(f"✅ 漫画详情:")
                    print(f"  标题: {comic.get('title')}")
                    print(f"  作者: {comic.get('author')}")
                    print(f"  描述: {comic.get('description', '')[:100]}...")
                    print(f"  分类: {comic.get('categories', [])}")
                    return comic
            else:
                print(f"❌ 响应中没有 data 字段")
        else:
            print(f"❌ 请求失败: {response.text[:500]}")
        return None
    except Exception as e:
        print(f"❌ 错误: {e}")
        return None

def get_comic_chapters(token: str, comic_id: str, page: int = 1):
    """获取漫画章节列表"""
    print("\n" + "=" * 50)
    print(f"获取漫画章节: {comic_id} (页码: {page})")
    print("=" * 50)
    
    url = f"{BASE_URL}/comics/{comic_id}/eps?page={page}"
    headers = get_pica_headers(url, "GET", token)
    
    print(f"URL: {url}")
    print(f"签名路径: comics/{comic_id}/eps")
    
    try:
        response = requests.get(url, headers=headers, timeout=30)
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            
            if "data" in data:
                eps = data.get("data", {}).get("eps", {})
                if eps:
                    docs = eps.get("docs", [])
                    total = eps.get("total", 0)
                    pages = eps.get("pages", 0)
                    print(f"✅ 找到 {len(docs)} 个章节 (总计: {total}, 页数: {pages})")
                    for ep in docs[:5]:
                        print(f"  - 第{ep.get('order')}话: {ep.get('title')}")
                    return docs
            else:
                print(f"❌ 响应中没有 data 字段")
        else:
            print(f"❌ 请求失败: {response.text[:500]}")
        return []
    except Exception as e:
        print(f"❌ 错误: {e}")
        return []

def get_chapter_pages(token: str, comic_id: str, order: int, page: int = 1):
    """获取章节页面列表"""
    print("\n" + "=" * 50)
    print(f"获取章节页面: {comic_id}/order/{order} (页码: {page})")
    print("=" * 50)
    
    url = f"{BASE_URL}/comics/{comic_id}/order/{order}/pages?page={page}"
    headers = get_pica_headers(url, "GET", token)
    
    print(f"URL: {url}")
    print(f"签名路径: comics/{comic_id}/order/{order}/pages")
    
    try:
        response = requests.get(url, headers=headers, timeout=30)
        print(f"状态码: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            
            if "data" in data:
                pages_data = data.get("data", {}).get("pages", {})
                if pages_data:
                    docs = pages_data.get("docs", [])
                    total = pages_data.get("total", 0)
                    print(f"✅ 找到 {len(docs)} 个页面 (总计: {total})")
                    for p in docs[:3]:
                        media = p.get("media", {})
                        url = f"{media.get('fileServer')}/static/{media.get('path')}"
                        print(f"  - {url[:80]}...")
                    return docs
            else:
                print(f"❌ 响应中没有 data 字段")
        else:
            print(f"❌ 请求失败: {response.text[:500]}")
        return []
    except Exception as e:
        print(f"❌ 错误: {e}")
        return []

# ============== 主测试流程 ==============
def debug_api_response(token: str, url: str, method: str = "GET", body: dict = None):
    """调试 API 响应，打印完整信息"""
    print("\n" + "=" * 50)
    print(f"调试 API: {url}")
    print("=" * 50)
    
    headers = get_pica_headers(url, method, token)
    
    # 打印完整请求头
    print("请求头:")
    for k, v in headers.items():
        if k == "authorization":
            print(f"  {k}: {v[:30]}...")
        else:
            print(f"  {k}: {v}")
    
    try:
        if method == "GET":
            response = requests.get(url, headers=headers, timeout=30)
        else:
            response = requests.post(url, json=body, headers=headers, timeout=30)
        
        print(f"\n状态码: {response.status_code}")
        print(f"响应头:")
        for k, v in response.headers.items():
            print(f"  {k}: {v}")
        
        print(f"\n响应体:")
        try:
            data = response.json()
            print(json.dumps(data, indent=2, ensure_ascii=False)[:1000])
        except:
            print(response.text[:1000])
        
        return response
    except Exception as e:
        print(f"错误: {e}")
        import traceback
        traceback.print_exc()
        return None

def main():
    print("\n" + "=" * 60)
    print("PicaComic API 完整测试 - 查询参数测试")
    print("=" * 60)
    
    # 1. 登录
    token = login(USERNAME, PASSWORD)
    if not token:
        print("\n❌ 登录失败，无法继续测试")
        return
    
    # 2. 获取随机漫画 (这个能工作)
    random_comics = get_random_comics(token)
    
    test_comic_id = None
    if random_comics:
        test_comic_id = random_comics[0].get("_id")
        print(f"\n使用测试漫画 ID: {test_comic_id}")
    
    if test_comic_id:
        # 测试章节 API - 各种参数组合
        print("\n" + "=" * 60)
        print("测试章节 API 的各种参数组合")
        print("=" * 60)
        
        # 不带参数
        debug_api_response(token, f"{BASE_URL}/comics/{test_comic_id}/eps")
        
        # 带 page 参数
        debug_api_response(token, f"{BASE_URL}/comics/{test_comic_id}/eps?page=1")
        
        # 测试页面 API
        print("\n" + "=" * 60)
        print("测试页面 API")
        print("=" * 60)
        
        # 不带参数
        debug_api_response(token, f"{BASE_URL}/comics/{test_comic_id}/order/1/pages")
        
        # 带 page 参数
        debug_api_response(token, f"{BASE_URL}/comics/{test_comic_id}/order/1/pages?page=1")
    
    # 3. 测试热门漫画 API - 各种参数组合
    print("\n" + "=" * 60)
    print("测试热门漫画 API 的各种参数组合")
    print("=" * 60)
    
    # 不带任何参数
    debug_api_response(token, f"{BASE_URL}/comics")
    
    # 只带 page
    debug_api_response(token, f"{BASE_URL}/comics?page=1")
    
    # 只带 s
    debug_api_response(token, f"{BASE_URL}/comics?s=dd")
    
    # 带 page 和 s
    debug_api_response(token, f"{BASE_URL}/comics?page=1&s=dd")
    
    # 4. 测试搜索 API
    print("\n" + "=" * 60)
    print("测试搜索 API")
    print("=" * 60)
    
    # 不带 page 参数
    search_url = f"{BASE_URL}/comics/advanced-search"
    headers = get_pica_headers(search_url, "POST", token)
    payload = {"keyword": "女", "categories": [], "sort": "dd"}
    
    print(f"\n调试 POST {search_url}")
    try:
        response = requests.post(search_url, json=payload, headers=headers, timeout=30)
        print(f"状态码: {response.status_code}")
        data = response.json()
        print(f"响应: {json.dumps(data, indent=2, ensure_ascii=False)[:500]}")
    except Exception as e:
        print(f"错误: {e}")
    
    # 带 page 参数
    search_url2 = f"{BASE_URL}/comics/advanced-search?page=1"
    headers2 = get_pica_headers(search_url2, "POST", token)
    
    print(f"\n调试 POST {search_url2}")
    try:
        response = requests.post(search_url2, json=payload, headers=headers2, timeout=30)
        print(f"状态码: {response.status_code}")
        data = response.json()
        print(f"响应: {json.dumps(data, indent=2, ensure_ascii=False)[:500]}")
    except Exception as e:
        print(f"错误: {e}")

if __name__ == "__main__":
    main()
