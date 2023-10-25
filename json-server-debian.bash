#!/usr/bin/env bash

NODE_VERSION_MAJOR=20

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

DISTRO=$( cat /etc/*-release | grep 'PRETTY_NAME=' | cut -d "=" -f 2)

if [[ $DISTRO == *"Ubuntu"* ]]
then
  apt -y install curl gnupg2 ca-certificates lsb-release ubuntu-keyring
  curl -q https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg > /dev/null
  gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu `lsb_release -cs` nginx" | tee /etc/apt/sources.list.d/nginx.list
  echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx

elif [[ $DISTRO == *"Debian"* ]]
then
  apt -y install curl gnupg2 ca-certificates lsb-release debian-archive-keyring
  curl -q https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg > /dev/null
  gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/debian `lsb_release -cs` nginx" | tee /etc/apt/sources.list.d/nginx.list
  echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx
else
    echo "No recognized Linux distribution used"
    exit 1
fi

echo "******************************************"
echo "************ Installing nginx ************"
echo "******************************************"
echo

apt -y install nginx
nginx -v

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

apt -y install snapd
systemctl restart snapd.service

sleep 20

snap install core

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

useradd -m -s /bin/bash usr_api

echo
echo "**************************************************"
echo "**** Creating necessary files for json-server ****"
echo "**************************************************"
echo

mkdir -p /srv/www-api
touch /srv/www-api/db.json

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

apt -y install ca-certificates curl gnupg
mkdir -p /etc/apt/keyrings
curl -fsSLq https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_VERSION_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list
apt -y install nodejs npm
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

  access_log /var/log/nginx/$1.access.log;
  error_log /var/log/nginx/$1.error.log;
}
EOF
fi

echo
echo "************************************"
echo "******* nginx reload service *******"
echo "************************************"
echo

nginx -s reload
