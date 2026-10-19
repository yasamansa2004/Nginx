# Special Scenario: Serve a Landing Page and Selected WordPress Pages on One Domain

## 1. Scenario

**Goal:** Serve a custom landing application from the company server
while keeping the existing WordPress website hosted by ParsPack. Both
applications must remain accessible through the same public domain,
`connectteb.com`, without exposing a separate WordPress subdomain or
changing the public URLs.

This is a path-based reverse-proxy scenario.

-   The landing application is served from the company infrastructure.
-   WordPress remains hosted on ParsPack.
-   Nginx is the single public HTTPS entry point.
-   Nginx routes requests to the correct upstream according to the
    requested path.
-   The browser continues to use `https://connectteb.com/...` for both
    applications.

> **Important:** This README documents the intended routing design and
> operational procedure. Validate the actual WordPress origin response
> and the final Nginx configuration in your environment before
> considering the migration complete.

## 2. Target Architecture

``` text
                             Browser
                                |
                                | HTTPS :443
                                v
                    connectteb.com DNS record
                                |
                                v
                     Company Nginx reverse proxy
                         (TLS termination)
                                |
                +---------------+----------------+
                |                                |
        Landing/default paths             Selected WordPress paths
                |                                |
                v                                v
     Landing: 192.168.178.36:3000      ParsPack origin: 194.5.195.189:443
                                               |
                                               v
                                      Existing WordPress site
```

### Upstreams

  -----------------------------------------------------------------------
  Name                    Destination             Purpose
  ----------------------- ----------------------- -----------------------
  `landing`               `192.168.178.36:3000`   Landing frontend

  `gateway`               `192.168.178.36:8080`   Existing API upstream;
                                                  separate virtual host

  `web`                   `192.168.178.36:9090`   Existing web service;
                                                  separate virtual host

  `wordpress_origin`      `194.5.195.189:443`     WordPress hosted by
                                                  ParsPack
  -----------------------------------------------------------------------

Use the **origin IP** for `wordpress_origin`, not `connectteb.com`. Once
DNS points to the company Nginx server, using `connectteb.com` as the
proxy destination can send the request back to the same Nginx server and
create a proxy loop.

The origin IP above comes from this scenario. Confirm with the hosting
provider that it is still the correct origin IP before deployment.

## 3. Required Routing Behavior

The following routes are intended to go to WordPress:

  Public URL/path                  Destination
  -------------------------------- -----------------------------
  `/blog/` and `/blog/*`           ParsPack WordPress
  `/about-us/`                     ParsPack WordPress
  `/contact-us/`                   ParsPack WordPress
  `/حریم-خصوصی/`                   ParsPack WordPress
  `/سوالات-متداول/`                ParsPack WordPress
  `/wp-admin/` and `/wp-admin/*`   ParsPack WordPress
  `/wp-login.php`                  ParsPack WordPress
  `/wp-content/*`                  ParsPack WordPress assets
  `/wp-includes/*`                 ParsPack WordPress assets
  `/wp-json/*`                     ParsPack WordPress REST API

All other paths should go to the landing application.

The two Persian slugs above correspond to the URL-encoded paths:

-   `/%d8%ad%d8%b1%db%8c%d9%85-%d8%ae%d8%b5%d9%88%d8%b5%db%8c/`
-   `/%d8%b3%d9%88%d8%a7%d9%84%d8%a7%d8%aa-%d9%85%d8%aa%d8%af%d8%a7%d9%88%d9%84/`

Nginx generally matches locations against a normalized URI, where
percent-encoded characters are decoded. Test the exact Persian paths
after adding them to the configuration.

## 4. DNS and TLS

### DNS

Point the `connectteb.com` apex (`@`) A record to the public IP of the
company Nginx server. Configure `www` according to the site's intended
canonical-domain policy (for example, a CNAME to the apex).

Do not change unrelated API or application subdomain records unless they
are part of the migration plan.

Before changing DNS, confirm:

1.  The company Nginx server is reachable from the internet on TCP ports
    80 and 443.
