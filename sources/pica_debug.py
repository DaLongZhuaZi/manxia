import requests
import time
import uuid
import hmac
import hashlib
import json

# Configuration
API_KEY = "C69BAF41DA5ABD1FFEDC6D2FEA56B"
SECRET_KEY = "~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn"

BASE_URL = "https://picaapi.picacomic.com"

def generate_signature(path_with_query, method, timestamp, nonce):
    """
    Signature format: path + time + nonce + method + apiKey
    IMPORTANT: path must include query parameters!
    """
    raw = f"{path_with_query}{timestamp}{nonce}{method}{API_KEY}"
    raw = raw.lower()
    
    key = SECRET_KEY.encode('utf-8')
    msg = raw.encode('utf-8')
    signature = hmac.new(key, msg, hashlib.sha256).hexdigest()
    return signature

def get_headers(path, method, token=None, params=None):
    """
    Generate headers with signature.
    params: query parameters dict - MUST be included in signature!
    """
    timestamp = str(int(time.time()))
    nonce = str(uuid.uuid4()).replace('-', '')
    
    # Build full path with query string for signature
    path_with_query = path
    if params:
        from urllib.parse import urlencode
        query_string = urlencode(params)
        path_with_query = f"{path}?{query_string}"
    
    signature = generate_signature(path_with_query, method, timestamp, nonce)
    
    headers = {
        "api-key": API_KEY,
        "app-channel": "2",
        "app-version": "2.2.1.3.3.4",
        "app-uuid": "defaultUuid",
        "app-platform": "android",
        "app-build-version": "44",
        "accept": "application/vnd.picacomic.com.v1+json",
        "Content-Type": "application/json; charset=UTF-8",
        "User-Agent": "okhttp/3.8.1", # Using the one from config, not the WebView one
        "image-quality": "original",
        "time": timestamp,
        "nonce": nonce,
        "signature": signature
    }
    
    if token:
        headers["authorization"] = token
        
    return headers

def login(username, password):
    # Try "auth/sign-in" as the path for signature
    sig_path = "auth/sign-in"
    url = f"{BASE_URL}/{sig_path}"
    
    print(f"Logging in as {username}...")
    headers = get_headers(sig_path, "POST")
    
    payload = {
        "email": username,
        "password": password
    }
    
    try:
        response = requests.post(url, json=payload, headers=headers)
        print(f"Status Code: {response.status_code}")
        print(f"Response: {response.text}")
        
        if response.status_code == 200:
            data = response.json()
            token = data.get("data", {}).get("token")
            print(f"Login Successful! Token: {token[:20]}...")
            return token
        else:
            print("Login Failed.")
            return None
    except Exception as e:
        print(f"Error: {e}")
        return None

def get_comics(token):
    path = "comics"
    url = f"{BASE_URL}/{path}"
    
    print("\nFetching Comics...")
    params = {
        "page": 1,
        "s": "dd"
    }
    headers = get_headers(path, "GET", token, params)
    
    try:
        response = requests.get(url, params=params, headers=headers)
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            docs = data.get("data", {}).get("comics", {}).get("docs", [])
            print(f"Found {len(docs)} comics.")
            for doc in docs[:3]:
                print(f"- {doc.get('title')} (Author: {doc.get('author')})")
        else:
            print("Get Comics Failed.")
            print(f"Response: {response.text}")
    except Exception as e:
        print(f"Error: {e}")

def get_categories(token):
    path = "categories"
    url = f"{BASE_URL}/{path}"
    
    print("\nFetching Categories...")
    headers = get_headers(path, "GET", token)
    
    try:
        response = requests.get(url, headers=headers)
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            categories = data.get("data", {}).get("categories", [])
            print(f"Found {len(categories)} categories:")
            for cat in categories[:10]:
                print(f"  - {cat.get('title', cat)}")
            return categories
        else:
            print("Get Categories Failed.")
            print(f"Response: {response.text}")
            return []
    except Exception as e:
        print(f"Error: {e}")
        return []

