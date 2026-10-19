# Connectteb.com — Nginx Landing Page and WordPress Routing

## 1. Project Overview

This document explains the Nginx configuration for `connectteb.com`, including:

- Serving the main landing page from our own server.
- Serving WordPress under `/blog/`.
- Forwarding WordPress API requests.
- Redirecting old WordPress article URLs to their new `/blog/` URLs.
- Fixing the Nginx `map_hash_bucket_size` error.
- Testing the configuration and troubleshooting common problems.

The instructions are based on the configuration and command outputs discussed during troubleshooting.

> **Important:** this README documents the intended solution based on the troubleshooting history. It does not prove that every change is already present on the server. First verify the active site configuration and test the generated map, then apply the steps in order.

---

## 2. Current Architecture

### 2.1. Nginx server

The Nginx server discussed in this setup is `rt-nginx1`.

| Item | Path |
|------|------|
| Main configuration file | `/etc/nginx/nginx.conf` |
| Site configurations | `/etc/nginx/sites-available/` |
| Enabled sites | `/etc/nginx/sites-enabled/` |

The exact site configuration filename must be verified on the server.

### 2.2. Backend services

The upstream definitions previously shared were:

```nginx
upstream gateway {
    server 192.168.178.36:8080;
}

upstream web {
    server 192.168.178.36:9090;
}

upstream landing {
    server 192.168.178.36:3000;
}

upstream wordpress_origin {
    server 194.5.195.189:443;
}
```

These upstreams point to the following services:

| Upstream | Address | Purpose |
|----------|---------|---------|
| `gateway` | `192.168.178.36:8080` | Application gateway |
| `web` | `192.168.178.36:9090` | Existing web service |
| `landing` | `192.168.178.36:3000` | Landing frontend |
| `wordpress_origin` | `194.5.195.189:443` | WordPress origin |

These are the upstream definitions from the troubleshooting history. Do not replace existing upstreams without first checking the current configuration.

### 2.3. Expected URL routing

| URL | Expected destination |
|-----|----------------------|
| `https://connectteb.com/` | Landing page |
| `https://connectteb.com/blog/` | WordPress |
| `https://connectteb.com/blog/article-slug/` | WordPress article |
| `https://connectteb.com/wp-json/` | WordPress REST API |
| `https://connectteb.com/wp-admin/` | WordPress administration |
| `https://connectteb.com/wp-login.php` | WordPress login |
| `https://connectteb.com/about-us` | Existing configured route |
| `https://connectteb.com/contact-us` | Existing configured route |
| `https://connectteb.com/faq` | Existing configured route |
| `https://connectteb.com/privacy` | Existing configured route |

The exact routing behavior for the individual pages depends on the existing Nginx locations.

---

## 3. Problem Description

Previously, WordPress articles were accessible using URLs such as:

```text
https://connectteb.com/article-slug/
```

After moving WordPress under `/blog/`, the new URLs became:

```text
https://connectteb.com/blog/article-slug/
```

For example:

Old URL:

```text
https://connectteb.com/علت-ریزش-مو-بعد-کرونا/
```

New URL:

```text
https://connectteb.com/blog/علت-ریزش-مو-بعد-کرونا/
```

The new URL was returning HTTP 200 during troubleshooting, while the old URL needed to be redirected. Google may still have indexed the old URLs.

The desired behavior is:

```text
Old WordPress URL
        |
        v
Nginx checks the old URL
        |
        v
URL exists in the legacy redirect map
        |
        v
HTTP 301 redirect
        |
        v
New WordPress URL under /blog/
```

Example:

```text
https://connectteb.com/علت-ریزش-مو-بعد-کرونا/
                         |
                         | HTTP 301
                         v
https://connectteb.com/blog/علت-ریزش-مو-بعد-کرونا/
```

The goal is to redirect known old article URLs **without** redirecting every unknown URL to WordPress.

---

## 4. Troubleshooting Findings

### 4.1. The new article URL works

During troubleshooting, the following command returned HTTP 200:

```bash
curl -sS -D - -o /dev/null \
'https://connectteb.com/blog/علت-ریزش-مو-بعد-کرونا/'
```

This indicated that the new article URL was accessible at that time.

### 4.2. The landing frontend returns HTTP 200 for unknown paths

The following command was used to test the landing frontend:

```bash
curl -i \
'http://192.168.178.36:3000/this-page-should-not-exist-12345'
```

The frontend returned HTTP 200 for an unknown path.

