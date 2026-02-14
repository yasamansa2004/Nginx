Jira:

```
server {
    server_name jira.mtyn.ir;

    location / {
        proxy_pass http://192.168.7.60:8080/;
	proxy_pass_header Authorization;
	proxy_set_header Host $host;
	proxy_set_header X-Real-IP $remote_addr;
	proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
	proxy_http_version 1.1;
	proxy_set_header Connection "";
	proxy_buffering off;
	client_max_body_size 0;
	proxy_read_timeout 36000s;
	proxy_redirect off;
    }

    listen 443 ssl;  # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/jira.mtyn.ir/fullchain.pem;  # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/jira.mtyn.ir/privkey.pem;  # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf;  # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;  # managed by Certbot


}

```

Confluence:

```
server {

    server_name docs.mtyn.ir;

    location / {
    proxy_pass                              http://192.168.7.60:8090/;
      proxy_pass_header Authorization;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_http_version 1.1;
      proxy_set_header Connection "";
      proxy_buffering off;
      client_max_body_size 0;
      proxy_read_timeout 36000s;
      proxy_redirect off;
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/docs.mtyn.ir/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/docs.mtyn.ir/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

}
```
