hetzner-install
===============

installs Ubuntu 12.04 (Precise Pangolin) on a dedicated server at Hetzner using debootstrap

a normal install usually looks like this

1. boot your server into 64bit Linux rescue system

2. on your local machine do
```shell
./push-keys.sh
scp do-* server1.example.org
ssh server1.example.org
```

3. then on your server do
```shell
./do-partition-gpt.sh
./do-install-precise.sh
```
