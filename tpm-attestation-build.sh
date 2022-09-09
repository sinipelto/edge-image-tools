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

commonBin='common.sh'

# shellcheck source=/dev/null
source ${commonBin}

requiredPkgs='git cmake build-essential curl autoconf autoconf-archive libcmocka0 libcmocka-dev
	procps libcurl4-openssl-dev libssl-dev uuid-dev uthash-dev doxygen libltdl-dev libseccomp-dev
	libgnutls28-dev ca-certificates automake bash coreutils dh-autoreconf libtasn1-6-dev net-tools
	iproute2 libjson-c-dev libjson-glib-dev libini-config-dev expect libtool sed devscripts equivs
	gcc dh-exec pkgconf gawk make socat softhsm gnutls-bin glib-2.0'

repoName='azure-iot-sdk-c'
repoVersion='lts_01_2022_custom'
repoUrl="https://github.com/sinipelto/${repoName}.git"

buildDir='prov_bundle'

bundleZipName="prov-bundle.tar.gz"
bundleZip="${PWD}/${bundleZipName}"

# workingDir='/root'

# Get CPU thread count for multithreading params
cpus=$(nproc)
cpus=$((cpus * 2))


################################################################################
################################	START	####################################
################################################################################

[[ ${1} == 'test' ]] && echo "Script self-test OK" && exit 0

# pushd ${workingDir}

waitAptitude
installPackages "${requiredPkgs}"

rm -vrf ${repoName}

git clone -b ${repoVersion} ${repoUrl}

pushd ${repoName}

git submodule update --init --recursive

rm -vrf ${buildDir}
mkdir -v ${buildDir}

pushd ${buildDir}

cmake -Duse_prov_client:BOOL=ON ..

cmake --build . -- -j "${cpus}"

# Go back to original dir
popd

rm -vf "${bundleZip}"
tar -czvf "${bundleZip}" -C . ${buildDir}

popd

# popd

echo "${0} DONE"
