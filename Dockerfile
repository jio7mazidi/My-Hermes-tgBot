FROM python:3.11-slim

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

WORKDIR /code

# دانلود سورس‌کد
RUN git clone https://github.com/NousResearch/Hermes-Agent.git .

# نصب پیش‌نیازها
RUN pip install --no-cache-dir -e .

# ۱. جراحی سورس برای روت مستقیم به آی‌پی تلگرام و افزایش تایم‌اوت
RUN cat << 'EOF' > patch.py
import os
for r, d, fs in os.walk('/code'):
    for f in fs:
        if f.endswith('.py'):
            p = os.path.join(r, f)
            try:
                txt = open(p, 'r', errors='ignore').read()
                # روت مستقیم به آی‌پی تلگرام
                if 'api.telegram.org' in txt:
                    txt = txt.replace('api.telegram.org', '149.154.167.220')
                # افزایش تایم‌اوت برای جلوگیری از قطع اتصال در هاست‌های ابری
                txt = txt.replace('connect_timeout=5', 'connect_timeout=30').replace('read_timeout=5', 'read_timeout=30')
                open(p, 'w').write(txt)
            except: pass
EOF
RUN python3 patch.py && rm patch.py

# ۲. تزریق لایه محافظ SSL (غیرفعال‌سازی بررسی گواهی)
RUN cat << 'EOF' > /code/sitecustomize.py
import httpx, ssl
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

old_async = httpx.AsyncClient.send
old_sync = httpx.Client.send

async def new_async(self, req, *a, **k):
    if req.url.host == '149.154.167.220':
        req.headers['host'] = 'api.telegram.org'
    self.verify = ctx
    return await old_async(self, req, *a, **k)

def new_sync(self, req, *a, **k):
    if req.url.host == '149.154.167.220':
        req.headers['host'] = 'api.telegram.org'
    self.verify = ctx
    return old_sync(self, req, *a, **k)

httpx.AsyncClient.send = new_async
httpx.Client.send = new_sync
EOF

# تنظیمات محیطی
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/code
ENV GATEWAY_ALLOW_ALL_USERS=true

# اجرای همزمان ربات و سرور بیدارباش (Keep-alive) برای Render
CMD hermes gateway run & python3 -c "from http.server import HTTPServer, BaseHTTPRequestHandler; \
class H(BaseHTTPRequestHandler): \
    def do_GET(self): \
        self.send_response(200); self.end_headers(); self.wfile.write(b'OK') \
HTTPServer(('0.0.0.0', 7860), H).serve_forever()"
