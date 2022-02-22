#!/bin/bash
set -e

targetDev="${1}" && { [ -z "${targetDev}" ] && echo "Given targetDev is empty or not set." && echo -e "USAGE: ${0} <device>\nList of SCSI block devices: $(ls -l /dev/sd*)" && exit 1; }

# [[ ${targetDev} == *"sda"* || ${targetDev} == *"sdb"* || ${targetDev} == *"sdc"* ]] && echo "ERROR: Protected device." && exit 1

paramsFile='config/local_config'

# Read and parse common variables
# shellcheck disable=SC1090
source "${paramsFile}"

workingDir="${HOME}/Downloads"

imgServer=${IMAGE_SERVER_URL} && { [ -z "${imgServer}" ] && echo "Variable imgServer is empty or not set." && exit 1; }
sasToken=${SAS_TOKEN_URL_QUERY} && { [ -z "${sasToken}" ] && echo "Variable sasToken is empty or not set." && exit 1; }

imgVerFile=${IMAGE_VER_FILE} && { [ -z "${imgVerFile}" ] && echo "Variable imgVerFile is empty or not set." && exit 1; }
imgOs=${IMAGE_OS} && { [ -z "${imgOs}" ] && echo "Variable imgOs is empty or not set." && exit 1; }
imgArch=${IMAGE_ARCH} && { [ -z "${imgArch}" ] && echo "Variable imgArch is empty or not set." && exit 1; }

# Complete URL for fetching the latest image version
imgVerFileUrl="${imgServer}/${imgOs}/${imgArch}/${imgVerFile}${sasToken}"

imgFilesListUrl="${imgServer}/${imgOs}/${imgArch}${sasToken}&comp=list&restype=directory"


##### START #####

cd "${workingDir}"

imgVer=$(curl -f -L "${imgVerFileUrl}")

availableImages=$(curl -f -L "${imgFilesListUrl}")
imgFileZip=$(echo "$availableImages" | tr '<>' '\n' | grep "${imgVer}")

[ -z "${imgFileZip}" ] && echo "ERROR: Could not find the correct image file with following parameters: os: ${imgOs} arch: ${imgArch} ver: ${imgVer}. Abort." && exit 1

#fileExt=${imgFileZip##*.}
fileNoExt=${imgFileZip%.*}

imgFile="${fileNoExt}"
imgFileUrl="${imgServer}/${imgOs}/${imgArch}/${imgFileZip}${sasToken}"

{ [ -f "${imgFileZip}" ] && echo "NOTE: File already exists. No need to download."; } || curl -f -L -o "${imgFileZip}" "${imgFileUrl}"

{ [ -f "${imgFile}" ] && echo "NOTE: Image file already exists. No need to unpack."; } || winpty unxz -vv -d -k "${imgFileZip}"

echo "Writing image.."

dd status=progress if="${imgFile}" of="${targetDev}" bs=64k

echo "Image written to target device."