This matters because an Nginx configuration based only on HTTP 404 responses cannot reliably identify old WordPress articles. For example, this approach is not sufficient by itself:

```nginx
error_page 404 = @wordpress_fallback;
```

If the landing application returns HTTP 200 for an unknown path, Nginx does not see a 404 to trigger the fallback.

### 4.3. The WordPress REST API is accessible

The following command was used to query WordPress:

```bash
curl -sS \
--resolve connectteb.com:443:194.5.195.189 \
'https://connectteb.com/wp-json/wp/v2/posts?per_page=5&_fields=slug,link'
```

The response contained article slugs and links. This provides a way to generate a redirect map automatically rather than manually configuring hundreds of article URLs.

The `--resolve` option forces this particular request to connect to `194.5.195.189` for `connectteb.com`, while retaining the hostname for HTTPS.

This test confirms API access through that route at the time of the test. It does not, by itself, confirm that every future API request will succeed.

---

## 5. Step 1 — Identify the Active Nginx Configuration

Before editing files, identify the configuration currently being used.

```bash
sudo nginx -T 2>&1 | less
```

Search inside the output for:

- `server_name connectteb.com`
- `wordpress_origin`
- `legacy_blog_redirect`

The `nginx -T` command displays the effective configuration, including files loaded through `include` directives. Press `q` to exit `less`.

List the site configuration files:

```bash
sudo ls -l /etc/nginx/sites-available/
sudo ls -l /etc/nginx/sites-enabled/
```

Identify the file containing the HTTPS server block for `connectteb.com`. Do not assume that the filename is `connectteb.com.conf`; use the filename found on the actual server.

Before editing, create backups. To back up the main configuration:

```bash
sudo cp -a \
/etc/nginx/nginx.conf \
/etc/nginx/nginx.conf.backup-$(date +%Y%m%d-%H%M%S)
```

Back up the active site configuration as well, replacing `ACTUAL_SITE_FILE` with its actual filename:

```bash
sudo cp -a \
/etc/nginx/sites-available/ACTUAL_SITE_FILE \
/etc/nginx/sites-available/ACTUAL_SITE_FILE.backup-$(date +%Y%m%d-%H%M%S)
```

---

## 6. Step 2 — Create the Redirect Map Directory

```bash
sudo mkdir -p /etc/nginx/maps
```

The intended output file is:

```text
/etc/nginx/maps/wordpress-legacy-redirects.map
```

This file contains mappings from old article paths to new article paths. For example:

```nginx
"/old-article" "/blog/old-article/";
"/old-article/" "/blog/old-article/";
```

The actual map will contain the article slugs retrieved from WordPress. Do not manually enter hundreds of article URLs.

---

## 7. Step 3 — Create the Redirect Generator

Create the Python script:

```bash
sudo nano /usr/local/bin/generate-wordpress-redirects.py
```

Paste the following code into the file:

```python
#!/usr/bin/env python3
"""Generate an Nginx map of legacy WordPress article URLs."""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API_URL = "https://connectteb.com/wp-json/wp/v2/posts"
OUTPUT = Path("/etc/nginx/maps/wordpress-legacy-redirects.map")
PER_PAGE = 100
TIMEOUT = 30

redirects = {}
page = 1

while True:
    query = urllib.parse.urlencode({
        "per_page": PER_PAGE,
        "page": page,
        "_fields": "slug",
    })
    request = urllib.request.Request(
        f"{API_URL}?{query}",
        headers={"User-Agent": "connectteb-redirect-generator/1.0"},
    )

    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            total_pages = int(response.headers.get("X-WP-TotalPages", "1"))
            posts = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, ValueError) as error:
        print(f"API request failed on page {page}: {error}", file=sys.stderr)
        sys.exit(1)

    for post in posts:
        slug = urllib.parse.unquote(post.get("slug", ""))

        if (
            not slug
            or "/" in slug
            or "\\" in slug
        ):
            continue

        old_path = "/" + slug
        new_path = "/blog/" + slug + "/"

        redirects[old_path] = new_path
        redirects[old_path + "/"] = new_path

    print(
        f"Processed page {page}/{total_pages} "
        f"- {len(redirects)} redirect entries"
    )

    if page >= total_pages or not posts:
        break

    page += 1


def nginx_quote(value):
    value = value.replace("\\", "\\\\")
    value = value.replace('"', '\\"')
    return f'"{value}"'


OUTPUT.parent.mkdir(
    parents=True,
    exist_ok=True
)

temporary_output = OUTPUT.with_suffix(".map.tmp")

with temporary_output.open(
    "w",
    encoding="utf-8"
) as file:
    for old_path, new_path in sorted(
        redirects.items()
    ):
        file.write(
            f"{nginx_quote(old_path)} "
            f"{nginx_quote(new_path)};\n"
        )

temporary_output.replace(OUTPUT)

print(
    f"Finished. Generated {len(redirects)} "
    f"redirect entries in {OUTPUT}"
)
```

