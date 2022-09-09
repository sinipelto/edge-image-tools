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

# Import common functions
commonScript='common.sh'
# shellcheck source=/dev/null
source ${commonScript}

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


#################
##### START #####
#################

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
