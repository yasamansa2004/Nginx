# Nginx: Finding Where `ssl_protocols` Is Defined (Step by Step)

A simple guide for learning how to track down TLS settings in Nginx when they are **not** in `nginx.conf`, and how to think about supporting very old clients (like Android 3).

---

## 1. The Problem

You opened `/etc/nginx/nginx.conf` and searched for `ssl_protocols`, but you found nothing.
You also ran:

```bash
sudo grep -RniE 'ssl_protocols|ssl_ciphers|ssl_prefer_server_ciphers' /etc/nginx/
```

and the result was **empty**.

But `nginx -T` clearly shows this active setting:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

So where is it coming from?

---

## 2. Key Idea: Nginx Can Load Many Files

Your `nginx.conf` ends with this line:

```nginx
include /etc/nginx/conf.d/*.conf;
```

`include` tells Nginx: "Load all these other files as if they were written here."

So the real configuration is a **combination** of many files:

```
/etc/nginx/nginx.conf
   └── includes /etc/nginx/conf.d/*.conf
          └── each file may include more files (for example, a Certbot file)
```

A setting can hide in any file in this chain, **even outside `/etc/nginx/`**.

---

## 3. Clue From Your Output

Around line 371 of the `nginx -T` output you saw this comment:

```
# This file contains important security parameters. If you modify this file
# manually, Certbot will be unable to automatically provide future security updates...
```

This means:

- The settings come from a **Certbot** (Let's Encrypt) options file.
- Certbot normally stores it at: `/etc/letsencrypt/options-ssl-nginx.conf`
- That is **outside** `/etc/nginx/`, which is why your first `grep` found nothing.

> The file is probably `/etc/letsencrypt/options-ssl-nginx.conf`, but always confirm it (Step 4.1 below).

---

## 4. Step-by-Step Instructions

### Step 4.1 – Find the exact file that holds the TLS settings

**Option A:** Search a wider area (include `/etc/letsencrypt`):

```bash
sudo grep -RniE 'ssl_protocols|ssl_ciphers|ssl_prefer_server_ciphers' /etc/nginx /etc/letsencrypt 2>/dev/null
```

**Option B:** Ask Nginx itself. `nginx -T` prints a header before every file:

```bash
sudo nginx -T 2>&1 | sed -n '350,390p'
```

Look for a line like:

```
# configuration file /etc/letsencrypt/options-ssl-nginx.conf:
```

The header **right above** the `ssl_protocols` line is the file you want.

### Step 4.2 – Find which site loads that file

```bash
sudo grep -Rn 'options-ssl-nginx.conf' /etc/nginx/
```

This shows which `server { ... }` blocks contain a line like:

```nginx
include /etc/letsencrypt/options-ssl-nginx.conf;
```

### Step 4.3 – Find the configuration of the driver site

Find the file:

```bash
sudo grep -Rl 'server_name driver.beroozresaan.com' /etc/nginx/
```

Show the block (replace `FILE_PATH` with the result):

```bash
sudo grep -n -B 10 -A 35 'server_name driver.beroozresaan.com' FILE_PATH
```

Or, without knowing the file:

```bash
sudo nginx -T 2>&1 | grep -n -B 5 -A 18 'server_name driver.beroozresaan.com'
```

Check these things in the output:

| Look for | Why it matters |
|---|---|
| `listen ...` | Which IP and port the site uses |
| `ssl_certificate ...` | Which certificate is served |
| `include .../options-ssl-nginx.conf` | Whether the Certbot TLS rules apply |

---

## 5. Why Android 3 Is Hard

Your current setting allows only:

```nginx
ssl_protocols TLSv1.2 TLSv1.3;
```

Android 3 is extremely old. Three things must all work, not just one:

1. **TLS version**: the old device may only speak TLS 1.0.
2. **Cipher suites**: your list contains only modern ciphers (`ECDHE-...-GCM`, `CHACHA20`) that Android 3 does not know.
3. **Certificate trust**: the device may not trust the modern certificate authority that signed your certificate.

> Enabling TLS 1.0 **alone** will not fix it. All three must be compatible.

---

## 6. Do NOT Do This

Do **not** simply add this to `nginx.conf` or to the Certbot file:

```nginx
ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;   # BAD idea globally
```

Reasons:

- It affects **every HTTPS site** on this server (for example `countly.beroozresaan.com`).
- TLS 1.0 is obsolete and insecure.
- Editing the Certbot file may be overwritten on updates.

---

## 7. Safer Approach: Isolate the Legacy Endpoint

Give the old devices their **own** endpoint, so other services stay secure.

### Options

- **A separate IP address** with its own `server` block (best).
- **A separate port** (for example `8443`) with its own `server` block.

> Nginx note: on the same IP and port, the TLS protocol settings of the **default** server are usually used for all sites. This is why a different IP or port is often needed.

### Example idea (legacy server block)

```nginx
server {
    listen 192.0.2.10:443 ssl;          # a dedicated IP (example value)
    server_name driver.beroozresaan.com;

    ssl_certificate     /home/support/.acme.sh/api.beroozresaan.com/fullchain.crt;
    ssl_certificate_key /home/support/.acme.sh/api.beroozresaan.com/api.beroozresaan.com.key;

    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers   "HIGH:!aNULL:!MD5:@SECLEVEL=0";   # allows older ciphers; weaker!

    # ... your existing location / proxy settings ...
}
```

Notes:

- `@SECLEVEL=0` is often needed because modern OpenSSL blocks TLS 1.0 by default.
- Do **not** include the Certbot options file in this block, because it would override your legacy settings.
- This is only an example. Confirm with the real output of Step 4 first.

---

## 8. Safe Change Procedure (Always Follow)

```bash
# 1. Back up before editing
sudo cp -a /etc/nginx /etc/nginx.backup-$(date +%F)

# 2. Edit the file
sudo nano /path/to/file.conf

# 3. Test the syntax (must say "syntax is ok" and "test is successful")
sudo nginx -t

# 4. Apply without downtime
sudo systemctl reload nginx
```

If `nginx -t` shows an error, **do not reload**. Fix it or restore the backup.

---

## 9. Verify From the Outside

Check that a TLS 1.0 handshake works on the legacy endpoint:

```bash
openssl s_client -connect driver.beroozresaan.com:443 -tls1
```

Check that your other sites still refuse old TLS:

```bash
openssl s_client -connect countly.beroozresaan.com:443 -tls1
```

(The second command should **fail**. That means your other services stay secure.)

Note: newer OpenSSL on your own machine may refuse `-tls1`. If so, test from a machine or tool that still supports it.

---

## 10. Quick Cheat Sheet

| Goal | Command |
|---|---|
| Show the full active config | `sudo nginx -T` |
| Test config syntax | `sudo nginx -t` |
| Reload safely | `sudo systemctl reload nginx` |
| Search a setting in config files | `sudo grep -RniE 'setting_name' /etc/nginx /etc/letsencrypt` |
| Find which file a line came from | Look at the `# configuration file ...:` header above it in `nginx -T` |
| Find a site's config | `sudo grep -Rl 'server_name your.domain' /etc/nginx/` |

---

## 11. What You Learned

1. `nginx.conf` is only the **starting point**; `include` pulls in other files.
2. Settings can live **outside** `/etc/nginx/` (for example in `/etc/letsencrypt/`).
3. `nginx -T` is the best tool: it shows the final config **and** the filename of each part.
4. Supporting a very old client needs **three** things: TLS version, ciphers, and certificate trust.
5. Never weaken security globally. **Isolate** legacy support on a separate IP or port.
6. Always: **backup, edit, `nginx -t`, reload, test**.

---

## 12. Next Step

Run the commands in **Step 4**, then check:

- the file containing `ssl_protocols`
- the `driver.beroozresaan.com` server block (`listen`, certificate, includes)

With that output you can decide exactly where to place the legacy configuration.