Save the file:

1. Press `Ctrl + O`.
2. Press `Enter`.
3. Press `Ctrl + X`.

Make the script executable:

```bash
sudo chmod +x /usr/local/bin/generate-wordpress-redirects.py
```

### How the script works

The script:

1. Requests up to 100 published WordPress posts per API page.
2. Reads each post's slug.
3. Decodes percent-encoded slug text.
4. Creates a mapping for the old URL with and without a trailing slash.
5. Writes the mappings to the output file.
6. Replaces the previous output file after generating the new one.

The script does **not** reload Nginx automatically. This is intentional: the generated map must be checked and the Nginx configuration tested before reloading the service.

### Scope limitation

The script uses `/wp-json/wp/v2/posts`, so it covers only posts returned by that endpoint. It does not automatically include ordinary WordPress pages or custom post types. If those also have old root-level URLs, they must be handled separately.

---

## 8. Step 4 — Generate the Map

```bash
sudo /usr/local/bin/generate-wordpress-redirects.py
```

Successful output should resemble:

```text
Processed page 1/5 - 200 redirect entries
Processed page 2/5 - 400 redirect entries
Finished. Generated ... redirect entries in /etc/nginx/maps/wordpress-legacy-redirects.map
```

These numbers are examples. The actual number depends on the number of published posts.

Check that the file exists:

```bash
sudo ls -lh /etc/nginx/maps/wordpress-legacy-redirects.map
```

Inspect the first entries:

```bash
sudo head -n 10 /etc/nginx/maps/wordpress-legacy-redirects.map
```

Search for the article discussed during troubleshooting:

```bash
sudo grep -F 'علت-ریزش-مو-بعد-کرونا' \
/etc/nginx/maps/wordpress-legacy-redirects.map
```

If the expected article does not appear, do not continue as if the map were complete. Check the API response and the script output first.

---

## 9. Step 5 — Configure the Nginx Map

```bash
sudo nano /etc/nginx/nginx.conf
```

Find the existing `http { ... }` block. The `map` directive must be inside the `http` block, not inside a `server` or `location` block.

The intended configuration is:

```nginx
map $uri $legacy_blog_redirect {
    default "";
    include /etc/nginx/maps/wordpress-legacy-redirects.map;
}
```

If this map already exists, do not add a duplicate. Check that the included file path matches the actual generated file.

The map uses `$uri`, which is Nginx's normalized URI path. This is why the script decodes the percent-encoded WordPress slugs before writing the map.

---

## 10. Step 6 — Fix the `map_hash_bucket_size` Error

During troubleshooting, the following command failed:

```bash
sudo nginx -t
```

The error was:

```text
nginx: [emerg] could not build map_hash,
you should increase map_hash_bucket_size: 64
```

This means Nginx could not build the hash table for the configured map with the current bucket size.

### 10.1. Add the hash directives

Inside the existing `http { ... }` block, add:

```nginx
map_hash_bucket_size 128;
map_hash_max_size 65536;
```

For example:

```nginx
http {

    map_hash_bucket_size 128;
    map_hash_max_size 65536;

    map $uri $legacy_blog_redirect {
        default "";
        include /etc/nginx/maps/wordpress-legacy-redirects.map;
    }

    # Keep the other existing HTTP configuration here.
}
```

This is an example of the relevant section, not a replacement for the complete configuration file. Do not delete the existing settings inside `http`. If either hash directive already exists, edit the existing directive rather than adding a duplicate.

### 10.2. Save the file

In nano:

1. Press `Ctrl + O`.
2. Press `Enter`.
3. Press `Ctrl + X`.

### 10.3. Test the configuration

```bash
sudo nginx -t
```

If the test succeeds, the output should include:

```text
syntax is ok
test is successful
```

If the same bucket-size error persists, try:

```nginx
map_hash_bucket_size 256;
```

Then test again with `sudo nginx -t`. Do not reload Nginx until the configuration test succeeds.

