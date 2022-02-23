#!/bin/bash
set -e

userId=$(id -u)
(( userId != 0 )) && echo "Current user not root. This script must be run as root user or with sudo privileges." && exit 1

# Read image params variables from file
# shellcheck source=/dev/null
source /image_params

version=${IMAGE_VERSION}
os=${IMAGE_OS}
arch=${IMAGE_ARCH}
versionFile=${IMAGE_VER_FILE}

# Read/List SAS token for update image file share
# Images will be in format: YYYY-MM-DD_VERSION.img.xz
imgServer=${IMAGE_SERVER_URL}
sasToken=${SAS_TOKEN_URL_QUERY}

imgVersionUrl="${imgServer}/${os}/${arch}/${versionFile}${sasToken}"

waitBin='/root/bin/wait-for-it.sh'
sleepBin='/bin/sleep'
shutdownBin='/sbin/shutdown'
dateBin='/bin/date'

dateTime=$(${dateBin})
#isoDate=$(${dateBin} '+%Y-%m-%dT%H:%M:%S')

# Timeout before rebooting
rebootSec=10
# Timeout for the very first boot before taking any actions
syncTimeout=20

initUserRaspi='pi'
initUserUbuntu='ubuntu'

#persistenceFile='/persistence/.info'
provFile='/root/.provisioned'

provText="Pre-Built IoT Edge Image\nImage Version: ${version}\nDevice Provision Date: ${dateTime}"
#persistenceText="Persistence partition created with image version: ${version}\nPersistence partition Creation Date: ${dateTime}"

devConnStr=${DEV_EDGE_CONNECTION_STRING}

ensure_apt() {
	echo "Ensure connection to APT required services available.."

	${waitBin} -t 30 -h 'archive.ubuntu.com' -p 80
	${waitBin} -t 30 -h 'deb.debian.org' -p 80
	${waitBin} -t 30 -h 'packages.microsoft.com' -p 443

	echo "Connections ok."
}

base_config() {
	echo "Running system base configurations.."

	sed -i 's/^REGDOMAIN=.*/REGDOMAIN=FI/' /etc/default/crda
	rm -f /etc/xdg/autostart/piwiz.desktop
	localectl set-x11-keymap "fi" pc105
	setupcon -k --force

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
	pkgFileDeb='/etc/apt/sources.list.d/microsoft-prod.list'
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
	elif [[ ${os} == "rasp"* ]]; then
		curl -f -L "https://packages.microsoft.com/config/debian/stretch/multiarch/prod.list" > ${pkgFileDeb}
		curl -f -L "https://packages.microsoft.com/keys/microsoft.asc" | gpg --dearmor > ${gpgKeyFile}
	fi

	echo "Configuring apt sources done."
}

install_deps() {
	echo "Install dependencies.."

	ensure_apt

	apt-get update

	# Must be installed first!
	# Installs: moby-engine, moby-cli
	apt-get install -y moby-engine

	# Install once moby-engine is already installed
	# NOTE: This installation removes package 'hostname' from raspi OS - installs hostname:armhf in place
	# => needs to be allowed explicitly for this installation using the special arg
	apt-get install -y --allow-remove-essential aziot-edge

	echo "Install dependencies done."
}

config_edge() {
	echo "Configure iot edge specific settings.."

	echo "Fetch provisioning information.."

	# TODO! Use real DPS service ? generate secret, request provision data how??
	connStr=${devConnStr}

	echo "Set iot edge device connection string.."
	iotedge config mp --force --connection-string "${connStr}"

	echo "Apply iot edge config.."
	iotedge config apply

	# Not needed - already done by apply
	# echo "Restart aziot services"
	# aziotctl system restart

	echo "Check aziot services.."
	aziotctl check

	echo "Run iot edge checks.."
	iotedge check || true

	echo "Configure iot edge specific settings done."
}

provision() {
	echo "First boot - Start initial provisioning.."

	echo "Wait for a while to allow the clock to synchronize.."
	${sleepBin} ${syncTimeout}

	base_config
	config_sources
	install_deps
	config_edge

	echo "Mark the system provisioned."
	echo -e "${provText}" > ${provFile}

	doReboot=1
	echo "Initial provisioning done."
}

update() {
	echo "Updating system.."

	# TODO: curl download image zip
	#	extract zip
	#	losetup mount image
	#	clone partition to local disk
	#	change rootfs id to new
	#	delete old

	# TODO currently creates a bootloop
	#doReboot=1
	echo "System update done."
}

check_updates() {
	echo "Checking for image updates.."

	remoteVersion=$(curl -f -L "${imgVersionUrl}")

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

setup_persistence() {
	echo "Starting to setup persistence partition.."

	# TODO: create new partition to pstart=end-4M pend=end-4
	#	format partition ext4
	#	add mount entry to mount partition at boot

	# echo "Write persistence partition info."
	# shellcheck disable=SC2059
	# echo -e "${persistenceText}" > ${persistenceFile}

	echo "Persistence partition setup done."
}

isUpdate=0
doReboot=0

echo "[${dateTime}] - Provisioning and update script starting up.."

# TODO
# if [ -f "${persistenceFile}" ]; then
# 	echo "Persistence partition already exists. Skip persistence partition setup."
# else
# 	setup_persistence
# fi

check_updates

if [ -f "${provFile}" ]; then
	echo "Already provisioned. Skip initial provisioning."
else
	[ ${isUpdate} -eq 0 ] && provision
fi

[ ${doReboot} -eq 1 ] && echo "Reboot requested." && echo "Reboot in ${rebootSec}..." && ${sleepBin} ${rebootSec} && ${shutdownBin} -r now

echo "[${dateTime}] - Provisioning and update script finished."
