```
server {
    server_name testrail.mtyn.ir;

    location / {
        proxy_pass http://192.168.7.60:8000/;
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
    ssl_certificate /etc/letsencrypt/live/testrail.mtyn.ir/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/testrail.mtyn.ir/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot

}




server {
    if ($host = testrail.mtyn.ir) {
        return 301 https://$host$request_uri;
    } # managed by Certbot


    server_name testrail.mtyn.ir;
    listen 80;
    return 404; # managed by Certbot


}

```
