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
#sed -i -r 's/GRUB_CMDLINE_LINUX_DEFAULT=\"(.*)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 processor.max_cstate=1 intel_idle.max_cstate=0 default_hugepagesz=1GB hugepagesz=1G hugepages=4\"/' /etc/default/grub
#sed -i -r 's/GRUB_CMDLINE_LINUX_DEFAULT=\"(.*)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 processor.max_cstate=1 intel_idle.max_cstate=0 \"/' /etc/default/grub
#update-grub

#echo 'auto xenbr0iface xenbr0 inet dhcp\nbridge_ports enp1s0f0\n' >> /etc/network/interfaces

echo "MaxSessions 20" >> /etc/ssh/sshd_config

apt-get update
apt-get -y install software-properties-common
add-apt-repository -y ppa:neovim-ppa/stable
apt-get update

# for building
apt-get install -y libtool autoconf automake build-essential vim htop tmux libnl-3-dev
apt-get install -y libffi6 libffi-dev python-dev python-pip 

apt-get -y install build-essential
apt-get -y install bcc bin86 gawk bridge-utils iproute libcurl3 libcurl4-openssl-dev bzip2 module-init-tools transfig tgif 
apt-get -y install make gcc libc6-dev zlib1g-dev python python-dev python-twisted libncurses5-dev patch libvncserver-dev libsdl-dev libjpeg-dev
apt-get -y install iasl libbz2-dev e2fslibs-dev git-core uuid-dev ocaml ocaml-findlib libx11-dev bison flex xz-utils libyajl-dev
apt-get -y install gettext libpixman-1-dev libaio-dev markdown pandoc python-numpy
apt-get -y install libc6-dev-i386
apt-get -y install lzma lzma-dev liblzma-dev
apt-get -y install libsystemd-dev numactl
apt-get -y install neovim
apt-get -y install python-dev python-pip python3-dev python3-pip

apt-get update

# for OFED
#wget http://www.mellanox.com/downloads/ofed/mlnx_ofed-4.6-1.0.1.1/mlnx_ofed_linux-4.6-1.0.1.1-ubuntu16.04-x86_64.tgz
#tar xfz ./mlnx_ofed_linux-4.6-1.0.1.1-ubuntu16.04-x86_64.tgz
#sudo ./mlnx_ofed_linux-4.6-1.0.1.1-ubuntu16.04-x86_64/mlnxofedinstall --all --force

wget http://www.mellanox.com/downloads/ofed/MLNX_OFED-4.1-1.0.2.0/MLNX_OFED_LINUX-4.1-1.0.2.0-ubuntu14.04-x86_64.tgz
tar xfz ./MLNX_OFED_LINUX-4.1-1.0.2.0-ubuntu14.04-x86_64.tgz
sudo ./MLNX_OFED_LINUX-4.1-1.0.2.0-ubuntu14.04-x86_64/mlnxofedinstall --all --force

echo "options mlx4_core log_num_mgm_entry_size=-1" >> /etc/modprobe.d/mlnx.conf
/etc/init.d/openibd  restart

mkdir /extra_disk
/usr/local/etc/emulab/mkextrafs.pl /extra_disk

# set the amount of locked memory. will require a reboot
cat <<EOF  | tee /etc/security/limits.d/90-rmda.conf > /dev/null
* soft memlock unlimited
* hard memlock unlimited
EOF

# allow pdsh to use ssh
#echo "ssh" | tee /etc/pdsh/rcmd_default
#
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

# for passwordless ssh to take effect
service ssh restart

# done
rm -f $SETUPFLAG

reboot
