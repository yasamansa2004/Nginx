```
###########################
#####     NextCloud   #####
##########################

server {
    listen 80;
    server_name cloud.mtyn.ir;

    location / {
        proxy_pass http://192.168.7.212:8081;
	proxy_set_header Host               $host;
    	proxy_set_header X-Real-IP          $remote_addr;
    	proxy_set_header X-Forwarded-For    $proxy_add_x_forwarded_for;
    	proxy_set_header X-Forwarded-Host   $host:$server_port;
    	proxy_set_header X-Forwarded-Server $host;
    	proxy_set_header X-Forwarded-Proto  $scheme;

    }
}

#server {
#    listen 80;
#    server_name nextcloud.example.com;
#    return 301 https://$host$request_uri;
#}


```
