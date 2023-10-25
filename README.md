### personal-json-server

#### For the installation of your own JSON-Server, we need a domain associated with the public IP of your VPS/VM and an email for Let's Encrypt registration.

> [json-server-rhel.bash](json-server-rhel.bash) for RHEL/Centos 8

```bash
[root@rhel-server ~]# git clone git@github.com:jorggr/personal-json-server.git

[root@rhel-server ~]# cd personal-json-server

[root@rhel-server ~]# chmod u+x json-server-rhel.bash

[root@rhel-server ~]# ./json-server-rhel.bash my.domain.xyz letsencrypt@email.xyz
```

> [json-server-debian.bash](json-server-debian.bash) for Debian/Ubuntu

```bash
root@debian-server:~# git clone git@github.com:jorggr/personal-json-server.git

root@debian-server:~# cd personal-json-server

root@debian-server:~# chmod u+x json-server-debian.bash

root@debian-server:~# ./json-server-debian.bash my.domain.xyz letsencrypt@email.xyz
```

![Example json-server running](/img/json-server.png)
