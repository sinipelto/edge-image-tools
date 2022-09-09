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

userId=$(id -u)
(( userId != 0 )) && echo "Current user not root. This script must be run as root user or with sudo privileges." && exit 1

paramsFile='/image_params'

rootBin='/root/bin'
waitBin="${rootBin}/wait-for-it.sh"
commonBin="${rootBin}/common.sh"

edgeConfigTemplateFile='/root/edge-config-tpm.toml.template'
edgeConfigTarget='/etc/aziot/config.toml'

ekOutputFile='/root/ek_out'
regOutputFile='/root/rg_out'

provToolBin="${rootBin}/tpm_device_provision"
provClientBin="${rootBin}/prov_dev_client_sample"

tpmSocketHost='localhost'
tpmServerPort='2321'
tpmCtrlPort='2322'

sleepBin='/bin/sleep'
shutdownBin='/sbin/shutdown'
dateBin='/bin/date'

# shellcheck source=/dev/null
source ${commonBin}

# Read image params variables from file
# shellcheck source=/dev/null
source ${paramsFile}

version=${IMAGE_VERSION:?"Variable IMAGE_VERSION is empty or not set."}
os=${IMAGE_OS:?"Variable IMAGE_OS is empty or not set."}
arch=${IMAGE_ARCH:?"Variable IMAGE_ARCH is empty or not set."}
versionFile=${IMAGE_VER_FILE:?"Variable IMAGE_VER_FILE is empty or not set."}

idScope=${DPS_ID_SCOPE:?"Variable DPS_ID_SCOPE is empty or not set."}

# Read/List SAS token for update image file share
# Images will be in format: YYYY-MM-DD_VERSION.img.xz
imgServer=${IMAGE_SERVER_URL:?"Variable IMAGE_SERVER_URL is empty or not set."}
sasToken=${SAS_TOKEN_URL_QUERY:?"Variable SAS_TOKEN_URL_QUERY is empty or not set."}

imgVersionUrl="${imgServer}/${os}/${arch}/${versionFile}${sasToken}"

countryCode=${COUNTRYCODE_UPPER_2LETTER?:"Variable COUNTRYCODE_UPPER_2LETTER is empty or not set."}
localeCode=${LOCALE_LOWER_2LETTER?:"Variable LOCALE_LOWER_2LETTER is empty or not set."}

dateTime=$(${dateBin})
#isoDate=$(${dateBin} '+%Y-%m-%dT%H:%M:%S')

# Timeout before rebooting
rebootMin=1

# Timeout for the very first boot before taking any actions
syncTimeout=20

initUserRaspi='pi'
initUserUbuntu='ubuntu'

provFile='/root/.provisioned'
provText="Pre-Built IoT Edge Image\nImage Version: ${version}\nDevice Provision Date: ${dateTime}"

ensure_tpm() {
	echo "Ensure connection to TPM and ResourceManager available.."

	${waitBin} -t 30 -h ${tpmSocketHost} -p ${tpmServerPort}
	${waitBin} -t 30 -h ${tpmSocketHost} -p ${tpmCtrlPort}

	echo "Connections to TPM ok."
}

ensure_apt() {
	echo "Ensure connection to APT required services available.."

	${waitBin} -t 30 -h 'archive.ubuntu.com' -p 80
	${waitBin} -t 30 -h 'deb.debian.org' -p 80
	${waitBin} -t 30 -h 'packages.microsoft.com' -p 443

	echo "Connections ok."
}

base_config() {
	echo "Running system base configurations.."

	# These must be done on a running system => in provision script
	sed -i "s/^REGDOMAIN=.*/REGDOMAIN=${countryCode}/" /etc/default/crda
	rm -f /etc/xdg/autostart/piwiz.desktop
	localectl set-x11-keymap "${localeCode}" pc105
	setupcon -k --force

	# For some systems (e.g. Ubuntu) the initial user(s) are created
	# only after the system first boot => delete needed in provision script
	echo "Ensure original user deleted."
	# shellcheck disable=SC2015
	[[ ${os} == "ubuntu"* ]] && userdel -rf ${initUserUbuntu} || true
	# shellcheck disable=SC2015
	[[ ${os} == "rasp"* ]] && userdel -rf ${initUserRaspi} || true

	echo "Base configuration done."
}

config_sources() {
	echo "Configuring apt sources.."

	ensure_apt

	pkgFileUbu='packages-microsoft-prod.deb'
	pkgSrcList='/etc/apt/sources.list.d/microsoft-prod.list'
	gpgKeyFile='/etc/apt/trusted.gpg.d/microsoft.gpg'

	# Microsoft APT source Ubuntu 18.04 + gpg key
	if [[ ${os} == "ubuntu18" ]]; then
		curl -f -L "https://packages.microsoft.com/config/ubuntu/18.04/${pkgFileUbu}" > ${pkgFileUbu}
		dpkg -i ${pkgFileUbu}
		rm -fv ${pkgFileUbu}
	elif [[ ${os} == "ubuntu20" ]]; then
		curl -f -L "https://packages.microsoft.com/config/ubuntu/20.04/${pkgFileUbu}" > ${pkgFileUbu}
		dpkg -i ${pkgFileUbu}
		rm -fv ${pkgFileUbu}
		# TODO: Temporary fix for correcting architectures for the MS Ubuntu package source list 
		sed -i s'/\[arch=.*\]/\[arch=amd64,arm64,armhf\]/' ${pkgSrcList}
	elif [[ ${os} == "rasp"* ]]; then
		curl -f -L "https://packages.microsoft.com/config/debian/stretch/multiarch/prod.list" > ${pkgSrcList}
		curl -f -L "https://packages.microsoft.com/keys/microsoft.asc" | gpg --dearmor > ${gpgKeyFile}
	fi

	echo "Configuring apt sources done."
}

