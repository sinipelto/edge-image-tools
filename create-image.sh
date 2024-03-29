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

dpsIdScope=${DPS_ID_SCOPE} && [ -z "${dpsIdScope}" ] && echo "Variable DPS_ID_SCOPE is empty or not set." && exit 1

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

createPersistence=${USE_PERSISTENCE} && [ -z "${createPersistence}" ] && echo "Variable USE_PERSISTENCE is empty or not set." && exit 1
persistenceSize=${PERSISTENCE_SIZE_MBYTES} && [ -z "${persistenceSize}" ] && echo "Variable PERSISTENCE_SIZE_MBYTES is empty or not set." && exit 1
persistenceMount=${PERSISTENCE_MOUNT_POINT:?"Variable PERSISTENCE_MOUNT_POINT is empty or not set."}

wlanSsid=${WLAN_SSID:?"Variable WLAN_SSID is empty or not set."}
wlanPassword=${WLAN_PASSWORD:?"Variable WLAN_PASSWORD is empty or not set."}

countryCode=${COUNTRYCODE_UPPER_2LETTER:?"Variable COUNTRYCODE_UPPER_2LETTER is empty or not set."}
localeCode=${LOCALE_LOWER_2LETTER:?"Variable LOCALE_LOWER_2LETTER is empty or not set."}

timezone=${TIMEZONE:?"Variable TIMEZONE is empty or not set."}

deviceHostname=${DEVICE_HOSTNAME:?"Variable DEVICE_HOSTNAME is empty or not set."}

ntpServers=${NTP_SERVERS:?"Variable NTP_SERVERS is empty or not set."}
ntpFallbackServers=${FALLBACK_NTP_SERVERS:?"Variable FALLBACK_NTP_SERVERS is empty or not set."}

zeroDev='/dev/zero'

partBoot='/mnt_boot' # Boot
partRoot='/mnt_root' # Rootfs
partPersist='/mnt_persistence' # Persistence

partNumBoot=1
partNumRoot=2
partNumPersist=2

# After we have changed the partition layout
# We need to assign the new numbers to target correct partitions
partNumRootNew=3

rootImgFile='rootfs.img'

persistenceLabel='persistence'

templatePath='templates'
servicePath='services'
binPath='pre-built'
configPath='config'

qemuBin="qemu-${imgArch}-static"
bashBin='/bin/bash'

rootBin="${partRoot}/root/bin"

rootPath="${partRoot}/root"
netplanPath="${partRoot}/etc/netplan"
persistencePath="${partRoot}/persistence"

partParamsFile="${partRoot}/${imgParamsFile}"
partInfoFile="${partRoot}/image_info"

# License: MIT - Free/Commercial use + modifications
waitforitScript='wait-for-it.sh'

provisionScript='provision-image.sh'
provisionService='provisioning.service'
provisionServicePath="${servicePath}/${provisionService}"

resizeLine='s/ init=\/usr\/lib\/raspi-config\/init_resize.sh//g'

systemdPath="${partRoot}/etc/systemd/system"

sshFile='ssh'
netFile='network-config'
netplanFile='90-network.yaml'
wpaFile='wpa_supplicant.conf'
userFile='user-data'

netFileTemplate="${templatePath}/${netFile}.template"
netplanFileTemplate="${templatePath}/${netplanFile}.template"
wpaFileTemplate="${templatePath}/${wpaFile}.template"
userFileTemplate="${templatePath}/${userFile}.template"

wlanSsidReplaceVar='<WLAN_SSID>'
wlanPasswordReplaceVar='<WLAN_PASSWORD>'
countryCodeReplaceVar='<COUNTRYCODE_UPPER_2LETTER>'
localeCodeReplaceVar='<LOCALE_LOWER_2LETTER>'
hostnameReplaceVar='<DEVICE_HOSTNAME>'
timezoneReplaceVar='<TIMEZONE>'

