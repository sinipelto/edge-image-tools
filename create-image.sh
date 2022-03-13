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

devMode=${DEV_MODE} && [ -z "${devMode}" ] && echo "Variable DEV_MODE is empty or not set." && exit 1
localMode=${LOCAL_MODE} && [ -z "${localMode}" ] && echo "Variable LOCAL_MODE is empty or not set." && exit 1

imgOs=${IMAGE_OS} && [ -z "${imgOs}" ] && echo "Variable IMAGE_OS is empty or not set." && exit 1
imgArch=${IMAGE_ARCH} && [ -z "${imgArch}" ] && echo "Variable IMAGE_ARCH is empty or not set." && exit 1

imgVerFile=${IMAGE_VER_FILE} && [ -z "${imgVerFile}" ] && echo "Variable IMAGE_VER_FILE is empty or not set." && exit 1
imgParamsFile=${IMAGE_PARAMS_FILE} && [ -z "${imgParamsFile}" ] && echo "Variable IMAGE_PARAMS_FILE is empty or not set." && exit 1

versionFromShare=${VERSION_FROM_SHARE} && [ -z "${versionFromShare}" ] && echo "Variable VERSION_FROM_SHARE is empty or not set." && exit 1

imgServer=${IMAGE_SERVER_URL} && [ -z "${imgServer}" ] && echo "Variable IMAGE_SERVER_URL is empty or not set." && exit 1
sasToken=${SAS_TOKEN_URL_QUERY} && [ -z "${sasToken}" ] && echo "Variable SAS_TOKEN_URL_QUERY is empty or not set." && exit 1

# Complete URL for fetching the latest image version
imgVerFileUrl=${imgServer}/${imgOs}/${imgArch}/${imgVerFile}${sasToken}

initVer=${INITIAL_VERSION} && [ -z "${initVer}" ] && echo "Variable INITIAL_VERSION is empty or not set." && exit 1
minorMax=${MINOR_MAX} && [ -z "${minorMax}" ] && echo "Variable MINOR_MAX is empty or not set." && exit 1
revMax=${REV_MAX} && [ -z "${revMax}" ] && echo "Variable REV_MAX is empty or not set." && exit 1

distroName=${DISTRO_NAME} && [ -z "${distroName}" ] && echo "Variable DISTRO_NAME is empty or not set." && exit 1
distroVer=${DISTRO_VERSION} && [ -z "${distroVer}" ] && echo "Variable DISTRO_VERSION is empty or not set." && exit 1

maintName=${MAINT_NAME} && [ -z "${maintName}" ] && echo "Variable MAINT_NAME is empty or not set." && exit 1
maintEmail=${MAINT_EMAIL} && [ -z "${maintEmail}" ] && echo "Variable MAINT_EMAIL is empty or not set." && exit 1

srcUrl=${IMAGE_SRC_URL} && [ -z "${srcUrl}" ] && echo "Variable IMAGE_SRC_URL is empty or not set." && exit 1

