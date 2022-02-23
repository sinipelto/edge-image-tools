#!/bin/bash
set -e

# Import common functions
commonScript="common.sh"
# shellcheck source=/dev/null
source ${commonScript}

# Current user NOT root (build agent user)
# Assuming either current user ROOT user or current user has SUDO
userId=$(id -u)
(( userId != 0 )) && echo "Current user not root. This script must be run as root user or with sudo privileges." && exit 1

devMode=${DEV_MODE} && [ -z "${devMode}" ] && echo "Variable devMode is empty or not set." && exit 1
localMode=${LOCAL_MODE} && [ -z "${localMode}" ] && echo "Variable localMode is empty or not set." && exit 1

imgOs=${IMAGE_OS} && [ -z "${imgOs}" ] && echo "Variable imgOs is empty or not set." && exit 1
imgArch=${IMAGE_ARCH} && [ -z "${imgArch}" ] && echo "Variable imgArch is empty or not set." && exit 1

imgVerFile=${IMAGE_VER_FILE} && [ -z "${imgVerFile}" ] && echo "Variable imgVerFile is empty or not set." && exit 1
imgParamsFile=${IMAGE_PARAMS_FILE} && [ -z "${imgParamsFile}" ] && echo "Variable imgParamsFile is empty or not set." && exit 1

versionFromShare=${VERSION_FROM_SHARE} && [ -z "${versionFromShare}" ] && echo "Variable versionFromShare is empty or not set." && exit 1

imgServer=${IMAGE_SERVER_URL} && [ -z "${imgServer}" ] && echo "Variable imgServer is empty or not set." && exit 1
sasToken=${SAS_TOKEN_URL_QUERY} && [ -z "${sasToken}" ] && echo "Variable sasToken is empty or not set." && exit 1

# Complete URL for fetching the latest image version
imgVerFileUrl=${imgServer}/${imgOs}/${imgArch}/${imgVerFile}${sasToken}

initVer=${INITIAL_VERSION} && [ -z "${initVer}" ] && echo "Variable initVer is empty or not set." && exit 1
minorMax=${MINOR_MAX} && [ -z "${minorMax}" ] && echo "Variable minorMax is empty or not set." && exit 1
revMax=${REV_MAX} && [ -z "${revMax}" ] && echo "Variable revMax is empty or not set." && exit 1

distroName=${DISTRO_NAME} && [ -z "${distroName}" ] && echo "Variable distroName is empty or not set." && exit 1
distroVer=${DISTRO_VERSION} && [ -z "${distroVer}" ] && echo "Variable distroVer is empty or not set." && exit 1

maintName=${MAINT_NAME} && [ -z "${maintName}" ] && echo "Variable maintName is empty or not set." && exit 1
maintEmail=${MAINT_EMAIL} && [ -z "${maintEmail}" ] && echo "Variable maintEmail is empty or not set." && exit 1

srcUrl=${SRC_URL} && [ -z "${srcUrl}" ] && echo "Variable srcUrl is empty or not set." && exit 1