wlanSsidReplaceLine="s/${wlanSsidReplaceVar}/${wlanSsid//\//\\/}/g"
wlanPasswordReplaceLine="s/${wlanPasswordReplaceVar}/${wlanPassword//\//\\/}/g"
countryCodeReplaceLine="s/${countryCodeReplaceVar}/${countryCode//\//\\/}/g"
localeCodeReplaceLine="s/${localeCodeReplaceVar}/${localeCode//\//\\/}/g"
hostnameReplaceLine="s/${hostnameReplaceVar}/${deviceHostname//\//\\/}/g"
timezoneReplaceLine="s/${timezoneReplaceVar}/${timezone//\//\\/}/g"


timesyncFile='timesyncd.conf'
timesyncFileTemplate="${templatePath}/${timesyncFile}.template"
timesyncPath="${partRoot}/etc/systemd"

ntpServersReplaceVar='<NTP_SERVERS>'
ntpFallbackServersReplaceVar='<FALLBACK_NTP_SERVERS>'

ntpServersReplaceLine="s/${ntpServersReplaceVar}/${ntpServers//\//\\/}/g"
ntpFallbackServersReplaceLine="s/${ntpFallbackServersReplaceVar}/${ntpFallbackServers//\//\\/}/g"

edgeConfigFileTemplate="${templatePath}/edge-config-tpm.toml.template"

aptConfPath="${partRoot}/etc/apt/apt.conf.d"

aptPeriodicFile="${aptConfPath}/10periodic"
aptAutoFile="${aptConfPath}/20auto-upgrades"
aptUnattendedFIle="${aptConfPath}/50unattended-upgrades"

aptDisableUpgradeFile="${configPath}/90-disable-auto-upgrades"

hostnameFilePath="${partRoot}/etc/hostname"

cmdlineFile='cmdline.txt'
cmdlineFilePath="${partBoot}/${cmdlineFile}"

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

sudoersFile="${partRoot}/etc/sudoers.d/010_${baseUser}"

sshPath="${baseHome}/.ssh"
authFile="${sshPath}/authorized_keys"

partSshPath="${partRoot}${sshPath}"
partAuthFile="${partRoot}${authFile}"

# Stored state dir for restoring backed up vTPM state
tpmStateDest=${TPM_STATE_DEST:?"Variable TPM_STATE_DEST is empty or not set."}

tpmStateDestHost=${partRoot}${tpmStateDest}

tpmStateDestReplaceLine="s/<TPM_STATE_DIR>/${tpmStateDest//\//\\/}/g"

# TPM software simulator or a real tpm device? 
useTpmSim=${USE_TPM_SIMULATOR:?"Variable USE_TPM_SIMULATOR is empty or not set."}

# Do we display the TPM details on the output?
runTpmAttes=${RUN_TPM_ATTESTATION:?"Variable RUN_TPM_ATTESTATION is empty or not set."}

tpmLocalCaPath='/var/lib/swtpm-localca'

attesBundleZipHost="${binPath}/prov-bundle-ubuntu20-x86_64.tar.gz"
attesBundleZip="${binPath}/prov-bundle-${imgOs}-${imgArch}.tar.gz"

tpmBundleZipHost="${binPath}/tpm-bundle-ubuntu20-x86_64.tar.gz"
tpmBundleZip="${binPath}/tpm-bundle-${imgOs}-${imgArch}.tar.gz"

abrmdService='tpm2-abrmd.service'
abrmdServiceSim='tpm2-abrmd-swtpm.service'
abrmdServiceSimPath="${servicePath}/${abrmdServiceSim}"

swtpmService='tpm2-swtpm.service'
swtpmServicePath="${templatePath}/${swtpmService}.template"

provBundlePath='prov_bundle'
provTool="${provBundlePath}/provisioning_client/tools/tpm_device_provision/tpm_device_provision"
provClient="${provBundlePath}/provisioning_client/samples/prov_dev_client_sample/prov_dev_client_sample"

aptPackages='coreutils bash grep util-linux curl fdisk zip unzip 
	xz-utils binfmt-support qemu-user-static tar gnutls-bin'

# Get CPU thread count for multithreading params
cpus=$(nproc)
cpus=$((cpus * 2))

wSync() {
	sync
	sleep 1
}


################################################################################
################################	START	####################################
################################################################################

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