---

## 11. Step 7 — Add the Redirect Rule to the HTTPS Server

Find the existing HTTPS server block for `server_name connectteb.com;` in the site configuration file identified in Step 1:

```bash
sudo nano /etc/nginx/sites-available/ACTUAL_SITE_FILE
```

Replace `ACTUAL_SITE_FILE` with the actual filename.

Inside the HTTPS server block, add this rule **before** the general `location /` block:

```nginx
if ($legacy_blog_redirect != "") {
    return 301 https://connectteb.com$legacy_blog_redirect$is_args$args;
}
```

Do not put this rule inside `location /blog/`.

### What this rule does

For a known old article URL, Nginx finds the corresponding entry in the map and returns HTTP 301. For example:

```text
Old URL:
/علت-ریزش-مو-بعد-کرونا/

Mapped destination:
/blog/علت-ریزش-مو-بعد-کرونا/
```

The response becomes:

```text
HTTP 301
Location: https://connectteb.com/blog/علت-ریزش-مو-بعد-کرونا/
```

The variables `$is_args$args` preserve the original query string when one exists. For example, `/old-article/?utm_source=google` will retain the query string in the redirect.

### Important routing considerations

- Keep the existing upstreams.
- Keep the existing WordPress proxy locations.
- Keep the existing landing configuration.
- Do not duplicate the redirect rule if it already exists.
- Confirm that the rule is inside the correct HTTPS server block.
- Test the complete configuration before reloading.

The map contains only the old article paths generated by the script. An unknown path will not match an article entry and will continue through the existing Nginx routing rules.

---

## 12. Step 8 — Validate and Reload Nginx

```bash
sudo nginx -t
```

Do not proceed if this command fails. If the test succeeds, reload Nginx:

```bash
sudo systemctl reload nginx
```

Check the service status:

```bash
sudo systemctl status nginx --no-pager
```

A successful reload means Nginx has accepted the new configuration. It does not yet prove that every redirect works, so the URL tests below are still required.

---

## 13. Step 9 — Test the Old and New URLs

### 13.1. Old URL with a trailing slash

```bash
curl -sS -D - -o /dev/null \
'https://connectteb.com/علت-ریزش-مو-بعد-کرونا/'
```

Expected behavior:

```text
HTTP/2 301
location: https://connectteb.com/blog/علت-ریزش-مو-بعد-کرونا/
```

The exact HTTP version and header capitalization may differ. The important results are:

- The response is a permanent redirect.
- The `Location` header points to the correct new URL.

### 13.2. Old URL without a trailing slash

```bash
curl -sS -D - -o /dev/null \
'https://connectteb.com/علت-ریزش-مو-بعد-کرونا'
```

This should also redirect to the corresponding `/blog/` URL.

### 13.3. New URL

```bash
curl -sS -D - -o /dev/null \
'https://connectteb.com/blog/علت-ریزش-مو-بعد-کرونا/'
```

Expected result: `HTTP/2 200`.

### 13.4. Root page

```bash
curl -sS -D - -o /dev/null 'https://connectteb.com/'
```

Confirm that the landing page still behaves as expected.

### 13.5. WordPress blog

```bash
curl -sS -D - -o /dev/null 'https://connectteb.com/blog/'
```

Confirm that the WordPress blog remains accessible.

### 13.6. WordPress REST API

```bash
curl -sS -D - -o /dev/null \
'https://connectteb.com/wp-json/wp/v2/posts?per_page=1'
```

Confirm that the API remains accessible. These tests should be performed after the configuration is reloaded.

---

## 14. Step 10 — Update the Redirect Map

Whenever the published post list changes, regenerate the map:

```bash
sudo /usr/local/bin/generate-wordpress-redirects.py
```

Inspect the result:

```bash
sudo head -n 10 /etc/nginx/maps/wordpress-legacy-redirects.map
```

Check a particular article (replace `article-slug` with the actual slug):

```bash
sudo grep -F 'article-slug' \
/etc/nginx/maps/wordpress-legacy-redirects.map
```

If the map has changed, validate and reload:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Only run the reload if the test succeeds.

> **Important:** the script replaces the generated map file. Do not add manual mappings directly to that file unless you are comfortable recreating them after every script execution. If manual mappings are needed, keep them in a separate file and include that file in the Nginx map configuration.

---

## 15. Troubleshooting

### Problem A — `could not build map_hash`

Error:

