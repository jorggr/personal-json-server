## personal-json-server

> For the installation of your own JSON-Server, we need a domain associated with the public IP of your VPS/VM and an email for Let's Encrypt registration.

> [json-server-rhel.bash](json-server-rhel.bash) for RHEL/Centos 8

```bash
[root@my-server ~]# git clone git@github.com:jorggr/personal-json-server.git

[root@my-server ~]# cd personal-json-server

[root@my-server ~]# chmod u+x json-server-rhel.bash

[root@my-server ~]# ./json-server-rhel.bash my.domain.xyz letsencrypt@email.xyz
```