def get_comics_by_category(token, category):
    path = "comics"
    url = f"{BASE_URL}/{path}"
    
    print(f"\nFetching Comics in category '{category}'...")
    params = {
        "page": 1,
        "c": category,  # category parameter
        "s": "dd"
    }
    headers = get_headers(path, "GET", token, params)
    
    try:
        response = requests.get(url, params=params, headers=headers)
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"Response keys: {data.keys()}")
            docs = data.get("data", {}).get("comics", {}).get("docs", [])
            print(f"Found {len(docs)} comics.")
            for doc in docs[:3]:
                print(f"  - {doc.get('title')} (Author: {doc.get('author')})")
            return docs
        else:
            print("Get Comics Failed.")
            print(f"Response: {response.text}")
            return []
    except Exception as e:
        print(f"Error: {e}")
        return []

def get_leaderboard(token, tt="H24"):
    """Get leaderboard comics. tt can be: H24, D7, D30"""
    path = f"comics/leaderboard"
    url = f"{BASE_URL}/{path}"
    
    print(f"\nFetching Leaderboard (tt={tt})...")
    params = {
        "tt": tt,  # H24=24小时, D7=7天, D30=30天
        "ct": "VC"  # comic type
    }
    headers = get_headers(path, "GET", token, params)
    
    try:
        response = requests.get(url, params=params, headers=headers)
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"Response keys: {data.keys()}")
            comics = data.get("data", {}).get("comics", [])
            print(f"Found {len(comics)} comics in leaderboard.")
            for doc in comics[:5]:
                print(f"  - {doc.get('title')} (Author: {doc.get('author')})")
            return comics
        else:
            print("Get Leaderboard Failed.")
            print(f"Response: {response.text}")
            return []
    except Exception as e:
        print(f"Error: {e}")
        return []

def get_favourites(token, page=1, sort="dd"):
    """Get user's favourite comics"""
    path = "users/favourite"
    url = f"{BASE_URL}/{path}"
    
    print(f"\nFetching Favourites (page={page}, sort={sort})...")
    params = {
        "page": page,
        "s": sort
    }
    headers = get_headers(path, "GET", token, params)
    
    try:
        response = requests.get(url, params=params, headers=headers)
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"Response keys: {data.keys()}")
            comics_data = data.get("data", {}).get("comics", {})
            docs = comics_data.get("docs", [])
            total = comics_data.get("total", 0)
            pages = comics_data.get("pages", 0)
            print(f"Found {len(docs)} favourites (total: {total}, pages: {pages}).")
            for doc in docs[:5]:
                print(f"  - {doc.get('title')} (Author: {doc.get('author')})")
            return data
        else:
            print("Get Favourites Failed.")
            print(f"Response: {response.text}")
            return None
    except Exception as e:
        print(f"Error: {e}")
        return None

def get_my_comments(token, page=1):
    """Get user's comments (history of commented comics)"""
    path = "users/my-comments"
    url = f"{BASE_URL}/{path}"
    
    print(f"\nFetching My Comments (page={page})...")
    params = {
        "page": page
    }
    headers = get_headers(path, "GET", token, params)
    
    try:
        response = requests.get(url, params=params, headers=headers)
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"Response: {json.dumps(data, indent=2)[:1000]}")
            return data
        else:
            print("Get My Comments Failed.")
            print(f"Response: {response.text}")
            return None
    except Exception as e:
        print(f"Error: {e}")
        return None

def get_user_profile(token):
    """Get user profile"""
    path = "users/profile"
    url = f"{BASE_URL}/{path}"
    
    print(f"\nFetching User Profile...")
    headers = get_headers(path, "GET", token)
    
    try:
        response = requests.get(url, headers=headers)
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            user = data.get("data", {}).get("user", {})
            print(f"User: {user.get('name')} (Email: {user.get('email')})")
            print(f"Level: {user.get('level')}, Exp: {user.get('exp')}")
            print(f"Avatar: {user.get('avatar', {})}")
            return data
        else:
            print("Get User Profile Failed.")
            print(f"Response: {response.text}")
            return None
    except Exception as e:
        print(f"Error: {e}")
        return None

