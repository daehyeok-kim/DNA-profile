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
  echo "Node setup in progress. Wait until complete"
  echo "before installing any packages"
  echo "*******************************************"
elif [ -f $FLAG ]; then
  if [ -z "$HOSTS" ]; then
  # single host in cluster
    echo "***********************************************************"
    echo -e "node setup complete"
    echo "***********************************************************"
  else
    echo "*************************************************************************"
    echo -e "node setup complete"
    echo -e "Your cluster has the following hosts:\n\
$HOSTS\n"
    echo "*************************************************************************"
  fi
fi
EOF
chmod +x /etc/profile.d/firstboot.sh

export DEBIAN_FRONTEND=noninteractive

echo "MaxSessions 20" >> /etc/ssh/sshd_config

# allow pdsh to use ssh
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

# expand /dev/sda1
swapoff /dev/sda3
#parted /dev/sda 'rm 3 Yes'
#parted /dev/sda print
#parted /dev/sda 'resizepart 1 Yes 100%'
#parted /dev/sda 'resizepart 1 Yes 100%'
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | parted /dev/sda rm 3
  Yes
EOF
#parted /dev/sda print
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | parted /dev/sda resizepart 1
  Yes
  100%
EOF
resize2fs /dev/sda1

# allocate new swap space
dd if=/dev/zero of=/swapfile bs=1024 count=3145728
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab

# for building
apt-get update
apt-get -y install software-properties-common
add-apt-repository -y ppa:neovim-ppa/stable

apt-get -y install libtool autoconf automake build-essential vim htop tmux libnl-3-dev
apt-get -y install libffi6 libffi-dev python-dev python-pip 
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

# set the amount of locked memory. will require a reboot
cat <<EOF  | tee /etc/security/limits.d/90-rmda.conf > /dev/null
* soft memlock unlimited
* hard memlock unlimited
EOF

# done
rm -f $SETUPFLAG

reboot
