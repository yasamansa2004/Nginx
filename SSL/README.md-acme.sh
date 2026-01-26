
🔹 What is acme.sh (1-liner)

```
acme.sh is a lightweight Let’s Encrypt client written in shell that:
```
Doesn’t need root

Supports DNS / HTTP / Nginx modes

Is perfect for servers, Docker, Nginx, HAProxy

1️⃣ Install acme.sh

Run as normal user (recommended):
```
curl https://get.acme.sh | sh
```

Then load it:
```
source ~/.bashrc
```

Verify:
```
acme.sh --version
```

👉 It installs to:
```
~/.acme.sh/
```
2️⃣ Choose your validation method

You must choose ONE of these:

Method	When to use
--nginx	You already have Nginx
--webroot	Custom webroot / Docker
--dns	No public port 80 / wildcard cert

I’ll show nginx (most common) + dns (wildcard).

✅ Method A: Nginx mode (EASIEST)

✔ Auto edits nginx config
✔ No downtime

Issue certificate
```
acme.sh --issue \
  --nginx \
  -d example.com \
  -d www.example.com
```

If Nginx config is valid → cert issued 🎉

Install cert (IMPORTANT)
acme.sh does not auto-install certs.
```
acme.sh --install-cert -d example.com \
  --key-file       /etc/nginx/ssl/example.com.key \
  --fullchain-file /etc/nginx/ssl/example.com.crt \
  --reloadcmd     "systemctl reload nginx"
```

👉 Now update your nginx:
```
ssl_certificate     /etc/nginx/ssl/example.com.crt;
ssl_certificate_key /etc/nginx/ssl/example.com.key;
```
✅ Method B: DNS mode (Wildcard cert ⭐)

Best for:
```
*.example.com
```
No open port 80

Kubernetes / internal services

Example: Cloudflare
```
export CF_Token="xxxxxxxx"
export CF_Account_ID="xxxx"
```

Issue wildcard:
```
acme.sh --issue \
  --dns dns_cf \
  -d example.com \
  -d '*.example.com'
```

📌 DNS creds are saved securely in:
```
~/.acme.sh/account.conf
```
3️⃣ Auto-renew (already handled ✅)

acme.sh installs cron automatically:
```
crontab -l
```

Renew test:
```
acme.sh --renew -d example.com --force
```
4️⃣ Switch to Let’s Encrypt PROD (important!)

Default is staging (fake cert).
```
acme.sh --set-default-ca --server letsencrypt
```

Re-issue:
```
acme.sh --issue --nginx -d example.com
```
5️⃣ Debugging (when things break 😅)
```
acme.sh --issue --nginx -d example.com --debug 2
```

Logs:
```
~/.acme.sh/acme.sh.log
```




```
./acme.sh  --issue --dns dns_arvan --keylength 4096 -d beroozresaan.com -d *.beroozresaan.com --server zerossl --dnssleep 20 --force
```