def get_channel_addresses():
    """Get channel server addresses from init endpoint"""
    init_url = "http://68.183.234.72/init"
    
    print("Fetching channel addresses...")
    headers = {
        "Accept-Encoding": "gzip",
        "User-Agent": "okhttp/3.8.1"
    }
    
    try:
        response = requests.get(init_url, headers=headers)
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"Response: {json.dumps(data, indent=2)}")
            return data.get("addresses", [])
        else:
            print(f"Failed: {response.text}")
            return []
    except Exception as e:
        print(f"Error: {e}")
        return []

def get_comics_with_ip(token, server_ip):
    """Get comics using direct IP connection with custom DNS resolution"""
    import socket
    from urllib3.util.ssl_ import create_urllib3_context
    from requests.adapters import HTTPAdapter
    from urllib3.util import ssl_
    
    path = "comics"
    
    print(f"\nFetching Comics using IP {server_ip}...")
    
    # Create a custom session that resolves picaapi.picacomic.com to the given IP
    class HostHeaderSSLAdapter(HTTPAdapter):
        def __init__(self, server_ip, *args, **kwargs):
            self.server_ip = server_ip
            super().__init__(*args, **kwargs)
        
        def send(self, request, *args, **kwargs):
            # Replace the hostname with IP in the URL but keep Host header
            from urllib.parse import urlparse, urlunparse
            parsed = urlparse(request.url)
            # Replace host with IP
            new_netloc = self.server_ip
            if parsed.port:
                new_netloc = f"{self.server_ip}:{parsed.port}"
            new_url = urlunparse((parsed.scheme, new_netloc, parsed.path, parsed.params, parsed.query, parsed.fragment))
            request.url = new_url
            return super().send(request, *args, **kwargs)
    
    url = f"{BASE_URL}/{path}"
    
    timestamp = str(int(time.time()))
    nonce = str(uuid.uuid4()).replace('-', '')
    signature = generate_signature(path, "GET", timestamp, nonce)
    
    headers = {
        "Host": "picaapi.picacomic.com",  # Important: keep the original host
        "api-key": API_KEY,
        "app-channel": "2",
        "app-version": "2.2.1.3.3.4",
        "app-uuid": "defaultUuid",
        "app-platform": "android",
        "app-build-version": "44",
        "accept": "application/vnd.picacomic.com.v1+json",
        "Content-Type": "application/json; charset=UTF-8",
        "User-Agent": "okhttp/3.8.1",
        "image-quality": "original",
        "time": timestamp,
        "nonce": nonce,
        "signature": signature,
        "authorization": token
    }
    
    params = {
        "page": 1,
        "s": "dd"
    }
    
    try:
        session = requests.Session()
        adapter = HostHeaderSSLAdapter(server_ip)
        session.mount('https://', adapter)
        
        response = session.get(url, params=params, headers=headers, verify=False)
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"Response keys: {data.keys()}")
            if "data" in data:
                docs = data.get("data", {}).get("comics", {}).get("docs", [])
                print(f"Found {len(docs)} comics!")
                for doc in docs[:3]:
                    print(f"  - {doc.get('title')} (Author: {doc.get('author')})")
            else:
                print(f"Response: {json.dumps(data, indent=2)[:500]}")
        else:
            print(f"Failed: {response.text[:500]}")
    except Exception as e:
        import traceback
        print(f"Error: {e}")
        traceback.print_exc()

if __name__ == "__main__":
    # Credentials from logs
    USERNAME = ""
    PASSWORD = ""
    
    token = login(USERNAME, PASSWORD)
    if token:
        print("\n" + "="*50)
        print("Testing PicaComic API Endpoints")
        print("="*50)
        
        # Test user profile
        get_user_profile(token)
        
        # Test favourites
        print("\n" + "="*50)
        print("Testing Favourites API")
        print("="*50)
        get_favourites(token)
        
        # Test leaderboard
        print("\n" + "="*50)
        print("Testing Leaderboard API")
        print("="*50)
        get_leaderboard(token, "H24")
        
        # Test comics with filter
        print("\n" + "="*50)
        print("Testing Comics Filter API")
        print("="*50)
        get_comics(token)
        
        # Test my comments (as a potential history source)
        print("\n" + "="*50)
        print("Testing My Comments API")
        print("="*50)
        get_my_comments(token)
