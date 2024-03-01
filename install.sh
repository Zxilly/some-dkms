#!/bin/bash

if [ $(id -u) -ne 0 ]; then 
    echo "refuse to continue without root permission" 
    exit 1 
fi

prefix=alg
mkdir -p $prefix
cd $prefix

bbr_file=alg
bbr_src=$bbr_file.c
bbr_obj=$bbr_file.o

mkdir -p src
cd src
wget -O ./$bbr_src https://raw.githubusercontent.com/Zxilly/some-dkms/master/alg.c

if [ ! $? -eq 0 ]; then
    echo "Download Error"
    cd ../..
    rm -rf $prefix
    exit 1
fi

echo "===== Succussfully downloaded $bbr_src ====="

# Create Makefile
cat > ./Makefile << EOF
obj-m:=$bbr_obj

default:
	make -C /lib/modules/\$(shell uname -r)/build M=\$(PWD)/src modules

clean:
	-rm modules.order
	-rm Module.symvers
	-rm .[!.]* ..?*
	-rm $bbr_file.mod
	-rm $bbr_file.mod.c
	-rm *.o
	-rm *.cmd
EOF

# Create dkms.conf
cd ..
cat > ./dkms.conf << EOF
MAKE="'make' -C src/"
CLEAN="make -C src/ clean"
BUILT_MODULE_NAME=$bbr_file
BUILT_MODULE_LOCATION=src/
DEST_MODULE_LOCATION=/updates/net/ipv4
PACKAGE_NAME=pixie
PACKAGE_VERSION=1.0.0
REMAKE_INITRD=yes
EOF

# Start dkms install
echo "===== Start installation ====="

cp -R . /usr/src/pixie-1.0.0

dkms add -m pixie -v 1.0.0
if [ ! $? -eq 0 ]; then
    echo "DKMS add failed"
    dkms remove -m pixie/1.0.0 --all
    exit 1
fi

dkms build -m pixie -v 1.0.0
if [ ! $? -eq 0 ]; then
    echo "DKMS build failed"
    dkms remove -m pixie/1.0.0 --all
    exit 1
fi

dkms install -m pixie -v 1.0.0
if [ ! $? -eq 0 ]; then
    echo "DKMS install failed"
    dkms remove -m pixie/1.0.0 --all
    exit 1
fi

# Test loading module
modprobe $bbr_file

if [ ! $? -eq 0 ]; then
    echo "modprobe failed, please check your environment"
    echo "Please use \"dkms remove -m pixie/1.0.0 --all\" to remove the dkms module"
    exit 1
fi

sysctl -w net.core.default_qdisc=fq

if [ ! $? -eq 0 ]; then
    echo "sysctl test failed, please check your environment"
    echo "Please use \"dkms remove -m pixie/1.0.0 --all\" to remove the dkms module"
    exit 1
fi

sysctl -w net.ipv4.tcp_congestion_control=pixie

if [ ! $? -eq 0 ]; then
    echo "sysctl test failed, please check your environment"
    echo "Please use \"dkms remove -m pixie/1.0.0 --all\" to remove the dkms module"
    exit 1
fi

# Auto-load kernel module at system startup

echo $bbr_file | sudo tee -a /etc/modules
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = pixie" >> /etc/sysctl.conf
sysctl -p

if [ ! $? -eq 0 ]; then
    echo "sysctl failed, please check your environment"
    echo "Please use \"dkms remove -m pixie/1.0.0 --all\" to remove the dkms module"
    exit 1
fi

echo "===== Installation succeeded, enjoy! ====="