2.  The landing application is reachable from Nginx at
    `192.168.178.36:3000`.
3.  The current WordPress origin is reachable from Nginx.
4.  The TLS certificate and private key exist at the paths configured in
    Nginx.

### TLS

The public HTTPS connection terminates at company Nginx. The
Nginx-to-WordPress connection uses HTTPS as well.

The proxy request must preserve the WordPress hostname:

``` nginx
proxy_set_header Host connectteb.com;
proxy_ssl_server_name on;
proxy_ssl_name connectteb.com;
```

`Host` controls the HTTP virtual host selected by the origin.
`proxy_ssl_name` sets the TLS SNI name used when Nginx connects to the
origin.

Do not disable upstream certificate verification just to hide a
certificate problem. If upstream TLS verification fails, first verify
the origin certificate, hostname, CA chain, and whether the origin is
configured for this domain.

## 5. Nginx Configuration

### 5.1 Define upstreams

Place upstream blocks in the `http` context, commonly in
`/etc/nginx/conf.d/` or the main Nginx configuration, depending on the
server layout.

``` nginx
upstream landing {
    server 192.168.178.36:3000;
}

upstream wordpress_origin {
    server 194.5.195.189:443;
    keepalive 16;
}
```

Keep existing `gateway` and `web` upstreams if they are still used by
other virtual hosts. Do not duplicate upstream names that already exist
in the loaded configuration.

### 5.2 Main domain server block

The following is a **focused example** for the main domain. Merge it
carefully into the existing `connectteb.com` server block; do not
replace unrelated virtual hosts for `api.connectteb.com`,
`doctor.connectteb.com`, `patient.connectteb.com`,
`admin.connectteb.com`, or other services.

For compatibility with older Nginx versions, this example uses
`listen 443 ssl http2;`. If your Nginx version uses the newer standalone
HTTP/2 directive, use the syntax supported by that installed version.

``` nginx
server {
    listen 443 ssl http2;
    server_name connectteb.com;

    ssl_certificate     /etc/nginx/ssl/connectteb.com/connectteb.com.crt;
    ssl_certificate_key /etc/nginx/ssl/connectteb.com/connectteb.com.key;

    # Normalize /blog to /blog/
    location = /blog {
        return 301 /blog/;
    }

    # WordPress blog: preserve the original URI
    location ^~ /blog/ {
        proxy_pass https://wordpress_origin;

        proxy_http_version 1.1;
        proxy_set_header Host connectteb.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host connectteb.com;
        proxy_set_header X-Forwarded-Port 443;

        proxy_ssl_server_name on;
        proxy_ssl_name connectteb.com;

        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

    # Selected WordPress pages
    # Nginx location matching normally uses the normalized URI.
    location ~* ^/(about-us|contact-us|حریم-خصوصی|سوالات-متداول)/?$ {
        proxy_pass https://wordpress_origin;

        proxy_http_version 1.1;
        proxy_set_header Host connectteb.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host connectteb.com;
        proxy_set_header X-Forwarded-Port 443;

        proxy_ssl_server_name on;
        proxy_ssl_name connectteb.com;

        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

    # Normalize /wp-admin to /wp-admin/
    location = /wp-admin {
        return 301 /wp-admin/;
    }

    # WordPress admin
    location ^~ /wp-admin/ {
        proxy_pass https://wordpress_origin;

        proxy_http_version 1.1;
        proxy_set_header Host connectteb.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_ssl_server_name on;
        proxy_ssl_name connectteb.com;
    }

    # WordPress login
    location = /wp-login.php {
        proxy_pass https://wordpress_origin;

        proxy_http_version 1.1;
        proxy_set_header Host connectteb.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_ssl_server_name on;
        proxy_ssl_name connectteb.com;
    }

    # WordPress assets
    location ^~ /wp-content/ {
        proxy_pass https://wordpress_origin;

        proxy_set_header Host connectteb.com;
        proxy_set_header X-Forwarded-Proto https;
        proxy_ssl_server_name on;
        proxy_ssl_name connectteb.com;
    }

    location ^~ /wp-includes/ {
        proxy_pass https://wordpress_origin;

        proxy_set_header Host connectteb.com;
        proxy_set_header X-Forwarded-Proto https;
        proxy_ssl_server_name on;
        proxy_ssl_name connectteb.com;
    }

    # WordPress REST API
    location ^~ /wp-json/ {
        proxy_pass https://wordpress_origin;

        proxy_set_header Host connectteb.com;
        proxy_set_header X-Forwarded-Proto https;
        proxy_ssl_server_name on;
        proxy_ssl_name connectteb.com;
    }

    # Default route: landing frontend
    location / {
        proxy_pass http://landing;

        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
        proxy_redirect off;
    }
}
```

