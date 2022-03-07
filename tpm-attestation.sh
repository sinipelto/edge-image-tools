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

requiredPkgs='git cmake build-essential curl libcurl4-openssl-dev libssl-dev uuid-dev libseccomp-dev libgnutls28-dev ca-certificates automake autoconf bash coreutils dh-autoreconf libtasn1-6-dev net-tools iproute2 libjson-glib-dev expect libtool sed devscripts equivs gcc dh-exec pkg-config gawk make socat'

repoName='azure-iot-sdk-c'
repoVersion='lts_01_2022'
repoUrl="https://github.com/Azure/${repoName}.git"

srcFile='provisioning_client/samples/prov_dev_client_sample/prov_dev_client_sample.c'

# NOTE: global endpoint already defined in the source
# iotDpsGlobalEndpoint='global.azure-devices-provisioning.net'
iotDpsIdScope='0ne00000000'

iotProtocol='AMQP'
iotHsmType='SECURE_DEVICE_TYPE_TPM'

workingDir=${PWD}
# workingDir="/root"

# Get CPU thread count for multithreading params
cpus=$(nproc)


################################################################################
################################	START	####################################
################################################################################

cd "${workingDir}"

waitAptitude
installPackages "${requiredPkgs}"

rm -vrf ${repoName}

git clone -b ${repoVersion} ${repoUrl}

cd ${repoName}

git submodule update --init

# sed 's/^[[:space:]]*#define SAMPLE_/\/\/&/' test.c > out.c && cat out.c
# sed "s/\/\/[[:space:]]*#define SAMPLE_${iotProtocol}$/#define SAMPLE_${iotProtocol}/" out.c

sed -i 's/^[[:space:]]*#define SAMPLE_/\/\/&/' ${srcFile}
sed -i "s/\/\/[[:space:]]*#define SAMPLE_${iotProtocol}$/#define SAMPLE_${iotProtocol}/" ${srcFile}

# sed 's/^[[:space:]]*hsm_type = SECURE_DEVICE_TYPE_/\/\/&/' test.c > out.c && cat out.c
# sed "s/\/\/[[:space:]]*hsm_type = ${iotHsmType};$/hsm_type = ${iotHsmType};/" out.c

sed -i 's/^[[:space:]]*hsm_type = SECURE_DEVICE_TYPE_/\/\/&/' ${srcFile}
sed -i "s/\/\/[[:space:]]*hsm_type = ${iotHsmType};$/hsm_type = ${iotHsmType};/" ${srcFile}

sed -i "s/static const char\* id_scope = .*/static const char\* id_scope = \"${iotDpsIdScope}\";/" ${srcFile}

mkdir -v cmake

cd cmake

cmake -Duse_prov_client:BOOL=ON ..

cmake --build . -- -j "${cpus}"

# TODO: run tpm provision bin to get the EK and RegID

echo "DONE"