rm -vf ./*.img
if [ "${devMode}" -eq 1 ] && [ "${localMode}" -eq 1 ] && [ -f "${imgFileBak}" ]; then
	cp -v ${imgFileBak} ${imgFile}
else
	rm -vf ${imgFileZip}
	curl -f -L -o ${imgFileZip} "${srcUrl}"

	[ "${localMode}" -eq 1 ] && keepArchive='-k'
	[[ ${srcFileExt} == "xz" ]] && unxz -vv -d ${keepArchive} -T "${cpus}" ${imgFileZip}
	[[ ${srcFileExt} == "zip" ]] && unzip -o ${imgFileZip}
	mv -v ./*.img ${imgFile} || true
	[ "${devMode}" -eq 1 ] && [ "${localMode}" -eq 1 ] && cp -v ${imgFile} ${imgFile}.bak
fi

wSync
umount -lfv ${partBoot} || true
umount -lfv ${partRoot} || true
umount -lfv ${partPersist} || true
wSync

rm -vrf ${partBoot}
rm -vrf ${partRoot}
rm -vrf ${partPersist}

losetup -v -D
wSync

if [ "${createPersistence}" -eq 1 ]; then
	loopDev=$(losetup -f)
	losetup -v -P "${loopDev}" ${imgFile}
	wSync

	rootSize=$(blockdev --getsz "${loopDev}p${partNumRoot}")

	rm -vf ${rootImgFile}
	dd status=progress if="${loopDev}p${partNumRoot}" of=${rootImgFile}
	wSync

	parted -s -a opt "${loopDev}" rm ${partNumRoot}
	wSync

	partEnd=$(sfdisk -s -l -o End "${loopDev}" | tail -1)
	partEnd=$(( partEnd + 1 ))

	losetup -v -d "${loopDev}"
	losetup -v -D
	wSync

	partEnd=$(( partEnd + 64 ))
	truncate --size $(( partEnd * 512 )) ${imgFile}
	wSync

	dd status=progress if=${zeroDev} bs=1MB count="${persistenceSize}" >> ${imgFile}
	wSync

	loopDev=$(losetup -f)
	losetup -v -P "${loopDev}" ${imgFile}
	wSync

	parted -s -a opt "${loopDev}" mkpart primary ext4 ${partEnd}s 100%
	wSync

	partEnd=$(sfdisk -s -l -o End "${loopDev}" | tail -1)
	partEnd=$(( partEnd + 1 ))

	mkfs.ext4 "${loopDev}p${partNumPersist}"
	wSync

	e2fsck -v -y -f "${loopDev}p${partNumPersist}"
	wSync

	e2label "${loopDev}p${partNumPersist}" ${persistenceLabel}
	wSync

	losetup -v -d "${loopDev}"
	losetup -v -D
	wSync

	dd status=progress if=${zeroDev} bs=1b count="${rootSize}" >> ${imgFile}
	wSync

	loopDev=$(losetup -f)
	losetup -v -P "${loopDev}" ${imgFile}
	wSync

	parted -s -a opt "${loopDev}" mkpart primary ext4 ${partEnd}s $(( partEnd + rootSize - 1 ))s
	wSync

	partEnd=$(sfdisk -s -l -o End "${loopDev}" | tail -1)
	partEnd=$(( partEnd + 1 ))

	##### PARTNUMROOT/NEW == NULL ######
	partNumRoot=${partNumRootNew}

	losetup -v -d "${loopDev}"
	losetup -v -D
	wSync

	loopDev=$(losetup -f)
	losetup -v -P "${loopDev}" ${imgFile}
	wSync

	dd status=progress if=${rootImgFile} of="${loopDev}p${partNumRoot}"
	rm -vf ${rootImgFile}
	wSync

	losetup -v -d "${loopDev}"
	losetup -v -D
	wSync

	loopDev=$(losetup -f)
	losetup -v -P "${loopDev}" ${imgFile}
	wSync

	e2fsck -v -y -f "${loopDev}p${partNumPersist}"
	e2fsck -v -y -f "${loopDev}p${partNumRoot}"
	wSync

	losetup -v -d "${loopDev}"
	losetup -v -D
	wSync

	partEnd=$(( partEnd + 64 ))
	truncate --size $(( partEnd * 512 )) ${imgFile}
	wSync
fi

if [ "${expandRootfs}" -eq 1 ]; then
	# EXPAND ROOTFS PARTITION
	dd status=progress if=${zeroDev} bs=1MB count="${growSizeMbytes}" >> ${imgFile}
	wSync

	loopDev=$(losetup -f)
	losetup -v -P "${loopDev}" ${imgFile}
	wSync

	parted -s -a opt "${loopDev}" resizepart ${partNumRoot} 100%
	wSync

	# No --verbose available
	resize2fs "${loopDev}p${partNumRoot}"
	wSync

	e2fsck -v -y -f "${loopDev}p${partNumRoot}"
	wSync

	partEnd=$(sfdisk -s -l -o End "${loopDev}" | tail -1)
	partEnd=$(( partEnd + 1 ))

	losetup -v -d "${loopDev}"
	losetup -v -D
	wSync

	partEnd=$(( partEnd + 64 ))
	truncate --size $(( partEnd * 512 )) ${imgFile}
	wSync
fi

loopDev=$(losetup -f)
losetup -v -P "${loopDev}" ${imgFile}
wSync

mkdir -vp ${partBoot}
mkdir -vp ${partRoot}
mkdir -vp ${partPersist}

mount -v -t vfat -o rw "${loopDev}p${partNumBoot}" ${partBoot}
mount -v -t ext4 -o rw "${loopDev}p${partNumRoot}" ${partRoot}
mount -v -t ext4 -o rw "${loopDev}p${partNumPersist}" ${partPersist}
wSync

# Mount persistence partition inside rootfs partition for chroot manipulation
mkdir ${persistencePath}
mount -v -t ext4 -o rw "${loopDev}p${partNumPersist}" ${persistencePath}
wSync

mount --bind /dev ${partRoot}/dev/
mount --bind /sys ${partRoot}/sys/
mount --bind /proc ${partRoot}/proc/
mount --bind /dev/pts ${partRoot}/dev/pts

# Add auto mount entry to rootfs partition table
# TODO ensure label works + cleanup
# partUuid="UUID=$(blkid "${loopDev}p${partNumPersist}" -s UUID -o value)"
echo -e "LABEL=${persistenceLabel}\t${persistenceMount}\text4\tdefaults\t0\t2" >> ${partRoot}/etc/fstab

touch ${partBoot}/${sshFile}

sed -i "${wlanSsidReplaceLine}" ${netFileTemplate}
sed -i "${wlanSsidReplaceLine}" ${netplanFileTemplate}
sed -i "${wlanSsidReplaceLine}" ${wpaFileTemplate}

sed -i "${wlanPasswordReplaceLine}" ${netFileTemplate}
sed -i "${wlanPasswordReplaceLine}" ${netplanFileTemplate}
sed -i "${wlanPasswordReplaceLine}" ${wpaFileTemplate}

sed -i "${countryCodeReplaceLine}" ${userFileTemplate}
sed -i "${countryCodeReplaceLine}" ${wpaFileTemplate}

sed -i "${localeCodeReplaceLine}" ${userFileTemplate}
sed -i "${hostnameReplaceLine}" ${userFileTemplate}
sed -i "${timezoneReplaceLine}" ${userFileTemplate}

cp -v ${wpaFileTemplate} ${partBoot}/${wpaFile}
cp -v ${netFileTemplate} ${partBoot}/${netFile}
cp -v ${userFileTemplate} ${partBoot}/${userFile}

# NOTE: If disabled part+fs resizing => no free space left on rootfs with RaspiOS!
# Solution: For raspios the rootfs partition + fs is resized
sed -i "${resizeLine}" ${cmdlineFilePath}

# Update system hostname also in hostname file
cat > ${hostnameFilePath} << EOF
${deviceHostname}
EOF

# Extract necessary provisioning bundles for image and install them
# NOTE: Avoid log flood by not setting verbose
rm -rf ${provBundlePath}
tar -xzkf "${attesBundleZip}" -C .

[ ! -d ${rootBin} ] && mkdir -vm 0700 ${rootBin}

cp -v ${commonScript} ${rootBin}/
cp -v ${waitforitScript} ${rootBin}/
cp -v ${provisionScript} ${rootBin}/
cp -v ${provTool} ${rootBin}/
cp -v ${provClient} ${rootBin}/

chmod -vR 0700 ${rootBin}

cp -v ${edgeConfigFileTemplate} ${rootPath}/

cp -v ${provisionServicePath} ${systemdPath}/

[[ ${imgOs} == "ubuntu"* ]] && cp -v ${netplanFileTemplate} ${netplanPath}/${netplanFile}

cat > "${partParamsFile}" << EOF
export IMAGE_VERSION='${imgVer}'
export IMAGE_OS='${imgOs}'
export IMAGE_ARCH='${imgArch}'
export IMAGE_VER_FILE='${imgVerFile}'
export IMAGE_SERVER_URL='${imgServer}'
export SAS_TOKEN_URL_QUERY='${sasToken}'
export DPS_ID_SCOPE='${dpsIdScope}'
export COUNTRYCODE_UPPER_2LETTER='${countryCode}'
export LOCALE_LOWER_2LETTER='${localeCode}'
EOF
chmod -v 0444 "${partParamsFile}"

cat > ${partInfoFile} << EOF
Image Name: Iot Edge Base Image Based on ${distroName} ${distroVer}
Image Description: Patched generic self-provisioning image for IoT Edge devices.
Image Maintainer: ${maintName} <${maintEmail}>
Creation Date: $(date)
EOF
chmod -v 0444 ${partInfoFile}

if [ -n "${baseUser}" ]; then
cat > "${sudoersFile}" << EOF
${baseUser} ALL=(ALL) NOPASSWD:ALL
EOF
chmod -v 0440 "${sudoersFile}"
fi

# Remove APT unattended upgrades configuration files
rm -vf ${aptPeriodicFile}
rm -vf ${aptAutoFile}
rm -vf ${aptUnattendedFIle}

# Set high level config for disabling auto upgrades
cp -v ${aptDisableUpgradeFile} ${aptConfPath}/

# Set the timesyncd config for syncing time with proper NTP servers
# Ensuring that e.g. package manager caches will be in sync
sed -i "${ntpServersReplaceLine}" ${timesyncFileTemplate}
sed -i "${ntpFallbackServersReplaceLine}" ${timesyncFileTemplate}

cp -v ${timesyncFileTemplate} ${timesyncPath}/${timesyncFile}

# Install tpm bundle both locally and on target image
# TODO ensure all old files (not dirs) deleted first!
# TODO test if works
tar -xzkf ${tpmBundleZipHost} -C / || true
tar -xzkf "${tpmBundleZip}" -C ${partRoot}

sed -i "${tpmStateDestReplaceLine}" ${swtpmServicePath}
cp -v ${swtpmServicePath} "${systemdPath}/${swtpmService}"

echo "Set up systemd service for swtpm"

if [ "${useTpmSim}" -eq 1 ]; then
	echo "Using systemd service for TPM simulator.."
	cp -v ${abrmdServiceSimPath} "${systemdPath}/${abrmdService}"
else
	echo "Using systemd service for real TPM device.."
	# NOTE 2022-03-13: No real device configuration available yet due to lack of real hardware
	echo "ERROR: FEATURE NOT IMPLEMENTED YET"
	exit 1
fi

echo "Set up systemd service for tpm2-abrmd"

pkill tpm2-abrmd || true
sleep 1

pkill swtpm || true
sleep 1

# Set up swtpm state dir
rm -vrf "${tpmStateDestHost}"
mkdir -vm 0700 "${tpmStateDestHost}"

# Set up localca
rm -vrf ${tpmLocalCaPath:?}/*

swtpm_setup \
	--runas 0 \
	--tpmstate "${tpmStateDestHost}" \
	--tpm2 \
	--createek \
	--decryption \
	--create-ek-cert \
	--create-platform-cert \
	--lock-nvram \
	--not-overwrite \
	--display \
	--vmid iotedge-base-image

cp -vrT ${tpmLocalCaPath} ${partRoot}${tpmLocalCaPath}

swtpm socket \
	--runas 0 \
	--tpmstate dir="${tpmStateDestHost}" \
	--tpm2 \
	--server type=tcp,port=2321,disconnect \
	--ctrl type=tcp,port=2322 \
	--flags not-need-init,startup-clear &

sleep 1

tpm2-abrmd -o -t 'swtpm' &

sleep 1

# Extract and install the prov client tools for host
# NOTE: Disable verbosity to not flood logs
rm -rf ${provBundlePath}
tar -xzf "${attesBundleZipHost}" -C .

# Store results into persistence partition (for dev mode) or into null device (prod mode)
[[ $devMode -eq 1 ]] && ekOutputFile="${partPersist}/endorsement_key" && regOutputFile="${partPersist}/registration_id"
[[ $devMode -eq 0 ]] && ekOutputFile='/dev/null' && regOutputFile='/dev/null'

# Test and Printout EK and RegID for curren TPM device
# Built from forked repo: no getch => no stdin needed to be provided into the program
[ "${runTpmAttes}" -eq 1 ] && ${provTool} ${ekOutputFile} ${regOutputFile}

pkill tpm2-abrmd || true
sleep 1

pkill swtpm || true
sleep 1

cp -v "$(which "${qemuBin}")" ${partRoot}/usr/bin/
sed -i 's/^/#/g' ${partRoot}/etc/ld.so.preload && preloadModified=1 || preloadModified=0

chroot ${partRoot} "${qemuBin}" ${bashBin} -vc "systemctl enable ${swtpmService}"

chroot ${partRoot} "${qemuBin}" ${bashBin} -vc "systemctl enable ${abrmdService}"

chroot ${partRoot} "${qemuBin}" ${bashBin} -vc "systemctl enable ${provisionService}"

if [ "${delOgUser}" -eq 1 ]; then
	{ [[ ${imgOs} == "rasp"* ]] && chroot ${partRoot} "${qemuBin}" ${bashBin} -vc "userdel -rf ${ogUserRaspios}"; } || true
	{ [[ ${imgOs} == "ubuntu"* ]] && chroot ${partRoot} "${qemuBin}" ${bashBin} -vc "userdel -rf ${ogUserUbuntu}"; } || true
fi

if [ -n "${baseUser}" ]; then

chroot ${partRoot} "${qemuBin}" ${bashBin} -vc "useradd -m -G ${baseGroups} -s ${bashBin} ${baseUser}"

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
	chroot ${partRoot} "${qemuBin}" ${bashBin} -c "echo '${baseUser}:${basePass}' | chpasswd"
else
	echo "Base user password not set. Removing expiring and locking base user password."
	chroot ${partRoot} "${qemuBin}" ${bashBin} -vc "passwd -d -l ${baseUser}"
fi

# If local, generate new ssh key to local, and append it to auth keys
if [ "${localMode}" -eq 1 ] && [ "${createLocalKey}" -eq 1 ]; then
	echo "Local key creation requested. Creating local ssh key for base user."
	rm -fv "${keyFile}"*
	ssh-keygen -t "${keyType}" -a "${keyRounds}" -b "${keyBits}" -N "${keyPhrase}" -C "${keyComment}" -f "${keyFile}"
	cat "${keyFilePub}" >> "${partAuthFile}"
fi

chroot ${partRoot} "${qemuBin}" ${bashBin} -vc "chown -vR ${baseUser}:${baseUser} ${baseHome}"

chroot ${partRoot} "${qemuBin}" ${bashBin} -vc "chmod -v 0644 ${authFile}"

fi

[ ${preloadModified} -eq 1 ] && sed -i 's/^#//g' ${partRoot}/etc/ld.so.preload

wSync
umount -v ${persistencePath}
wSync

umount ${partRoot}/{dev/pts,dev,sys,proc}

wSync
umount -v ${partBoot}
umount -v ${partRoot}
umount -v ${partPersist}
wSync

rm -vrf ${partBoot}
rm -vrf ${partRoot}
rm -vrf ${partPersist}
rm -vrf ${persistencePath}

losetup -v -d "${loopDev}"
losetup -v -D
wSync

mv -v ${imgFile} "${newImgFile}"

rm -fv "${newImgFileZip}"
xz -vv -z -f -k -T "${cpus}" "${newImgFile}"