install_deps() {
	# Apt-get does not work without the actual running system => apt installs in provision script
	echo "Install dependencies.."

	ensure_apt
	waitAptitude

	apt-get update

	# Must be installed first!
	# Installs: moby-engine, moby-cli
	apt-get install -y --allow-remove-essential moby-engine

	# Install once moby-engine is already installed
	# NOTE: This installation removes package 'hostname' from raspi OS - installs hostname:armhf in place
	# => needs to be allowed explicitly for this installation using the special arg
	apt-get install -y --allow-remove-essential aziot-edge

	echo "Install dependencies done."
}

configure_edge() {
	echo "Configure iot edge specific settings.."

	echo "Ensure TPM device is available.."
	ensure_tpm

	echo "Fetch provisioning information from TPM.."
	${provToolBin} ${ekOutputFile} ${regOutputFile}

	echo "Register the edge device to pre-configured IoT Hub.."
	${provClientBin} "${idScope}"

	echo "Set edge configuration file.."

	# endKey=$(cat ${ekOutputFile})
	regId=$(cat ${regOutputFile})

	# Set ID_SCOPE and REG_ID for communicating with 
	sed -i "s/<DPS_ID_SCOPE>/${idScope}/" ${edgeConfigTemplateFile}
	sed -i "s/<DPS_REGISTRATION_ID>/${regId}/" ${edgeConfigTemplateFile}

	cp -v ${edgeConfigTemplateFile} ${edgeConfigTarget}

	echo "Apply iot edge config.."
	iotedge config apply

	# Not needed - already done by apply
	# echo "Restart aziot services"
	# aziotctl system restart

	echo "Check aziot services.."
	aziotctl check

	echo "Run iot edge checks.."
	# NOTE: Fails often, might fail even when configuration works -> cant be fully trusted
	iotedge check || true

	echo "Configure iot edge specific settings done."
}

provision() {
	echo "First boot - Start initial provisioning.."

	base_config
	config_sources
	install_deps
	configure_edge

	echo "Mark the system provisioned."
	echo -e "${provText}" > ${provFile}

	doReboot=1
	echo "Initial provisioning done."
}

update() {
	echo "Updating system.."

	# TODO remove
	sed -i "s/export IMAGE_VERSION=.*/export IMAGE_VERSION=${remoteVersion}/" ${paramsFile}

	# TODO: curl download image zip
	#	extract zip
	#	losetup mount image
	#	clone partition to local disk
	#	change rootfs id to new
	#	delete old

	# TODO enable after tests ok
	#doReboot=1
	echo "System update done."
}

check_updates() {
	echo "Checking for image updates.."

	remoteVersion=$(queryImageVersion "${imgVersionUrl}")

	# If failed to retrieve remote version, move on to allow later operations
	[ -z "${remoteVersion}" ] && echo "WARNING: Could not retrieve version from server. Skipping update." && return 0

	echo "Current image version: ${version} - Remote image version: ${remoteVersion}"

	# shellcheck disable=SC2206
	locArr=(${version//./ })
	# shellcheck disable=SC2206
	remArr=(${remoteVersion//./ })

	locMa=${locArr[0]}
	locMi=${locArr[1]}
	locRv=${locArr[2]}

	remMa=${remArr[0]}
	remMi=${remArr[1]}
	remRv=${remArr[2]}

	(( remMa > locMa )) && isUpdate=1
	(( remMi > locMi )) && isUpdate=1
	(( remRv > locRv )) && isUpdate=1

	[ ${isUpdate} -eq 0 ] && echo "No new image updates available."
	[ ${isUpdate} -eq 1 ] && echo "Image update available!" && update

	echo "Check updates done."
}


################################################################################
################################	START	####################################
################################################################################

isUpdate=0
doReboot=0

echo "[${dateTime}] - Provisioning and update script starting up.."

if [ ! -f "${provFile}" ]; then
	echo "First boot detected."

	echo "Ensure system clock is synced.."
	systemctl restart systemd-timesyncd.service

	echo "Wait for a while to allow the clock to synchronize.."
	${sleepBin} ${syncTimeout}

	echo "Ensure aptitude available.."
	waitAptitude
fi

check_updates

if [ -f "${provFile}" ]; then
	echo "Already provisioned. Skip initial provisioning."
else
	[ ${isUpdate} -eq 0 ] && provision
fi

[ ${doReboot} -eq 1 ] && echo "Reboot requested." && echo "Reboot in ${rebootMin} min..." && ${shutdownBin} -r +${rebootMin}

echo "[${dateTime}] - Provisioning and update script finished."
