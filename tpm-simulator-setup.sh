#!/bin/bash
set -e

userId=$(id -u)
(( userId != 0 )) && echo "Current user not root. This script must be run as root user or with sudo privileges." && exit 1

# paramsFile='/image_params'

# commonBin='/root/bin/common.sh'
# waitBin='/root/bin/wait-for-it.sh'

commonBin='common.sh'
# waitBin='wait-for-it.sh'

# shellcheck source=/dev/null
source ${commonBin}

# Read image params variables from file
# shellcheck source=/dev/null
#source ${paramsFile}

# 0: setup a new TPM manufacturing and create new EK
# 1: use an existing TPM setup with existing EK
tpmState=${1:-0}

# Stored state dir for restoring backed up vTPM state
tpmStateDir="vtpm_state"

repoName='libtpms'
repoVersion='v0.9.2'
repoUrl="https://github.com/stefanberger/${repoName}.git"

repoName2='swtpm'
repoVersion2='v0.7.1'
repoUrl2="https://github.com/stefanberger/${repoName2}.git"

repoName3='tpm2-tss'
repoVersion3='3.2.0'
repoUrl3="https://github.com/tpm2-software/${repoName3}.git"

repoName4='tpm2-abrmd'
repoVersion4='2.4.1'
repoUrl4="https://github.com/tpm2-software/${repoName4}.git"

requiredPkgs='git cmake build-essential curl autoconf autoconf-archive libcmocka0 libcmocka-dev procps libcurl4-openssl-dev libssl-dev uuid-dev uthash-dev doxygen libltdl-dev libseccomp-dev libgnutls28-dev ca-certificates automake bash coreutils dh-autoreconf libtasn1-6-dev net-tools iproute2 libjson-c-dev libjson-glib-dev libini-config-dev expect libtool sed devscripts equivs gcc dh-exec pkg-config gawk make socat softhsm gnutls-bin glib-2.0'

# Get CPU thread count for multithreading params
cpus=$(nproc)

# TODO if needed in autogen.sh / configure:
#	cross compile to arch
#	--build=ARCH
#	--host=ARCH
#	--target=ARCH
#	set --prefix = /root/p2/usr

setupLib() {
	local name=${1}
	local ver=${2}
	local url=${3}
	local autog=${4:-0}

	rm -vrf "${name}"

	git clone -b "${ver}" "${url}"

	cd "${name}"

	git submodule update --init --recursive

	if [ "${autog}" -eq 1 ]; then
		./autogen.sh --with-openssl --prefix=/usr --without-cuse --with-tss-user=root --with-tss-group=root --with-tpm2
	else
		./bootstrap
		./configure --prefix=/usr --with-dbuspolicydir=/etc/dbus-1/system.d --with-udevrulesdir=/etc/udev/rules.d --with-systemdsystemunitdir=/lib/systemd/system --with-systemdpresetdir=/lib/systemd/system-preset --datarootdir=/usr/share
	fi

	make clean
	make -j"${cpus}"
	make check
	make install

	cd ..
}


################################################################################
################################	START	####################################
################################################################################

waitAptitude
installPackages "${requiredPkgs}"

systemctl disable apparmor
apt remove --auto-remove --purge -y apparmor
echo "AppArmor purged"

# Clone, build and install libtmps
setupLib ${repoName} ${repoVersion} "${repoUrl}" 1
echo "Build & Install libtpms done"

# Clone, build and install swtpm
setupLib ${repoName2} ${repoVersion2} "${repoUrl2}" 1
echo "Build & Install swtpm done"

# Clone, build and install tpm2-tss
setupLib ${repoName3} ${repoVersion3} "${repoUrl3}" 0

udevadm control --reload-rules
udevadm trigger
ldconfig
pkill -HUP dbus-daemon
systemctl daemon-reload

sleep 1
echo "Build & Install tpm2-tss done"

# Clone, build and install tpm2-abrmd
setupLib ${repoName4} ${repoVersion4} "${repoUrl4}" 0

udevadm control --reload-rules
udevadm trigger
ldconfig
pkill -HUP dbus-daemon
systemctl daemon-reload

sleep 1
echo "Build & Install tpm2-abrmd done"

export TPM_PATH=/root/vtpm

rm -vrf ${TPM_PATH}

if [ "$tpmState" -eq 0 ]; then
	echo "Manufacturing a new TPM device"
	mkdir -v ${TPM_PATH}

	swtpm_setup \
	--runas 0 \
	--tpmstate ${TPM_PATH} \
	--tpm2 \
	--createek \
	--decryption \
	--create-ek-cert \
	--create-platform-cert \
	--lock-nvram \
	--overwrite \
	--display \
	--vmid iotedge-base-image
else
	echo "Restoring existing TPM state"
	cp -vr ${tpmStateDir} ${TPM_PATH}
	chmod -vR 0640 ${TPM_PATH}
	chmod -v 0755 ${TPM_PATH}
fi

pkill swtpm || true
pkill tpm2-abrmd || true
echo "Ensured existing processes killed"
sleep 1

swtpm socket \
--daemon \
--server type=tcp,port=2321,disconnect \
--ctrl type=tcp,port=2322 \
--tpmstate dir=${TPM_PATH} \
--tpm2 \
--flags not-need-init,startup-clear \
--runas 0

sleep 1
echo "Swtpm daemon started"

tpm2-abrmd -o --tcti "swtpm" &

sleep 1
echo "tpm2-abrmd resource manager daemon started"

echo "tpm-simulator-setup.sh DONE"
