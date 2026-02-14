```
####################
##  alertmanager  ##
####################
server {
    server_name alertmanager.mtyn.ir;
    listen 443;
    location / {
        proxy_pass http://37.152.190.187:9093;
        proxy_set_header Host               $host;
        proxy_set_header X-Real-IP          $remote_addr;
        proxy_set_header X-Forwarded-For    $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host   $host:$server_port;
        proxy_set_header X-Forwarded-Server $host;
        proxy_set_header X-Forwarded-Proto  $scheme;

    }


    ssl_certificate /etc/letsencrypt/live/alertmanager.mtyn.ir/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/alertmanager.mtyn.ir/privkey.pem; # managed by Certbot
}



```
