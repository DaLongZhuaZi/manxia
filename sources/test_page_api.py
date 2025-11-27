#!/usr/bin/env python3
"""简化的 PicaComic 页面 API 测试"""

import requests
import time
import hmac
import hashlib
import json
import random
import string

API_KEY = "C69BAF41DA5ABD1FFEDC6D2FEA56B"
SECRET_KEY = "~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn"
BASE_URL = "https://picaapi.picacomic.com"
USERNAME = ""
PASSWORD = ""

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

def generate_nonce(length=32):
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))

def compute_signature(path, method, timestamp, nonce):
    raw = f"{path}{timestamp}{nonce}{method}{API_KEY}".lower()
    return hmac.new(SECRET_KEY.encode('utf-8'), raw.encode('utf-8'), hashlib.sha256).hexdigest()

def get_headers(url, method="GET", token=None):
    timestamp = str(int(time.time()))
    nonce = generate_nonce()
    path = url.replace(BASE_URL + "/", "")
    signature = compute_signature(path, method, timestamp, nonce)
    
    headers = BASIC_HEADERS.copy()
    headers["time"] = timestamp
    headers["nonce"] = nonce
    headers["signature"] = signature
    if token:
        headers["authorization"] = token
    return headers

def login():
    url = f"{BASE_URL}/auth/sign-in"
    headers = get_headers(url, "POST")
    payload = {"email": USERNAME, "password": PASSWORD}
    response = requests.post(url, json=payload, headers=headers, timeout=30)
    if response.status_code == 200:
        data = response.json()
        if data.get("code") == 200:
            return data.get("data", {}).get("token")
    return None

def get_random_comics(token):
    url = f"{BASE_URL}/comics/random"
    headers = get_headers(url, "GET", token)
    response = requests.get(url, headers=headers, timeout=30)
    if response.status_code == 200:
        data = response.json()
        return data.get("data", {}).get("comics", [])
    return []

def get_chapter_pages(token, comic_id, order):
    url = f"{BASE_URL}/comics/{comic_id}/order/{order}/pages?page=1"
    headers = get_headers(url, "GET", token)
    response = requests.get(url, headers=headers, timeout=30)
    print(f"Status: {response.status_code}")
    if response.status_code == 200:
        return response.json()
    return None

def main():
    print("=== PicaComic Page API Test ===")
    
    print("\n1. Login...")
    token = login()
    if not token:
        print("Login failed!")
        return
    print(f"Token: {token[:30]}...")
    
    print("\n2. Get random comics...")
    comics = get_random_comics(token)
    if not comics:
        print("No comics found!")
        return
    
    comic_id = comics[0].get("_id")
    print(f"Comic ID: {comic_id}")
    print(f"Title: {comics[0].get('title')}")
    
    print("\n3. Get chapter pages...")
    pages_response = get_chapter_pages(token, comic_id, 1)
    
    if pages_response:
        print("\n=== API Response Structure ===")
        print(json.dumps(pages_response, indent=2, ensure_ascii=False)[:2000])
        
        # Extract page data
        pages_data = pages_response.get("data", {}).get("pages", {})
        docs = pages_data.get("docs", [])
        
        print(f"\n=== Found {len(docs)} pages ===")
        
        if docs:
            print("\n=== First page structure ===")
            first_page = docs[0]
            print(json.dumps(first_page, indent=2, ensure_ascii=False))
            
            # Show how to build URL
            media = first_page.get("media", {})
            if media:
                file_server = media.get("fileServer", "")
                path = media.get("path", "")
                full_url = f"{file_server}/static/{path}"
                print(f"\n=== Constructed URL ===")
                print(f"fileServer: {file_server}")
                print(f"path: {path}")
                print(f"Full URL: {full_url}")

if __name__ == "__main__":
    main()
