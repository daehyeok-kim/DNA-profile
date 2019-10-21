#!/bin/sh

# expand /dev/sda1
swapoff /dev/sda3
parted /dev/sda 'rm 3 Yes'
parted /dev/sda print
parted /dev/sda 'resizepart 1 Yes 100%'
parted /dev/sda print
resize2fs /dev/sda1
# allocate new swap space
dd if=/dev/zero of=/swapfile bs=1024 count=3145728
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab

# Install docker
apt-get -y install apt-transport-https ca-certificates curl
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

apt-get update
apt-get -y install docker-ce
