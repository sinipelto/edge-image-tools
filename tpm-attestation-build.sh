#!/bin/bash
set -e

userId=$(id -u)
(( userId != 0 )) && echo "Current user not root. This script must be run as root user or with sudo privileges." && exit 1

paramsFile='/image_params'

bashBin='/bin/bash'
rootBin='/root/bin'

waitBin='wait-for-it.sh'
commonBin='common.sh'

# waitBin="${rootBin}/wait-for-it.sh"
# commonBin="${rootBin}/common.sh"

# shellcheck source=/dev/null
source ${commonBin}

# Read image params variables from file
# shellcheck source=/dev/null
# source ${paramsFile}

# NOTE: global endpoint already defined in the source
# iotDpsGlobalEndpoint='global.azure-devices-provisioning.net'
idScope=${DPS_ID_SCOPE:?Variable DPS_ID_SCOPE is empty or not set.}

requiredPkgs='git cmake build-essential curl autoconf autoconf-archive libcmocka0 libcmocka-dev
	procps libcurl4-openssl-dev libssl-dev uuid-dev uthash-dev doxygen libltdl-dev libseccomp-dev
	libgnutls28-dev ca-certificates automake bash coreutils dh-autoreconf libtasn1-6-dev net-tools
	iproute2 libjson-c-dev libjson-glib-dev libini-config-dev expect libtool sed devscripts equivs
	gcc dh-exec pkgconf gawk make socat softhsm gnutls-bin glib-2.0'

repoName='azure-iot-sdk-c'
repoVersion='lts_01_2022_custom'
repoUrl="https://github.com/sinipelto/${repoName}.git"

buildDir='cmake'

provTool='provisioning_client/tools/tpm_device_provision/tpm_device_provision'

provClient='provisioning_client/samples/prov_dev_client_sample/prov_dev_client_sample'
provClientSrc="${provClient}.c"

provClientLL='provisioning_client/samples/prov_dev_client_ll_sample/prov_dev_client_ll_sample'
provClientLLSrc="${provClientLL}.c"

replaceIdScope="s/[[:space:]]*static[[:space:]]*const[[:space:]]*char[[:space:]]*\*[[:space:]]*id_scope[[:space:]]*=.*/static const char\* id_scope = \"${idScope}\";/"

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

# NOTE: All non-personal critical edits are made in the forked version of the repo

# sed 's/^[[:space:]]*#define SAMPLE_/\/\/&/' test.c > out.c && cat out.c
# sed "s/\/\/[[:space:]]*#define SAMPLE_${iotProtocol}$/#define SAMPLE_${iotProtocol}/" out.c

# sed -i 's/^[[:space:]]*#define SAMPLE_/\/\/&/' ${srcFile}
# sed -i "s/\/\/[[:space:]]*#define SAMPLE_${iotProtocol}$/#define SAMPLE_${iotProtocol}/" ${srcFile}

# sed 's/^[[:space:]]*hsm_type = SECURE_DEVICE_TYPE_/\/\/&/' test.c > out.c && cat out.c
# sed "s/\/\/[[:space:]]*hsm_type = ${iotHsmType};$/hsm_type = ${iotHsmType};/" out.c

# sed -i 's/^[[:space:]]*hsm_type = SECURE_DEVICE_TYPE_/\/\/&/' ${srcFile}
# sed -i "s/\/\/[[:space:]]*hsm_type = ${iotHsmType};$/hsm_type = ${iotHsmType};/" ${srcFile}

# Change the ID scope from the source file(s) to the one defined in settings
sed -i "${replaceIdScope}" ${provClientSrc}
sed -i "${replaceIdScope}" ${provClientLLSrc}

rm -vrf ${buildDir}
mkdir -v ${buildDir}

pushd ${buildDir}

cmake -Duse_prov_client:BOOL=ON ..

cmake --build . -- -j "${cpus}"

# Go back to original dir
# popd
# popd
# popd

echo "${0} DONE"
