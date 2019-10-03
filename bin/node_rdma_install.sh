#!/bin/bash

set -x

FLAG="/opt/.usersetup"
SETUPFLAG="/opt/.setup_in_process"
# FLAG will not exist on the *very* fist boot because
# it is created here!
if [ ! -f $SETUPFLAG ]; then
   touch $SETUPFLAG
   touch $FLAG
fi

HOSTS=$(cat /etc/hosts|grep cp-|awk '{print $4}'|sort)
let i=0
for each in $HOSTS; do
  (( i += 1 ))
done

cat <<EOF | tee /etc/profile.d/firstboot.sh > /dev/null
#!/bin/bash

if [ -f $SETUPFLAG ]; then
  echo "*******************************************"
  echo "RDMA node setup in progress. Wait until complete"
  echo "before installing any packages"
  echo "*******************************************"
elif [ -f $FLAG ]; then
  if [ -z "$HOSTS" ]; then
  # single host in cluster
    echo "***********************************************************"
    echo -e "RDMA node setup complete"
    echo "***********************************************************"
  else
    echo "*************************************************************************"
    echo -e "RDMA node setup complete"
    echo -e "Your cluster has the following hosts:\n\
$HOSTS\n"
    echo "*************************************************************************"
  fi
fi
EOF
chmod +x /etc/profile.d/firstboot.sh

export DEBIAN_FRONTEND=noninteractive

echo "MaxSessions 20" >> /etc/ssh/sshd_config

sed -i 's/HostbasedAuthentication no/HostbasedAuthentication yes/' /etc/ssh/sshd_config
cat <<EOF | tee -a /etc/ssh/ssh_config
    HostbasedAuthentication yes
    EnableSSHKeysign yes
EOF

cat <<EOF | tee /etc/ssh/shosts.equiv > /dev/null
$(for each in $HOSTS localhost; do grep $each /etc/hosts|awk '{print $1}'; done)
$(for each in $HOSTS localhost; do echo $each; done)
$(for each in $HOSTS; do grep $each /etc/hosts|awk '{print $2}'; done)
$(for each in $HOSTS; do grep $each /etc/hosts|awk '{print $3}'; done)
EOF

# Get the public key for each host in the cluster.
# Nodes must be up first
for each in $HOSTS; do
  while ! ssh-keyscan $each >> /etc/ssh/ssh_known_hosts || \
        ! grep -q $each /etc/ssh/ssh_known_hosts; do
    sleep 1
  done
  echo "Node $each is up"
done

# first name after IP address
for each in $HOSTS localhost; do
  ssh-keyscan $(grep $each /etc/hosts|awk '{print $2}') >> /etc/ssh/ssh_known_hosts
done
# IP address
for each in $HOSTS localhost; do
  ssh-keyscan $(grep $each /etc/hosts|awk '{print $1}') >> /etc/ssh/ssh_known_hosts
done

apt-get update
apt-get -y install software-properties-common
apt-get update

# for building
apt-get install -y libtool autoconf automake build-essential vim htop tmux libnl-3-dev
apt-get install -y libffi6 libffi-dev python-dev python-pip

apt-get -y install build-essential bcc bin86 gawk bridge-utils iproute libcurl3 libcurl4-openssl-dev bzip2 module-init-tools transfig tgif
apt-get -y install make gcc libc6-dev zlib1g-dev python python-dev python-twisted libncurses5-dev patch libvncserver-dev libsdl-dev libjpeg-dev
apt-get -y install iasl libbz2-dev e2fslibs-dev git-core uuid-dev ocaml ocaml-findlib libx11-dev bison flex xz-utils libyajl-dev
apt-get -y install gettext libpixman-1-dev libaio-dev markdown pandoc python-numpy libc6-dev-i386 lzma lzma-dev liblzma-dev
apt-get -y install libsystemd-dev numactl neovim python-dev python-pip python3-dev python3-pip systemtap
pip3 install psutil

# Install docker
apt-get -y install apt-transport-https ca-certificates curl
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

apt-get update
apt-get -y install docker-ce

echo "{\"graph\":\"/extra_disk/docker\"}" > /etc/docker/daemon.json

# Install kernel debug symbols
echo "deb http://ddebs.ubuntu.com $(lsb_release -cs) main restricted universe multiverse
deb http://ddebs.ubuntu.com $(lsb_release -cs)-updates main restricted universe multiverse
deb http://ddebs.ubuntu.com $(lsb_release -cs)-proposed main restricted universe multiverse" | \
tee -a /etc/apt/sources.list.d/ddebs.list

apt install ubuntu-dbgsym-keyring
apt-get update
apt-get -y install linux-image-$(uname -r)-dbgsym

# mount additional hard drive to /extra_disk
mkdir /extra_disk
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk /dev/sdb
  o # clear the in memory partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk
    # default
  w # write the partition table
  q # and we're done
EOF

mkfs.ext4 /dev/sdb1
mount /dev/sdb1 /extra_disk
echo "/dev/sdb1 /extra_disk ext4 defaults 0 0" >> /etc/fstab

mkdir /extra_disk/docker

# set the amount of locked memory. will require a reboot
cat <<EOF  | tee /etc/security/limits.d/90-rmda.conf > /dev/null
* soft memlock unlimited
* hard memlock unlimited
EOF

# for OFED
wget https://www.mellanox.com/downloads/ofed/MLNX_OFED-4.6-1.0.1.1/MLNX_OFED_LINUX-4.6-1.0.1.1-ubuntu18.04-x86_64.tgz
tar xfz ./MLNX_OFED_LINUX-4.6-1.0.1.1-ubuntu18.04-x86_64.tgz
./MLNX_OFED_LINUX-4.6-1.0.1.1-ubuntu18.04-x86_64/mlnxofedinstall --all --force

echo "options mlx4_core log_num_mgm_entry_size=-1" >> /etc/modprobe.d/mlnx.conf

echo 512 > /proc/sys/net/core/somaxconn
echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
echo never > /sys/kernel/mm/transparent_hugepage/enabled

sed -i -r 's/GRUB_CMDLINE_LINUX_DEFAULT=\"(.*)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 cgroup_enable=memory swapaccount=1\"/' /etc/default/grub
update-grub

# done
rm -f $SETUPFLAG

reboot
