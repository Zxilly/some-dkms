#!/bin/sh

if [ $(id -u) -ne 0 ]; then 
    echo "refuse to continue without root permission" 
    exit 1 
fi

kernel_ver="1.0.0"
algo=alg

prefix=tmp
mkdir -p $prefix
cd $prefix

alg_file=tcp_$algo
alg_src=$alg_file.c
alg_obj=$alg_file.o

mkdir -p src
cd src
wget -O ./$alg_src https://raw.githubusercontent.com/Zxilly/some-dkms/master/alg.c

if [ ! $? -eq 0 ]; then
    echo "Download Error"
    cd ../..
    rm -rf $prefix
    exit 1
fi

echo "===== Succussfully downloaded $alg_src ====="

# Create Makefile
cat > ./Makefile << EOF
obj-m:=$alg_obj

default:
	make -C /lib/modules/\$(shell uname -r)/build M=\$(PWD)/src modules

clean:
	-rm modules.order
	-rm Module.symvers
	-rm .[!.]* ..?*
	-rm $alg_file.mod
	-rm $alg_file.mod.c
	-rm *.o
	-rm *.cmd
EOF

# Create dkms.conf
cd ..
cat > ./dkms.conf << EOF
MAKE="'make' -C src/"
CLEAN="make -C src/ clean"
BUILT_MODULE_NAME=$alg_file
BUILT_MODULE_LOCATION=src/
DEST_MODULE_LOCATION=/updates/net/ipv4
PACKAGE_NAME=$algo
PACKAGE_VERSION=$kernel_ver
AUTO_INSTALL=yes
EOF

# Start dkms install
echo "===== Start installation ====="

cp -R . /usr/src/$algo-$kernel_ver

dkms add -m $algo -v $kernel_ver
if [ ! $? -eq 0 ]; then
    echo "DKMS add failed"
    dkms remove -m $algo/$kernel_ver --all
    exit 1
fi

dkms build -m $algo -v $kernel_ver
if [ ! $? -eq 0 ]; then
    echo "DKMS build failed"
    dkms remove -m $algo/$kernel_ver --all
    exit 1
fi

dkms install -m $algo -v $kernel_ver
if [ ! $? -eq 0 ]; then
    echo "DKMS install failed"
    dkms remove -m $algo/$kernel_ver --all
    exit 1
fi

# Test loading module
modprobe $alg_file

if [ ! $? -eq 0 ]; then
    echo "modprobe failed, please check your environment"
    echo "Please use \"dkms remove -m $algo/$kernel_ver --all\" to remove the dkms module"
    exit 1
fi

# Auto-load kernel module at system startup

echo $alg_file | sudo tee -a /etc/modules
echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = $algo" >> /etc/sysctl.conf
sysctl -p

if [ ! $? -eq 0 ]; then
    echo "sysctl failed, please check your environment"
    echo "Please use \"dkms remove -m $algo/$kernel_ver --all\" to remove the dkms module"
    exit 1
fi

echo "===== Installation succeeded, enjoy! ====="