srcFileExt=${srcUrl##*.}

imgFile='original.img'
imgFileBak="${imgFile}.bak"

[[ "${srcFileExt}" == "xz" ]] && imgFileZip="${imgFile}.xz"
[[ "${srcFileExt}" == "zip" ]] && imgFileZip="${imgFile}.zip"

newImgFile=${DEST_IMG_FILE} && [ -z "${newImgFile}" ] && echo "Variable newImgFile is empty or not set." && exit 1
newImgFileZip="${newImgFile}.xz"

growImage=${GROW_IMAGE} && [ -z "${growImage}" ] && echo "Variable growImage is empty or not set." && exit 1
growSizeMbytes=${GROW_SIZE_MBYTES} && [ -z "${growSizeMbytes}" ] && echo "Variable growSizeMbytes is empty or not set." && exit 1

zeroDev='/dev/zero'
part1='/media/part1'
part2='/media/part2'

partBoot=1
partRoot=2

qemuBin="qemu-${imgArch}-static"
bashBin="/bin/bash"

rootBin="${part2}/root/bin"

partParamsFile="${part2}/${imgParamsFile}"
partInfoFile="${part2}/image_info"

# License: MIT - Free/Commercial use + modifications
waitforitScript="wait-for-it.sh"

provisionScript="provision-image.sh"
provisionService="provisioning.service"

resizeLine='s/ init=\/usr\/lib\/raspi-config\/init_resize.sh//g'

systemdPath="${part2}/lib/systemd/system/"

assetPath='image_files'

sshFile='ssh'
wpaFile="${assetPath}/wpa_supplicant.conf"
netFile="${assetPath}/network-config"
userFile="${assetPath}/user-data"
netplanFile="${assetPath}/95-network.yaml"

cmdlineFile='cmdline.txt'
cmdlineFile="${part1}/${cmdlineFile}"

delOgUser=${DEL_OG_USER} && [ -z "${delOgUser}" ] && echo "Variable delOgUser is empty or not set." && exit 1

ogUserRaspios='pi'
ogUserUbuntu='ubuntu'

baseUser=${BASE_USER} && [ -z "${baseUser}" ] && echo "Variable baseUser is empty or not set." && exit 1
basePass=${BASE_USER_PASS} && [ -z "${basePass}" ] && echo "Variable basePass is empty or not set." && exit 1

baseHome="/home/${baseUser}"

# Tested with: ubuntu20, raspios armhf, raspios arm64
[[ "${imgOs}" == "rasp"* ]] && baseGroups="adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,input,render,netdev,gpio,i2c,spi"
[[ "${imgOs}" == "ubuntu"* ]] && baseGroups="users,adm,dialout,audio,netdev,video,plugdev,cdrom,games,input,sudo"

sshPubKey=${SSH_PUBLIC_KEY} && [ -z "${sshPubKey}" ] && echo "WARNING: Variable sshPubKey is empty or not set." && exit 1

keyType=${SSH_KEY_TYPE} && [ -z "${keyType}" ] && echo "Variable keyType is empty or not set." && exit 1
keyRounds=${SSH_KEY_ROUNDS} && [ -z "${keyRounds}" ] && echo "Variable keyRounds is empty or not set." && exit 1
keyBits=${SSH_KEY_BITS} && [ -z "${keyBits}" ] && echo "Variable keyBits is empty or not set." && exit 1
keyPhrase=${SSH_KEY_PHRASE}&& { [ -z "${keyPhrase}" ] && echo "WARNING: Variable keyPhrase is empty or not set."; }
keyComment=${SSH_KEY_COMMENT} && [ -z "${keyComment}" ] && echo "Variable keyComment is empty or not set." && exit 1
keyFile=${SSH_KEY_FILE} && [ -z "${keyFile}" ] && echo "Variable keyFile is empty or not set." && exit 1
keyFilePub="${keyFile}.pub"

sudoersFile="${part2}/etc/sudoers.d/010_${baseUser}"

sshPath="${baseHome}/.ssh"
authFile="${sshPath}/authorized_keys"

partSshPath="${part2}${sshPath}"
partAuthFile="${part2}${authFile}"

aptPackages='coreutils bash grep util-linux curl fdisk zip unzip xz-utils binfmt-support qemu-user-static'

# Get CPU thread count for multithreading params
cpus=$(< /proc/cpuinfo grep -c processor)


#################
##### START #####
#################

[[ ${1} == 'test' ]] && echo "Script self-test OK" && exit 0

# Remove scheme abc:// and paths /abc/def/
imgSrv=$(echo "${imgServer}" | awk -F/ '{print $3}')

chmod -v +x ${waitforitScript}
${bashBin} "${PWD}"/${waitforitScript} -t 30 -h "${imgSrv}" -p 443
${bashBin} "${PWD}"/${waitforitScript} -t 30 -h 'archive.ubuntu.com' -p 80
${bashBin} "${PWD}"/${waitforitScript} -t 30 -h 'packages.microsoft.com' -p 443
${bashBin} "${PWD}"/${waitforitScript} -t 30 -h 'deb.debian.org' -p 80

waitAptitude
installPackages "${aptPackages}"

# Fetch current version from storage record
# If from storage not allowed or get fails, use clock value for revision
[ "${versionFromShare}" -eq 0 ] && imgVer="0.0.$(date '+%s')"
[ "${versionFromShare}" -eq 1 ] && { imgVer=$(curl -f -L "${imgVerFileUrl}") || { echo "Failed to get image version from URL." && imgVer="${initVer}"; } }

# shellcheck disable=SC2206
verArr=(${imgVer//./ })

# Parse version num and handle accordingly
major=${verArr[0]}
minor=${verArr[1]}
rev=${verArr[2]}

# Bump up version num
# Check only equal if clock ver used, will not be bumped
# DONT use expr X++ => fails on trap when var=0 ((var++))
if (( minor == minorMax && rev == revMax )); then (( major+=1 )) && minor=0 && rev=0
elif (( rev == revMax )); then (( minor+=1 )) && rev=0
else (( rev+=1 ))
fi

imgVer="${major}.${minor}.${rev}"
echo ${imgVer} > "${imgVerFile}"

rm -fv ./*.img
if [ "${devMode}" -eq 1 ] && [ "${localMode}" -eq 1 ] && [ -f "${imgFileBak}" ]; then
	cp -v ${imgFileBak} ${imgFile}
else
	rm -fv ${imgFileZip}
	curl -f -L -o ${imgFileZip} "${srcUrl}"
	[[ ${srcFileExt} == "xz" ]] && unxz -vv -d -k -T "${cpus}" ${imgFileZip}
	[[ ${srcFileExt} == "zip" ]] && unzip -o ${imgFileZip}
	mv -v ./*.img ${imgFile} || true
#	[ "${localMode}" -eq 1 ] && cp -v ${imgFile} ${imgFile}.bak
fi

sync
umount -lfv ${part1} || true
umount -lfv ${part2} || true
sync

rm -rfv ${part1}
rm -rfv ${part2}

mkdir -pv ${part1}
mkdir -pv ${part2}

sync
losetup -v -D
sync

if [ "${growImage}" -eq 1 ]; then
	dd status=progress if=${zeroDev} bs=1M count="${growSizeMbytes}" >> ${imgFile}

	loopDev=$(losetup -f)
	losetup -v -f -P ${imgFile}

	parted "${loopDev}" resizepart ${partRoot} 100%

	sleep 1
	sync
	sleep 2

	e2fsck -v -y -f "${loopDev}p${partRoot}"

	sleep 1
	sync
	sleep 2

	# No --verbose available
	resize2fs "${loopDev}p${partRoot}"

	sleep 1
	sync
	sleep 2

	e2fsck -v -y -f "${loopDev}p${partRoot}"

	sleep 1
	sync
	sleep 2

	zerofree -v "${loopDev}p${partRoot}"

#	rm -fv ${extImgFile}
#	dd status=progress if="${loopDev}" of=${extImgFile} bs=${imgBlockSize}

	sleep 1
	sync
	sleep 2

	losetup -v -d "${loopDev}"

	sleep 1
	sync
	sleep 2

	losetup -v -D

	sleep 1
	sync
	sleep 2

#	rm -fv ${imgFile}
#	mv -v ${extImgFile} ${imgFile}
fi

loopDev=$(losetup -f)
losetup -v -f -P ${imgFile}

mount -v -t vfat -o rw "${loopDev}p${partBoot}" ${part1}
mount -v -t ext4 -o rw "${loopDev}p${partRoot}" ${part2}

touch ${part1}/${sshFile}

cp -v ${wpaFile} ${part1}/
cp -v ${netFile} ${part1}/
cp -v ${userFile} ${part1}/

# NOTE: If disabled part+fs resizing => no free space left on rootfs with RaspiOS!
# Solution: For raspios the rootfs partition + fs is resized
sed -i "${resizeLine}" ${cmdlineFile}

[ ! -d ${rootBin} ] && mkdir -vm 0700 ${rootBin}
cp -v ${commonScript} ${rootBin}/
cp -v ${waitforitScript} ${rootBin}/
cp -v ${provisionScript} ${rootBin}/
chmod -vR 0700 ${rootBin}

cp -v ${provisionService} ${systemdPath}/

[[ ${imgOs} == "ubuntu"* ]] && cp -v ${netplanFile} ${part2}/etc/netplan/

cat > "${partParamsFile}" << EOF
export IMAGE_VERSION='${imgVer}'
export IMAGE_OS='${imgOs}'
export IMAGE_ARCH='${imgArch}'
export IMAGE_VER_FILE='${imgVerFile}'
export IMAGE_SERVER_URL='${imgServer}'
export SAS_TOKEN_URL_QUERY='${sasToken}'
export DEV_EDGE_CONNECTION_STRING='${DEV_EDGE_CONNECTION_STRING}'
EOF
chmod -v 0444 "${partParamsFile}"

cat > ${partInfoFile} << EOF
Image Name: Iot Edge Base Image Based on ${distroName} ${distroVer}
Image Description: Patched generic self-provisioning image for IoT Edge devices.
Image Maintainer: ${maintName} <${maintEmail}>
Publish Date: $(date)
EOF
chmod -v 0444 ${partInfoFile}

cat > "${sudoersFile}" << EOF
${baseUser} ALL=(ALL) NOPASSWD:ALL
EOF
chmod -v 0440 "${sudoersFile}"

cp -v "$(which "${qemuBin}")" ${part2}/usr/bin/

sed -i 's/^/#/g' ${part2}/etc/ld.so.preload && preloadModified=1 || preloadModified=0

chroot ${part2} "${qemuBin}" ${bashBin} -vc "systemctl enable ${provisionService}"

if [ "${delOgUser}" -eq 1 ]; then
	{ [[ ${imgOs} == "rasp"* ]] && chroot ${part2} "${qemuBin}" ${bashBin} -vc "userdel -rf ${ogUserRaspios}"; } || true
	{ [[ ${imgOs} == "ubuntu"* ]] && chroot ${part2} "${qemuBin}" ${bashBin} -vc "userdel -rf ${ogUserUbuntu}"; } || true
fi

chroot ${part2} "${qemuBin}" ${bashBin} -vc "useradd -m -G ${baseGroups} -s ${bashBin} ${baseUser}"

[ ! -d "${partSshPath}" ] && mkdir -vm 0700 "${partSshPath}"

if [ -n "${sshPubKey}" ]; then
cat >> "${partAuthFile}" << EOF
${sshPubKey}
EOF
else
	echo "SSH Public key variable is empty, omitting.."
fi

if [ "${devMode}" -eq 1 ]; then
	# NO VERBOSE, password echoed
	chroot ${part2} "${qemuBin}" ${bashBin} -c "echo '${baseUser}:${basePass}' | chpasswd"

	# If dev + local, generate new ssh key to local, and append it to auth keys
	if [ "${localMode}" -eq 1 ]; then
		rm -fv "${keyFile}"*
		ssh-keygen -t "${keyType}" -a "${keyRounds}" -b "${keyBits}" -N "${keyPhrase}" -C "${keyComment}" -f "${keyFile}"
		cat "${keyFilePub}" >> "${partAuthFile}"
	fi
else
chroot ${part2} "${qemuBin}" ${bashBin} -vc "passwd -e -d -l ${baseUser}"
fi

chroot ${part2} "${qemuBin}" ${bashBin} -vc "chown -vR ${baseUser}:${baseUser} ${baseHome}"

chroot ${part2} "${qemuBin}" ${bashBin} -vc "chmod -v 0644 ${authFile}"

[ ${preloadModified} -eq 1 ] && sed -i 's/^#//g' ${part2}/etc/ld.so.preload

sleep 1
sync
sleep 2
umount -v ${part1}
umount -v ${part2}
sleep 1
sync
sleep 2
losetup -v -d "${loopDev}"
sleep 1
sync
sleep 2
losetup -v -D
sleep 1
sync
sleep 2

mv -v ${imgFile} "${newImgFile}"

rm -fv "${newImgFileZip}"
xz -vv -z -f -k -T "${cpus}" "${newImgFile}"
