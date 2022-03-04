#!/bin/bash
set -e

listDevices() {
	devices=$(find /dev/ -type b -name "sd[a-z]")
	echo -e "USAGE: ${0} <device>\nList of SCSI block devices:\n${devices}"
}

# For windows machines, this check is not valid so omit it
kernel=$(uname -a)
kernel=${kernel,,}
userId=$(id -u)
[[ ${kernel} =~ "mingw" || ${kernel} =~ "cygwin" ]] || { (( userId != 0 )) && echo "Bash Emulator not detected and current user not root/sudo. This script must be run as root user or with sudo privileges." && exit 1; }

targetDev="${1}" && [ -z "${targetDev}" ] && echo "Given targetDev is empty or not set." && listDevices && exit 1
[[ ! -b ${targetDev} ]] && echo "Block device '${targetDev}' does not exist!" && listDevices && exit 1

# [[ ${targetDev} == *"sda"* || ${targetDev} == *"sdb"* || ${targetDev} == *"sdc"* ]] && echo "ERROR: Protected device." && exit 1

paramsFile='config/local_config'

# Read and parse common variables
# shellcheck disable=SC1090
source "${paramsFile}"

workingDir="${HOME}/Downloads"

imgServer=${IMAGE_SERVER_URL} && [ -z "${imgServer}" ] && echo "Variable imgServer is empty or not set." && exit 1
sasToken=${SAS_TOKEN_URL_QUERY} && [ -z "${sasToken}" ] && echo "Variable sasToken is empty or not set." && exit 1

imgVerFile=${IMAGE_VER_FILE} && [ -z "${imgVerFile}" ] && echo "Variable imgVerFile is empty or not set." && exit 1
imgOs=${IMAGE_OS} && [ -z "${imgOs}" ] && echo "Variable imgOs is empty or not set." && exit 1
imgArch=${IMAGE_ARCH} && [ -z "${imgArch}" ] && echo "Variable imgArch is empty or not set." && exit 1

# Complete URL for fetching the latest image version
imgVerFileUrl="${imgServer}/${imgOs}/${imgArch}/${imgVerFile}${sasToken}"

imgFilesListUrl="${imgServer}/${imgOs}/${imgArch}${sasToken}&comp=list&restype=directory"


#################
##### START #####
#################

cd "${workingDir}"

read -rp "DATA LOSS WARNING! Selected device: ${targetDev}. Continue? (y/n) " ans

[[ ${ans} != "y" ]] && { echo "Answer was not YES. Exiting."; exit 0; }

imgVer=$(curl -f -L "${imgVerFileUrl}")
availableImages=$(curl -f -L "${imgFilesListUrl}")
imgFileZip=$(echo "$availableImages" | tr '<>' '\n' | grep "${imgVer}")

[ -z "${imgFileZip}" ] && echo "ERROR: Could not find the correct image file with following parameters: os: ${imgOs} arch: ${imgArch} ver: ${imgVer}. Abort." && exit 1

fileNoExt=${imgFileZip%.*}

imgFile="${fileNoExt}"
imgFileUrl="${imgServer}/${imgOs}/${imgArch}/${imgFileZip}${sasToken}"

{ [ -f "${imgFileZip}" ] && echo "NOTE: File already exists. No need to download."; } || curl -f -L -o "${imgFileZip}" "${imgFileUrl}"

{ [ -f "${imgFile}" ] && echo "NOTE: Image file already exists. No need to unpack."; } || winpty unxz -vv -d -k "${imgFileZip}"

echo "Writing image.."

count=0
countMax=30
while (( count < countMax )) && ! dd status=progress if="${imgFile}" of="${targetDev}" bs=64k; do
	echo ""
	(( count += 1 ))
	sleep 1
done
(( count >= countMax )) && echo "ERROR: Failed to write image to device." && exit 1

echo "Image written to target device."
