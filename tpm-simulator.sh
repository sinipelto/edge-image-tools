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

requiredPkgs='git cmake build-essential curl autoconf autoconf-archive libcmocka0 libcmocka-dev procps libcurl4-openssl-dev libssl-dev uuid-dev uthash-dev doxygen libltdl-dev libseccomp-dev libgnutls28-dev ca-certificates automake bash coreutils dh-autoreconf libtasn1-6-dev net-tools iproute2 libjson-c-dev libjson-glib-dev libini-config-dev expect libtool sed devscripts equivs gcc dh-exec pkg-config gawk make socat softhsm gnutls-bin'

# Get CPU thread count for multithreading params
cpus=$(nproc)

workingDir=${PWD}
# workingDir="/root"

# TODO if needed autogen.sh:
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

	cd "${workingDir}"

	rm -vrf "${name}"

	git clone -b "${ver}" "${url}"

	cd "${name}"

	git submodule update --init

	if [ "${autog}" -eq 1 ]; then
		./autogen.sh --with-openssl --prefix=/usr --without-cuse --with-tss-user=root --with-tss-group=root --with-tpm2
	else
		./bootstrap
		./configure
	fi

	make clean
	make -j"${cpus}"
	make check
	make install

	cd "${workingDir}"
}


################################################################################
################################	START	####################################
################################################################################

cd "${workingDir}"

waitAptitude
installPackages "${requiredPkgs}"

# Clone, build and install libtmps
setupLib ${repoName} ${repoVersion} "${repoUrl}" 1

# Clone, build and install swtpm
setupLib ${repoName2} ${repoVersion2} "${repoUrl2}" 1

# Clone, build and install tpm2-tss
setupLib ${repoName3} ${repoVersion3} "${repoUrl3}" 0

udevadm control --reload-rules
udevadm trigger
ldconfig

# Clone, build and install tpm2-abrmd
setupLib ${repoName4} ${repoVersion4} "${repoUrl4}" 0

udevadm control --reload-rules
udevadm trigger
ldconfig
systemctl daemon-reload

echo "DONE"

# TODO setup and configure TPM