### Important URI behavior

In this configuration, `proxy_pass https://wordpress_origin;` has **no
URI suffix**. That preserves the incoming path when proxying. For
example, `/blog/article-name/` is sent to the origin as
`/blog/article-name/`.

Do not change it to `proxy_pass https://wordpress_origin/;` without
understanding the URI replacement rules: adding the trailing slash in
this location changes how the request URI is forwarded.

### Other WordPress endpoints

Some WordPress features or plugins may require additional paths, such as
`/wp-comments-post.php`, `/wp-cron.php`, or `/xmlrpc.php`. Add only the
endpoints that the site actually needs and that are safe to expose.
Avoid proxying every root-level path to WordPress, because that would
make it harder to distinguish landing routes from WordPress routes.

## 6. Fixing the `nginx -t` Syntax Error

An encountered error was:

``` text
nginx: [emerg] invalid parameter "on" in /etc/nginx/sites-enabled/connecteb.com.conf:33
nginx: configuration file /etc/nginx/nginx.conf test failed
```

The relevant lines were:

``` nginx
listen 443 ssl
http2 on;
```

The `listen` directive is missing its semicolon. Nginx consequently
parses the next line as part of the `listen` directive and reports `on`
as an invalid parameter.

For compatibility with the syntax already used in the other virtual
hosts, change those lines to:

``` nginx
listen 443 ssl http2;
```

Alternatively, on Nginx versions that support the standalone `http2`
directive, use:

``` nginx
listen 443 ssl;
http2 on;
```

Do not use both forms together. Check the installed version and validate
the full configuration:

``` bash
nginx -v
sudo nginx -t
```

If the test succeeds, reload Nginx:

``` bash
sudo systemctl reload nginx
sudo systemctl status nginx --no-pager
```

A successful syntax test does not prove that the origin or application
is reachable; perform the runtime tests below too.

## 7. Pre-migration Origin Checks

Before changing DNS, test the ParsPack origin from the Nginx server.
`--resolve` connects to the specified IP while keeping `connectteb.com`
as the URL hostname, HTTP Host, and TLS SNI.

``` bash
curl -sS -D - -o /dev/null \
  --resolve connectteb.com:443:194.5.195.189 \
  https://connectteb.com/blog/

curl -sS -D - -o /dev/null \
  --resolve connectteb.com:443:194.5.195.189 \
  https://connectteb.com/about-us/

curl -sS -D - -o /dev/null \
  --resolve connectteb.com:443:194.5.195.189 \
  https://connectteb.com/wp-login.php
```

Repeat for `/contact-us/` and both Persian pages. Check the HTTP status
and `Location` headers. Resolve origin problems with the hosting
provider before switching DNS.

A `200`, `301`, or `302` can be normal depending on the page and
WordPress configuration. Unexpected `403`, `404`, TLS errors, or
redirects to a different hostname require investigation.

## 8. DNS Cutover Checklist

1.  Confirm the origin IP and origin TLS behavior with ParsPack.

2.  Test the landing upstream from the Nginx host:

    ``` bash
    curl -sS -D - -o /dev/null http://192.168.178.36:3000/
    ```

3.  Save a backup of the active Nginx configuration.

4.  Add the WordPress path locations and ensure the default `/` location
    points to the landing upstream.

5.  Check the certificate and key paths.

6.  Run `sudo nginx -t`.