srcFileExt=${srcUrl##*.}

imgFile='original.img'
imgFileBak="${imgFile}.bak"

[[ "${srcFileExt}" == "xz" ]] && imgFileZip="${imgFile}.xz"
[[ "${srcFileExt}" == "zip" ]] && imgFileZip="${imgFile}.zip"

newImgFile=${DEST_IMG_FILE} && [ -z "${newImgFile}" ] && echo "Variable DEST_IMG_FILE is empty or not set." && exit 1
newImgFileZip="${newImgFile}.xz"

expandRootfs=${EXPAND_ROOTFS} && [ -z "${expandRootfs}" ] && echo "Variable EXPAND_ROOTFS is empty or not set." && exit 1
growSizeMbytes=${EXPAND_SIZE_MBYTES} && [ -z "${growSizeMbytes}" ] && echo "Variable EXPAND_SIZE_MBYTES is empty or not set." && exit 1
growPercentage=${EXPAND_PERCENTAGE} && [ -z "${growPercentage}" ] && echo "Variable EXPAND_PERCENTAGE is empty or not set." && exit 1

createPersistence=${USE_PERSISTENCE} && [ -z "${createPersistence}" ] && echo "Variable USE_PERSISTENCE is empty or not set." && exit 1
persistenceSize=${PERSISTENCE_SIZE_MBYTES} && [ -z "${persistenceSize}" ] && echo "Variable PERSISTENCE_SIZE_MBYTES is empty or not set." && exit 1

zeroDev='/dev/zero'

part1='/media/boot' # Boot
part2='/media/root' # Rootfs
part3='/media/persistence' # Persistence

partNumBoot=1
partNumRoot=2
partNumPersist=3

qemuBin="qemu-${imgArch}-static"
bashBin='/bin/bash'

rootBin="${part2}/root/bin"

persistencePath="${part2}/persistence"

partParamsFile="${part2}/${imgParamsFile}"
partInfoFile="${part2}/image_info"

tpmDeviceSetupScript='tpm-device-setup.sh'

# License: MIT - Free/Commercial use + modifications
waitforitScript='wait-for-it.sh'

provisionScript='provision-image.sh'
provisionService='provisioning.service'
provisionServicePath="services/${provisionService}"

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

delOgUser=${DEL_OG_USER} && [ -z "${delOgUser}" ] && echo "Variable DEL_OG_USER is empty or not set." && exit 1

ogUserRaspios='pi'
ogUserUbuntu='ubuntu'

baseUser=${BASE_USER} && [ -z "${baseUser}" ] && echo "Variable BASE_USER is empty or not set." && exit 1
basePass=${BASE_USER_PASS} && [ -z "${basePass}" ] && echo "WARNING: Variable BASE_USER_PASS is empty or not set."

baseHome="/home/${baseUser}"

# Tested with: ubuntu20, raspios armhf, raspios arm64
[[ "${imgOs}" == "rasp"* ]] && baseGroups="adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,input,render,netdev,gpio,i2c,spi"
[[ "${imgOs}" == "ubuntu"* ]] && baseGroups="users,adm,dialout,audio,netdev,video,plugdev,cdrom,games,input,sudo"

sshPubKey=${SSH_PUBLIC_KEY} && [ -z "${sshPubKey}" ] && echo "WARNING: Variable SSH_PUBLIC_KEY is empty or not set."

createLocalKey=${CREATE_LOCAL_SSH_KEY} && [ -z "${createLocalKey}" ] && echo "Variable CREATE_LOCAL_SSH_KEY is empty or not set." && exit 1

keyType=${SSH_KEY_TYPE} && [ -z "${keyType}" ] && echo "Variable SSH_KEY_TYPE is empty or not set." && exit 1
keyRounds=${SSH_KEY_ROUNDS} && [ -z "${keyRounds}" ] && echo "Variable SSH_KEY_ROUNDS is empty or not set." && exit 1
keyBits=${SSH_KEY_BITS} && [ -z "${keyBits}" ] && echo "Variable SSH_KEY_BITS is empty or not set." && exit 1
keyPhrase=${SSH_KEY_PHRASE} && [ -z "${keyPhrase}" ] && echo "WARNING: Variable SSH_KEY_PHRASE is empty or not set."
keyComment=${SSH_KEY_COMMENT} && [ -z "${keyComment}" ] && echo "WARNING: Variable SSH_KEY_COMMENT is empty or not set."
keyFile=${SSH_KEY_FILE} && [ -z "${keyFile}" ] && echo "Variable SSH_KEY_FILE is empty or not set." && exit 1
keyFilePub="${keyFile}.pub"

sudoersFile="${part2}/etc/sudoers.d/010_${baseUser}"

sshPath="${baseHome}/.ssh"
authFile="${sshPath}/authorized_keys"

partSshPath="${part2}${sshPath}"
partAuthFile="${part2}${authFile}"

tpmStateDest=${TPM_STATE_DEST?:"Variable TPM_STATE_DEST is empty or not set."}

aptPackages='coreutils bash grep util-linux curl fdisk zip unzip xz-utils binfmt-support qemu-user-static'

# Get CPU thread count for multithreading params
cpus=$(nproc)

wSync() {
	sync
	sleep 2
}

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

# If from storage not allowed or get fails, use clock value for revision
[ "${versionFromShare}" -eq 0 ] && dateSec=$(date '+%s') && imgVer="0.0.${dateSec}"

# Fetch current version from storage record
if [ "${versionFromShare}" -eq 1 ]; then 
	imgVer=$(queryImageVersion "${imgVerFileUrl}")
	[ -z "${imgVer}" ] && echo "Version file not available. Fallback to init value." && imgVer="${initVer}"
fi

echo "Old Image Version: ${imgVer}"

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

echo "New Image Version: ${imgVer}"

echo ${imgVer} > "${imgVerFile}"

rm -fv ./*.img
if [ "${devMode}" -eq 1 ] && [ "${localMode}" -eq 1 ] && [ -f "${imgFileBak}" ]; then
	cp -v ${imgFileBak} ${imgFile}
else
	rm -fv ${imgFileZip}
	curl -f -L -o ${imgFileZip} "${srcUrl}"
	[ "${localMode}" -eq 1 ] && keepArchive='-k' || keepArchive=''
	[[ ${srcFileExt} == "xz" ]] && unxz -vv -d "${keepArchive}" -T "${cpus}" ${imgFileZip}
	[[ ${srcFileExt} == "zip" ]] && unzip -o ${imgFileZip}
	mv -v ./*.img ${imgFile} || true
#	[ "${devMode}" -eq 1 ] && [ "${localMode}" -eq 1 ] && cp -v ${imgFile} ${imgFile}.bak
fi

wSync
umount -lfv ${part1} || true
umount -lfv ${part2} || true
umount -lfv ${part3} || true
wSync

rm -vrf ${part1}
rm -vrf ${part2}
rm -vrf ${part3}

mkdir -vp ${part1}
mkdir -vp ${part2}
mkdir -vp ${part3}

losetup -v -D
wSync

if [ "${expandRootfs}" -eq 1 ]; then
	# EXPAND ROOTFS PARTITION
	dd status=progress if=${zeroDev} bs=1M count="${growSizeMbytes}" >> ${imgFile}
	wSync

	loopDev=$(losetup -f)
	losetup -v -f -P ${imgFile}
	wSync

	# shellcheck disable=SC2086
	parted -s -a opt "${loopDev}" resizepart ${partNumRoot} ${growPercentage}%
	wSync

	e2fsck -v -y -f "${loopDev}p${partNumRoot}"
	wSync

	# No --verbose available
	resize2fs "${loopDev}p${partNumRoot}"
	wSync

	e2fsck -v -y -f "${loopDev}p${partNumRoot}"
	wSync

	losetup -v -d "${loopDev}"
	wSync
	losetup -v -D
	wSync
fi

if [ "${createPersistence}" -eq 1 ]; then
	# CREATE PERSISTENCE PARTITION
	ogSectors=$(blockdev --getsz ${imgFile})

	dd status=progress if=${zeroDev} bs=1M count="${persistenceSize}" >> ${imgFile}
	wSync

	loopDev=$(losetup -f)
	losetup -v -f -P ${imgFile}
	wSync

	parted -s -a opt "${loopDev}" mkpart primary ext4 "${ogSectors}"s 100%
	wSync

	mkfs.ext4 "${loopDev}p${partNumPersist}"
	wSync

	e2fsck -v -y -f "${loopDev}p${partNumPersist}"
	wSync

	losetup -v -d "${loopDev}"
	wSync
	losetup -v -D
	wSync
fi

loopDev=$(losetup -f)
losetup -v -f -P ${imgFile}
wSync

mount -v -t vfat -o rw "${loopDev}p${partNumBoot}" ${part1}
mount -v -t ext4 -o rw "${loopDev}p${partNumRoot}" ${part2}
mount -v -t ext4 -o rw "${loopDev}p${partNumPersist}" ${part3}
wSync

# Mount persistence partition inside rootfs partition for chroot manipulation
mkdir ${persistencePath}
mount -v -t ext4 -o rw "${loopDev}p${partNumPersist}" ${persistencePath}
wSync

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

cp -v ${provisionServicePath} ${systemdPath}/

[[ ${imgOs} == "ubuntu"* ]] && cp -v ${netplanFile} ${part2}/etc/netplan/

cat > "${partParamsFile}" << EOF
export IMAGE_VERSION='${imgVer}'
export IMAGE_OS='${imgOs}'
export IMAGE_ARCH='${imgArch}'
export IMAGE_VER_FILE='${imgVerFile}'
export IMAGE_SERVER_URL='${imgServer}'
export SAS_TOKEN_URL_QUERY='${sasToken}'
export DPS_ID_SCOPE='${DPS_ID_SCOPE}'
EOF
chmod -v 0444 "${partParamsFile}"

cat > ${partInfoFile} << EOF
Image Name: Iot Edge Base Image Based on ${distroName} ${distroVer}
Image Description: Patched generic self-provisioning image for IoT Edge devices.
Image Maintainer: ${maintName} <${maintEmail}>
Publish Date: $(date)
EOF
chmod -v 0444 ${partInfoFile}

if [ -n "${baseUser}" ]; then
cat > "${sudoersFile}" << EOF
${baseUser} ALL=(ALL) NOPASSWD:ALL
EOF
chmod -v 0440 "${sudoersFile}"
fi

${bashBin} ${tpmDeviceSetupScript} ${part2}

cp -v "$(which "${qemuBin}")" ${part2}/usr/bin/

sed -i 's/^/#/g' ${part2}/etc/ld.so.preload && preloadModified=1 || preloadModified=0

chroot ${part2} "${qemuBin}" ${bashBin} -vc "rm -vrf ${tpmStateDest}"
chroot ${part2} "${qemuBin}" ${bashBin} -vc "mkdir -vm 0700 ${tpmStateDest}"

chroot ${part2} "${qemuBin}" ${bashBin} -vc "swtpm_setup \
	--runas 0 \
	--tpmstate ${tpmStateDest} \
	--tpm2 \
	--createek \
	--decryption \
	--create-ek-cert \
	--create-platform-cert \
	--lock-nvram \
	--not-overwrite \
	--display \
	--vmid iotedge-base-image"

chroot ${part2} "${qemuBin}" ${bashBin} -vc "systemctl enable ${provisionService}"

if [ "${delOgUser}" -eq 1 ]; then
	{ [[ ${imgOs} == "rasp"* ]] && chroot ${part2} "${qemuBin}" ${bashBin} -vc "userdel -rf ${ogUserRaspios}"; } || true
	{ [[ ${imgOs} == "ubuntu"* ]] && chroot ${part2} "${qemuBin}" ${bashBin} -vc "userdel -rf ${ogUserUbuntu}"; } || true
fi

if [ -n "${baseUser}" ]; then

chroot ${part2} "${qemuBin}" ${bashBin} -vc "useradd -m -G ${baseGroups} -s ${bashBin} ${baseUser}"

[ ! -d "${partSshPath}" ] && mkdir -vm 0700 "${partSshPath}"

if [ -n "${sshPubKey}" ]; then
echo "SSH Public key set. Appending pub key for base user."
cat >> "${partAuthFile}" << EOF
${sshPubKey}
EOF
else
	echo "SSH Public key variable not set, omitting public key add."
fi

# NO VERBOSITY, password being echoed
if [ "${devMode}" -eq 1 ] && [ -n "${basePass}" ]; then
	echo "Base user password set. Applying password.."
	chroot ${part2} "${qemuBin}" ${bashBin} -c "echo '${baseUser}:${basePass}' | chpasswd"
else
	echo "Base user password not set. Removing expiring and locking base user password."
	chroot ${part2} "${qemuBin}" ${bashBin} -vc "passwd -d -l ${baseUser}"
fi

# If local, generate new ssh key to local, and append it to auth keys
if [ "${localMode}" -eq 1 ] && [ "${createLocalKey}" -eq 1 ]; then
	echo "Local key creation requested. Creating local ssh key for base user."
	rm -fv "${keyFile}"*
	ssh-keygen -t "${keyType}" -a "${keyRounds}" -b "${keyBits}" -N "${keyPhrase}" -C "${keyComment}" -f "${keyFile}"
	cat "${keyFilePub}" >> "${partAuthFile}"
fi

chroot ${part2} "${qemuBin}" ${bashBin} -vc "chown -vR ${baseUser}:${baseUser} ${baseHome}"

chroot ${part2} "${qemuBin}" ${bashBin} -vc "chmod -v 0644 ${authFile}"

fi

[ ${preloadModified} -eq 1 ] && sed -i 's/^#//g' ${part2}/etc/ld.so.preload

wSync
umount -v ${part1}
umount -v ${part2}
umount -v ${part3}
wSync

rm -vrf ${part1}
rm -vrf ${part2}
rm -vrf ${part3}

losetup -v -d "${loopDev}"
wSync
losetup -v -D
wSync

mv -v ${imgFile} "${newImgFile}"

rm -fv "${newImgFileZip}"
xz -vv -z -f -k -T "${cpus}" "${newImgFile}"