```text
could not build map_hash, you should increase map_hash_bucket_size: 64
```

Check that the existing `http` block contains:

```nginx
map_hash_bucket_size 128;
map_hash_max_size 65536;
```

If necessary, try `map_hash_bucket_size 256;`, then run `sudo nginx -t`.

### Problem B — `nginx -t` reports a syntax error

Read the complete error message, including the filename and line number, and inspect the relevant lines in that file. Do not reload Nginx until the test succeeds.

### Problem C — The old URL still returns HTTP 404

Check whether the URL exists in the map (replace `article-slug` with the real slug):

```bash
sudo grep -F 'article-slug' \
/etc/nginx/maps/wordpress-legacy-redirects.map
```

If the entry is missing, regenerate the map and check the API response.

If the entry exists, check:

1. The map is included in the active Nginx configuration.
2. The redirect rule is inside the correct HTTPS server block.
3. The configuration test succeeds.
4. Nginx has been reloaded.
5. The tested hostname resolves to the expected Nginx server.

### Problem D — The redirect points to the wrong URL

Inspect the generated mapping with `grep -F 'article-slug'` as above. Check whether the destination contains `/blog/` and the expected slug. Also check whether another redirect rule is affecting the same URL.

### Problem E — The redirect rule does not run

Inspect the effective configuration:

```bash
sudo nginx -T 2>&1 | less
```

Search for `legacy_blog_redirect` and confirm that:

- The `map` directive is loaded inside `http`.
- The HTTPS server block contains the redirect rule.
- The map file exists.
- The article path appears in the map.

### Problem F — The API script fails

Run the API test separately:

```bash
curl -sS -D - \
'https://connectteb.com/wp-json/wp/v2/posts?per_page=1&_fields=slug,link'
```

Check the HTTP response and the returned JSON. The generator depends on the WordPress REST API being accessible and returning the expected pagination headers. Do not assume the map was refreshed if the script failed.

### Problem G — The landing page breaks after the change

Check the active configuration with `sudo nginx -T 2>&1 | less` and verify that the redirect rule was added only to the intended HTTPS server block. The redirect rule should only redirect paths found in the map. The existing landing and WordPress routing rules should remain in place.

---

## 16. Rollback Procedure

If the new redirect behavior causes a problem, remove the redirect `if` block from the HTTPS server configuration:

```nginx
if ($legacy_blog_redirect != "") {
    return 301 https://connectteb.com$legacy_blog_redirect$is_args$args;
}
```

Keep the other routing rules unchanged. Then run:

```bash
sudo nginx -t
```

If the test succeeds:

```bash
sudo systemctl reload nginx
```

This disables the new redirect behavior while retaining the existing landing and WordPress routing.

If you also added hash directives solely for this map, review whether they can be removed. Do not remove them if other maps depend on them.

---

## 17. Final Checklist

### Configuration

- [ ] The active site configuration has been identified.
- [ ] Backups of the relevant configuration files have been created.
- [ ] `/etc/nginx/maps/` exists.
- [ ] The redirect generator exists.
- [ ] The generated map file exists.
- [ ] The expected article slug appears in the map.
- [ ] The map is included in the existing `http` block.
- [ ] The hash directives are configured without duplicates.
- [ ] The redirect rule is in the correct HTTPS server block.

### Validation

- [ ] `sudo nginx -t` succeeds.
- [ ] Nginx has been reloaded.
- [ ] The old article URL returns HTTP 301.
- [ ] The redirect points to the correct `/blog/` URL.
- [ ] The new article URL returns HTTP 200.
- [ ] The landing page still works.
- [ ] The WordPress blog still works.
- [ ] The WordPress REST API still works.

---

## 18. Final Architecture

The intended request flow is:

```text
                         User / Google
                               |
                               v
                     https://connectteb.com
                               |
                               v
                             Nginx
                               |
               +---------------+----------------+
               |                                |
               v                                v
     Known legacy article URL             Other request
               |                                |
               v                                v
      Legacy redirect map               Existing routing
               |                                |
               v                    +-----------+-----------+
          HTTP 301                  |                       |
               |                    v                       v
               v                  Landing                WordPress
       /blog/article-slug/       :3000 or              under /blog/
                                 configured              and API
                                 upstreams
```

The diagram shows the intended routing logic. The actual landing and WordPress destinations remain determined by the active Nginx configuration.

The main purpose of this change is to preserve old WordPress article URLs through permanent redirects while keeping the landing page and WordPress routing intact.
