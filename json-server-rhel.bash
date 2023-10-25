#!/usr/bin/env bash

Help()
{
  echo "*********************************************"
  echo "You must provide two arguments to the command"
  echo
  echo "Use: \# json-server-rhel.bash domain.example email@domain.example"
  echo
  echo " arg01: domain name"
  echo " arg02: email"
  echo
  echo "*********************************************"
  echo
}

if [ $# -lt 2 ]; then
  Help
  exit 1
fi

dnf -yq install vim checkpolicy

DISTRO=$( cat /etc/*-release | grep 'PRETTY_NAME=' | cut -d "=" -f 2)
if [[ $DISTRO == *"Red Hat Enterprise Linux"* ]]
then
    echo "************************************************"
    echo "* Installing EPEL for Red Hat Enterprise Linux *"
    echo "************************************************"
    echo
    subscription-manager repos --enable=codeready-builder-for-rhel-8-$(arch)-rpms
    dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
elif [[ $DISTRO == *"CentOS"* ]]
then
    echo "************************************************"
    echo "********* Installing EPEL for CentOS ***********"
    echo "************************************************"
    echo
    dnf config-manager --set-enabled powertools
    dnf -yq install epel-release epel-next-release
else
    echo "No recognized Linux distribution used"
    exit 1
fi

echo "******************************************"
echo "************ Installing nginx ************"
echo "******************************************"
echo

dnf -yq module reset php
dnf -yq module enable php:8.0

dnf -yq module reset nginx
dnf -yq module enable nginx:1.22
dnf -yq install nginx

nginx -version

echo "*****************************************"
echo "********** Start nginx service **********"
echo "*****************************************"
echo

systemctl enable nginx.service --now
systemctl status nginx.service

echo
echo "******************************************"
echo "************ Installing snapd ************"
echo "******************************************"
echo

dnf -yq install snapd
systemctl restart snapd.service

sleep 20

if [[ ! -e "/snap" ]]; then
    ln -s /var/lib/snapd/snap /snap
fi

echo
echo "******************************************"
echo "*********** Installing certbot ***********"
echo "******************************************"
echo

if [[ ! -e "/usr/bin/certbot" ]]; then
    snap install --classic certbot
    ln -s /snap/bin/certbot /usr/bin/certbot
fi

certbot --version

echo
echo "***************************************************"
echo "************** Creating user usr_api **************"
echo "***************************************************"
echo

useradd usr_api
mkdir -p /srv/www-api
touch /srv/www-api/db.json

echo
echo "**************************************************"
echo "**** Creating necessary files for json-server ****"
echo "**************************************************"
echo

cat << 'EOF' > /srv/www-api/package.json
{
  "name": "json-server-app",
  "version": "1.0.0",
  "description": "",
  "main": "index.js",
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1",
    "json-server:start": "json-server db.json"
  },
  "keywords": [],
  "author": "",
  "license": "ISC",
  "dependencies": {
    "json-server": "^0.17.3"
  }
}
EOF

cat << 'EOF' > /srv/www-api/json-server.json
{
  "port": 8080
}
EOF

echo
echo "****************************************"
echo "***** Fixing permissions and owner *****"
echo "****************************************"
echo

chown -R usr_api: /srv/www-api
find /srv/www-api -type d -exec chmod 755 {} \;
find /srv/www-api -type f -exec chmod 660 {} \;

echo
echo "*******************************************"
echo "************* Installing node *************"
echo "*******************************************"
echo

dnf  -yq install https://rpm.nodesource.com/pub_20.x/nodistro/repo/nodesource-release-nodistro-1.noarch.rpm
dnf -yq install nodejs --setopt=nodesource-nodejs.module_hotfixes=1
node --version

echo
echo "**********************************"
echo "***** Installing json-server *****"
echo "**********************************"
echo

su - usr_api -c 'cd /srv/www-api && npm i'

echo
echo "*******************************************"
echo "** Creating Systemd: JSON Server Service **"
echo "*******************************************"
echo

cat << 'EOF' > /etc/systemd/system/json-server.service
[Unit]
Description=Service JSON Server
Wants=network.target
After=network.target
Before=nginx.service

[Service]
User=usr_api
Group=usr_api

Type=simple
WorkingDirectory=/srv/www-api
ExecStart=/bin/bash -c "npm run json-server:start"
ExecStop=/bin/bash -c "/bin/kill $(ps aux | grep 'json-server db.json' | awk '{print $2}')"

StandardOutput=null
StandardError=null
TimeoutSec=60
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo
echo "*******************************"
echo "**** Relabel api directory ****"
echo "*******************************"
echo

restorecon -vR /srv/www-api

echo
echo "*****************************************"
echo "******* Start json-server service *******"
echo "*****************************************"
echo

systemctl daemon-reload
systemctl enable json-server.service --now
systemctl status json-server.service

echo
echo "******* Generating certificate for $1 *******"
echo

if [[ ! -e "/etc/letsencrypt/live/$1/fullchain.pem" ]]; then
  certbot certonly --nginx -n -d $1 --agree-tos -m $2
fi

echo
echo "******* Creating nginx config for $1 *******"
echo

if [[ ! -e "/etc/nginx/conf.d/$1.conf" ]]; then
cat << EOF > /etc/nginx/conf.d/$1.conf
upstream json_server {
  ip_hash;
  server localhost:8080 max_fails=5 fail_timeout=10s;
}

server {
  listen 80;
  server_name $1;
  return 301 https://\$server_name\$request_uri;
}

server {
  listen 443 ssl;
  server_name $1;

  location / {
    proxy_pass http://json_server;
  }

  error_page 404 /404.html;
  location = /40x.html {
    add_header 'Content-Type' 'application/json charset=UTF-8';
    return 404 '{"error": {"status_code": 404,"status": "Error 40x"}}';
  }

  error_page 500 502 503 504 /50x.html;
  location = /50x.html {
    add_header 'Content-Type' 'application/json charset=UTF-8';
    return 500 '{"error": {"status_code": 500,"status": "Error 50x"}}';
  }

  location ~ /\.(?!well-known).* {
      deny all;
  }

  location = /robots.txt { access_log off; log_not_found off; }
  location = /favicon.ico { access_log off; log_not_found off; }
  location ~ /\. { access_log off; log_not_found off; allow all; }
  location ~ ~$ { access_log off; log_not_found off; deny all; }

  ssl_certificate /etc/letsencrypt/live/$1/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$1/privkey.pem;

  access_log /var/log/nginx/$1.access.log main;
  error_log /var/log/nginx/$1.error.log warn;
}
EOF
fi

echo
echo "************************************"
echo "******* nginx reload service *******"
echo "************************************"
echo

nginx -s reload

echo
echo "************************************"
echo "******* JSON Server policies *******"
echo "************************************"
echo

cat << 'EOF' > JSON-Server-port8080.te
module JSON-Server-port8080 1.0;

require {
  type httpd_t;
  type http_cache_port_t;
  class tcp_socket name_connect;
}

allow httpd_t http_cache_port_t:tcp_socket name_connect;
EOF

checkmodule -M -m -o JSON-Server-port8080.mod JSON-Server-port8080.te
semodule_package -o JSON-Server-port8080.pp -m JSON-Server-port8080.mod
semodule -i JSON-Server-port8080.pp
