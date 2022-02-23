#!/bin/bash
set -e

# Import common functions
# shellcheck source=/dev/null
source common.sh

# Current user NOT root (build agent user)
# Assuming either current user ROOT user or current user has SUDO
userId=$(id -u)
(( userId != 0 )) && echo "Current user not root. This script must be run as root user or with sudo privileges." && exit 1

dateStamp=$(date '+%Y-%m-%d')

devMode=${DEV_MODE} && [ -z "${devMode}" ] && echo "Variable devMode is empty or not set." && exit 1
localMode=${LOCAL_MODE} && [ -z "${localMode}" ] && echo "Variable localMode is empty or not set." && exit 1

imgVerFile=${IMAGE_VER_FILE} && [ -z "${imgVerFile}" ] && echo "Variable imgVerFile is empty or not set." && exit 1
imgOs=${IMAGE_OS} && [ -z "${imgOs}" ] && echo "Variable imgOs is empty or not set." && exit 1
imgArch=${IMAGE_ARCH} && [ -z "${imgArch}" ] && echo "Variable imgArch is empty or not set." && exit 1

imgFile=${DEST_IMG_FILE} && [ -z "${imgFile}" ] && echo "Variable imgFile is empty or not set." && exit 1
imgFileZip="${imgFile}.xz"

mountPoint="/media/azure_img_share"
remoteMountPoint=${SMB_REMOTE_MOUNT_POINT} && [ -z "${remoteMountPoint}" ] && echo "Variable remoteMountPoint is empty or not set." && exit 1

smbVer=3.0
fileMode=0777

username=${SMB_USERNAME} && [ -z "${username}" ] && echo "Variable username is empty or not set." && exit 1
password=${SMB_PASSWORD} && [ -z "${password}" ] && echo "Variable password is empty or not set." && exit 1

aptPackages='coreutils bash util-linux cifs-utils'

credFile="${PWD}/smbcredentials.cred"

[[ ${1} == 'test' ]] && echo "Script self-test OK" && exit 0

# Bumped by create-image.sh!
imgVer=$(cat "${imgVerFile}")

newImgFile="${imgOs}-${imgArch}_${dateStamp}_${imgVer}.img"
newImgFileZip="${newImgFile}.xz"

remoteImgPath="${mountPoint}/${imgOs}/${imgArch}"

remoteVerFile="${remoteImgPath}/${imgVerFile}"
remoteNewImgZip="${remoteImgPath}/${newImgFileZip}"


##### START #####

[ ! -f "${imgFileZip}" ] && echo "ERROR: Image Archive does not exist." && exit 1

waitAptitude
installPackages "${aptPackages}"

# No extra verbosity when echoing credentials!
echo "username=${username}" > "${credFile}"
echo "password=${password}" >> "${credFile}"

chmod -v 0400 "${credFile}"

umount -vlf ${mountPoint} || true

rm -rfv ${mountPoint}
mkdir -vp ${mountPoint}

mount -v -t cifs "${remoteMountPoint}" ${mountPoint} -o vers=${smbVer},credentials="${credFile}",dir_mode=${fileMode},file_mode=${fileMode},serverino

[ ! -d "${remoteImgPath}" ] && mkdir -vp "${remoteImgPath}"

cp -v "${imgFileZip}" "${remoteNewImgZip}"

echo "${imgVer}" > "${remoteVerFile}"

umount -v ${mountPoint}
