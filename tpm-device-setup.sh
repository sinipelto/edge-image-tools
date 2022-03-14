#!/bin/bash
set -e

userId=$(id -u)
(( userId != 0 )) && echo "Current user not root. This script must be run as root user or with sudo privileges." && exit 1

commonBin='common.sh'
# waitBin='wait-for-it.sh'

# shellcheck source=/dev/null
source ${commonBin}

imgArch=${IMAGE_ARCH:?"Variable IMAGE_ARCH is empty or not set."}

pathPrefix=${1:-''}

buildPrefix="${pathPrefix}/usr"
dbusDir="${pathPrefix}/etc/dbus-1/system.d"
udevDir="${pathPrefix}/etc/udev/rules.d"
systemdDir="${pathPrefix}/lib/systemd/system"
systemdPresetDir="${pathPrefix}/lib/systemd/system-preset"
dataRootDir="${pathPrefix}/usr/share"

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

requiredPkgs='git build-essential curl autoconf autoconf-archive libcmocka0 libcmocka-dev procps libcurl4-openssl-dev libssl-dev uuid-dev uthash-dev doxygen libltdl-dev libseccomp-dev libgnutls28-dev ca-certificates automake bash coreutils dh-autoreconf libtasn1-6-dev net-tools iproute2 libjson-c-dev libjson-glib-dev libini-config-dev expect libtool sed devscripts equivs gcc dh-exec pkg-config gawk make socat softhsm gnutls-bin glib-2.0 gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu'

# Get CPU thread count for multithreading params
cpus=$(nproc)

buildArch='x86_64-pc-linux-gnu'

[[ ${imgArch} == "arm" ]] && hostArch='arm-linux-gnu'
[[ ${imgArch} == "aarch64" ]] && hostArch='aarch64-linux-gnu'

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
		./bootstrap.sh
		./autogen.sh --prefix="${buildPrefix}" --with-openssl --without-cuse --with-tss-user=root --with-tss-group=root --with-tpm2 --build=${buildArch} --host=${hostArch}
	else
		./bootstrap
		./configure --prefix="${buildPrefix}" --with-dbuspolicydir="${dbusDir}" --with-udevrulesdir="${udevDir}" --with-systemdsystemunitdir="${systemdDir}" --with-systemdpresetdir="${systemdPresetDir}" --datarootdir="${dataRootDir}" --build=${buildArch} --host=${hostArch}
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

[[ ${1} == 'test' ]] && echo "Script self-test OK" && exit 0

waitAptitude
installPackages "${requiredPkgs}"

systemctl disable apparmor
apt remove --auto-remove --purge -y apparmor
echo "AppArmor disabled and purged"

# Clone, build and install libtmps
setupLib ${repoName} ${repoVersion} "${repoUrl}" 1
echo "Build & Install libtpms done"

# Clone, build and install swtpm
setupLib ${repoName2} ${repoVersion2} "${repoUrl2}" 1
echo "Build & Install swtpm done"

# Clone, build and install tpm2-tss
setupLib ${repoName3} ${repoVersion3} "${repoUrl3}" 0
echo "Build & Install tpm2-tss done"

# TODO even possible or needed run on choot?
# udevadm control --reload-rules
# udevadm trigger
# ldconfig
# pkill -HUP dbus-daemon
# systemctl daemon-reload
# sleep 1

# Clone, build and install tpm2-abrmd
setupLib ${repoName4} ${repoVersion4} "${repoUrl4}" 0
echo "Build & Install tpm2-abrmd done"

# TODO even possible or needed run on choot?
# udevadm control --reload-rules
# udevadm trigger
# ldconfig
# pkill -HUP dbus-daemon
# systemctl daemon-reload
# sleep 1

echo "tpm-device-setup.sh DONE"
