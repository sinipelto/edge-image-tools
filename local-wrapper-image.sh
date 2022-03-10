#!/bin/bash
set -e

# Assuming either current user ROOT user or current user has SUDO
userId=$(id -u)
(( userId != 0 )) && echo "Current user not root. This script must be run as root user or with sudo privileges." && exit 1

# Read local variables from separate file
# shellcheck source=/dev/null
source config/local_config

bashBin='/bin/bash'

# Scripts to execute in this local wrapper
scripts=("${PWD}/create-image.sh" "${PWD}/publish-image.sh")


################################################################################
################################	START	####################################
################################################################################

# shellcheck disable=SC2068
for script in ${scripts[@]}; do
	chmod -v +x "${script}"
	# Test all params are correctly set
	${bashBin} "${script}" 'test'
done

# If only testing, dont execute
if [[ ${1} != 'test' ]]; then
	# shellcheck disable=SC2068
	for script in ${scripts[@]}; do
		# If all ok, run the scripts
		${bashBin} "${script}"
	done
fi
