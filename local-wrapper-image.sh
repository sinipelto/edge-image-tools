#!/bin/bash

# Do not tolerate any errors
set -e

# Assuming either current user ROOT user or current user has SUDO
userId=$(id -u)
(( userId != 0 )) && echo "Current user not root. This script must be run as root user or with sudo privileges." && exit 1

# Read local variables from separate file
# shellcheck source=/dev/null
source config/local_config

bashBin='/bin/bash'

# Scripts to execute in this local wrapper
createScript="${PWD}/create-image.sh"
publishScript="${PWD}/publish-image.sh"

##### START #####


chmod -v +x "${createScript}"
chmod -v +x "${publishScript}"

# Test all params are correctly set
${bashBin} "${createScript}" 'test'
${bashBin} "${publishScript}" 'test'

if [[ ${1} != 'test' ]]; then
	# If all ok, run the scripts
	${bashBin} "${createScript}"
	${bashBin} "${publishScript}"
fi
