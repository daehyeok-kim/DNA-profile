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
