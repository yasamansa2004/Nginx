```
###########################
#####     NextCloud   #####
##########################

# Redirect all HTTP to HTTPS
server {
    listen 80;
    server_name cloud.mtyn.ir;

    return 301 https://$host$request_uri;
}

# HTTPS server
server {
    listen 443 ssl http2;
    server_name cloud.mtyn.ir;

    # SSL certs (example with Let's Encrypt)
    ssl_certificate /etc/letsencrypt/live/cloud.mtyn.ir/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/cloud.mtyn.ir/privkey.pem;

    # HSTS for security
    add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;

    location / {
        proxy_pass http://192.168.7.212:8081;
        proxy_set_header Host               $host;
        proxy_set_header X-Real-IP          $remote_addr;
        proxy_set_header X-Forwarded-For    $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host   $host:$server_port;
        proxy_set_header X-Forwarded-Server $host;
        proxy_set_header X-Forwarded-Proto  $scheme;
        proxy_http_version 1.1;
        proxy_buffering off;
    }

    # Optional: WebSocket support
    location /ocs/v2.php/ {
        proxy_pass http://192.168.7.212:8081;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "upgrade";
        proxy_set_header Upgrade $http_upgrade;
    }
}


```
