#!/bin/bash

# Do not tolerate any errors
set -e

# Read local variables from separate file
source local_variables


##### START #####

(( $(id -u) != 0 )) && echo "Current user not ROOT. This script must be run with root/sudo privileges." && exit 1

bashBin='/bin/bash'

# Scripts to execute in this local wrapper
createScript="${PWD}/create-image.sh"
publishScript="${PWD}/publish-image.sh"

chmod +x "${createScript}"
chmod +x "${publishScript}"

# Test all params are correctly set
${bashBin} "${createScript}" 'test'
${bashBin} "${publishScript}" 'test'

if [[ ${1} != 'test' ]]; then
	# If all ok, run the scripts
	${bashBin} "${createScript}"
	${bashBin} "${publishScript}"
fi
