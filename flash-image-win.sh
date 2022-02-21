#!/bin/bash
set -e

# TODO find out what is the device name in bash emulator - /dev/sdX or \\.\PhysicalDriveX not working!
#targetDev="${1}" && { [ -z "${targetDev}" ] && echo "Given targetDev is empty or not set." && echo "USAGE: ${0} <device>" && exit 1; }

# Read and parse common variables
varFile="<REMOVED>"

# shellcheck disable=SC1091
source "${varFile}"

imgServer=${IMAGE_SERVER_URL} && { [ -z "${imgServer}" ] && echo "Variable imgServer is empty or not set." && exit 1; }
sasToken=${SAS_TOKEN} && { [ -z "${sasToken}" ] && echo "Variable sasToken is empty or not set." && exit 1; }

imgVerFile=${IMAGE_VER_FILE} && { [ -z "${imgVerFile}" ] && echo "Variable imgVerFile is empty or not set." && exit 1; }
imgOs=${IMAGE_OS} && { [ -z "${imgOs}" ] && echo "Variable imgOs is empty or not set." && exit 1; }
imgArch=${IMAGE_ARCH} && { [ -z "${imgArch}" ] && echo "Variable imgArch is empty or not set." && exit 1; }

# Complete URL for fetching the latest image version
imgVerFileUrl="${imgServer}/${imgOs}/${imgArch}/${imgVerFile}${sasToken}"

imgFilesListUrl="${imgServer}/${imgOs}/${imgArch}${sasToken}&comp=list&restype=directory"


##### START #####

npm i -g etcher

imgVer=$(curl -f -L "${imgVerFileUrl}")

availableImages=$(curl -f -L "${imgFilesListUrl}")
imgFileZip=$(echo "$availableImages" | tr '<>' '\n' | grep "${imgVer}")

[ -z "${imgFileZip}" ] && echo "ERROR: Could not find the correct image file with following parameters: os: ${imgOs} arch: ${imgArch} ver: ${imgVer}. Abort." && exit 1

#fileExt=${imgFileZip##*.}
fileNoExt=${imgFileZip%.*}

imgFile="${fileNoExt}"
imgFileUrl="${imgServer}/${imgOs}/${imgArch}/${imgFileZip}${sasToken}"

echo $imgFileZip
{ [ -f "${imgFileZip}" ] && echo "NOTE: File already exists. No need to download."; } || curl -f -L -o "${imgFileZip}" "${imgFileUrl}"

echo $imgFile
{ [ -f "${imgFile}" ] && echo "NOTE: Image file already exists. No need to unpack."; } || winpty unxz -vv -d -k "${imgFileZip}"

# TODO: Figure out how to find the correct device name inside Cygwin/Mingw bash emulator
#etcher -y -d "${targetDev}" "${imgFile}"

# This works -> Finds and prompts the correct device
etcher "${imgFile}"
