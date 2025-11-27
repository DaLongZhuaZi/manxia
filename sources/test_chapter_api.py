#!/usr/bin/env python3
"""Test PicaComic chapter API to check data structure"""

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

def get_chapters(token, comic_id):
    url = f"{BASE_URL}/comics/{comic_id}/eps?page=1"
    headers = get_headers(url, "GET", token)
    response = requests.get(url, headers=headers, timeout=30)
    print(f"Status: {response.status_code}")
    if response.status_code == 200:
        return response.json()
    return None

def main():
    print("=== PicaComic Chapter API Test ===")
    
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
    
    print("\n3. Get chapters...")
    chapters_response = get_chapters(token, comic_id)
    
    if chapters_response:
        print("\n=== API Response Structure ===")
        print(json.dumps(chapters_response, indent=2, ensure_ascii=False)[:3000])
        
        # Extract chapter data
        eps_data = chapters_response.get("data", {}).get("eps", {})
        docs = eps_data.get("docs", [])
        
        print(f"\n=== Found {len(docs)} chapters ===")
        
        if docs:
            print("\n=== First 3 chapters structure ===")
            for i, ch in enumerate(docs[:3]):
                print(f"\n--- Chapter {i+1} ---")
                print(json.dumps(ch, indent=2, ensure_ascii=False))
            
            print("\n=== Chapter fields analysis ===")
            first_ch = docs[0]
            print(f"Available fields: {list(first_ch.keys())}")
            print(f"order: {first_ch.get('order')}")
            print(f"title: {first_ch.get('title')}")
            print(f"updated_at: {first_ch.get('updated_at')}")
            print(f"_id: {first_ch.get('_id')}")

if __name__ == "__main__":
    main()
