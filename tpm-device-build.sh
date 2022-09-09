#!/bin/bash
# Copyright (C) 2022 Toni Blåfield
# 
# edge-image-tools is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# edge-image-tools is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
# 
# You should have received a copy of the GNU Lesser General Public License
# along with edge-image-tools. If not, see <http://www.gnu.org/licenses/>.

set -e

userId=$(id -u)
(( userId != 0 )) && echo "Current user not root. This script must be run as root user or with sudo privileges." && exit 1

# waitBin='wait-for-it.sh'
commonBin='common.sh'

# shellcheck source=/dev/null
source ${commonBin}

imgOs=${IMAGE_OS:?"Variable IMAGE_OS is empty or not set."}
imgArch=${IMAGE_ARCH:?"Variable IMAGE_ARCH is empty or not set."}

pkgName='tpm-bundle'
pkgArchiveName="${pkgName}.tar.gz"
pkgArchive="./${pkgArchiveName}"
buildDest="/root/${pkgName}"

sysrootPath=${1:-''}

# 0 = local compile (target == host)
# 1 = cross-compile (target != host)
buildMode=${2:?"ERROR: Argument 2 for variable buildMode was not provided."}

buildPrefix="/usr"
dbusDir="/etc/dbus-1/system.d"
udevDir="/etc/udev/rules.d"
systemdDir="/lib/systemd/system"
systemdPresetDir="/lib/systemd/system-preset"
dataRootDir="/usr/share"

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

requiredPkgs='git cmake build-essential curl autoconf autoconf-archive libcmocka0 libcmocka-dev
	procps libcurl4-openssl-dev libssl-dev uuid-dev uthash-dev doxygen libltdl-dev libseccomp-dev
	libgnutls28-dev ca-certificates automake bash coreutils dh-autoreconf libtasn1-6-dev net-tools
	iproute2 libjson-c-dev libjson-glib-dev libini-config-dev expect libtool sed devscripts equivs
	gcc dh-exec pkgconf gawk make socat softhsm gnutls-bin glib-2.0 trousers libc6-dev libc-dev
	python3 python3-twisted libglib2.0-dev libseccomp2 libgmp-dev libnss3-dev
	libnspr4-dev'

crossPkgs='gcc-arm-linux-gnueabi binutils-arm-linux-gnueabi
	gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf
	gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu
	g++-arm-linux-gnueabi g++-arm-linux-gnueabihf
	g++-arm-linux-gnu g++-aarch64-linux-gnu'

buildDeps=('libssl-dev' 'libc-dev' 'libc6-dev' 'libgmp-dev' 'libnspr4-dev' 'libnss3-dev'
	'openssl' 'libcmocka0' 'libcmocka-dev' 'uthash-dev' 'libjson-c-dev'
	'libini-config-dev' 'libcurl4-openssl-dev' 'libltdl-dev' 'libglib2.0-dev' 'libseccomp-dev'
	'uuid-dev' 'libgnutls28-dev' 'libtasn1-6-dev' 'libjson-glib-dev'
)

# Get CPU thread count for multithreading params
cpus=$(nproc)
cpus=$((cpus * 2))

# workingDir='/root'

# Ensure all arch non-specified sources are specified as host arch (amd64)
# Leave any already specified archs untouched
hostArchReplaceLine='s/^deb\s\([a-z]\)\(.*\)/deb \[arch=amd64\] \1\2/'
targetArchReplaceLine='s/^deb\s\([a-z]\)\(.*\)/deb \[arch=armhf,arm64\] \1\2/'

[[ ${imgArch} == "x86_64" ]] && hostArch='x86_64-pc-linux-gnu' && dpkgArch='amd64'
[[ ${imgArch} == "arm" ]] && hostArch='arm-linux-gnueabi' # or hf ?
[[ ${imgArch} == "aarch64" ]] && hostArch='aarch64-linux-gnu' && dpkgArch='arm64'

sourcesPathSrc='sources'
sourcesPathDest='/etc/apt/sources.list.d'
mainSourcesFile='/etc/apt/sources.list'
sourcesFileName="${imgOs}-${dpkgArch}-sources.list"
sourcesFile="${sourcesPathSrc}/${sourcesFileName}"

setupLib() {
local name=${1}
local ver=${2}
local url=${3}

rm -vrf "${name}"

git clone -b "${ver}" "${url}"

pushd "${name}"

git submodule update --init --recursive

# Run bootstrap
[ -f 'bootstrap.sh' ] && chmod +x ./bootstrap.sh && ./bootstrap.sh
[ -f 'bootstrap' ] && chmod +x bootstrap && ./bootstrap

# Configure for build
if [ -f 'autogen.sh' ]; then
	chmod +x ./autogen.sh
	[ "${buildMode}" -eq 0 ] && ./autogen.sh --prefix=${buildPrefix} --with-openssl --without-cuse --with-tss-user=root --with-tss-group=root --with-tpm2
	[ "${buildMode}" -eq 1 ] && ./autogen.sh --host=${hostArch} --with-sysroot="${sysrootPath}" --prefix=${buildPrefix} --with-openssl --without-cuse --with-tss-user=root --with-tss-group=root --with-tpm2
elif [ -f 'configure' ]; then
	chmod +x ./configure
	[ "${buildMode}" -eq 0 ] && ./configure --prefix=${buildPrefix} --with-dbuspolicydir="${dbusDir}" --with-udevrulesdir="${udevDir}" --with-systemdsystemunitdir="${systemdDir}" --with-systemdpresetdir="${systemdPresetDir}" --datarootdir="${dataRootDir}"
	[ "${buildMode}" -eq 1 ] && ./configure --host=${hostArch} --with-sysroot="${sysrootPath}" --prefix=${buildPrefix} --with-dbuspolicydir="${dbusDir}" --with-udevrulesdir="${udevDir}" --with-systemdsystemunitdir="${systemdDir}" --with-systemdpresetdir="${systemdPresetDir}" --datarootdir="${dataRootDir}"
fi

# Build using make with threads == cores
make -j"${cpus}"

# Ensure tests and checks pass etc
# make check

# Install also to the host machine for libs to be available for linking later
[ "${buildMode}" -eq 0 ] && make install

# Install to prefixed location
DESTDIR="${buildDest}" make install

popd
}