7.  Reload Nginx only if the test succeeds.

8.  Test with a local override before DNS cutover, if possible:

    ``` bash
    curl -sS -D - -o /dev/null \
      --resolve connectteb.com:443:COMPANY_NGINX_PUBLIC_IP \
      https://connectteb.com/
    ```

    Replace `COMPANY_NGINX_PUBLIC_IP` with the actual public IP.

9.  Update the apex DNS A record to the company Nginx public IP.

10. Keep the ParsPack origin reachable from the company server.

11. Validate every required WordPress page and landing route after DNS
    changes.

## 9. Validation Matrix

  ------------------------------------------------------------------------------------------
  Test                                       Expected destination    What to verify
  ------------------------------------------ ----------------------- -----------------------
  `https://connectteb.com/`                  Landing                 Landing page loads

  `https://connectteb.com/a-landing-route`   Landing                 Frontend routing works

  `https://connectteb.com/blog/`             WordPress               Blog page loads

  `https://connectteb.com/about-us/`         WordPress               Correct page loads

  `https://connectteb.com/contact-us/`       WordPress               Correct page loads

  Persian privacy page                       WordPress               Correct page loads with
                                                                     encoded URL

  Persian FAQ page                           WordPress               Correct page loads with
                                                                     encoded URL

  `https://connectteb.com/wp-login.php`      WordPress               Login page loads

  `https://connectteb.com/wp-admin/`         WordPress               Admin redirects/login
                                                                     behave normally

  WordPress CSS, JS, images                  WordPress origin        Assets load without
                                                                     404s

  Existing API subdomains                    Existing API upstreams  Unchanged services
                                                                     still work
  ------------------------------------------------------------------------------------------

Use browser Developer Tools → Network to check failed CSS, JavaScript,
image, login, and REST API requests.

## 10. Troubleshooting

### Nginx configuration test fails

``` bash
sudo nginx -t
sudo nginx -T | less
```

Inspect the reported file and line number. A missing semicolon can cause
the parser to report an error on the following directive.

### Landing returns `502 Bad Gateway`

Check that the app is listening on the expected address and port:

``` bash
curl -v http://192.168.178.36:3000/
```

Confirm network reachability and firewall rules between Nginx and the
landing host.

### WordPress returns `502` or TLS errors

From the Nginx server, run the origin `curl --resolve` tests in Section
7. Confirm:

-   The origin IP is correct.
-   The origin accepts HTTPS for `connectteb.com`.
-   The TLS certificate is valid for the hostname and its chain is
    trusted.
-   The origin web server routes the `connectteb.com` Host header to the
    intended WordPress site.
-   Nginx can reach the origin on TCP 443.

### WordPress redirects to the wrong host or URL

Inspect the `Location` header:

``` bash
curl -sS -D - -o /dev/null https://connectteb.com/blog/
```

Check the WordPress site's existing canonical URL settings and any
hosting-level redirects. Do not change `WP_HOME` or `WP_SITEURL`
blindly; first verify the current values and intended canonical URL.

### WordPress page loads but CSS or images are missing

Check the browser Network panel. Ensure requests for `/wp-content/` and
`/wp-includes/` are routed to WordPress and that the origin generates
asset URLs using the expected public domain.

### Persian page goes to the landing app

Check how Nginx normalizes the request URI and inspect the active
configuration:

``` bash
sudo nginx -T
```

Verify the actual slug in WordPress and test both the browser's
percent-encoded URL and the normalized path. Ensure the regex includes
the exact slug and optional trailing slash.

### Admin page loads but login or REST calls fail

Check `/wp-login.php`, `/wp-admin/`, `/wp-json/`, cookies, redirects,
and browser Network requests. Some plugins may use additional root-level
WordPress endpoints; add narrowly scoped locations only when confirmed
necessary.

### Blog listing works, but clicking an article returns `404`

**Do not create one Nginx `location` for every article.** Hundreds of
blog posts should be handled by the existing prefix location:

```nginx
location ^~ /blog/ {
    proxy_pass https://wordpress_origin;
    # Keep the existing proxy headers and TLS/SNI settings here.
}
```

This one location matches `/blog/` and every URL below it, for example
`/blog/example-article/`. Because `proxy_pass` has no URI suffix, the
original request path is preserved when sent to WordPress.

#### Step 1: Inspect the exact URL of a broken article

Click a post in the blog listing and copy the full URL from the browser.
The path determines which application receives the request:

- `https://connectteb.com/blog/example-article/` matches the existing
  `/blog/` WordPress location.
- `https://connectteb.com/example-article/` does **not** match `/blog/`
  and is sent to the landing application by the default `location /`.

Replace `example-article` below with the real article slug when testing.

#### Step 2: If the article URL starts with `/blog/`

Test the same path directly against the WordPress origin from the Nginx
server. `--resolve` connects to the origin IP while retaining
`connectteb.com` as the URL hostname and TLS SNI:

```bash
curl -sS -D - -o /dev/null \
  --resolve connectteb.com:443:194.5.195.189 \
  https://connectteb.com/blog/example-article/
```

Interpret the result:

- If the origin itself returns `404`, check that the post exists, its
  WordPress permalink/slug is correct, and WordPress rewrite rules are
  working. Confirm the URL against a known working article and review
  WordPress permalink settings before changing Nginx.
- If the origin returns a successful response but the public URL returns
  `404`, inspect the active Nginx configuration and logs, then compare
  the public response with the origin response:

  ```bash
  sudo nginx -T
  sudo tail -n 100 /var/log/nginx/access.log
  sudo tail -n 100 /var/log/nginx/error.log
  ```

  Log paths may differ on your server. Confirm the request is reaching
  the expected `connectteb.com` server block and `/blog/` location.

#### Step 3: If article URLs are at the domain root

If WordPress generates URLs such as
`https://connectteb.com/example-article/`, Nginx currently sends those
requests to the landing application. There are two approaches:

1. **Preferred when acceptable:** configure WordPress to use a consistent
   blog prefix, such as `/blog/%postname%/`, so article URLs become
   `https://connectteb.com/blog/example-article/`. Then the existing
   `location ^~ /blog/` handles every article; no per-post Nginx rules
   are required. Test the setting on the site and consider existing
   inbound links, search indexing, and redirects before changing live
   permalinks. Set up and verify appropriate permanent redirects from old
   URLs if those URLs must continue to work.
2. **If root-level article URLs must be preserved:** design and test a
   more advanced routing fallback that sends only genuine landing-app
   404s to WordPress. This requires knowing how the landing application
   signals a real 404; some single-page applications return `200` for
   unknown paths, so a generic Nginx `error_page 404` fallback may not
   work as expected. Do not route every unknown root-level path to
   WordPress without evaluating the effect on landing routes.

**Recommended diagnostic order:** copy one broken article URL, identify
whether its path starts with `/blog/`, test that exact path against the
origin, and only then change routing or WordPress settings.

## 11. Rollback Plan

If the migration causes an outage:

1.  Restore the saved Nginx configuration.
2.  Run `sudo nginx -t`.
3.  Reload Nginx only after the test succeeds.
4.  If necessary, restore the previous DNS A record so the domain points
    directly to ParsPack again.
5.  Confirm the WordPress site is available through the restored path.
6.  Investigate the failing upstream or route before attempting another
    cutover.

DNS rollback is not instantaneous for every client because of DNS
caching and TTLs.

## 12. Operational Notes

-   Keep Nginx as the only public entry point for the combined domain.
-   Do not use the public domain as the WordPress proxy destination when
    that domain resolves to the company Nginx server; use the verified
    origin IP.
-   Preserve the public Host header and use the correct upstream TLS SNI
    name.
-   Keep path routing explicit. Sending every root-level path to
    WordPress defeats the goal of serving the landing application by
    default.
-   Keep a backup before changing production Nginx configuration.
-   A successful `nginx -t` validates syntax only; it does not validate
    DNS, upstream availability, WordPress behavior, or application
    health.