################################################################################
################################	START	####################################
################################################################################

[[ ${1} == 'test' ]] && echo "Script self-test OK" && exit 0

# pushd ${workingDir}

if [ "${buildMode}" -eq 1 ]; then
	# Ensure architecture specified correctly in existing sources lists
	sed -i "${hostArchReplaceLine}" ${mainSourcesFile}
	sed -i "${hostArchReplaceLine}" ${sourcesPathDest}/* || true
fi

waitAptitude
installPackages "${requiredPkgs}"

if [ "${buildMode}" -eq 1 ]; then
	waitAptitude
	installPackages "${crossPkgs}"

	export CFLAGS="--sysroot=${sysrootPath} -I/usr/include -I/usr/include/glib-2.0 -I/usr/include/* -I/usr/include/aarch64-linux-gnu/glib-2.0 -I/usr/include/aarch64-linux-gnu -I/usr/include/aarch64-linux-gnu/* -I${buildDest}/usr/include -I${sysrootPath}/usr/include -L/usr/lib -L/usr/lib/aarch64-linux-gnu -L${buildDest}/usr/lib -L${sysrootPath}/usr/lib"
	export CXXFLAGS="--sysroot=${sysrootPath} -I/usr/include -I/usr/include/glib-2.0 -I/usr/include/* -I/usr/include/aarch64-linux-gnu/glib-2.0 -I/usr/include/aarch64-linux-gnu -I/usr/include/aarch64-linux-gnu/* -I${buildDest}/usr/include -I${sysrootPath}/usr/include -L/usr/lib -L/usr/lib/aarch64-linux-gnu -L${buildDest}/usr/lib -L${sysrootPath}/usr/lib"
	export LDFLAGS="--sysroot=${sysrootPath} -I/usr/include -I/usr/include/glib-2.0 -I/usr/include/* -I/usr/include/aarch64-linux-gnu/glib-2.0 -I/usr/include/aarch64-linux-gnu -I/usr/include/aarch64-linux-gnu/* -L${buildDest}/usr/lib -L${sysrootPath}/usr/lib"

	export PKG_CONFIG_PATH="/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/aarch64-linux-gnu:/usr/lib/pkgconfig:/usr/share/pkgconfig:/usr/lib:${buildDest}/usr/lib/pkgconfig:${buildDest}/usr/share/pkgconfig:${buildDest}/usr/lib:${sysrootPath}/usr/lib/pkgconfig:${sysrootPath}/usr/share/pkgconfig"
	export PKG_CONFIG_LIBDIR="/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/aarch64-linux-gnu:/usr/lib/pkgconfig:/usr/share/pkgconfig:/usr/lib:${buildDest}/usr/lib/pkgconfig:${buildDest}/usr/share/pkgconfig:${buildDest}/usr/lib:${sysrootPath}/usr/lib/pkgconfig:${sysrootPath}/usr/share/pkgconfig:${sysrootPath}/usr/lib"
	export PKG_CONFIG_SYSROOT_DIR="${sysrootPath}"

	# Ensure target architecture marked on separate sources
	sed -i "${targetArchReplaceLine}" "${sourcesFile}"
	cp -v "${sourcesFile}" ${sourcesPathDest}
	dpkg --add-architecture ${dpkgArch}

	waitAptitude
	apt-get update -y
	for dep in "${buildDeps[@]}"; do
		installPackage "${dep}:${dpkgArch}"
	done
fi

rm -vrf ${buildDest}
mkdir -v ${buildDest}

# Clone, build and install libtmps
setupLib ${repoName} ${repoVersion} "${repoUrl}"
echo "Build & Install libtpms done"

# Clone, build and install swtpm
setupLib ${repoName2} ${repoVersion2} "${repoUrl2}"
echo "Build & Install swtpm done"

# Clone, build and install tpm2-tss
setupLib ${repoName3} ${repoVersion3} "${repoUrl3}"
echo "Build & Install tpm2-tss done"

# Clone, build and install tpm2-abrmd
setupLib ${repoName4} ${repoVersion4} "${repoUrl4}"
echo "Build & Install tpm2-abrmd done"

tar -czvf ${pkgArchive} -C ${buildDest} .
chmod 0644 ${pkgArchive}

# popd

echo "${0} DONE"
